import SwiftUI

struct TodayRoutineView: View {
    @EnvironmentObject private var model: AppModel
    /// Non-nil while the plan is being edited; holds every change until Done.
    @State private var editDraft: RoutineEditDraft?

    var body: some View {
        Group {
            if let draft = editDraft {
                RoutineEditView(
                    draft: Binding(get: { editDraft ?? draft }, set: { editDraft = $0 }),
                    onClose: { editDraft = nil }
                )
            } else {
                routineList
            }
        }
        .navigationDestination(for: RoutineItem.self) { item in
            ExerciseDetailView(itemID: item.id, fallback: item)
        }
    }

    private var routineList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    Eyebrow(text: Self.dateLine(.now))
                    Spacer(minLength: 0)
                    if let routine = model.routine, !routine.routineItems.isEmpty {
                        Button {
                            editDraft = RoutineEditDraft(routine: routine)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 13, weight: .heavy))
                                Text("EDIT")
                                    .font(.system(size: 13, weight: .heavy))
                                    .tracking(0.6)
                            }
                            .foregroundStyle(AppTheme.ink)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(AppTheme.paper, in: Capsule())
                            .overlay(Capsule().strokeBorder(AppTheme.ink, lineWidth: 2))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit routine")
                    }
                }
                .padding(.top, -6)
                .padding(.bottom, -6)
                DisplayTitle(text: isComplete ? "Done for today." : "Let’s move.")
                    .padding(.top, 6)

                if let routine = model.routine, !routine.routineItems.isEmpty {
                    summaryCard(routine)
                        .padding(.top, 22)
                    InkRule().padding(.top, 18)
                    LazyVStack(spacing: 0) {
                        ForEach(routine.routineItems) { item in
                            NavigationLink(value: item) {
                                RoutineRow(item: item, isDone: model.isDone(item), log: model.todayLog(for: item))
                            }
                            .buttonStyle(.plain)
                            .draggable(item.id.uuidString)
                            .dropDestination(for: String.self) { values, _ in
                                guard let value = values.first, let draggedID = UUID(uuidString: value) else { return false }
                                Task { await model.moveRoutineItem(draggedID, before: item.id) }
                                return true
                            }
                        }
                    }
                } else if model.isLoading {
                    ProgressView("Loading today’s routine…")
                        .tint(AppTheme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        InkRule().padding(.bottom, 14)
                        Text("No routine yet.")
                            .font(.system(size: 28, weight: .heavy))
                            .tracking(-0.8)
                            .foregroundStyle(AppTheme.ink)
                        Text("Your prescribed routine shows up here once your PT adds it.")
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.muted)
                    }
                    .padding(.top, 24)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .refreshable { await model.loadHome() }
        .tabBarClearance()
        .signScreen()
    }

    private var isComplete: Bool {
        guard let items = model.routine?.routineItems, !items.isEmpty else { return false }
        return items.allSatisfy(model.isDone)
    }

    @ViewBuilder
    private func summaryCard(_ routine: Routine) -> some View {
        let total = routine.routineItems.count
        let done = routine.routineItems.filter(model.isDone).count
        let remaining = total - done
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                SignLabel("Today’s routine", color: isComplete ? AppTheme.paper : AppTheme.ink)
                Text(isComplete ? "All \(total) moves logged" : "\(remaining) \(remaining == 1 ? "move" : "moves") to go")
                    .font(.system(size: 27, weight: .heavy))
                    .tracking(-0.8)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                Text(isComplete ? "Nice work. It’s all in History." : (done == 0 ? "Tap a move to start" : "\(done) logged, keep going"))
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(isComplete ? AppTheme.paper : AppTheme.ink)
            Spacer(minLength: 0)
            ZStack {
                Circle().fill(isComplete ? AppTheme.sign : AppTheme.paper)
                Circle().strokeBorder(AppTheme.ink, lineWidth: 2)
                if isComplete {
                    Image(systemName: "checkmark").font(.system(size: 32, weight: .black)).foregroundStyle(AppTheme.ink)
                } else {
                    Text("\(done)/\(total)")
                        .font(.system(size: 28, weight: .heavy).monospacedDigit())
                        .foregroundStyle(AppTheme.ink)
                }
            }
            .frame(width: isComplete ? 72 : 90, height: isComplete ? 72 : 90)
        }
        .padding(22)
        .signCard(fill: isComplete ? AppTheme.done : AppTheme.sign)
        .accessibilityElement(children: .combine)
    }

    static func dateLine(_ date: Date) -> String {
        let weekday = date.formatted(.dateTime.weekday(.abbreviated))
        let monthDay = date.formatted(.dateTime.month(.abbreviated).day())
        return "\(weekday) · \(monthDay)"
    }
}

