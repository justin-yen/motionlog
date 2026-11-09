@preconcurrency import Speech
import AVFoundation
import Foundation
import OSLog

enum VoiceTranscriptionError: LocalizedError {
    case permissionDenied
    case unavailable
    case emptyTranscript
    case developmentServerUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Speech recognition permission is needed to convert the recording into exercise details."
        case .unavailable:
            "Speech recognition is temporarily unavailable. The raw recording is still attached."
        case .emptyTranscript:
            "No speech could be recognized. The raw recording is still attached."
        case .developmentServerUnavailable:
            "The Simulator transcription helper is unavailable. Run the app from the shared PTTracker Xcode scheme, then try again. The raw recording is still attached."
        }
    }
}

@MainActor
final class VoiceLogTranscriber {
    private nonisolated static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MotionLog",
        category: "VoiceTranscription"
    )

    func transcribe(url: URL) async throws -> String {
        guard await Self.requestAuthorization() else { throw VoiceTranscriptionError.permissionDenied }
        let transcript: String
        if #available(iOS 26.0, *) {
            do {
                transcript = try await Self.recognizeOnDevice(url: url)
            } catch {
                Self.logger.notice("On-device transcription failed; trying Simulator helper. Error: \(String(describing: error), privacy: .public)")
                #if targetEnvironment(simulator)
                transcript = try await Self.recognizeWithDevelopmentServer(url: url)
                #else
                throw error
                #endif
            }
        } else {
            do {
                transcript = try await Self.recognizeLegacy(url: url)
            } catch {
                Self.logger.notice("Legacy transcription failed; trying Simulator helper. Error: \(String(describing: error), privacy: .public)")
                #if targetEnvironment(simulator)
                transcript = try await Self.recognizeWithDevelopmentServer(url: url)
                #else
                throw error
                #endif
            }
        }
        Self.logger.info("Transcription completed: characters=\(transcript.count)")
        return transcript
    }

    private nonisolated static func requestAuthorization() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    @available(iOS 26.0, *)
    private nonisolated static func recognizeOnDevice(url: URL) async throws -> String {
        if SpeechTranscriber.isAvailable,
           let locale = await SpeechTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: "en_US")
           ) {
            return try await recognizeWithSpeechTranscriber(url: url, locale: locale)
        }
        return try await recognizeWithDictationTranscriber(url: url)
    }

    @available(iOS 26.0, *)
    private nonisolated static func recognizeWithSpeechTranscriber(
        url: URL,
        locale: Locale
    ) async throws -> String {
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        if let installationRequest = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) {
            try await installationRequest.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let resultTask = Task<String, Error> {
            var parts: [String] = []
            for try await result in transcriber.results where result.isFinal {
                let text = String(result.text.characters)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { parts.append(text) }
            }
            return parts.joined(separator: " ")
        }

        do {
            if let finalTime = try await analyzeConvertedAudio(
                at: url,
                modules: [transcriber],
                analyzer: analyzer
            ) {
                try await analyzer.finalizeAndFinish(through: finalTime)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            let transcript = try await resultTask.value
            guard !transcript.isEmpty else { throw VoiceTranscriptionError.emptyTranscript }
            return transcript
        } catch {
            resultTask.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    @available(iOS 26.0, *)
    private nonisolated static func recognizeWithDictationTranscriber(url: URL) async throws -> String {
        guard let locale = await DictationTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: "en_US")
        ) else {
            throw VoiceTranscriptionError.unavailable
        }

        let transcriber = DictationTranscriber(locale: locale, preset: .shortDictation)
        if let installationRequest = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) {
            try await installationRequest.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let resultTask = Task<String, Error> {
            var parts: [String] = []
            for try await result in transcriber.results where result.isFinal {
                let text = String(result.text.characters)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { parts.append(text) }
            }
            return parts.joined(separator: " ")
        }

        do {
            if let finalTime = try await analyzeConvertedAudio(
                at: url,
                modules: [transcriber],
                analyzer: analyzer
            ) {
                try await analyzer.finalizeAndFinish(through: finalTime)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            let transcript = try await resultTask.value
            guard !transcript.isEmpty else { throw VoiceTranscriptionError.emptyTranscript }
            return transcript
        } catch {
            resultTask.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    @available(iOS 26.0, *)
    private nonisolated static func analyzeConvertedAudio(
        at url: URL,
        modules: [any SpeechModule],
        analyzer: SpeechAnalyzer
    ) async throws -> CMTime? {
        let audioFile = try AVAudioFile(forReading: url)
        var analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: modules,
            considering: audioFile.processingFormat
        )
        if analyzerFormat == nil {
            analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules)
        }
        guard let analyzerFormat,
              let converter = AVAudioConverter(from: audioFile.processingFormat, to: analyzerFormat),
        let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: AVAudioFrameCount(audioFile.length)
        ) else {
            throw VoiceTranscriptionError.unavailable
        }
        try audioFile.read(into: inputBuffer)

        let sampleRateRatio = analyzerFormat.sampleRate / audioFile.processingFormat.sampleRate
        let outputCapacity = max(
            1,
            AVAudioFrameCount((Double(inputBuffer.frameLength) * sampleRateRatio).rounded(.up))
        )
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: analyzerFormat,
            frameCapacity: outputCapacity
        ) else {
            throw VoiceTranscriptionError.unavailable
        }

        var suppliedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            if suppliedInput {
                inputStatus.pointee = .endOfStream
                return nil
            }
            suppliedInput = true
            inputStatus.pointee = .haveData
            return inputBuffer
        }
        if let conversionError { throw conversionError }
        guard status == .haveData || status == .endOfStream else {
            throw VoiceTranscriptionError.unavailable
        }

        let input = AnalyzerInput(buffer: outputBuffer)
        let sequence = AsyncStream<AnalyzerInput> { continuation in
            continuation.yield(input)
            continuation.finish()
        }
        return try await analyzer.analyzeSequence(sequence)
    }

    private nonisolated static func recognizeLegacy(url: URL) async throws -> String {
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
            bridge.scheduleTimeout()
        }
    }

    #if targetEnvironment(simulator)
    private nonisolated static func recognizeWithDevelopmentServer(url: URL) async throws -> String {
        guard let endpoint = URL(string: "http://127.0.0.1:55330/transcribe") else {
            throw VoiceTranscriptionError.unavailable
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Data(contentsOf: url, options: .mappedIfSafe)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                logger.error("Simulator transcription helper returned a non-success response")
                throw VoiceTranscriptionError.developmentServerUnavailable
            }
            let payload = try JSONDecoder().decode(DevelopmentTranscriptionResponse.self, from: data)
            let transcript = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else { throw VoiceTranscriptionError.emptyTranscript }
            logger.info("Simulator transcription helper completed: characters=\(transcript.count)")
            return transcript
        } catch let error as VoiceTranscriptionError {
            throw error
        } catch {
            logger.error("Simulator transcription helper failed: \(String(describing: error), privacy: .public)")
            throw VoiceTranscriptionError.developmentServerUnavailable
        }
    }
    #endif
}

