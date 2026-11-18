import SwiftUI

struct ExerciseLogView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let item: RoutineItem

    @StateObject private var recorder = AudioRecorder()
    @State private var transcriber = VoiceLogTranscriber()
    @State private var sets: Int?
    @State private var reps: Int?
    @State private var duration: Int?
    @State private var band = ""
    @State private var weight = ""
    @State private var weightUnit: WeightUnit = .lb
    @State private var pain: Double?
    @State private var notes = ""
    @State private var extraction: VoiceLogExtraction?
    @State private var isTranscribing = false
    @State private var transcriptionError: String?
    @State private var showVoiceConfirm = false
    @State private var didLoadDefaults = false

    private var tracksReps: Bool { item.exercise.trackingMode != .duration }
    private var tracksTime: Bool { item.exercise.trackingMode != .reps }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    SignBackButton(title: item.exercise.name)
                    Spacer(minLength: 12)
                    if let goal = item.goalLine { Eyebrow(text: goal).lineLimit(1) }
                }

                DisplayTitle(text: "Log it.")
                    .padding(.top, 14)

                voiceCard
                    .padding(.top, 20)

                if let transcriptionError {
                    Text(transcriptionError)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .padding(.top, 10)
                }

                HStack(spacing: 12) {
                    SignLabel("Or enter it", color: AppTheme.muted)
                    HairRule()
                }
                .padding(.top, 22)
                .padding(.bottom, 14)

                VStack(alignment: .leading, spacing: 14) {
                    if tracksReps {
                        HStack(spacing: 12) {
                            labeled("Sets") { StepperField(value: $sets, range: 0...20, accessibilityName: "Sets") }
                            labeled("Reps / set") { StepperField(value: $reps, range: 0...100, accessibilityName: "Reps per set") }
                        }
                    }
                    if tracksTime {
                        labeled("Time") {
                            StepperField(value: $duration, range: 0...3600, step: 5, accessibilityName: "Seconds", format: { RoutineItem.durationText($0) })
                        }
                    }

                    labeled("Band or resistance") {
                        TextField("", text: $band, prompt: Text("e.g. Red band").foregroundStyle(AppTheme.disabled))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppTheme.ink)
                            .signField()
                    }

                    labeled("Weight") {
                        HStack(spacing: 10) {
                            TextField("", text: $weight, prompt: Text("Optional").foregroundStyle(AppTheme.disabled))
                                .keyboardType(.decimalPad)
                                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                                .foregroundStyle(AppTheme.ink)
                                .signField()
                            UnitToggle(selection: $weightUnit)
                        }
                    }

                    PainScale(value: $pain)
                        .padding(.top, 2)

                    labeled("Notes") {
                        TextField("", text: $notes, prompt: Text("How did it feel?").foregroundStyle(AppTheme.disabled), axis: .vertical)
                            .lineLimit(2...6)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppTheme.ink)
                            .padding(.vertical, 14)
                            .signField(height: 52)
                    }
                }

                Text("Voice notes keep the audio, the transcript, and the values you confirm.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.muted)
                    .padding(.top, 16)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                HairRule()
                Button {
                    Task { await save() }
                } label: {
                    if model.isLoading { ProgressView().tint(AppTheme.paper) } else { Text("Save exercise") }
                }
                .buttonStyle(SignButtonStyle(kind: .ink))
                .disabled(model.isLoading || isTranscribing || recorder.isRecording)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 4)
            }
            .background(AppTheme.paper)
        }
        .signScreen()
        .onAppear {
            model.isTabBarHidden = true
            loadPrescriptionDefaults()
        }
        .onDisappear { model.isTabBarHidden = false }
        .fullScreenCover(isPresented: $showVoiceConfirm) {
            if let extraction {
                VoiceConfirmView(
                    exerciseName: item.exercise.name,
                    extraction: extraction,
                    isSaving: model.isLoading,
                    onConfirm: { Task { await save() } },
                    onEdit: { showVoiceConfirm = false }
                )
            }
        }
        .alert("Recording unavailable", isPresented: recordingErrorBinding) {
            Button("OK") { recorder.errorMessage = nil }
        } message: {
            Text(recorder.errorMessage ?? "Please try again.")
        }
    }

    // MARK: Voice card

    private var voiceCard: some View {
        Button {
            Task { await toggleRecording() }
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(AppTheme.ink)
                    if isTranscribing {
                        ProgressView().tint(AppTheme.sign)
                    } else {
                        Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(AppTheme.sign)
                    }
                }
                .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 3) {
                    Text(voiceTitle)
                        .font(.system(size: 20, weight: .heavy))
                        .tracking(-0.2)
                    Text(voiceSubtitle)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(2)
                }
                .foregroundStyle(AppTheme.ink)
                Spacer(minLength: 0)
                if recorder.isRecording {
                    Circle().fill(Color.red).frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .signCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isTranscribing)
        .accessibilityLabel(voiceTitle)
        .accessibilityHint(voiceSubtitle)
    }

    private var voiceTitle: String {
        if recorder.isRecording { return "Listening…" }
        if isTranscribing { return "Reading it back…" }
        return recorder.recordingURL == nil ? "Say what you did" : "Replace voice note"
    }

    private var voiceSubtitle: String {
        if recorder.isRecording { return "Tap to stop when you’re done." }
        if isTranscribing { return "Turning your note into sets, reps and pain." }
        if extraction != nil { return "Voice note attached. Tap to record again." }
        return tracksReps ? "“Two sets of twelve, felt easy.”" : "“Held it for about fifty seconds.”"
    }

    // MARK: Helpers

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SignLabel(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var draft: ExerciseLogDraft {
        ExerciseLogDraft(
            exercise: item.exercise,
            routineItemID: item.id,
            setsCompleted: tracksReps ? sets : nil,
            repsPerSet: tracksReps ? reps : nil,
            durationSeconds: tracksTime ? duration : nil,
            bandResistance: band.nilIfBlank,
            weightValue: Double(weight),
            weightUnit: weight.nilIfBlank == nil ? nil : weightUnit,
            painAfter: pain.map { Int($0.rounded()) },
            notes: notes.nilIfBlank,
            localAudioURL: recorder.recordingURL,
            voiceExtraction: extraction
        )
    }

    private func save() async {
        recorder.stop()
        let saved = await model.save(draft)
        if saved {
            showVoiceConfirm = false
            dismiss()
        }
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
            let transcript = try await transcriber.transcribe(url: url)
            let result = await model.parseVoiceLog(transcript: transcript, item: item)
            extraction = result
            apply(result)
            showVoiceConfirm = true
        } catch {
            transcriptionError = error.localizedDescription
        }
    }

    private func apply(_ result: VoiceLogExtraction) {
        sets = result.setsCompleted
        reps = result.repsPerSet
        duration = result.durationSeconds
        band = result.bandResistance ?? ""
        weight = result.weightValue?.formatted() ?? ""
        if let value = result.weightUnit { weightUnit = value }
        pain = result.painAfter.map(Double.init)
        notes = result.noteBullets.map { "• \($0)" }.joined(separator: "\n")
    }

    private func loadPrescriptionDefaults() {
        guard !didLoadDefaults else { return }
        didLoadDefaults = true
        sets = item.targetSets
        reps = item.targetReps
        duration = item.targetDurationSeconds
        band = item.targetBandResistance ?? ""
        weight = item.targetWeightValue.map { $0.formatted() } ?? ""
        weightUnit = item.targetWeightUnit ?? .lb
    }

    private var recordingErrorBinding: Binding<Bool> {
        Binding(
            get: { recorder.errorMessage != nil },
            set: { if !$0 { recorder.errorMessage = nil } }
        )
    }
}

