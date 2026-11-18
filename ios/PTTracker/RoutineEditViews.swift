import SwiftUI

// MARK: - Edit mode on Today

/// Today's list in edit mode: remove with undo, drag to reorder, tap a move to change it,
/// and add moves at the end. Nothing is saved until Done.
struct RoutineEditView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var draft: RoutineEditDraft
    let onClose: () -> Void

    @State private var editingMove: EditableMove?
    @State private var isAdding = false
    @State private var isSaving = false
    @State private var confirmDiscard = false

    var body: some View {
        List {
            header
                .editListRow()
                .moveDisabled(true)

            ForEach(draft.moves) { move in
                EditMoveRow(
                    move: move,
                    onToggleRemove: { draft.setRemoved(!move.isRemoved, moveID: move.id) },
                    onOpen: { editingMove = move }
                )
                .editListRow(separator: true)
                .moveDisabled(move.isRemoved)
            }
            .onMove { draft.move(fromOffsets: $0, toOffset: $1) }

            addRow
                .editListRow()
                .moveDisabled(true)

            if draft.keptCount == 0 {
                Text("Keep at least one move in your plan, or add one.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.muted)
                    .editListRow()
                    .moveDisabled(true)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active))
        .safeAreaInset(edge: .bottom, spacing: 0) { dock }
        .signScreen()
        .onAppear { model.isTabBarHidden = true }
        .onDisappear { model.isTabBarHidden = false }
        .sheet(item: $editingMove) { move in
            MoveEditorSheet(
                exercise: move.item.exercise,
                start: MovePrescription(item: move.item),
                original: move.original.map(MovePrescription.init(item:)),
                saveTitle: "Save move",
                onSave: { prescription in
                    draft.update(moveID: move.id, prescription: prescription)
                    editingMove = nil
                },
                onRemove: {
                    draft.setRemoved(true, moveID: move.id)
                    editingMove = nil
                }
            )
        }
        .sheet(isPresented: $isAdding) {
            AddMoveSheet(planned: draft.plannedExerciseNames) { exercise, prescription, isNew in
                draft.add(exercise: exercise, prescription: prescription, isNewExercise: isNew)
                isAdding = false
            } onClose: {
                isAdding = false
            }
        }
        .confirmationDialog("Discard your changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) { onClose() }
            Button("Keep editing", role: .cancel) {}
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Editing · starts today")
            DisplayTitle(text: "Your moves.")
                .padding(.top, 6)
            InkRule().padding(.top, 20)
        }
        .padding(.top, 22)
    }

    private var addRow: some View {
        Button {
            isAdding = true
        } label: {
            HStack(spacing: 14) {
                PlusCircle()
                Text("Add a move")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(AppTheme.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: 60)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color(red: 0.788, green: 0.804, blue: 0.839), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 14)
        .padding(.bottom, 24)
    }

    private var dock: some View {
        HStack(spacing: 12) {
            Button("Cancel") {
                if draft.hasChanges { confirmDiscard = true } else { onClose() }
            }
            .buttonStyle(SignButtonStyle(kind: .ghost))
            .frame(width: 136)

            Button {
                Task { await done() }
            } label: {
                if isSaving {
                    ProgressView().tint(AppTheme.ink)
                } else {
                    Text("Done")
                }
            }
            .buttonStyle(SignButtonStyle())
            .disabled(draft.keptCount == 0)
            .accessibilityHint(draft.keptCount == 0 ? "Keep at least one move in your plan" : "")
        }
        .disabled(isSaving)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(AppTheme.paper)
    }

    private func done() async {
        guard draft.hasChanges else { return onClose() }
        isSaving = true
        let saved = await model.saveRoutine(draft)
        isSaving = false
        if saved { onClose() }
    }
}

private struct EditMoveRow: View {
    let move: EditableMove
    let onToggleRemove: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggleRemove) {
                ZStack {
                    Circle().fill(move.isRemoved ? AppTheme.inkMuted : AppTheme.ink)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(AppTheme.paper)
                        .frame(width: 12, height: 3)
                }
                .frame(width: 30, height: 30)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, -7)
            .disabled(move.isRemoved)
            .accessibilityLabel("Remove \(move.item.exercise.name)")

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(move.item.exercise.name)
                            .font(.system(size: 19, weight: .heavy))
                            .tracking(-0.2)
                            .strikethrough(move.isRemoved, color: AppTheme.inkMuted)
                            .foregroundStyle(move.isRemoved ? AppTheme.inkMuted : AppTheme.ink)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if !move.isRemoved {
                            if move.isNew {
                                RowTag(text: "New", filled: true)
                            } else if move.isChanged {
                                RowTag(text: "Changed", filled: false)
                            }
                        }
                    }
                    if let summary = move.item.shortPrescription {
                        Text(summary)
                            .font(.system(size: 15, weight: .medium))
                            .strikethrough(move.isRemoved, color: AppTheme.inkMuted)
                            .foregroundStyle(move.isRemoved ? AppTheme.inkMuted : AppTheme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(move.isRemoved)
            .accessibilityHint(move.isRemoved ? "" : "Opens the move’s prescription")

            if move.isRemoved {
                Button("Undo", action: onToggleRemove)
                    .font(.system(size: 14, weight: .heavy))
                    .underline(true, color: AppTheme.sign)
                    .foregroundStyle(AppTheme.ink)
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Undo removing \(move.item.exercise.name)")
            }
        }
        .padding(.vertical, 8)
    }
}

