import Foundation

actor SupabasePTRepository: PTRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func todayRoutine() async throws -> Routine {
        let day = LocalDateKey.string(for: .now)
        let query = "routines?scheduled_for=lte.\(day)&select=id,title,scheduled_for,routine_items!inner(id,position,target_sets,target_reps,target_duration_seconds,target_band_resistance,target_weight_value,target_weight_unit,prescription_notes,exercise:exercises(id,name,tracking_mode,instructions,image_path,video_url,pt_note))&order=scheduled_for.desc&routine_items.order=position.asc&limit=1"
        let data = try await client.rest(path: query)
        let decoder = JSONDecoder.supabase
        guard let dto = try decoder.decode([RoutineDTO].self, from: data).first else {
            throw ClientError.server(message: "No current routine has been prescribed yet.")
        }
        return dto.model
    }

    func saveLog(_ draft: ExerciseLogDraft) async throws -> ExerciseLog {
        guard let session = await client.session else {
            throw ClientError.server(message: "Please sign in again.")
        }
        var body: [String: Any] = [
            "owner_id": session.userID.uuidString.lowercased(),
            "exercise_id": draft.exercise.id.uuidString.lowercased(),
            "performed_at": ISO8601DateFormatter().string(from: .now)
        ]
        body.put("routine_item_id", draft.routineItemID?.uuidString.lowercased())
        body.put("sets_completed", draft.setsCompleted)
        body.put("reps_per_set", draft.repsPerSet)
        body.put("duration_seconds", draft.durationSeconds)
        body.put("band_resistance", draft.bandResistance)
        body.put("weight_value", draft.weightValue)
        body.put("weight_unit", draft.weightUnit?.rawValue)
        body.put("pain_after", draft.painAfter)
        body.put("notes", draft.notes)

        let data = try await client.rest(
            path: "exercise_logs?select=*",
            method: "POST",
            body: body,
            prefer: "return=representation"
        )
        guard let row = try JSONDecoder.supabase.decode([ExerciseLogRow].self, from: data).first else {
            throw ClientError.invalidResponse
        }
        if let localAudioURL = draft.localAudioURL {
            try await retainAudio(
                at: localAudioURL,
                exerciseLogID: row.id,
                ownerID: session.userID,
                extraction: draft.voiceExtraction
            )
        }
        return row.model(exerciseName: draft.exercise.name, hasAudio: draft.localAudioURL != nil)
    }

    func logs(from start: Date, to end: Date) async throws -> [ExerciseLog] {
        // A bounded range lets Postgres use the (owner_id, performed_at) index instead of reading every log.
        let iso = ISO8601DateFormatter()
        let range = "performed_at=gte.\(iso.string(from: start))&performed_at=lt.\(iso.string(from: end))"
        let data = try await client.rest(path: "exercise_logs?select=*,exercise:exercises(name)&\(range)&order=performed_at.desc")
        return try JSONDecoder.supabase.decode([ExerciseLogRow].self, from: data).map {
            $0.model(exerciseName: $0.exercise?.name ?? "Exercise", hasAudio: false)
        }
    }

    func reorder(routineID: UUID, itemIDs: [UUID]) async throws {
        // Positions are unique per routine, so park every row first, then set the final order.
        try await setPositions(itemIDs, offset: Self.parkedPositionOffset)
        try await setPositions(itemIDs, offset: 0)
    }

    func plans(from start: Date, to end: Date) async throws -> [Routine] {
        // Two index lookups on (owner_id, scheduled_for): plans that start inside the range, and the
        // one plan still in force when the range begins. Only a few rows, however long the history.
        let first = LocalDateKey.string(for: start)
        let last = LocalDateKey.string(for: end)
        let select = "select=id,title,scheduled_for,routine_items!inner(\(Self.routineItemColumns))&routine_items.order=position.asc"
        async let inside = client.rest(path: "routines?\(select)&scheduled_for=gte.\(first)&scheduled_for=lt.\(last)&order=scheduled_for.desc")
        async let before = client.rest(path: "routines?\(select)&scheduled_for=lt.\(first)&order=scheduled_for.desc&limit=1")
        let decoder = JSONDecoder.supabase
        let plans = try decoder.decode([RoutineDTO].self, from: try await inside)
            + decoder.decode([RoutineDTO].self, from: try await before)
        return plans.map(\.model)
    }

    private static let routineItemColumns = "id,position,target_sets,target_reps,target_duration_seconds,target_band_resistance,target_weight_value,target_weight_unit,prescription_notes,exercise:exercises(id,name,tracking_mode,instructions,image_path,video_url,pt_note)"

    func exercises() async throws -> [Exercise] {
        let data = try await client.rest(path: "exercises?select=id,name,tracking_mode,instructions,image_path,video_url,pt_note&order=name.asc")
        return try JSONDecoder.supabase.decode([Exercise].self, from: data)
    }

    func saveRoutine(_ update: RoutineUpdate) async throws -> Routine {
        guard let session = await client.session else {
            throw ClientError.server(message: "Please sign in again.")
        }
        let owner = session.userID.uuidString.lowercased()

        if !update.newExercises.isEmpty {
            let rows: [[String: Any]] = update.newExercises.map { exercise in
                var row: [String: Any] = [
                    "id": exercise.id.uuidString.lowercased(),
                    "owner_id": owner,
                    "name": exercise.name
                ]
                // Bulk inserts need the same keys on every row.
                row["tracking_mode"] = exercise.trackingMode.map { $0.rawValue as Any } ?? NSNull()
                return row
            }
            // A retry after a failed save may resend a move that was already created.
            _ = try await client.rest(path: "exercises?on_conflict=id", method: "POST", body: rows, prefer: "resolution=ignore-duplicates,return=minimal")
        }

        if update.editsTodaysRoutine() {
            let routineID = update.base.id.uuidString.lowercased()
            let removed = update.removedItemIDs
            if !removed.isEmpty {
                let list = removed.map { $0.uuidString.lowercased() }.joined(separator: ",")
                _ = try await client.rest(path: "routine_items?id=in.(\(list))", method: "DELETE", prefer: "return=minimal")
            }
            let kept = update.items.filter { !update.newItemIDs.contains($0.id) }
            try await setPositions(kept.map(\.id), offset: Self.parkedPositionOffset)
            for item in kept {
                _ = try await client.rest(
                    path: "routine_items?id=eq.\(item.id.uuidString.lowercased())",
                    method: "PATCH",
                    body: Self.prescriptionBody(item),
                    prefer: "return=minimal"
                )
            }
            let added = update.items.filter { update.newItemIDs.contains($0.id) }
            if !added.isEmpty {
                let rows = added.map { Self.insertBody($0, routineID: routineID, owner: owner, keepID: true) }
                _ = try await client.rest(path: "routine_items", method: "POST", body: rows, prefer: "return=minimal")
            }
        } else {
            // Keep the older plan for past days in History; the new plan starts today.
            // Upsert so a routine already dated today (say, from a save that failed partway) is reused.
            var routineBody: [String: Any] = [
                "owner_id": owner,
                "scheduled_for": LocalDateKey.string(for: .now)
            ]
            routineBody["title"] = update.base.title.map { $0 as Any } ?? NSNull()
            let data = try await client.rest(
                path: "routines?on_conflict=owner_id,scheduled_for&select=id",
                method: "POST",
                body: routineBody,
                prefer: "resolution=merge-duplicates,return=representation"
            )
            struct Created: Decodable { let id: UUID }
            guard let created = try JSONDecoder.supabase.decode([Created].self, from: data).first else {
                throw ClientError.invalidResponse
            }
            let routineID = created.id.uuidString.lowercased()
            _ = try await client.rest(path: "routine_items?routine_id=eq.\(routineID)", method: "DELETE", prefer: "return=minimal")
            if !update.items.isEmpty {
                let rows = update.items.map { Self.insertBody($0, routineID: routineID, owner: owner, keepID: false) }
                _ = try await client.rest(path: "routine_items", method: "POST", body: rows, prefer: "return=minimal")
            }
        }

        // Last, so a failed save above leaves the log screen asking for the same numbers as before.
        for (exerciseID, mode) in update.trackingModeChanges {
            _ = try await client.rest(
                path: "exercises?id=eq.\(exerciseID.uuidString.lowercased())",
                method: "PATCH",
                body: ["tracking_mode": mode.rawValue],
                prefer: "return=minimal"
            )
        }
        return try await todayRoutine()
    }

    private static let parkedPositionOffset = 10_000

    private func setPositions(_ itemIDs: [UUID], offset: Int) async throws {
        for (position, id) in itemIDs.enumerated() {
            _ = try await client.rest(
                path: "routine_items?id=eq.\(id.uuidString.lowercased())",
                method: "PATCH",
                body: ["position": position + offset],
                prefer: "return=minimal"
            )
        }
    }

    /// Every prescription column, with NSNull for anything the other mode used, so a switch
    /// from reps to time (or band to weight) clears the old values.
    private static func prescriptionBody(_ item: RoutineItem) -> [String: Any] {
        [
            "position": item.position,
            "target_sets": item.targetSets.map { $0 as Any } ?? NSNull(),
            "target_reps": item.targetReps.map { $0 as Any } ?? NSNull(),
            "target_duration_seconds": item.targetDurationSeconds.map { $0 as Any } ?? NSNull(),
            "target_band_resistance": item.targetBandResistance.map { $0 as Any } ?? NSNull(),
            "target_weight_value": item.targetWeightValue.map { $0 as Any } ?? NSNull(),
            "target_weight_unit": item.targetWeightUnit.map { $0.rawValue as Any } ?? NSNull()
        ]
    }

    private static func insertBody(_ item: RoutineItem, routineID: String, owner: String, keepID: Bool) -> [String: Any] {
        var body = prescriptionBody(item)
        body["owner_id"] = owner
        body["routine_id"] = routineID
        body["exercise_id"] = item.exercise.id.uuidString.lowercased()
        // Bulk inserts need the same keys on every row, so absent values are sent as null.
        body["prescription_notes"] = item.prescriptionNotes.map { $0 as Any } ?? NSNull()
        if keepID { body["id"] = item.id.uuidString.lowercased() }
        return body
    }

    private func retainAudio(
        at localURL: URL,
        exerciseLogID: UUID,
        ownerID: UUID,
        extraction: VoiceLogExtraction?
    ) async throws {
        let recordingID = UUID()
        let storagePath = "\(ownerID.uuidString.lowercased())/\(recordingID.uuidString.lowercased()).m4a"
        let audioData = try Data(contentsOf: localURL, options: .mappedIfSafe)
        try await client.uploadAudio(audioData, path: storagePath)
        var body: [String: Any] = [
            "id": recordingID.uuidString.lowercased(),
            "owner_id": ownerID.uuidString.lowercased(),
            "exercise_log_id": exerciseLogID.uuidString.lowercased(),
            "storage_path": storagePath,
            "transcription_status": extraction == nil ? "pending" : "complete"
        ]
        if let extraction {
            body["transcript"] = extraction.transcript
            body["structured_data"] = extraction.structuredData
        }
        _ = try await client.rest(
            path: "audio_recordings",
            method: "POST",
            body: body,
            prefer: "return=minimal"
        )
    }
}

