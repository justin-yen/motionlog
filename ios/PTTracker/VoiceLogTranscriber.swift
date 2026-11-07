@preconcurrency import Speech
import Foundation

enum VoiceTranscriptionError: LocalizedError {
    case permissionDenied
    case unavailable
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Speech recognition permission is needed to convert the recording into exercise details."
        case .unavailable:
            "Speech recognition is temporarily unavailable. The raw recording is still attached."
        case .emptyTranscript:
            "No speech could be recognized. The raw recording is still attached."
        }
    }
}

@MainActor
final class VoiceLogTranscriber {
    func transcribe(url: URL) async throws -> VoiceLogExtraction {
        guard await Self.requestAuthorization() else { throw VoiceTranscriptionError.permissionDenied }
        let transcript = try await Self.recognize(url: url)
        return VoiceLogParser.parse(transcript)
    }

    private nonisolated static func requestAuthorization() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private nonisolated static func recognize(url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let bridge = RecognitionBridge(continuation: continuation)
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US")), recognizer.isAvailable else {
                bridge.finish(.failure(VoiceTranscriptionError.unavailable))
                return
            }

            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = false
            request.taskHint = .dictation
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    bridge.finish(.failure(error))
                } else if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    bridge.finish(
                        text.isEmpty
                            ? .failure(VoiceTranscriptionError.emptyTranscript)
                            : .success(text)
                    )
                }
            }
            bridge.retain(recognizer: recognizer, task: task)
        }
    }
}

private final class RecognitionBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?

    init(continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func retain(recognizer: SFSpeechRecognizer, task: SFSpeechRecognitionTask) {
        lock.lock()
        guard continuation != nil else {
            lock.unlock()
            task.cancel()
            return
        }
        self.recognizer = recognizer
        self.task = task
        lock.unlock()
    }

    func finish(_ result: Result<String, Error>) {
        lock.lock()
        guard let pending = continuation else {
            lock.unlock()
            return
        }
        continuation = nil
        let activeTask = task
        task = nil
        recognizer = nil
        lock.unlock()

        activeTask?.finish()
        pending.resume(with: result)
    }
}

enum VoiceLogParser {
    static func parse(_ transcript: String) -> VoiceLogExtraction {
        let normalized = normalizeNumberWords(in: transcript.lowercased())
        let setRepMatch = firstMatch(
            in: normalized,
            pattern: #"\b(\d+)\s*(?:sets?\s*(?:of)?|x|by)\s*(\d+)(?:\s*reps?)?\b"#
        )
        let durationMatch = firstMatch(
            in: normalized,
            pattern: #"\b(\d+)\s*(seconds?|secs?|minutes?|mins?)\b"#
        )
        let weightMatch = firstMatch(
            in: normalized,
            pattern: #"\b(\d+(?:\.\d+)?)\s*(pounds?|lbs?|kilograms?|kgs?)\b"#
        )
        let bandMatch = firstMatch(
            in: normalized,
            pattern: #"\b(yellow|red|green|blue|black|purple|orange|light|medium|heavy)\s+band\b"#
        )

        let durationValue = durationMatch.flatMap { Int($0[1]) }.map { value in
            durationMatch?[2].hasPrefix("min") == true ? value * 60 : value
        }
        let weightUnit: WeightUnit? = weightMatch.map {
            $0[2].hasPrefix("k") ? .kg : .lb
        }

        return VoiceLogExtraction(
            transcript: transcript,
            setsCompleted: setRepMatch.flatMap { Int($0[1]) },
            repsPerSet: setRepMatch.flatMap { Int($0[2]) },
            durationSeconds: durationValue,
            bandResistance: bandMatch.map { "\($0[1].capitalized) band" },
            weightValue: weightMatch.flatMap { Double($0[1]) },
            weightUnit: weightUnit,
            eachSide: normalized.contains("each side") || normalized.contains("per side")
        )
    }

    private static func firstMatch(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }

    private static func normalizeNumberWords(in text: String) -> String {
        let numbers = [
            "one": "1", "two": "2", "three": "3", "four": "4", "five": "5",
            "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10",
            "eleven": "11", "twelve": "12", "thirteen": "13", "fourteen": "14",
            "fifteen": "15", "sixteen": "16", "seventeen": "17", "eighteen": "18",
            "nineteen": "19", "twenty": "20", "thirty": "30", "forty": "40",
            "fifty": "50", "sixty": "60"
        ]
        return numbers.reduce(text) { result, pair in
            result.replacingOccurrences(of: #"\b\#(pair.key)\b"#, with: pair.value, options: .regularExpression)
        }
    }
}
