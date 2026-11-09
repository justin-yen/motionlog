import Foundation

enum TrackingMode: String, Codable, CaseIterable, Sendable {
    case reps
    case duration
}

enum WeightUnit: String, Codable, CaseIterable, Sendable {
    case lb
    case kg
}

struct Exercise: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var trackingMode: TrackingMode?
    var instructions: [String]?
    var imagePath: String?
    var videoURL: URL?
    var ptNote: String?

    enum CodingKeys: String, CodingKey {
        case id, name, instructions
        case trackingMode = "tracking_mode"
        case imagePath = "image_path"
        case videoURL = "video_url"
        case ptNote = "pt_note"
    }
}

struct RoutineItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var exercise: Exercise
    var position: Int
    var targetSets: Int?
    var targetReps: Int?
    var targetDurationSeconds: Int?
    var targetBandResistance: String?
    var targetWeightValue: Double?
    var targetWeightUnit: WeightUnit?
    var prescriptionNotes: String?
    var isComplete: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, exercise, position
        case targetSets = "target_sets"
        case targetReps = "target_reps"
        case targetDurationSeconds = "target_duration_seconds"
        case targetBandResistance = "target_band_resistance"
        case targetWeightValue = "target_weight_value"
        case targetWeightUnit = "target_weight_unit"
        case prescriptionNotes = "prescription_notes"
        case isComplete = "is_complete"
    }

    var prescriptionSummary: String? {
        var parts: [String] = []
        if let targetSets { parts.append("\(targetSets) sets") }
        if let targetReps { parts.append("\(targetReps) reps") }
        if let targetDurationSeconds { parts.append("\(targetDurationSeconds) sec") }
        if let targetBandResistance { parts.append(targetBandResistance) }
        if let targetWeightValue, let targetWeightUnit {
            parts.append("\(targetWeightValue.formatted()) \(targetWeightUnit.rawValue)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct Routine: Identifiable, Codable, Sendable {
    let id: UUID
    var title: String?
    var scheduledFor: Date
    var routineItems: [RoutineItem]

    enum CodingKeys: String, CodingKey {
        case id, title
        case scheduledFor = "scheduled_for"
        case routineItems = "routine_items"
    }
}

struct ExerciseLogDraft: Sendable {
    let exercise: Exercise
    let routineItemID: UUID?
    var setsCompleted: Int?
    var repsPerSet: Int?
    var durationSeconds: Int?
    var bandResistance: String?
    var weightValue: Double?
    var weightUnit: WeightUnit?
    var painAfter: Int?
    var notes: String?
    var localAudioURL: URL?
    var voiceExtraction: VoiceLogExtraction?
}

struct VoiceLogExtraction: Codable, Equatable, Sendable {
    let transcript: String
    var setsCompleted: Int?
    var repsPerSet: Int?
    var durationSeconds: Int?
    var bandResistance: String?
    var weightValue: Double?
    var weightUnit: WeightUnit?
    var painAfter: Int?
    var eachSide: Bool
    var noteBullets: [String]

    var structuredData: [String: Any] {
        var values: [String: Any] = ["each_side": eachSide]
        if let setsCompleted { values["sets_completed"] = setsCompleted }
        if let repsPerSet { values["reps_per_set"] = repsPerSet }
        if let durationSeconds { values["duration_seconds"] = durationSeconds }
        if let bandResistance { values["band_resistance"] = bandResistance }
        if let weightValue { values["weight_value"] = weightValue }
        if let weightUnit { values["weight_unit"] = weightUnit.rawValue }
        if let painAfter { values["pain_after"] = painAfter }
        if !noteBullets.isEmpty { values["note_bullets"] = noteBullets }
        return values
    }
}

struct ExerciseLog: Identifiable, Codable, Sendable {
    let id: UUID
    let exerciseID: UUID
    let exerciseName: String
    let performedAt: Date
    let setsCompleted: Int?
    let repsPerSet: Int?
    let durationSeconds: Int?
    let bandResistance: String?
    let weightValue: Double?
    let weightUnit: WeightUnit?
    let painAfter: Int?
    let notes: String?
    let hasAudio: Bool

    enum CodingKeys: String, CodingKey {
        case id, notes
        case exerciseID = "exercise_id"
        case exerciseName = "exercise_name"
        case performedAt = "performed_at"
        case setsCompleted = "sets_completed"
        case repsPerSet = "reps_per_set"
        case durationSeconds = "duration_seconds"
        case bandResistance = "band_resistance"
        case weightValue = "weight_value"
        case weightUnit = "weight_unit"
        case painAfter = "pain_after"
        case hasAudio = "has_audio"
    }

    var summary: String {
        var parts: [String] = []
        if let setsCompleted { parts.append("\(setsCompleted) sets") }
        if let repsPerSet { parts.append("\(repsPerSet) reps") }
        if let durationSeconds { parts.append("\(durationSeconds) sec") }
        if let bandResistance { parts.append(bandResistance) }
        if let weightValue, let weightUnit {
            parts.append("\(weightValue.formatted()) \(weightUnit.rawValue)")
        }
        if let painAfter { parts.append("Pain \(painAfter)/10") }
        return parts.isEmpty ? "Completed" : parts.joined(separator: " · ")
    }
}

struct AuthSession: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case userID = "user_id"
    }
}