private struct RoutineRow: View {
    let item: RoutineItem
    let isDone: Bool
    let log: ExerciseLog?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                CheckDot(isOn: isDone)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.exercise.name)
                        .font(.system(size: 19, weight: .heavy))
                        .tracking(-0.2)
                        .foregroundStyle(AppTheme.ink)
                    if let summary = item.shortPrescription {
                        Text(summary)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppTheme.muted)
                    }
                }
                Spacer(minLength: 8)
                // Option C: once logged, what you did replaces the chevron, in blue.
                if let result = log?.resultSummary {
                    Text(result)
                        .font(.system(size: 20, weight: .heavy).monospacedDigit())
                        .tracking(-0.4)
                        .foregroundStyle(AppTheme.done)
                        .lineLimit(1)
                        .fixedSize()
                        .layoutPriority(1)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 24, alignment: .trailing)
                }
            }
            .padding(.vertical, 18)
            HairRule()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(isDone ? (log?.resultSummary.map { "Done, logged \($0)" } ?? "Done") : "Not done")
    }
}

struct ExerciseDetailView: View {
    @EnvironmentObject private var model: AppModel
    let itemID: UUID
    let fallback: RoutineItem

    private var item: RoutineItem {
        model.routine?.routineItems.first(where: { $0.id == itemID }) ?? fallback
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    SignBackButton(title: "Today")
                    Spacer()
                    if let position = positionLine {
                        Eyebrow(text: position)
                    }
                }

                DisplayTitle(text: "\(item.exercise.name).", size: item.exercise.name.count > 18 ? 34 : 44)
                    .padding(.top, 14)

                let stats = item.prescriptionStats
                let logs = model.todayLogs(for: item)
                if !logs.isEmpty {
                    // One blue sign for the day, one row per log, oldest first.
                    SignLabel("Today’s work", color: AppTheme.done)
                        .padding(.top, 18)
                    TodaysWorkCard(logs: logs.reversed())
                        .padding(.top, 10)
                    if !stats.isEmpty {
                        SignLabel("Prescribed")
                            .padding(.top, 24)
                        StatCard(stats: stats, compact: true)
                            .padding(.top, 10)
                    }
                } else {
                    if model.isDone(item) {
                        HStack(spacing: 8) {
                            CheckDot(isOn: true, size: 22)
                            Text("Logged today")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(AppTheme.done)
                        }
                        .padding(.top, 10)
                    }
                    if !stats.isEmpty {
                        StatCard(stats: stats)
                            .padding(.top, 20)
                    }
                }

                if let notes = item.prescriptionNotes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppTheme.muted)
                        .padding(.top, 12)
                }

                if let instructions = item.exercise.instructions, !instructions.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SignLabel("How to do it")
                        ForEach(Array(instructions.enumerated()), id: \.offset) { index, instruction in
                            HStack(alignment: .firstTextBaseline, spacing: 14) {
                                Text("\(index + 1)")
                                    .font(.system(size: 20, weight: .heavy).monospacedDigit())
                                    .frame(width: 22, alignment: .leading)
                                Text(instruction)
                                    .font(.system(size: 17, weight: .medium))
                                    .lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .foregroundStyle(AppTheme.ink)
                        }
                    }
                    .padding(.top, 30)
                }

                if let note = item.exercise.ptNote, !note.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SignLabel("From your PT", color: AppTheme.sign)
                        Text(note)
                            .font(.system(size: 18, weight: .bold))
                            .lineSpacing(3)
                            .foregroundStyle(AppTheme.paper)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .background(AppTheme.ink, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.top, 26)
                }

                if let videoURL = item.exercise.videoURL {
                    Link(destination: videoURL) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                            Text("Watch a demonstration")
                        }
                        .font(.system(size: 15, weight: .bold))
                        .underline(true, color: AppTheme.sign)
                        .foregroundStyle(AppTheme.ink)
                    }
                    .padding(.top, 20)
                }

            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Pinned so the action never hides under the tab bar, however long the page is.
            VStack(spacing: 0) {
                HairRule()
                NavigationLink {
                    ExerciseLogView(item: item)
                } label: {
                    Text(model.isDone(item) ? "Log it again" : "Log this exercise")
                }
                .buttonStyle(SignButtonStyle())
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .background(AppTheme.paper)
        }
        .tabBarClearance()
        .signScreen()
    }

    private var positionLine: String? {
        guard let items = model.routine?.routineItems,
              let index = items.firstIndex(where: { $0.id == itemID }) else { return nil }
        return "Move \(index + 1) of \(items.count)"
    }
}