#if targetEnvironment(simulator)
private struct DevelopmentTranscriptionResponse: Decodable {
    let text: String
}
#endif

private final class RecognitionBridge: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var timeoutTask: Task<Void, Never>?

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

    func scheduleTimeout() {
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            self?.finish(.failure(VoiceTranscriptionError.unavailable))
        }

        lock.lock()
        guard continuation != nil else {
            lock.unlock()
            timeoutTask.cancel()
            return
        }
        self.timeoutTask = timeoutTask
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
        let activeTimeoutTask = timeoutTask
        task = nil
        timeoutTask = nil
        recognizer = nil
        lock.unlock()

        activeTimeoutTask?.cancel()
        activeTask?.finish()
        pending.resume(with: result)
    }
}

enum VoiceLogParser {
    private static let setRepPattern = #"\b(\d+)\s*(?:sets?\s*(?:of)?|x|by)\s*(\d+)(?:\s*reps?)?\b"#
    private static let durationPattern = #"\b(\d+)\s*(seconds?|secs?|minutes?|mins?)\b"#
    private static let weightPattern = #"\b(\d+(?:\.\d+)?)\s*(pounds?|lbs?|kilograms?|kgs?)\b"#
    private static let bandPattern = #"\b(yellow|red|green|blue|black|purple|orange|light|medium|heavy)\s+band\b"#
    private static let painAfterNumberPattern = #"\bpain(?:\s+(?:level|score))?(?:\s+(?:(?:was|is)(?:\s+(?:at|out\s+of))?|at))?\s*(?:a\s*)?(\d+)(?:\s*(?:out\s+of|/)\s*10)?\b"#
    private static let painBeforeNumberPattern = #"\b(\d+)\s*(?:(?:out\s+of|/)\s*10)\s+(?:for\s+)?pain\b"#

