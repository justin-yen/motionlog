import Foundation

/// One calendar month of History data: only the logs made that month, grouped by day once, and
/// only the plans that were in force during it. Built when the month loads, so drawing a day is a
/// dictionary lookup instead of a scan over every log the user has ever made.
struct HistoryMonth: Sendable {
    let start: Date
    let plans: [Routine]
    private let logsByDay: [String: [ExerciseLog]]

    init(start: Date, logs: [ExerciseLog], plans: [Routine], calendar: Calendar = .autoupdatingCurrent) {
        self.start = start
        self.plans = plans
        logsByDay = Dictionary(grouping: logs) { LocalDateKey.string(for: $0.performedAt, calendar: calendar) }
    }

    /// Logs made on this day, newest first.
    func logs(on date: Date, calendar: Calendar = .autoupdatingCurrent) -> [ExerciseLog] {
        (logsByDay[LocalDateKey.string(for: date, calendar: calendar)] ?? [])
            .sorted { $0.performedAt > $1.performedAt }
    }

    func plan(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> Routine? {
        plans.plan(for: date, calendar: calendar)
    }

    /// First instant of the month containing `date`, and of the month after it.
    static func bounds(containing date: Date, calendar: Calendar = .autoupdatingCurrent) -> (start: Date, end: Date) {
        let interval = calendar.dateInterval(of: .month, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 31 * 86_400)
        return (interval.start, interval.end)
    }
}

enum PlanRange {
    /// The plans covering days in [start, end): those dated inside it, plus the newest one dated
    /// before it. Newest first. Mirrors the two Supabase queries so the mock behaves the same.
    static func covering(start: Date, end: Date, in plans: [Routine], calendar: Calendar = .autoupdatingCurrent) -> [Routine] {
        let first = LocalDateKey.string(for: start, calendar: calendar)
        let last = LocalDateKey.string(for: end, calendar: calendar)
        let dated = plans
            .map { (key: LocalDateKey.string(for: $0.scheduledFor, calendar: calendar), plan: $0) }
            .sorted { $0.key > $1.key }
        let inside = dated.filter { $0.key >= first && $0.key < last }.map(\.plan)
        let before = dated.first { $0.key < first }.map { [$0.plan] } ?? []
        return inside + before
    }
}