struct PrescriptionStat: Hashable {
    let label: String
    let value: String
    var isText = false
}

/// The yellow prescription card: one column per target.
private struct StatCard: View {
    let stats: [PrescriptionStat]
    var compact = false

    private var numberSize: CGFloat { compact ? 26 : 40 }
    private var textSize: CGFloat { compact ? 16 : 19 }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                if index > 0 {
                    Rectangle().fill(AppTheme.ink).frame(width: 2).padding(.horizontal, compact ? 12 : 16)
                }
                VStack(alignment: .leading, spacing: compact ? 3 : 6) {
                    SignLabel(stat.label)
                    Text(stat.value)
                        .font(stat.isText ? .system(size: textSize, weight: .heavy) : .system(size: numberSize, weight: .heavy).monospacedDigit())
                        .tracking(stat.isText ? 0 : -1)
                        .minimumScaleFactor(0.6)
                        .lineLimit(2)
                        .foregroundStyle(AppTheme.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 20)
        .padding(.vertical, compact ? 12 : 16)
        .signCard(offset: compact ? 4 : 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Prescribed")
    }
}

/// "Today's work": one blue card for the day with a shared header and a row per log,
/// oldest first. Pain, the note, and a band logged alongside a weight sit under their row.
struct TodaysWorkCard: View {
    let logs: [ExerciseLog]

    enum Column: Hashable {
        case sets, reps, duration, weight, band

        var title: String {
            switch self {
            case .sets: "Sets"
            case .reps: "Reps"
            case .duration: "Duration"
            case .weight: "Weight"
            case .band: "Band"
            }
        }

        var width: CGFloat? {
            switch self {
            case .sets, .reps: 52
            case .duration: 84
            case .weight, .band: nil
            }
        }
    }

    /// Columns any of today's logs used. A weight takes the last column over a band.
    static func columns(for logs: [ExerciseLog]) -> [Column] {
        var columns: [Column] = []
        if logs.contains(where: { $0.setsCompleted != nil }) { columns.append(.sets) }
        if logs.contains(where: { $0.repsPerSet != nil }) { columns.append(.reps) }
        if logs.contains(where: { $0.durationSeconds != nil }) { columns.append(.duration) }
        if logs.contains(where: { $0.weightText != nil }) {
            columns.append(.weight)
        } else if logs.contains(where: { $0.bandResistance?.isEmpty == false }) {
            columns.append(.band)
        }
        return columns
    }

