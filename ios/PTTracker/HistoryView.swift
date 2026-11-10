import SwiftUI

enum AdherenceStatus: Equatable {
    case complete
    case partial
    case skipped
}

struct HistoryExerciseSnapshot: Identifiable, Equatable {
    let item: RoutineItem
    let status: AdherenceStatus

    var id: UUID { item.id }
}

struct HistoryDaySnapshot: Equatable {
    let date: Date
    let exercises: [HistoryExerciseSnapshot]

    var loggedCount: Int { exercises.count { $0.status != .skipped } }
    var completeCount: Int { exercises.count { $0.status == .complete } }
    var totalCount: Int { exercises.count }

    var status: AdherenceStatus {
        if !exercises.isEmpty, completeCount == exercises.count { return .complete }
        if loggedCount > 0 { return .partial }
        return .skipped
    }

    static func make(date: Date, routine: Routine, logs: [ExerciseLog], calendar: Calendar = .current) -> Self {
        let dayLogs = logs.filter { calendar.isDate($0.performedAt, inSameDayAs: date) }
        let exercises = routine.routineItems
            .sorted { $0.position < $1.position }
            .map { item in
                let matches = dayLogs.filter { $0.exerciseID == item.exercise.id }
                let status: AdherenceStatus
                if matches.isEmpty {
                    status = .skipped
                } else if matches.contains(where: { meetsPrescription($0, item: item) }) {
                    status = .complete
                } else {
                    status = .partial
                }
                return HistoryExerciseSnapshot(item: item, status: status)
            }
        return Self(date: calendar.startOfDay(for: date), exercises: exercises)
    }