private struct RowTag: View {
    let text: String
    let filled: Bool

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(filled ? AppTheme.paper : AppTheme.ink)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(filled ? AppTheme.ink : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(AppTheme.ink, lineWidth: 1.5))
    }
}

private struct PlusCircle: View {
    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 14, weight: .black))
            .foregroundStyle(AppTheme.ink)
            .frame(width: 32, height: 32)
            .overlay(Circle().strokeBorder(AppTheme.ink, lineWidth: 2))
    }
}

private extension View {
    func editListRow(separator: Bool = false) -> some View {
        self
            .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
            .listRowBackground(AppTheme.paper)
            .listRowSeparator(separator ? .visible : .hidden)
            .listRowSeparatorTint(AppTheme.hair)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}

// MARK: - Edit-move sheet

/// Sheet for changing one move: reps or time, sets, and resistance.
struct MoveEditorSheet: View {
    let exercise: Exercise
    @State var start: MovePrescription
    let original: MovePrescription?
    let saveTitle: String
    let onSave: (MovePrescription) -> Void
    var onRemove: (() -> Void)?

    init(
        exercise: Exercise,
        start: MovePrescription,
        original: MovePrescription?,
        saveTitle: String,
        onSave: @escaping (MovePrescription) -> Void,
        onRemove: (() -> Void)? = nil
    ) {
        self.exercise = exercise
        _start = State(initialValue: start)
        self.original = original
        self.saveTitle = saveTitle
        self.onSave = onSave
        self.onRemove = onRemove
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SignLabel("Edit move", color: AppTheme.muted)
                MoveEditorHeading(exercise: exercise, prescription: start)
                MovePrescriptionForm(rx: $start, original: original)
                    .padding(.top, 16)
                Button(saveTitle) { onSave(start) }
                    .buttonStyle(SignButtonStyle())
                    .padding(.top, 24)
                if let onRemove {
                    Button("Remove from plan", action: onRemove)
                        .font(.system(size: 15, weight: .heavy))
                        .underline(true, color: AppTheme.sign)
                        .foregroundStyle(AppTheme.ink)
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(AppTheme.paper)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(AppTheme.paper)
    }
}

private struct MoveEditorHeading: View {
    let exercise: Exercise
    let prescription: MovePrescription

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(exercise.name)
                .font(.system(size: 28, weight: .heavy))
                .tracking(-0.9)
                .foregroundStyle(AppTheme.ink)
                .padding(.top, 2)
                .accessibilityAddTraits(.isHeader)
            // Previews the row text as you change the numbers.
            Text(prescription.summary(for: exercise))
                .font(.system(size: 16, weight: .heavy).monospacedDigit())
                .foregroundStyle(AppTheme.done)
                .accessibilityLabel("New prescription: \(prescription.summary(for: exercise))")
        }
    }
}

/// The shared controls for a move's prescription.
struct MovePrescriptionForm: View {
    @Binding var rx: MovePrescription
    let original: MovePrescription?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SignSegmented(options: MovePrescription.Count.allCases, selection: $rx.count, title: \.rawValue)
                .accessibilityLabel("Count by")