    private static let timeWidth: CGFloat = 78
    private var columns: [Column] { Self.columns(for: logs) }
    private var rule: some View { Rectangle().fill(AppTheme.paper.opacity(0.45)).frame(height: 1.5) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                SignLabel("Time", color: AppTheme.paper).frame(width: Self.timeWidth, alignment: .leading)
                ForEach(columns, id: \.self) { column in
                    SignLabel(column.title, color: AppTheme.paper)
                        .lineLimit(1)
                        .frame(width: column.width, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 10)
            .padding(.bottom, 8)
            .accessibilityHidden(true)

            ForEach(Array(logs.enumerated()), id: \.element.id) { _, log in
                rule
                row(for: log)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .signCard(fill: AppTheme.done)
    }

    private func row(for log: ExerciseLog) -> some View {
        let extraBand = columns.contains(.band) ? nil : log.bandResistance.flatMap { $0.isEmpty ? nil : $0 }
        let note = log.notes.flatMap { $0.isEmpty ? nil : $0 }
        let hasValues = columns.contains { value(for: $0, in: log) != nil }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(log.performedAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: Self.timeWidth, alignment: .leading)
                if hasValues {
                    ForEach(columns, id: \.self) { column in
                        cell(value(for: column, in: log), column: column)
                    }
                } else {
                    Text("Done")
                        .font(.system(size: 16, weight: .heavy))
                }
                Spacer(minLength: 0)
            }

            if extraBand != nil || log.painAfter != nil || note != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if extraBand != nil || log.painAfter != nil {
                        HStack(spacing: 8) {
                            if let pain = log.painAfter {
                                Text("Pain \(pain)")
                                    .font(.system(size: 12, weight: .heavy).monospacedDigit())
                                    .tracking(0.3)
                                    .padding(.horizontal, 9)
                                    .frame(height: 22)
                                    .overlay(Capsule().strokeBorder(AppTheme.paper, lineWidth: 1.5))
                            }
                            if let extraBand {
                                Text(extraBand)
                                    .font(.system(size: 13, weight: .bold))
                            }
                        }
                    }
                    if let note {
                        Text("“\(note)”")
                            .font(.system(size: 13, weight: .semibold))
                            .italic()
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, Self.timeWidth)
            }
        }
        .foregroundStyle(AppTheme.paper)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(for: log, extraBand: extraBand, note: note))
    }

    @ViewBuilder
    private func cell(_ value: String?, column: Column) -> some View {
        let isNumber = column == .sets || column == .reps
        Text(value ?? "–")
            .font(isNumber ? .system(size: 26, weight: .heavy).monospacedDigit() : .system(size: 16, weight: .heavy))
            .tracking(isNumber ? -0.5 : 0)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .opacity(value == nil ? 0.6 : 1)
            .frame(width: column.width, alignment: .leading)
    }

    private func value(for column: Column, in log: ExerciseLog) -> String? {
        switch column {
        case .sets: log.setsCompleted.map(String.init)
        case .reps: log.repsPerSet.map(String.init)
        case .duration: log.durationSeconds.map(RoutineItem.durationText)
        case .weight: log.weightText
        case .band: log.bandResistance.flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    private func accessibilityText(for log: ExerciseLog, extraBand: String?, note: String?) -> String {
        var parts = [log.performedAt.formatted(date: .omitted, time: .shortened)]
        for column in columns {
            if let value = value(for: column, in: log) { parts.append("\(column.title) \(value)") }
        }
        if parts.count == 1 { parts.append("Done") }
        if let extraBand { parts.append("Band \(extraBand)") }
        if let pain = log.painAfter { parts.append("Pain \(pain) of 10") }
        if let note { parts.append("Note: \(note)") }
        return parts.joined(separator: ", ")
    }
}

extension RoutineItem {
    /// Compact prescription for list rows, e.g. "3 × 10 · Red band" or "3 × 15 sec · 10 lb".
    var shortPrescription: String? {
        var parts: [String] = []
        if let targetSets, let targetReps {
            parts.append("\(targetSets) × \(targetReps)")
        } else if let targetSets, let targetDurationSeconds {
            let time = Self.durationText(targetDurationSeconds)
            parts.append(targetSets > 1 ? "\(targetSets) × \(time)" : time)
        } else if let targetSets {
            parts.append(targetSets == 1 ? "1 set" : "\(targetSets) sets")
        } else if let targetReps {
            parts.append("\(targetReps) reps")
        }
        if targetSets == nil, let targetDurationSeconds { parts.append(Self.durationText(targetDurationSeconds)) }
        if let targetBandResistance { parts.append(targetBandResistance) }
        if let targetWeightValue, let targetWeightUnit {
            parts.append("\(targetWeightValue.formatted()) \(targetWeightUnit.rawValue)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var prescriptionStats: [PrescriptionStat] {
        var stats: [PrescriptionStat] = []
        if let targetSets { stats.append(.init(label: "Sets", value: "\(targetSets)")) }
        if let targetReps { stats.append(.init(label: "Reps", value: "\(targetReps)")) }
        if let targetDurationSeconds {
            stats.append(.init(label: "Time", value: Self.durationText(targetDurationSeconds), isText: stats.count >= 2))
        }
        if let targetWeightValue, let targetWeightUnit {
            stats.append(.init(label: "Weight", value: "\(targetWeightValue.formatted()) \(targetWeightUnit.rawValue)", isText: true))
        } else if let targetBandResistance {
            stats.append(.init(label: "Band", value: targetBandResistance, isText: true))
        }
        return stats
    }

    /// Short goal line for the log screen header, e.g. "Goal 2 × 12".
    var goalLine: String? {
        shortPrescription.map { "Goal \($0)" }
    }

    static func durationText(_ seconds: Int) -> String {
        if seconds >= 60, seconds % 60 == 0 { return "\(seconds / 60) min" }
        if seconds > 60 { return "\(seconds / 60):\(String(format: "%02d", seconds % 60))" }
        return "\(seconds) sec"
    }
}

extension ExerciseLog {
    /// Short result for the Today list's right-hand column, e.g. "3 × 8" or "50 sec".
    var resultSummary: String? {
        if let setsCompleted, let repsPerSet { return "\(setsCompleted) × \(repsPerSet)" }
        if let durationSeconds { return RoutineItem.durationText(durationSeconds) }
        if let setsCompleted { return "\(setsCompleted) sets" }
        if let repsPerSet { return "\(repsPerSet) reps" }
        if let weightText { return weightText }
        return "Done"
    }

    /// "12 lb" when both a weight and its unit were logged.
    var weightText: String? {
        guard let weightValue, let weightUnit else { return nil }
        return "\(weightValue.formatted()) \(weightUnit.rawValue)"
    }
}
