import Foundation
import OSLog

protocol ExerciseLogParsingService: Sendable {
    func parse(transcript: String, item: RoutineItem) async throws -> VoiceLogExtraction
}

struct LocalExerciseLogParsingService: ExerciseLogParsingService {
    func parse(transcript: String, item: RoutineItem) async throws -> VoiceLogExtraction {
        VoiceLogParser.parse(transcript)
    }
}

struct SupabaseExerciseLogParsingService: ExerciseLogParsingService {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func parse(transcript: String, item: RoutineItem) async throws -> VoiceLogExtraction {
        let request = ExerciseLogParseRequest(transcript: transcript, item: item)
        let data = try await client.invokeFunction("parse-exercise-log", body: request)
        let response = try JSONDecoder().decode(ExerciseLogParseResponse.self, from: data)
        guard response.version == 1 else { throw ClientError.invalidResponse }
        return response.extraction.model(transcript: transcript)
    }
}

struct FallbackExerciseLogParsingService: ExerciseLogParsingService {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MotionLog",
        category: "ExerciseLogParsing"
    )

    let primary: any ExerciseLogParsingService
    let fallback: any ExerciseLogParsingService

    func parse(transcript: String, item: RoutineItem) async throws -> VoiceLogExtraction {
        do {
            let extraction = try await primary.parse(transcript: transcript, item: item)
            Self.logger.info("Remote structured extraction completed")
            return extraction
        } catch {
            Self.logger.error("Remote structured extraction failed; using local fallback: \(String(describing: error), privacy: .public)")
            return try await fallback.parse(transcript: transcript, item: item)
        }
    }
}

struct ExerciseLogParseRequest: Encodable, Sendable {
    let version = 1
    let transcript: String
    let exercise: ExerciseContext

    init(transcript: String, item: RoutineItem) {
        self.transcript = transcript
        exercise = ExerciseContext(item: item)
    }

    struct ExerciseContext: Encodable, Sendable {
        let name: String
        let trackingMode: TrackingMode?
        let prescription: Prescription

        init(item: RoutineItem) {
            name = item.exercise.name
            trackingMode = item.exercise.trackingMode
            prescription = Prescription(item: item)
        }

        enum CodingKeys: String, CodingKey {
            case name, prescription
            case trackingMode = "tracking_mode"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(prescription, forKey: .prescription)
            if let trackingMode {
                try container.encode(trackingMode, forKey: .trackingMode)
            } else {
                try container.encodeNil(forKey: .trackingMode)
            }
        }
    }

    struct Prescription: Encodable, Sendable {
        let sets: Int?
        let reps: Int?
        let durationSeconds: Int?
        let bandResistance: String?
        let weightValue: Double?
        let weightUnit: WeightUnit?
        let notes: String?

        init(item: RoutineItem) {
            sets = item.targetSets
            reps = item.targetReps
            durationSeconds = item.targetDurationSeconds
            bandResistance = item.targetBandResistance
            weightValue = item.targetWeightValue
            weightUnit = item.targetWeightUnit
            notes = item.prescriptionNotes
        }

        enum CodingKeys: String, CodingKey {
            case sets, reps, notes
            case durationSeconds = "duration_seconds"
            case bandResistance = "band_resistance"
            case weightValue = "weight_value"
            case weightUnit = "weight_unit"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeNullable(sets, forKey: .sets)
            try container.encodeNullable(reps, forKey: .reps)
            try container.encodeNullable(durationSeconds, forKey: .durationSeconds)
            try container.encodeNullable(bandResistance, forKey: .bandResistance)
            try container.encodeNullable(weightValue, forKey: .weightValue)
            try container.encodeNullable(weightUnit, forKey: .weightUnit)
            try container.encodeNullable(notes, forKey: .notes)
        }
    }
}

struct ExerciseLogParseResponse: Decodable, Sendable {
    let version: Int
    let extraction: Extraction

    struct Extraction: Decodable, Sendable {
        let setsCompleted: Int?
        let repsPerSet: Int?
        let durationSeconds: Int?
        let bandResistance: String?
        let weightValue: Double?
        let weightUnit: WeightUnit?
        let painAfter: Int?
        let eachSide: Bool?
        let notes: [String]

        enum CodingKeys: String, CodingKey {
            case notes
            case setsCompleted = "sets_completed"
            case repsPerSet = "reps_per_set"
            case durationSeconds = "duration_seconds"
            case bandResistance = "band_resistance"
            case weightValue = "weight_value"
            case weightUnit = "weight_unit"
            case painAfter = "pain_after"
            case eachSide = "each_side"
        }

        func model(transcript: String) -> VoiceLogExtraction {
            VoiceLogExtraction(
                transcript: transcript,
                setsCompleted: setsCompleted.flatMap { $0 > 0 ? $0 : nil },
                repsPerSet: repsPerSet.flatMap { $0 > 0 ? $0 : nil },
                durationSeconds: durationSeconds.flatMap { $0 > 0 ? $0 : nil },
                bandResistance: bandResistance?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                weightValue: weightValue.flatMap { $0 >= 0 ? $0 : nil },
                weightUnit: weightValue == nil ? nil : weightUnit,
                painAfter: painAfter.flatMap { 0...10 ~= $0 ? $0 : nil },
                eachSide: eachSide ?? false,
                noteBullets: notes.compactMap {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                }
            )
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private extension KeyedEncodingContainer {
    mutating func encodeNullable<Value: Encodable>(_ value: Value?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
