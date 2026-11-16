import Foundation

/// The values the edit-move sheet works on. A move is counted in reps or held for a time,
/// and resistance (none, a band, or a weight) is a separate choice that works with either.
struct MovePrescription: Equatable, Sendable {
    enum Count: String, CaseIterable, Sendable { case reps = "Reps", time = "Time" }
    enum Resistance: String, CaseIterable, Sendable { case none = "None", band = "Band", weight = "Weight" }

    static let bandColors = ["Yellow", "Red", "Green", "Blue", "Black"]
    static let quickSeconds = [15, 30, 45, 60]

    var count: Count
    var sets: Int
    var reps: Int
    var seconds: Int
    var resistance: Resistance
    /// Stored the way existing routines name bands, e.g. "Red band".
    var band: String
    var weight: Double
    var unit: WeightUnit

    /// Starting values for a move that isn't in the plan yet.
    static func defaults(for mode: TrackingMode?) -> MovePrescription {
        MovePrescription(
            count: mode == .duration ? .time : .reps,
            sets: mode == .duration ? 3 : 2,
            reps: 10,
            seconds: 30,
            resistance: .none,
            band: "Red band",
            weight: 5,
            unit: .lb
        )
    }

    init(count: Count, sets: Int, reps: Int, seconds: Int, resistance: Resistance, band: String, weight: Double, unit: WeightUnit) {
        self.count = count
        self.sets = sets
        self.reps = reps
        self.seconds = seconds
        self.resistance = resistance
        self.band = band
        self.weight = weight
        self.unit = unit
    }

    init(item: RoutineItem) {
        let isTimed = item.targetReps == nil
            && (item.targetDurationSeconds != nil || item.exercise.trackingMode == .duration)
        count = isTimed ? .time : .reps
        sets = item.targetSets ?? (isTimed ? 1 : 2)
        reps = item.targetReps ?? 10
        seconds = item.targetDurationSeconds ?? 30
        if item.targetWeightValue != nil {
            resistance = .weight
        } else if item.targetBandResistance?.isEmpty == false {
            resistance = .band
        } else {
            resistance = .none
        }
        band = item.targetBandResistance.flatMap { $0.isEmpty ? nil : $0 } ?? "Red band"
        weight = item.targetWeightValue ?? 5
        unit = item.targetWeightUnit ?? .lb
    }

    /// Writes these values onto a routine item, clearing whatever the other mode used.
    func applied(to item: RoutineItem) -> RoutineItem {
        var item = item
        item.targetSets = sets
        switch count {
        case .reps:
            item.targetReps = reps
            item.targetDurationSeconds = nil
            item.exercise.trackingMode = .reps
        case .time:
            item.targetReps = nil
            item.targetDurationSeconds = seconds
            item.exercise.trackingMode = .duration
        }
        switch resistance {
        case .none:
            item.targetBandResistance = nil
            item.targetWeightValue = nil
            item.targetWeightUnit = nil
        case .band:
            item.targetBandResistance = band
            item.targetWeightValue = nil
            item.targetWeightUnit = nil
        case .weight:
            item.targetBandResistance = nil
            item.targetWeightValue = weight
            item.targetWeightUnit = unit
        }
        return item
    }

    /// The line under the move name in the sheet, the same text the Today row will show.
    func summary(for exercise: Exercise) -> String {
        let item = applied(to: RoutineItem(id: UUID(), exercise: exercise, position: 0))
        return item.shortPrescription ?? ""
    }

    /// Band chip choices, keeping a band name from an older routine that isn't one of the colors.
    var bandOptions: [String] {
        let standard = Self.bandColors.map { "\($0) band" }
        return standard.contains(band) ? standard : standard + [band]
    }

    static func bandColorName(_ band: String) -> String {
        band.hasSuffix(" band") ? String(band.dropLast(5)) : band
    }

    var weightStep: Double { unit == .kg ? 0.5 : 1 }
}

/// One row of the plan while it is being edited on Today.
struct EditableMove: Identifiable, Equatable, Sendable {
    let id: UUID
    var item: RoutineItem
    /// The row as it was before editing started; nil for a move added during this edit.
    let original: RoutineItem?
    var isRemoved = false

    var isNew: Bool { original == nil }

    var isChanged: Bool {
        guard let original else { return false }
        return !original.hasSamePrescription(as: item)
    }
}

/// Everything changed on Today between tapping Edit and tapping Done.
struct RoutineEditDraft: Sendable {
    let base: Routine
    var moves: [EditableMove]
    /// Moves picked from the common list or typed in, which need creating before they can be planned.
    var newExercises: [Exercise] = []

    init(routine: Routine) {
        base = routine
        moves = routine.routineItems.map { EditableMove(id: $0.id, item: $0, original: $0) }
    }