// MARK: - Controls

private struct StepperField: View {
    @Binding var value: Int?
    let range: ClosedRange<Int>
    var step = 1
    let accessibilityName: String
    var format: (Int) -> String = { "\($0)" }

    var body: some View {
        HStack {
            stepButton("minus", delta: -step)
                .disabled((value ?? 0) <= range.lowerBound)
            Spacer(minLength: 4)
            Text(value.map(format) ?? "–")
                .font(.system(size: 22, weight: .heavy).monospacedDigit())
                .foregroundStyle(value == nil ? AppTheme.disabled : AppTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            stepButton("plus", delta: step)
                .disabled((value ?? 0) >= range.upperBound)
        }
        .padding(.horizontal, -6)
        .signField()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue(value.map(format) ?? "Not entered")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: change(by: step)
            case .decrement: change(by: -step)
            @unknown default: break
            }
        }
    }

    private func stepButton(_ symbol: String, delta: Int) -> some View {
        Button {
            change(by: delta)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .heavy))
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppTheme.ink)
    }

    private func change(by delta: Int) {
        let next = (value ?? 0) + delta
        value = min(max(next, range.lowerBound), range.upperBound)
    }
}

private struct UnitToggle: View {
    @Binding var selection: WeightUnit

    var body: some View {
        HStack(spacing: 0) {
            ForEach(WeightUnit.allCases, id: \.self) { unit in
                let isOn = unit == selection
                Button {
                    selection = unit
                } label: {
                    Text(unit.rawValue)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(isOn ? AppTheme.paper : AppTheme.ink)
                        .frame(width: 50, height: 54)
                        .background(isOn ? AppTheme.ink : AppTheme.paper)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(AppTheme.ink, lineWidth: 2))
        .accessibilityLabel("Weight unit")
    }
}

/// 0–10 pain scale. Starts unset so "no answer" isn't saved as zero.
struct PainScale: View {
    @Binding var value: Double?

    private let thumb: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SignLabel("Pain")
                Spacer()
                if let value {
                    (Text("\(Int(value))").foregroundStyle(AppTheme.ink)
                     + Text(" / 10").foregroundStyle(AppTheme.muted).fontWeight(.semibold))
                        .font(.system(size: 15, weight: .heavy).monospacedDigit())
                } else {
                    Text("Tap to rate")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.muted)
                }
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                let fraction = (value ?? 0) / 10
                let thumbX = (width - thumb) * fraction
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.paper)
                        .overlay(Capsule().strokeBorder(AppTheme.ink, lineWidth: 2))
                        .frame(height: 12)
                    if value != nil {
                        Capsule().fill(AppTheme.sign)
                            .overlay(Capsule().strokeBorder(AppTheme.ink, lineWidth: 2))
                            .frame(width: max(thumbX + thumb / 2, 12), height: 12)
                    }
                    Circle()
                        .fill(value == nil ? AppTheme.paper : AppTheme.ink)
                        .overlay(Circle().strokeBorder(AppTheme.ink, lineWidth: 2))
                        .background(Circle().fill(AppTheme.sign).offset(x: 2, y: 2).opacity(value == nil ? 0 : 1))
                        .frame(width: thumb, height: thumb)
                        .offset(x: thumbX)
                }
                .frame(height: 44)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let raw = (drag.location.x - thumb / 2) / max(width - thumb, 1)
                            let next = (min(max(raw, 0), 1) * 10).rounded()
                            if next != value {
                                value = next
                                UISelectionFeedbackGenerator().selectionChanged()
                            }
                        }
                )
            }
            .frame(height: 44)

            HStack {
                Text("0 · None")
                Spacer()
                if value != nil {
                    Button("Clear") { value = nil }
                        .buttonStyle(.plain)
                        .underline()
                }
                Spacer()
                Text("10 · Worst")
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(AppTheme.muted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pain during or after, 0 to 10")
        .accessibilityValue(value.map { "\(Int($0)) out of 10" } ?? "Not entered")
        .accessibilityAdjustableAction { direction in
            let current = value ?? 0
            switch direction {
            case .increment: value = min(current + 1, 10)
            case .decrement: value = max(current - 1, 0)
            @unknown default: break
            }
        }
    }
}