    private static func meetsPrescription(_ log: ExerciseLog, item: RoutineItem) -> Bool {
        if let target = item.targetSets, (log.setsCompleted ?? -1) < target { return false }
        if let target = item.targetReps, (log.repsPerSet ?? -1) < target { return false }
        if let target = item.targetDurationSeconds, (log.durationSeconds ?? -1) < target { return false }
        if let target = item.targetBandResistance,
           log.bandResistance?.localizedCaseInsensitiveCompare(target) != .orderedSame { return false }
        if let target = item.targetWeightValue, (log.weightValue ?? -.infinity) < target { return false }
        if let target = item.targetWeightUnit, log.weightUnit != target { return false }
        return true
    }
}

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedDate: Date?
    @State private var panelIsExpanded = false
    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now

    private var calendar: Calendar { .current }

    var body: some View {
        GeometryReader { proxy in
            // Keep every calendar week visible at the half snap point, matching 5B.
            let halfTop = min(460, proxy.size.height * 0.59)
            let expandedTop = proxy.size.height * 0.20

            ZStack(alignment: .top) {
                overview

                if let selectedDate, let routine = model.routine {
                    let snapshot = HistoryDaySnapshot.make(
                        date: selectedDate,
                        routine: routine,
                        logs: model.history,
                        calendar: calendar
                    )
                    HistoryDayPanel(
                        snapshot: snapshot,
                        isExpanded: $panelIsExpanded,
                        onClose: closePanel
                    )
                    .id(calendar.startOfDay(for: selectedDate))
                    .frame(height: proxy.size.height - (panelIsExpanded ? expandedTop : halfTop))
                    .offset(y: panelIsExpanded ? expandedTop : halfTop)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.985, anchor: .top)),
                        removal: .opacity
                    ))
                    .zIndex(2)
                }
            }
            .clipped()
        }
        .tabBarClearance()
        .signScreen()
        .animation(.spring(response: 0.44, dampingFraction: 0.86), value: selectedDate)
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: panelIsExpanded)
        .accessibilityAction(.escape, closePanel)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: displayedMonth.formatted(.dateTime.month(.wide).year()))
            DisplayTitle(text: "History.")
                .padding(.top, 6)

            MonthCalendar(
                month: displayedMonth,
                today: .now,
                selectedDate: selectedDate,
                snapshotForDate: snapshot(for:),
                onSelect: selectDate
            )
            .padding(.top, 22)

            monthSummary
                .padding(.top, 22)
                .accessibilityHidden(selectedDate != nil)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
    }

    private var monthSummary: some View {
        let snapshots = elapsedDates.map(snapshot(for:))
        let completedDays = snapshots.count { $0.status == .complete }
        let totalMoves = snapshots.reduce(0) { $0 + $1.totalCount }
        let completedMoves = snapshots.reduce(0) { $0 + $1.completeCount }
        let partialMoves = snapshots.reduce(0) { total, day in
            total + day.exercises.count { $0.status == .partial }
        }

        return VStack(alignment: .leading, spacing: 4) {
            SignLabel("So far this month")
            Text("\(completedDays) of \(snapshots.count) days complete")
                .font(.system(size: 24, weight: .heavy))
                .tracking(-0.7)
                .foregroundStyle(AppTheme.ink)
                .monospacedDigit()
            Text("\(completedMoves) of \(totalMoves) moves · \(partialMoves) partial · tap a day for details")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .signCard()
    }

    private var elapsedDates: [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let today = calendar.startOfDay(for: .now)
        var date = interval.start
        var values: [Date] = []
        while date < interval.end, date <= today {
            values.append(date)
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return values
    }

    private func snapshot(for date: Date) -> HistoryDaySnapshot {
        guard let routine = model.routine else {
            return HistoryDaySnapshot(date: date, exercises: [])
        }
        return HistoryDaySnapshot.make(date: date, routine: routine, logs: model.history, calendar: calendar)
    }

    private func selectDate(_ date: Date) {
        if let selectedDate, calendar.isDate(selectedDate, inSameDayAs: date) {
            closePanel()
        } else {
            panelIsExpanded = false
            withAnimation(.easeInOut(duration: 0.16)) { selectedDate = date }
        }
    }

    private func closePanel() {
        panelIsExpanded = false
        selectedDate = nil
    }
}

private struct MonthCalendar: View {
    let month: Date
    let today: Date
    let selectedDate: Date?
    let snapshotForDate: (Date) -> HistoryDaySnapshot
    let onSelect: (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private var calendar: Calendar { .current }

    private var dates: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let days = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let leading = calendar.component(.weekday, from: interval.start) - calendar.firstWeekday
        let normalizedLeading = (leading + 7) % 7
        let monthDates: [Date?] = days.compactMap { day in
            calendar.date(bySetting: .day, value: day, of: interval.start)
        }
        return Array(repeating: nil, count: normalizedLeading) + monthDates
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(calendar.veryShortWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(AppTheme.muted)
                    .frame(maxWidth: .infinity)
            }

            ForEach(Array(dates.enumerated()), id: \.offset) { _, date in
                if let date {
                    let isFuture = calendar.startOfDay(for: date) > calendar.startOfDay(for: today)
                    Button {
                        if !isFuture { onSelect(date) }
                    } label: {
                        CalendarDayCell(
                            date: date,
                            snapshot: snapshotForDate(date),
                            isToday: calendar.isDate(date, inSameDayAs: today),
                            isSelected: selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false,
                            isFuture: isFuture
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isFuture)
                } else {
                    Color.clear.frame(height: 46)
                }
            }
        }
    }
}

private struct CalendarDayCell: View {
    let date: Date
    let snapshot: HistoryDaySnapshot
    let isToday: Bool
    let isSelected: Bool
    let isFuture: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11)
                .fill(fill)
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(border, style: strokeStyle)

            if snapshot.status == .skipped, !isFuture {
                Capsule().fill(AppTheme.disabled).frame(width: 24, height: 2).rotationEffect(.degrees(-35))
            }

            VStack(spacing: 1) {
                Text(date.formatted(.dateTime.day()))
                    .font(.system(size: 15, weight: isFuture ? .semibold : .heavy))
                if snapshot.status == .partial, !isFuture {
                    Text("\(snapshot.loggedCount)/\(snapshot.totalCount)")
                        .font(.system(size: 9, weight: .heavy))
                }
            }
            .foregroundStyle(foreground)
        }
        .frame(height: 46)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AppTheme.ink, lineWidth: 3)
                    .padding(-3)
            }
        }
        .background {
            if isToday {
                RoundedRectangle(cornerRadius: 11).fill(AppTheme.ink).offset(x: 3, y: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityValue(isFuture ? "Future" : statusLabel)
    }

    private var fill: Color {
        if isFuture { return .clear }
        switch snapshot.status {
        case .complete: return AppTheme.done
        case .partial: return AppTheme.done.opacity(0.18)
        case .skipped: return AppTheme.paper
        }
    }

    private var border: Color {
        if isFuture { return .clear }
        if isToday { return AppTheme.ink }
        switch snapshot.status {
        case .complete: return AppTheme.done
        case .partial: return AppTheme.done
        case .skipped: return AppTheme.hair
        }
    }

    private var strokeStyle: StrokeStyle {
        snapshot.status == .skipped && !isFuture
            ? StrokeStyle(lineWidth: 2, dash: [5, 4])
            : StrokeStyle(lineWidth: 2)
    }

    private var foreground: Color {
        if isFuture { return AppTheme.disabled }
        return snapshot.status == .complete ? .white : AppTheme.ink
    }

    private var statusLabel: String {
        switch snapshot.status {
        case .complete: return "Complete"
        case .partial: return "Partially complete"
        case .skipped: return "Skipped"
        }
    }
}

private struct HistoryDayPanel: View {
    let snapshot: HistoryDaySnapshot
    @Binding var isExpanded: Bool
    let onClose: () -> Void
    @GestureState private var dragOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            grabber
            ScrollView {
                VStack(spacing: 0) {
                    header
                    ForEach(snapshot.exercises) { exercise in
                        HistoryExerciseRow(snapshot: exercise)
                    }
                }
                .padding(.horizontal, 24)
                // The floating tab bar overlays this panel. Extra scroll clearance keeps
                // the last exercise reachable and lets the header scroll away at half height.
                .padding(.bottom, 220)
            }
            .scrollIndicators(.hidden)
        }
        .background(AppTheme.paper)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .stroke(AppTheme.ink, lineWidth: 2)
                .mask(alignment: .top) { Rectangle().frame(height: 26) }
        }
        .shadow(color: AppTheme.ink.opacity(0.18), radius: 10, y: -4)
        .offset(y: max(-10, dragOffset))
    }

    private var grabber: some View {
        Capsule()
            .fill(AppTheme.ink)
            .frame(width: 44, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .updating($dragOffset) { value, state, _ in state = value.translation.height }
                    .onEnded { value in
                        let projected = value.predictedEndTranslation.height
                        if isExpanded {
                            if projected > 55 { isExpanded = false }
                        } else if projected < -45 {
                            isExpanded = true
                        } else if projected > 70 {
                            onClose()
                        }
                    }
            )
            .accessibilityLabel("Resize day details")
            .accessibilityHint(isExpanded ? "Swipe down to return to half height" : "Swipe up to expand or down to close")
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: dateLine, color: AppTheme.muted)
                    Text(title)
                        .font(.system(size: 26, weight: .heavy))
                        .tracking(-0.9)
                        .foregroundStyle(AppTheme.ink)
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(AppTheme.sign)
                        .frame(width: 30, height: 30)
                        .background(AppTheme.ink, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close day details")
            }

            HStack {
                Text("\(snapshot.completeCount) on target")
                Spacer()
                Text("\(snapshot.loggedCount)/\(snapshot.totalCount) logged")
                    .foregroundStyle(AppTheme.muted)
            }
            .font(.system(size: 12.5, weight: .heavy))
            .monospacedDigit()
            .padding(.top, 10)
            .padding(.bottom, 7)

            HStack(spacing: 4) {
                ForEach(snapshot.exercises) { exercise in
                    Capsule()
                        .fill(segmentFill(for: exercise.status))
                        .overlay(Capsule().stroke(segmentBorder(for: exercise.status), style: segmentStroke(for: exercise.status)))
                        .frame(height: 10)
                }
            }
            .padding(.bottom, 12)
            InkRule()
        }
    }

    private var dateLine: String {
        let base = snapshot.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return Calendar.current.isDateInToday(snapshot.date) ? "Today · \(base)" : base
    }

    private var title: String {
        switch snapshot.status {
        case .complete: return "All \(snapshot.totalCount) done."
        case .partial:
            return Calendar.current.isDateInToday(snapshot.date)
                ? "\(snapshot.loggedCount) of \(snapshot.totalCount), so far."
                : "\(snapshot.loggedCount) of \(snapshot.totalCount) done."
        case .skipped: return "Nothing logged."
        }
    }

    private func segmentFill(for status: AdherenceStatus) -> Color {
        switch status {
        case .complete: return AppTheme.done
        case .partial: return AppTheme.done.opacity(0.32)
        case .skipped: return .clear
        }
    }

    private func segmentBorder(for status: AdherenceStatus) -> Color {
        status == .skipped ? AppTheme.disabled : AppTheme.done
    }

    private func segmentStroke(for status: AdherenceStatus) -> StrokeStyle {
        status == .skipped ? StrokeStyle(lineWidth: 2, dash: [4, 3]) : StrokeStyle(lineWidth: 2)
    }
}

