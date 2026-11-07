import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.history.isEmpty {
                ContentUnavailableView(
                    "No exercise history yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Completed exercises will appear here.")
                )
            } else {
                List(model.history) { log in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(log.exerciseName).font(.headline)
                            Spacer()
                            if log.hasAudio { Image(systemName: "waveform").foregroundStyle(AppTheme.voiceRed) }
                        }
                        Text(log.summary).foregroundStyle(.secondary)
                        Text(log.performedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(AppTheme.background)
        .navigationTitle("Exercise History")
        .refreshable { await model.loadHome() }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section("Privacy") {
                Label("Raw voice notes are retained", systemImage: "waveform.badge.mic")
                Text("Export is not part of the first MVP. Account deletion will be added before App Store submission.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Sign out", role: .destructive) {
                    Task { await model.signOut() }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppTheme.background)
        .navigationTitle("Settings")
    }
}
