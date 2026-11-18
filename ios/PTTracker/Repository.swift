import Foundation

protocol PTRepository: Sendable {
    func todayRoutine() async throws -> Routine
    func saveLog(_ draft: ExerciseLogDraft) async throws -> ExerciseLog
    /// Logs performed in [start, end), newest first.
    func logs(from start: Date, to end: Date) async throws -> [ExerciseLog]
    func reorder(routineID: UUID, itemIDs: [UUID]) async throws
    /// Exercises the user already has, for the add-a-move picker.
    func exercises() async throws -> [Exercise]
    /// The plans that cover days in [start, end): every plan dated inside the range, plus the
    /// newest plan dated before it (which is still in force when the range begins). Newest first.
    func plans(from start: Date, to end: Date) async throws -> [Routine]
    /// Saves an edited plan and returns the routine Today should now show.
    func saveRoutine(_ update: RoutineUpdate) async throws -> Routine
}

actor MockPTRepository: PTRepository {
    private var routine = SampleData.routine
    private var logs: [ExerciseLog] = []
    private var pastRoutines: [Routine] = []
    private var library = [SampleData.bridge, SampleData.standingRow, SampleData.heelRaise, SampleData.clamshell]
    private var todayRoutineRequests = 0

    func todayRoutine() async throws -> Routine {
        todayRoutineRequests += 1
        return routine
    }

    func todayRoutineRequestCount() -> Int { todayRoutineRequests }

    func saveLog(_ draft: ExerciseLogDraft) async throws -> ExerciseLog {
        let log = ExerciseLog(
            id: UUID(),
            exerciseID: draft.exercise.id,
            exerciseName: draft.exercise.name,
            performedAt: .now,
            setsCompleted: draft.setsCompleted,
            repsPerSet: draft.repsPerSet,
            durationSeconds: draft.durationSeconds,
            bandResistance: draft.bandResistance,
            weightValue: draft.weightValue,
            weightUnit: draft.weightUnit,
            painAfter: draft.painAfter,
            notes: draft.notes,
            hasAudio: draft.localAudioURL != nil
        )
        logs.insert(log, at: 0)
        if let itemID = draft.routineItemID,
           let index = routine.routineItems.firstIndex(where: { $0.id == itemID }) {
            routine.routineItems[index].isComplete = true
        }
        return log
    }

    func logs(from start: Date, to end: Date) async throws -> [ExerciseLog] {
        logs.filter { $0.performedAt >= start && $0.performedAt < end }
            .sorted { $0.performedAt > $1.performedAt }
    }

    func reorder(routineID: UUID, itemIDs: [UUID]) async throws {
        guard routine.id == routineID else { return }
        let byID = Dictionary(uniqueKeysWithValues: routine.routineItems.map { ($0.id, $0) })
        routine.routineItems = itemIDs.enumerated().compactMap { position, id in
            guard var item = byID[id] else { return nil }
            item.position = position
            return item
        }
    }

    func plans(from start: Date, to end: Date) async throws -> [Routine] {
        PlanRange.covering(start: start, end: end, in: [routine] + pastRoutines)
    }

    func exercises() async throws -> [Exercise] {
        library.sorted { $0.name < $1.name }
    }

    func saveRoutine(_ update: RoutineUpdate) async throws -> Routine {
        library.append(contentsOf: update.newExercises)
        for (id, mode) in update.trackingModeChanges {
            if let index = library.firstIndex(where: { $0.id == id }) { library[index].trackingMode = mode }
        }
        if !update.editsTodaysRoutine() { pastRoutines.insert(routine, at: 0) }
        routine = Routine(
            id: update.editsTodaysRoutine() ? update.base.id : UUID(),
            title: update.base.title,
            scheduledFor: .now,
            routineItems: update.items
        )
        return routine
    }
}

enum SampleData {
    static let bridge = Exercise(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Bridge",
        trackingMode: .duration,
        instructions: ["Lie on your back with knees bent.", "Lift your hips slowly.", "Keep your ribs relaxed."],
        ptNote: "Stop before your low back starts to arch."
    )
    static let standingRow = Exercise(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Standing row",
        trackingMode: .reps,
        instructions: ["Anchor the band at chest height.", "Keep your shoulders relaxed.", "Pull your elbows straight back."],
        videoURL: URL(string: "https://www.youtube.com/results?search_query=standing+resistance+band+row+physical+therapy"),
        ptNote: "Keep your ribs down and move slowly."
    )
    static let heelRaise = Exercise(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Heel raise",
        trackingMode: .reps
    )
    static let clamshell = Exercise(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        name: "Clamshell",
        trackingMode: .reps
    )

    static let routine = Routine(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
        title: "Today’s Routine",
        scheduledFor: .now,
        routineItems: [
            RoutineItem(id: UUID(), exercise: bridge, position: 0, targetDurationSeconds: 45),
            RoutineItem(id: UUID(), exercise: standingRow, position: 1, targetSets: 3, targetReps: 10, targetBandResistance: "Red band"),
            RoutineItem(id: UUID(), exercise: heelRaise, position: 2, targetSets: 2, targetReps: 12),
            RoutineItem(id: UUID(), exercise: clamshell, position: 3, targetSets: 2, targetReps: 10, targetBandResistance: "Green band")
        ]
    )
}
