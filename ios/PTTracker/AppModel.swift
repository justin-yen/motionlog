import Foundation

enum AppTab: String, CaseIterable, Sendable {
    case today = "Today"
    case history = "History"
    case profile = "Profile"
}

@MainActor
final class AppModel: ObservableObject {
    enum AuthStep: Equatable {
        case phone
        case code(phone: String)
        case authenticated
    }

    @Published var authStep: AuthStep
    @Published var routine: Routine?
    /// Logs from the current month, newest first. Today reads today's logs from here.
    @Published var history: [ExerciseLog] = [] {
        didSet { refreshCurrentMonth() }
    }
    /// History data by month start: that month's logs (grouped by day) and the plans in force.
    @Published private(set) var historyMonths: [Date: HistoryMonth] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedTab: AppTab = .today
    @Published var isTabBarHidden = false

    let isMockMode: Bool
    private let repository: any PTRepository
    private let supabase: SupabaseClient?
    private let exerciseLogParser: any ExerciseLogParsingService
    private let authTestPhone: String?
    private let authTestCode: String?
    private var lastLoadedDay: Date?
    private var isRefreshingForDayChange = false

    init(configuration: AppConfiguration = .current) {
        isMockMode = configuration.useMockData
        authTestPhone = configuration.authTestPhone
        authTestCode = configuration.authTestCode
        if configuration.useMockData {
            repository = MockPTRepository()
            supabase = nil
            exerciseLogParser = LocalExerciseLogParsingService()
            authStep = .authenticated
        } else if let url = configuration.supabaseURL, let key = configuration.supabaseAnonKey {
            let client = SupabaseClient(baseURL: url, anonKey: key)
            repository = SupabasePTRepository(client: client)
            supabase = client
            exerciseLogParser = FallbackExerciseLogParsingService(
                primary: SupabaseExerciseLogParsingService(client: client),
                fallback: LocalExerciseLogParsingService()
            )
            authStep = KeychainStore.loadSession() == nil ? .phone : .authenticated
        } else {
            repository = MockPTRepository()
            supabase = nil
            exerciseLogParser = LocalExerciseLogParsingService()
            authStep = .phone
            errorMessage = "Supabase configuration is missing."
        }
    }

    init(repository: any PTRepository) {
        isMockMode = true
        self.repository = repository
        supabase = nil
        exerciseLogParser = LocalExerciseLogParsingService()
        authTestPhone = nil
        authTestCode = nil
        authStep = .authenticated
    }

    func requestCode(phone: String) async {
        guard let supabase else {
            errorMessage = "Connect Supabase before requesting a real code."
            return
        }
        if phone == authTestPhone {
            errorMessage = nil
            authStep = .code(phone: phone)
            return
        }
        await perform {
            try await supabase.requestOTP(phone: phone)
            self.authStep = .code(phone: phone)
        }
    }

    func testCodeHint(for phone: String) -> String? {
        phone == authTestPhone ? authTestCode : nil
    }

    func verifyCode(_ code: String, phone: String) async {
        guard let supabase else { return }
        await perform {
            _ = try await supabase.verifyOTP(phone: phone, code: code)
            self.authStep = .authenticated
            await self.loadHome()
        }
    }

    func loadHome(at date: Date = .now) async {
        var didLoad = false
        await perform {
            let month = HistoryMonth.bounds(containing: date)
            async let routine = self.repository.todayRoutine()
            async let logs = self.repository.logs(from: month.start, to: month.end)
            async let plans = self.repository.plans(from: month.start, to: month.end)
            self.routine = try await routine
            // History can still fall back to the current plan if older plans fail to load.
            self.currentMonthPlans = (try? await plans) ?? []
            self.historyMonths = [:]
            self.history = try await logs
            didLoad = true
        }
        if didLoad { lastLoadedDay = Calendar.current.startOfDay(for: date) }
    }

    /// Refreshes data when an already-running app becomes active on a new local day.
    /// Same-day foreground transitions are intentionally ignored.
    func refreshForCurrentDayIfNeeded(at date: Date = .now) async {
        guard authStep == .authenticated else { return }
        let day = Calendar.current.startOfDay(for: date)
        guard lastLoadedDay != day, !isRefreshingForDayChange else { return }
        isRefreshingForDayChange = true
        defer { isRefreshingForDayChange = false }
        await loadHome(at: date)
    }

