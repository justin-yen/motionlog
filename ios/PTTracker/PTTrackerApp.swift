import SwiftUI

@main
struct PTTrackerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(AppTheme.ink)
                .preferredColorScheme(.light)
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
        .background(AppTheme.paper.ignoresSafeArea())
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
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            // All three stacks stay alive so each tab keeps its navigation state.
            tab(.today) { TodayRoutineView() }
            tab(.history) { HistoryView() }
            tab(.profile) { ProfileView() }
        }
        .overlay(alignment: .bottom) {
            // Screens reserve room for this bar with .tabBarClearance().
            if !model.isTabBarHidden {
                SignTabBar(selection: $model.selectedTab)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 4)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.isTabBarHidden)
        .background(AppTheme.paper.ignoresSafeArea())
    }

    private func tab<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        let isSelected = model.selectedTab == tab
        return NavigationStack { content() }
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
    }
}

struct SignTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let isOn = selection == tab
                Button {
                    selection = tab
                } label: {
                    Text(tab.rawValue.uppercased())
                        .font(.system(size: 15, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(isOn ? AppTheme.ink : AppTheme.paper)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(isOn ? AppTheme.sign : .clear, in: RoundedRectangle(cornerRadius: 13))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 72)
        .background(AppTheme.ink, in: RoundedRectangle(cornerRadius: 22))
    }
}