            PrescriptionStepper(
                label: "Sets",
                value: "\(rx.sets)",
                was: wasText(original?.sets, rx.sets, sameMode: true) { "\($0)" },
                isChanged: original.map { $0.sets != rx.sets } ?? false,
                canDecrement: rx.sets > 1,
                canIncrement: rx.sets < 20,
                step: { rx.sets = min(20, max(1, rx.sets + $0)) }
            )

            if rx.count == .reps {
                PrescriptionStepper(
                    label: "Reps per set",
                    value: "\(rx.reps)",
                    was: wasText(original?.reps, rx.reps, sameMode: original?.count == .reps) { "\($0)" },
                    isChanged: original.map { $0.count != .reps || $0.reps != rx.reps } ?? false,
                    canDecrement: rx.reps > 1,
                    canIncrement: rx.reps < 100,
                    step: { rx.reps = min(100, max(1, rx.reps + $0)) }
                )
            } else {
                let parts = Self.timeParts(rx.seconds)
                PrescriptionStepper(
                    label: "Time per set",
                    value: parts.value,
                    unit: parts.unit,
                    was: wasText(original?.seconds, rx.seconds, sameMode: original?.count == .time) { RoutineItem.durationText($0) },
                    isChanged: original.map { $0.count != .time || $0.seconds != rx.seconds } ?? false,
                    canDecrement: rx.seconds > 5,
                    canIncrement: rx.seconds < 600,
                    step: { rx.seconds = min(600, max(5, rx.seconds + $0 * 5)) }
                )
                HStack(spacing: 8) {
                    ForEach(MovePrescription.quickSeconds, id: \.self) { seconds in
                        ChoiceChip(text: "\(seconds)s", isOn: rx.seconds == seconds) { rx.seconds = seconds }
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("\(seconds) seconds")
                    }
                }
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) { HairRule() }
            }

            SignLabel("Resistance", color: AppTheme.muted)
                .padding(.top, 18)
            SignSegmented(options: MovePrescription.Resistance.allCases, selection: $rx.resistance, title: \.rawValue)
                .padding(.top, 8)
                .accessibilityLabel("Resistance")

            switch rx.resistance {
            case .none:
                EmptyView()
            case .band:
                FlowLayout(spacing: 8) {
                    ForEach(rx.bandOptions, id: \.self) { band in
                        ChoiceChip(text: MovePrescription.bandColorName(band), dot: BandSwatch.color(for: band), isOn: rx.band == band) {
                            rx.band = band
                        }
                        .accessibilityLabel(band)
                    }
                }
                .padding(.top, 12)
            case .weight:
                weightRow
            }
        }
    }

    private var weightRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Weight")
                    .font(.system(size: 17, weight: .heavy))
                if let original, original.resistance != .weight {
                    Text(original.resistance == .none ? "was none" : "was a band")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.muted)
                }
            }
            .foregroundStyle(AppTheme.ink)
            Spacer(minLength: 8)
            StepCircle(symbol: "minus", enabled: rx.weight > 0) { rx.weight = max(0, rx.weight - rx.weightStep) }
            Text(rx.weight.formatted())
                .font(.system(size: 26, weight: .heavy).monospacedDigit())
                .foregroundStyle(original.map { $0.resistance != .weight || $0.weight != rx.weight || $0.unit != rx.unit } ?? false ? AppTheme.done : AppTheme.ink)
                .frame(minWidth: 44)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            StepCircle(symbol: "plus", enabled: rx.weight < 500) { rx.weight = min(500, rx.weight + rx.weightStep) }
            SignSegmented(options: [WeightUnit.lb, .kg], selection: $rx.unit, title: \.rawValue, height: 34, compact: true)
                .frame(width: 84)
                .accessibilityLabel("Unit")
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
    }

    /// "was 12" under a label when the value changed within the same counting mode.
    private func wasText(_ before: Int?, _ now: Int, sameMode: Bool, format: (Int) -> String) -> String? {
        guard let before, sameMode, before != now else { return nil }
        return "was \(format(before))"
    }

    static func timeParts(_ seconds: Int) -> (value: String, unit: String?) {
        if seconds < 60 { return ("\(seconds)", "sec") }
        if seconds % 60 == 0 { return ("\(seconds / 60)", "min") }
        return ("\(seconds / 60):\(String(format: "%02d", seconds % 60))", nil)
    }
}

