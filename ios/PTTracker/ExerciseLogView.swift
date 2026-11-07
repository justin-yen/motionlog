import SwiftUI

struct ExerciseLogView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let item: RoutineItem

    @StateObject private var recorder = AudioRecorder()
    @State private var transcriber = VoiceLogTranscriber()
    @State private var sets = ""
    @State private var reps = ""
    @State private var duration = ""
    @State private var band = ""
    @State private var weight = ""
    @State private var weightUnit: WeightUnit = .lb
    @State private var notes = ""
    @State private var extraction: VoiceLogExtraction?
    @State private var isTranscribing = false
    @State private var transcriptionError: String?

    var body: some View {
        Form {
            if item.exercise.trackingMode != .duration {
                Section("Repetitions") {
                    numberField("Sets completed", text: $sets)
                    numberField("Reps per set", text: $reps)
                }
            }

            if item.exercise.trackingMode != .reps {
                Section("Time") {
                    numberField("Seconds completed", text: $duration)
                }
            }

            Section("Resistance or weight") {
                TextField("Band, color, or resistance", text: $band)
                HStack {
                    TextField("Weight", text: $weight)
                        .keyboardType(.decimalPad)
                    Picker("Unit", selection: $weightUnit) {
                        ForEach(WeightUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
            }

            Section("Notes") {
                TextField("How did it feel?", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section {
                Button {
                    Task { await toggleRecording() }
                } label: {
                    Label(
                        voiceButtonTitle,
                        systemImage: recorder.isRecording ? "stop.fill" : "mic.fill"
                    )
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.white)
                }
                .listRowBackground(AppTheme.voiceRed)
                .disabled(isTranscribing)

                if recorder.isRecording {
                    HStack {
                        Circle().fill(.red).frame(width: 8, height: 8)
                        Text("Recording…")
                    }
                } else if recorder.recordingURL != nil {
                    Label("Voice note attached", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                if let extraction {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("“\(extraction.transcript)”")
                            .foregroundStyle(.secondary)
                        Text("Review the filled fields above before saving.")
                            .font(.footnote.bold())
                    }
                } else if let transcriptionError {
                    Text(transcriptionError).foregroundStyle(.orange)
                }
                Text("Audio, transcript, and confirmed structured values are retained with this session.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Save exercise") {
                    Task {
                        recorder.stop()
                        let saved = await model.save(draft)
                        if saved { dismiss() }
                    }
                }
                .frame(maxWidth: .infinity)
                .disabled(model.isLoading || isTranscribing || recorder.isRecording)
            }
        }
        .navigationTitle(item.exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadPrescriptionDefaults)
        .alert("Recording unavailable", isPresented: recordingErrorBinding) {
            Button("OK") { recorder.errorMessage = nil }
        } message: {
            Text(recorder.errorMessage ?? "Please try again.")
        }
    }

    private func numberField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text).keyboardType(.numberPad)
    }

    private var draft: ExerciseLogDraft {
        ExerciseLogDraft(
            exercise: item.exercise,
            routineItemID: item.id,
            setsCompleted: Int(sets),
            repsPerSet: Int(reps),
            durationSeconds: Int(duration),
            bandResistance: band.nilIfBlank,
            weightValue: Double(weight),
            weightUnit: weight.nilIfBlank == nil ? nil : weightUnit,
            notes: notes.nilIfBlank,
            localAudioURL: recorder.recordingURL,
            voiceExtraction: extraction
        )
    }

    private var voiceButtonTitle: String {
        if recorder.isRecording { return "Stop and transcribe" }
        if isTranscribing { return "Transcribing…" }
        return recorder.recordingURL == nil ? "Say what you did" : "Replace voice note"
    }

    private func toggleRecording() async {
        transcriptionError = nil
        if recorder.isRecording {
            recorder.stop()
            await transcribeRecording()
        } else {
            extraction = nil
            await recorder.toggle()
        }
    }

    private func transcribeRecording() async {
        guard let url = recorder.recordingURL else { return }
        isTranscribing = true
        defer { isTranscribing = false }
        do {
            let result = try await transcriber.transcribe(url: url)
            extraction = result
            apply(result)
        } catch {
            transcriptionError = error.localizedDescription
        }
    }

    private func apply(_ result: VoiceLogExtraction) {
        if let value = result.setsCompleted { sets = String(value) }
        if let value = result.repsPerSet { reps = String(value) }
        if let value = result.durationSeconds { duration = String(value) }
        if let value = result.bandResistance { band = value }
        if let value = result.weightValue { weight = value.formatted() }
        if let value = result.weightUnit { weightUnit = value }
        if result.eachSide, !notes.lowercased().contains("each side") {
            notes = notes.nilIfBlank.map { "\($0) · Each side" } ?? "Each side"
        }
    }

    private func loadPrescriptionDefaults() {
        sets = item.targetSets.map(String.init) ?? ""
        reps = item.targetReps.map(String.init) ?? ""
        duration = item.targetDurationSeconds.map(String.init) ?? ""
        band = item.targetBandResistance ?? ""
        weight = item.targetWeightValue.map { String($0) } ?? ""
        weightUnit = item.targetWeightUnit ?? .lb
    }

    private var recordingErrorBinding: Binding<Bool> {
        Binding(
            get: { recorder.errorMessage != nil },
            set: { if !$0 { recorder.errorMessage = nil } }
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