    /// Loads a past month for History the first time it's shown. The current month is kept up
    /// to date by loadHome and by saving logs and plans.
    func loadHistoryMonth(containing date: Date) async {
        let month = HistoryMonth.bounds(containing: date)
        guard historyMonths[month.start] == nil else { return }
        do {
            async let logs = repository.logs(from: month.start, to: month.end)
            async let plans = repository.plans(from: month.start, to: month.end)
            historyMonths[month.start] = HistoryMonth(start: month.start, logs: try await logs, plans: try await plans)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// History data for the month containing `date`, if it has loaded.
    func historyMonth(containing date: Date) -> HistoryMonth? {
        historyMonths[HistoryMonth.bounds(containing: date).start]
    }

    private var currentMonthPlans: [Routine] = []

    private func refreshCurrentMonth() {
        let month = HistoryMonth.bounds(containing: .now)
        historyMonths[month.start] = HistoryMonth(start: month.start, logs: history, plans: currentMonthPlans)
    }

    func save(_ draft: ExerciseLogDraft) async -> Bool {
        var didSave = false
        await perform {
            let saved = try await self.repository.saveLog(draft)
            self.history.insert(saved, at: 0)
            if let itemID = draft.routineItemID,
               let itemIndex = self.routine?.routineItems.firstIndex(where: { $0.id == itemID }) {
                self.routine?.routineItems[itemIndex].isComplete = true
            }
            didSave = true
        }
        return didSave
    }

    func parseVoiceLog(transcript: String, item: RoutineItem) async -> VoiceLogExtraction {
        do {
            return try await exerciseLogParser.parse(transcript: transcript, item: item)
        } catch {
            return VoiceLogParser.parse(transcript)
        }
    }

    func moveRoutineItems(from source: IndexSet, to destination: Int) async {
        guard var routine else { return }
        routine.routineItems.move(fromOffsets: source, toOffset: destination)
        for index in routine.routineItems.indices { routine.routineItems[index].position = index }
        self.routine = routine
        do {
            try await repository.reorder(routineID: routine.id, itemIDs: routine.routineItems.map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveRoutineItem(_ draggedID: UUID, before targetID: UUID) async {
        guard var routine,
              draggedID != targetID,
              let source = routine.routineItems.firstIndex(where: { $0.id == draggedID }),
              let target = routine.routineItems.firstIndex(where: { $0.id == targetID }) else { return }
        let item = routine.routineItems.remove(at: source)
        let adjustedTarget = source < target ? target - 1 : target
        routine.routineItems.insert(item, at: adjustedTarget)
        for index in routine.routineItems.indices { routine.routineItems[index].position = index }
        self.routine = routine
        do {
            try await repository.reorder(routineID: routine.id, itemIDs: routine.routineItems.map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The plan that was in force on a given day, or nil before the first plan. Falls back to the
    /// current plan if that month's plans haven't loaded or couldn't be fetched.
    func plan(for date: Date) -> Routine? {
        guard let month = historyMonth(containing: date), !month.plans.isEmpty else { return routine }
        return month.plan(for: date)
    }

    /// Exercises the user already has, for the add-a-move picker. Empty if they can't be loaded.
    func exerciseLibrary() async -> [Exercise] {
        (try? await repository.exercises()) ?? []
    }

    /// Saves the plan edited on Today. Returns false and shows the error if saving failed,
    /// so the user stays in edit mode with their changes.
    func saveRoutine(_ draft: RoutineEditDraft) async -> Bool {
        var didSave = false
        await perform {
            self.routine = try await self.repository.saveRoutine(draft.update())
            didSave = true
            let month = HistoryMonth.bounds(containing: .now)
            self.currentMonthPlans = (try? await self.repository.plans(from: month.start, to: month.end)) ?? self.currentMonthPlans
            self.refreshCurrentMonth()
        }
        return didSave
    }

    /// Every log for this exercise made today, newest first.
    func todayLogs(for item: RoutineItem) -> [ExerciseLog] {
        history
            .filter { $0.exerciseID == item.exercise.id && Calendar.current.isDateInToday($0.performedAt) }
            .sorted { $0.performedAt > $1.performedAt }
    }

    /// The most recent log remains the compact result shown on the Today routine row.
    func todayLog(for item: RoutineItem) -> ExerciseLog? {
        todayLogs(for: item).first
    }

    /// Done if the routine says so or there is a log for it today.
    func isDone(_ item: RoutineItem) -> Bool {
        item.isComplete || todayLog(for: item) != nil
    }

    func signOut() async {
        await supabase?.signOut()
        routine = nil
        history = []
        selectedTab = .today
        authStep = .phone
    }

    private func perform(_ operation: () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await operation()
        } catch ClientError.sessionExpired {
            await supabase?.signOut()
            routine = nil
            history = []
            authStep = .phone
            errorMessage = ClientError.sessionExpired.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