private struct PrescriptionStepper: View {
    let label: String
    let value: String
    var unit: String?
    let was: String?
    let isChanged: Bool
    let canDecrement: Bool
    let canIncrement: Bool
    let step: (Int) -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(AppTheme.ink)
                if let was {
                    Text(was)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.muted)
                }
            }
            Spacer(minLength: 8)
            StepCircle(symbol: "minus", enabled: canDecrement) { step(-1) }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 30, weight: .heavy).monospacedDigit())
                    .tracking(-0.9)
                if let unit {
                    Text(unit)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.muted)
                }
            }
            .foregroundStyle(isChanged ? AppTheme.done : AppTheme.ink)
            .frame(minWidth: 56)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            StepCircle(symbol: "plus", enabled: canIncrement) { step(1) }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { HairRule() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue([value, unit].compactMap { $0 }.joined(separator: " "))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if canIncrement { step(1) }
            case .decrement: if canDecrement { step(-1) }
            @unknown default: break
            }
        }
    }
}

private struct StepCircle: View {
    let symbol: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(enabled ? AppTheme.ink : AppTheme.disabled)
                .frame(width: 44, height: 44)
                .overlay(Circle().strokeBorder(enabled ? AppTheme.ink : AppTheme.hair, lineWidth: 2))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Ink-bordered segmented control; the selected segment is filled ink.
struct SignSegmented<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    var height: CGFloat = 42
    var compact = false

    init(options: [Option], selection: Binding<Option>, title: @escaping (Option) -> String, height: CGFloat = 42, compact: Bool = false) {
        self.options = options
        _selection = selection
        self.title = title
        self.height = height
        self.compact = compact
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                if index > 0 { Rectangle().fill(AppTheme.ink).frame(width: 2) }
                let isOn = option == selection
                Button {
                    selection = option
                } label: {
                    Text(compact ? title(option) : title(option).uppercased())
                        .font(.system(size: compact ? 13 : 14, weight: .heavy))
                        .tracking(compact ? 0 : 0.6)
                        .foregroundStyle(isOn ? AppTheme.paper : AppTheme.ink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(isOn ? AppTheme.ink : AppTheme.paper)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 12))
        .overlay(RoundedRectangle(cornerRadius: compact ? 10 : 12).strokeBorder(AppTheme.ink, lineWidth: 2))
    }
}

private struct ChoiceChip: View {
    let text: String
    var dot: Color?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let dot {
                    Circle().fill(dot)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
                }
                Text(text)
                    .font(.system(size: 14, weight: .heavy))
            }
            .foregroundStyle(isOn ? AppTheme.paper : AppTheme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .frame(maxWidth: dot == nil ? .infinity : nil)
            .background(isOn ? AppTheme.ink : AppTheme.paper, in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? AppTheme.ink : AppTheme.hair, lineWidth: 2))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private enum BandSwatch {
    static func color(for band: String) -> Color {
        switch MovePrescription.bandColorName(band).lowercased() {
        case "yellow": return AppTheme.sign
        case "red": return Color(red: 0.898, green: 0.282, blue: 0.302)
        case "green": return Color(red: 0.188, green: 0.643, blue: 0.424)
        case "blue": return AppTheme.done
        case "black": return AppTheme.ink
        default: return AppTheme.hair
        }
    }
}

/// Wraps chips onto as many lines as they need.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Add a move

/// Pick a move (your own, a common one, or a new name), then set its prescription.
struct AddMoveSheet: View {
    @EnvironmentObject private var model: AppModel
    let planned: Set<String>
    let onAdd: (Exercise, MovePrescription, Bool) -> Void
    let onClose: () -> Void

    @State private var library: [Exercise] = []
    @State private var query = ""
    @State private var path: [Choice] = []

    struct Choice: Hashable {
        let exercise: Exercise
        let isNew: Bool
    }

