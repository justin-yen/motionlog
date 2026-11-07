import Foundation

@MainActor
final class AppModel: ObservableObject {
    enum AuthStep: Equatable {
        case phone
        case code(phone: String)
        case authenticated
    }

    @Published var authStep: AuthStep
    @Published var routine: Routine?
    @Published var history: [ExerciseLog] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    let isMockMode: Bool
    private let repository: any PTRepository
    private let supabase: SupabaseClient?

    init(configuration: AppConfiguration = .current) {
        isMockMode = configuration.useMockData
        if configuration.useMockData {
            repository = MockPTRepository()
            supabase = nil
            authStep = .authenticated
        } else if let url = configuration.supabaseURL, let key = configuration.supabaseAnonKey {
            let client = SupabaseClient(baseURL: url, anonKey: key)
            repository = SupabasePTRepository(client: client)
            supabase = client
            authStep = KeychainStore.loadSession() == nil ? .phone : .authenticated
        } else {
            repository = MockPTRepository()
            supabase = nil
            authStep = .phone
            errorMessage = "Supabase configuration is missing."
        }
    }

    func requestCode(phone: String) async {
        guard let supabase else {
            errorMessage = "Connect Supabase before requesting a real code."
            return
        }
        await perform {
            try await supabase.requestOTP(phone: phone)
            self.authStep = .code(phone: phone)
        }
    }

    func verifyCode(_ code: String, phone: String) async {
        guard let supabase else { return }
        await perform {
            _ = try await supabase.verifyOTP(phone: phone, code: code)
            self.authStep = .authenticated
            await self.loadHome()
        }
    }

    func loadHome() async {
        await perform {
            async let routine = self.repository.todayRoutine()
            async let history = self.repository.history()
            self.routine = try await routine
            self.history = try await history
        }
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

    func signOut() async {
        await supabase?.signOut()
        routine = nil
        history = []
        authStep = .phone
    }

    private func perform(_ operation: () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