enum LocalDateKey {
    static func string(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else {
            return date.formatted(.iso8601.year().month().day())
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

private struct RoutineDTO: Decodable {
    let id: UUID
    let title: String?
    let scheduledFor: Date
    let routineItems: [RoutineItemDTO]

    enum CodingKeys: String, CodingKey {
        case id, title
        case scheduledFor = "scheduled_for"
        case routineItems = "routine_items"
    }

    var model: Routine {
        Routine(id: id, title: title, scheduledFor: scheduledFor, routineItems: routineItems.map(\.model))
    }
}

private struct RoutineItemDTO: Decodable {
    let id: UUID
    let position: Int
    let targetSets: Int?
    let targetReps: Int?
    let targetDurationSeconds: Int?
    let targetBandResistance: String?
    let targetWeightValue: Double?
    let targetWeightUnit: WeightUnit?
    let prescriptionNotes: String?
    let exercise: Exercise

    enum CodingKeys: String, CodingKey {
        case id, position, exercise
        case targetSets = "target_sets"
        case targetReps = "target_reps"
        case targetDurationSeconds = "target_duration_seconds"
        case targetBandResistance = "target_band_resistance"
        case targetWeightValue = "target_weight_value"
        case targetWeightUnit = "target_weight_unit"
        case prescriptionNotes = "prescription_notes"
    }

    var model: RoutineItem {
        RoutineItem(
            id: id,
            exercise: exercise,
            position: position,
            targetSets: targetSets,
            targetReps: targetReps,
            targetDurationSeconds: targetDurationSeconds,
            targetBandResistance: targetBandResistance,
            targetWeightValue: targetWeightValue,
            targetWeightUnit: targetWeightUnit,
            prescriptionNotes: prescriptionNotes
        )
    }
}

private struct ExerciseLogRow: Decodable {
    struct ExerciseName: Decodable { let name: String }
    let id: UUID
    let exerciseID: UUID
    let performedAt: Date
    let setsCompleted: Int?
    let repsPerSet: Int?
    let durationSeconds: Int?
    let bandResistance: String?
    let weightValue: Double?
    let weightUnit: WeightUnit?
    let painAfter: Int?
    let notes: String?
    let exercise: ExerciseName?

    enum CodingKeys: String, CodingKey {
        case id, notes, exercise
        case exerciseID = "exercise_id"
        case performedAt = "performed_at"
        case setsCompleted = "sets_completed"
        case repsPerSet = "reps_per_set"
        case durationSeconds = "duration_seconds"
        case bandResistance = "band_resistance"
        case weightValue = "weight_value"
        case weightUnit = "weight_unit"
        case painAfter = "pain_after"
    }

    func model(exerciseName: String, hasAudio: Bool) -> ExerciseLog {
        ExerciseLog(
            id: id,
            exerciseID: exerciseID,
            exerciseName: exerciseName,
            performedAt: performedAt,
            setsCompleted: setsCompleted,
            repsPerSet: repsPerSet,
            durationSeconds: durationSeconds,
            bandResistance: bandResistance,
            weightValue: weightValue,
            weightUnit: weightUnit,
            painAfter: painAfter,
            notes: notes,
            hasAudio: hasAudio
        )
    }
}

private extension JSONDecoder {
    static var supabase: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            if let date = ISO8601DateFormatter().date(from: value) { return date }
            let day = DateFormatter()
            day.locale = Locale(identifier: "en_US_POSIX")
            day.dateFormat = "yyyy-MM-dd"
            guard let date = day.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(), debugDescription: "Invalid date")
            }
            return date
        }
        return decoder
    }
}

private extension Dictionary where Key == String, Value == Any {
    mutating func put(_ key: String, _ value: Any?) {
        if let value { self[key] = value }
    }
}