    /// A plan needs at least one move; Done is held back until there is one.
    var keptCount: Int { moves.filter { !$0.isRemoved }.count }

    var hasChanges: Bool {
        moves.contains { $0.isRemoved || $0.isNew || $0.isChanged }
            || moves.filter { !$0.isRemoved }.map(\.id) != base.routineItems.map(\.id)
    }

    /// Names already in the plan, so the add sheet doesn't offer them twice.
    var plannedExerciseNames: Set<String> {
        Set(moves.filter { !$0.isRemoved }.map { $0.item.exercise.name.lowercased() })
    }

    mutating func add(exercise: Exercise, prescription: MovePrescription, isNewExercise: Bool) {
        let blank = RoutineItem(id: UUID(), exercise: exercise, position: moves.count)
        let item = prescription.applied(to: blank)
        moves.append(EditableMove(id: item.id, item: item, original: nil))
        if isNewExercise {
            var created = exercise
            created.trackingMode = item.exercise.trackingMode
            newExercises.append(created)
        }
    }

    mutating func update(moveID: UUID, prescription: MovePrescription) {
        guard let index = moves.firstIndex(where: { $0.id == moveID }) else { return }
        moves[index].item = prescription.applied(to: moves[index].item)
        if let created = newExercises.firstIndex(where: { $0.id == moves[index].item.exercise.id }) {
            newExercises[created].trackingMode = moves[index].item.exercise.trackingMode
        }
    }

    mutating func setRemoved(_ removed: Bool, moveID: UUID) {
        guard let index = moves.firstIndex(where: { $0.id == moveID }) else { return }
        if removed, moves[index].isNew {
            // A move added in this edit just disappears; there is nothing to undo back to.
            let exerciseID = moves[index].item.exercise.id
            moves.remove(at: index)
            newExercises.removeAll { $0.id == exerciseID }
        } else {
            moves[index].isRemoved = removed
        }
    }

    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        moves.move(fromOffsets: source, toOffset: destination)
    }

    /// The saved plan: kept moves in their new order, numbered from zero.
    func update() -> RoutineUpdate {
        let kept = moves.filter { !$0.isRemoved }
        let items = kept.enumerated().map { position, move -> RoutineItem in
            var item = move.item
            item.position = position
            return item
        }
        let newExerciseIDs = Set(newExercises.map(\.id))
        var modeChanges: [UUID: TrackingMode] = [:]
        for move in kept where !newExerciseIDs.contains(move.item.exercise.id) {
            let before = move.original?.exercise.trackingMode ?? base.routineItems
                .first { $0.exercise.id == move.item.exercise.id }?.exercise.trackingMode
            if let mode = move.item.exercise.trackingMode, mode != before {
                modeChanges[move.item.exercise.id] = mode
            }
        }
        return RoutineUpdate(
            base: base,
            items: items,
            newItemIDs: Set(kept.filter(\.isNew).map(\.id)),
            newExercises: newExercises,
            trackingModeChanges: modeChanges
        )
    }
}

/// What the repository needs to save an edited plan.
struct RoutineUpdate: Sendable {
    let base: Routine
    let items: [RoutineItem]
    let newItemIDs: Set<UUID>
    let newExercises: [Exercise]
    /// Existing exercises whose reps-or-time mode changed, so logging asks for the right numbers.
    let trackingModeChanges: [UUID: TrackingMode]

    var removedItemIDs: [UUID] {
        let kept = Set(items.map(\.id))
        return base.routineItems.map(\.id).filter { !kept.contains($0) }
    }

    /// Edits to a plan dated today change it in place; an older plan is kept for History
    /// and a new one dated today replaces it.
    func editsTodaysRoutine(today: Date = .now) -> Bool {
        LocalDateKey.string(for: base.scheduledFor) == LocalDateKey.string(for: today)
    }
}

/// Some common PT moves to add without typing.
enum CommonMoves {
    static let all: [(name: String, mode: TrackingMode)] = [
        ("Side-lying leg lift", .reps),
        ("Bird dog", .reps),
        ("Mini squat", .reps),
        ("Dead bug", .reps),
        ("Wall sit", .duration),
        ("Plank", .duration),
        ("Single-leg balance", .duration),
        ("Calf stretch", .duration)
    ]
}

extension RoutineItem {
    func hasSamePrescription(as other: RoutineItem) -> Bool {
        targetSets == other.targetSets
            && targetReps == other.targetReps
            && targetDurationSeconds == other.targetDurationSeconds
            && targetBandResistance == other.targetBandResistance
            && targetWeightValue == other.targetWeightValue
            && targetWeightUnit == other.targetWeightUnit
            && exercise.trackingMode == other.exercise.trackingMode
    }
}