    static func parse(_ transcript: String) -> VoiceLogExtraction {
        let normalized = normalizeNumberWords(in: transcript.lowercased())
        let setRepMatch = firstMatch(in: normalized, pattern: setRepPattern)
        let durationMatch = firstMatch(in: normalized, pattern: durationPattern)
        let weightMatch = firstMatch(in: normalized, pattern: weightPattern)
        let bandMatch = firstMatch(in: normalized, pattern: bandPattern)
        let painAfter = firstMatch(in: normalized, pattern: painAfterNumberPattern)
            .flatMap { Int($0[1]) }
            ?? firstMatch(in: normalized, pattern: painBeforeNumberPattern).flatMap { Int($0[1]) }
        let eachSide = normalized.contains("each side") || normalized.contains("per side")

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
            painAfter: painAfter.flatMap { 0...10 ~= $0 ? $0 : nil },
            eachSide: eachSide,
            noteBullets: noteBullets(from: normalized, eachSide: eachSide)
        )
    }

    private static func noteBullets(from normalized: String, eachSide: Bool) -> [String] {
        var remainder = normalized
        [
            setRepPattern,
            durationPattern,
            weightPattern,
            bandPattern,
            painAfterNumberPattern,
            painBeforeNumberPattern,
            #"\b(?:each|per)\s+side\b"#
        ].forEach { remainder = replacingMatches(in: remainder, pattern: $0, with: " ") }

        remainder = replacingMatches(
            in: remainder,
            pattern: #"\b(?:um+|uh+|erm+|hmm+|like|basically|actually|you\s+know)\b"#,
            with: " "
        )
        remainder = replacingMatches(
            in: remainder,
            pattern: #"\b(?:i\s+(?:did|completed|performed)|that\s+was|it\s+was)\b"#,
            with: " "
        )

        let separators = try? NSRegularExpression(
            pattern: #"[.!?;,]+|\s+and\s+(?=(?:i|my|it|the|there)\b)|\s+(?=i\s+(?:had|felt|noticed|needed|could|was|am|moved|used|stopped|started)\b)"#,
            options: .caseInsensitive
        )
        let range = NSRange(remainder.startIndex..., in: remainder)
        let separated = separators?.stringByReplacingMatches(
            in: remainder,
            range: range,
            withTemplate: "\n"
        ) ?? remainder

        var bullets = separated
            .components(separatedBy: .newlines)
            .compactMap(cleanNoteFragment)
        if eachSide { bullets.insert("Each side", at: 0) }
        var seen = Set<String>()
        return bullets.filter { seen.insert($0.lowercased()).inserted }
    }

    private static func cleanNoteFragment(_ fragment: String) -> String? {
        var value = fragment.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(
            of: #"^(?:(?:and|but|then|so|with|for|my|i)\s+)+"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(
            of: #"^(?:was|is)\s+"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(
            of: #"\s+(?:my|i)$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "-–—:,. "))

        let ignored = ["", "with", "for", "my", "i", "completed", "done"]
        guard !ignored.contains(value.lowercased()), value.count > 2 else { return nil }
        return value.prefix(1).uppercased() + value.dropFirst()
    }

    private static func replacingMatches(in text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return text
        }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: replacement
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
