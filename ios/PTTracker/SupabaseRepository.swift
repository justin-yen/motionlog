import Foundation

actor SupabasePTRepository: PTRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func todayRoutine() async throws -> Routine {
        let day = LocalDateKey.string(for: .now)
        let query = "routines?scheduled_for=lte.\(day)&select=id,title,scheduled_for,routine_items(id,position,target_sets,target_reps,target_duration_seconds,target_band_resistance,target_weight_value,target_weight_unit,prescription_notes,exercise:exercises(id,name,tracking_mode,instructions,image_path,video_url,pt_note))&order=scheduled_for.desc&routine_items.order=position.asc&limit=1"
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

    func history() async throws -> [ExerciseLog] {
        let data = try await client.rest(path: "exercise_logs?select=*,exercise:exercises(name)&order=performed_at.desc")
        return try JSONDecoder.supabase.decode([ExerciseLogRow].self, from: data).map {
            $0.model(exerciseName: $0.exercise?.name ?? "Exercise", hasAudio: false)
        }
    }

    func reorder(routineID: UUID, itemIDs: [UUID]) async throws {
        for (position, id) in itemIDs.enumerated() {
            _ = try await client.rest(
                path: "routine_items?id=eq.\(id.uuidString.lowercased())",
                method: "PATCH",
                body: ["position": position],
                prefer: "return=minimal"
            )
        }
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
