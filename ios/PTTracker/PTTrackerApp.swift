import SwiftUI

@main
struct PTTrackerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(AppTheme.coral)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            switch model.authStep {
            case .phone:
                PhoneSignInView()
            case .code(let phone):
                CodeVerificationView(phone: phone)
            case .authenticated:
                MainTabView()
                    .task { await model.loadHome() }
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "Please try again.")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { TodayRoutineView() }
                .tabItem { Label("Today", systemImage: "checklist") }
            NavigationStack { HistoryView() }
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