// MARK: - Voice confirm

struct VoiceConfirmView: View {
    let exerciseName: String
    let extraction: VoiceLogExtraction
    let isSaving: Bool
    let onConfirm: () -> Void
    let onEdit: () -> Void

    var body: some View {
        ZStack {
            AppTheme.ink.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Button(action: onEdit) {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark").font(.system(size: 16, weight: .heavy))
                                Text("CLOSE").font(.system(size: 14, weight: .heavy)).tracking(1.1)
                            }
                            .foregroundStyle(AppTheme.paper)
                            .frame(height: 44)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Eyebrow(text: exerciseName, color: AppTheme.inkMuted)
                    }

                    Eyebrow(text: "You said", color: AppTheme.sign)
                        .padding(.top, 30)
                    Text("“\(extraction.transcript)”")
                        .font(.system(size: 26, weight: .bold))
                        .tracking(-0.5)
                        .lineSpacing(4)
                        .foregroundStyle(AppTheme.paper)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)

                    if rows.isEmpty {
                        Text("No sets, reps, or pain were picked up. Tap Edit to fill them in.")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.inkMuted)
                            .padding(.top, 28)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                                HStack(alignment: .firstTextBaseline, spacing: 20) {
                                    SignLabel(row.label)
                                    Spacer(minLength: 0)
                                    Text(row.value)
                                        .font(.system(size: row.isNote ? 16 : 20, weight: row.isNote ? .bold : .heavy).monospacedDigit())
                                        .multilineTextAlignment(.trailing)
                                        .foregroundStyle(AppTheme.ink)
                                }
                                .padding(.vertical, 14)
                                if index < rows.count - 1 {
                                    Rectangle().fill(AppTheme.ink).frame(height: 1.5)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)
                        .signCard(shadow: AppTheme.inkSoft)
                        .padding(.top, 30)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 14) {
                    Button(action: onConfirm) {
                        if isSaving { ProgressView().tint(AppTheme.ink) } else { Text("Confirm & save") }
                    }
                    .buttonStyle(SignButtonStyle())
                    .disabled(isSaving)
                    Button("Edit before saving", action: onEdit)
                        .font(.system(size: 15, weight: .bold))
                        .underline()
                        .foregroundStyle(AppTheme.paper)
                        .buttonStyle(.plain)
                        .frame(height: 32)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(AppTheme.ink)
            }
        }
        .preferredColorScheme(.dark)
    }

    private struct Row {
        let label: String
        let value: String
        var isNote = false
    }

    private var rows: [Row] {
        var rows: [Row] = []
        if let sets = extraction.setsCompleted { rows.append(Row(label: "Sets", value: "\(sets)")) }
        if let reps = extraction.repsPerSet { rows.append(Row(label: "Reps / set", value: "\(reps)")) }
        if let seconds = extraction.durationSeconds { rows.append(Row(label: "Time", value: RoutineItem.durationText(seconds))) }
        if extraction.eachSide { rows.append(Row(label: "Sides", value: "Each side")) }
        if let band = extraction.bandResistance { rows.append(Row(label: "Band", value: band)) }
        if let weight = extraction.weightValue {
            rows.append(Row(label: "Weight", value: "\(weight.formatted()) \(extraction.weightUnit?.rawValue ?? "")"))
        }
        if let pain = extraction.painAfter { rows.append(Row(label: "Pain", value: "\(pain) / 10")) }
        if !extraction.noteBullets.isEmpty {
            rows.append(Row(label: "Note", value: extraction.noteBullets.joined(separator: "\n"), isNote: true))
        }
        return rows
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