private struct HistoryExerciseRow: View {
    let snapshot: HistoryExerciseSnapshot

    var body: some View {
        HStack(spacing: 12) {
            StatusMark(status: snapshot.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.item.exercise.name)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(snapshot.status == .skipped ? AppTheme.muted : AppTheme.ink)
                Text(snapshot.item.prescriptionSummary ?? "Complete as prescribed")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.muted)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { HairRule() }
        .accessibilityElement(children: .combine)
    }
}

private struct StatusMark: View {
    let status: AdherenceStatus

    var body: some View {
        ZStack {
            Circle().fill(status == .complete ? AppTheme.done : status == .partial ? AppTheme.done.opacity(0.28) : .clear)
            Circle().stroke(border, style: stroke)
            switch status {
            case .complete:
                Image(systemName: "checkmark").font(.system(size: 12, weight: .black)).foregroundStyle(.white)
            case .partial:
                Rectangle().fill(AppTheme.done).frame(width: 18, height: 2)
            case .skipped:
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(AppTheme.disabled)
            }
        }
        .frame(width: 26, height: 26)
    }

    private var border: Color { status == .skipped ? AppTheme.disabled : AppTheme.done }
    private var stroke: StrokeStyle {
        status == .skipped ? StrokeStyle(lineWidth: 2, dash: [4, 3]) : StrokeStyle(lineWidth: 2)
    }
}