    var body: some View {
        NavigationStack(path: $path) {
            picker
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Choice.self) { choice in
                    AddMovePrescriptionPage(choice: choice) { prescription in
                        onAdd(choice.exercise, prescription, choice.isNew)
                    }
                }
        }
        .task { library = await model.exerciseLibrary() }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(AppTheme.paper)
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func matches(_ name: String) -> Bool {
        trimmedQuery.isEmpty || name.localizedCaseInsensitiveContains(trimmedQuery)
    }

    private var yourMoves: [Exercise] {
        library.filter { !planned.contains($0.name.lowercased()) && matches($0.name) }
    }

    private var commonMoves: [(name: String, mode: TrackingMode)] {
        let known = Set(library.map { $0.name.lowercased() }).union(planned)
        return CommonMoves.all.filter { !known.contains($0.name.lowercased()) && matches($0.name) }
    }

    private var canCreate: Bool {
        guard !trimmedQuery.isEmpty else { return false }
        let name = trimmedQuery.lowercased()
        return !planned.contains(name)
            && !library.contains { $0.name.lowercased() == name }
            && !CommonMoves.all.contains { $0.name.lowercased() == name }
    }

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Add a move")
                        .font(.system(size: 30, weight: .heavy))
                        .tracking(-0.9)
                        .foregroundStyle(AppTheme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Close", action: onClose)
                        .font(.system(size: 13, weight: .heavy))
                        .textCase(.uppercase)
                        .foregroundStyle(AppTheme.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .overlay(Capsule().strokeBorder(AppTheme.ink, lineWidth: 2))
                        .buttonStyle(.plain)
                }

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AppTheme.muted)
                    TextField("Search or type a new move", text: $query)
                        .font(.system(size: 17, weight: .semibold))
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                }
                .signField(height: 52)
                .padding(.top, 18)

                if canCreate {
                    Button {
                        path.append(Choice(exercise: Exercise(id: UUID(), name: trimmedQuery), isNew: true))
                    } label: {
                        HStack(spacing: 14) {
                            PlusCircle()
                            Text("Create “\(trimmedQuery)”")
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundStyle(AppTheme.ink)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 60)
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(AppTheme.ink, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)
                }

                if !yourMoves.isEmpty {
                    section("Your moves")
                    ForEach(yourMoves) { exercise in
                        pickRow(name: exercise.name, mode: exercise.trackingMode) {
                            path.append(Choice(exercise: exercise, isNew: false))
                        }
                    }
                }

                if !commonMoves.isEmpty {
                    section("Common moves")
                    ForEach(commonMoves, id: \.name) { move in
                        pickRow(name: move.name, mode: move.mode) {
                            path.append(Choice(exercise: Exercise(id: UUID(), name: move.name, trackingMode: move.mode), isNew: true))
                        }
                    }
                }

                if trimmedQuery.isEmpty {
                    Text("Not listed? Type its name above to create it.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.muted)
                        .padding(.top, 18)
                } else if yourMoves.isEmpty && commonMoves.isEmpty && !canCreate {
                    Text("That move is already in your plan.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.muted)
                        .padding(.top, 18)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppTheme.paper)
    }

    private func section(_ title: String) -> some View {
        SignLabel(title, color: AppTheme.muted)
            .padding(.top, 22)
            .padding(.bottom, 2)
    }

    private func pickRow(name: String, mode: TrackingMode?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(AppTheme.ink)
                    Text(mode == .duration ? "Time" : "Reps")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer(minLength: 8)
                PlusCircle()
            }
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) { HairRule() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(name)")
    }
}

private struct AddMovePrescriptionPage: View {
    let choice: AddMoveSheet.Choice
    let onAdd: (MovePrescription) -> Void
    @State private var rx: MovePrescription

    init(choice: AddMoveSheet.Choice, onAdd: @escaping (MovePrescription) -> Void) {
        self.choice = choice
        self.onAdd = onAdd
        _rx = State(initialValue: .defaults(for: choice.exercise.trackingMode))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SignBackButton(title: "Add a move")
                MoveEditorHeading(exercise: choice.exercise, prescription: rx)
                    .padding(.top, 6)
                MovePrescriptionForm(rx: $rx, original: nil)
                    .padding(.top, 16)
                Button("Add to plan") { onAdd(rx) }
                    .buttonStyle(SignButtonStyle())
                    .padding(.top, 24)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(AppTheme.paper)
        .toolbar(.hidden, for: .navigationBar)
    }
}