struct ProfileView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(text: model.isMockMode ? "Demo account" : "Signed in")
                DisplayTitle(text: "Profile.")
                    .padding(.top, 6)

                if let routine = model.routine {
                    VStack(alignment: .leading, spacing: 6) {
                        SignLabel("Your plan")
                        Text(routine.title ?? "Today’s routine")
                            .font(.system(size: 22, weight: .heavy))
                            .tracking(-0.5)
                            .foregroundStyle(AppTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(routine.routineItems.count) moves · set \(routine.scheduledFor.formatted(.dateTime.month(.abbreviated).day()))")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AppTheme.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 20)
                    .signCard()
                    .padding(.top, 22)
                }

                InkRule().padding(.top, 26)
                SignLabel("Privacy").padding(.top, 14)

                infoRow(
                    icon: "mic.fill",
                    filled: true,
                    title: "Voice notes are kept",
                    detail: "Each recording is saved with its transcript and the values you confirmed."
                )
                infoRow(
                    icon: "arrow.down.to.line",
                    filled: false,
                    title: "Export and delete",
                    detail: "Not in this version. Account deletion arrives before the App Store release."
                )

                Button("Sign out") {
                    Task { await model.signOut() }
                }
                .buttonStyle(SignButtonStyle(kind: .ghost))
                .padding(.top, 26)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .tabBarClearance()
        .signScreen()
    }

    private func infoRow(icon: String, filled: Bool, title: String, detail: String) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    if filled {
                        Circle().fill(AppTheme.ink)
                    } else {
                        Circle().strokeBorder(AppTheme.ink, lineWidth: 2)
                    }
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(filled ? AppTheme.sign : AppTheme.ink)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(AppTheme.ink)
                    Text(detail)
                        .font(.system(size: 14, weight: .medium))
                        .lineSpacing(2)
                        .foregroundStyle(AppTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 16)
            HairRule()
        }
        .accessibilityElement(children: .combine)
    }
}
