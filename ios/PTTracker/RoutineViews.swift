import SwiftUI

struct TodayRoutineView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if let routine = model.routine {
                List {
                    Section {
                        ProgressView(value: progress(routine))
                            .tint(AppTheme.coral)
                            .listRowBackground(Color.clear)
                    }
                    Section("Exercises") {
                        ForEach(routine.routineItems) { item in
                            NavigationLink {
                                ExerciseDetailView(item: item)
                            } label: {
                                RoutineRow(item: item)
                            }
                            .draggable(item.id.uuidString)
                            .dropDestination(for: String.self) { values, _ in
                                guard let value = values.first, let draggedID = UUID(uuidString: value) else { return false }
                                Task { await model.moveRoutineItem(draggedID, before: item.id) }
                                return true
                            }
                            .listRowBackground(AppTheme.card)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(AppTheme.background)
                .navigationTitle("Today’s Routine")
                .safeAreaInset(edge: .top) {
                    Text(routine.scheduledFor.formatted(date: .long, time: .omitted))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                }
            } else if model.isLoading {
                ProgressView("Loading today’s routine…")
            } else {
                ContentUnavailableView("No routine today", systemImage: "calendar", description: Text("Your next prescribed routine will appear here."))
            }
        }
    }

    private func progress(_ routine: Routine) -> Double {
        guard !routine.routineItems.isEmpty else { return 0 }
        return Double(routine.routineItems.filter(\.isComplete).count) / Double(routine.routineItems.count)
    }
}

private struct RoutineRow: View {
    let item: RoutineItem

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(item.isComplete ? AppTheme.coral : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.exercise.name)
                    .font(.headline)
                    .foregroundStyle(AppTheme.navy)
                if let summary = item.prescriptionSummary {
                    Text(summary).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct ExerciseDetailView: View {
    let item: RoutineItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                RoundedRectangle(cornerRadius: 24)
                    .fill(AppTheme.card)
                    .frame(height: 210)
                    .overlay {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 64))
                            .foregroundStyle(AppTheme.coral)
                    }
                if let summary = item.prescriptionSummary {
                    detailSection("Prescription", text: summary)
                }
                if let instructions = item.exercise.instructions, !instructions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("How to do it").font(.headline)
                        ForEach(Array(instructions.enumerated()), id: \.offset) { index, instruction in
                            Text("\(index + 1). \(instruction)")
                        }
                    }
                }
                if let note = item.exercise.ptNote { detailSection("From your PT", text: note) }
                if let videoURL = item.exercise.videoURL {
                    Link(destination: videoURL) {
                        Label("Watch demonstration", systemImage: "play.rectangle")
                    }
                }
                NavigationLink {
                    ExerciseLogView(item: item)
                } label: {
                    Text("Log this exercise").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(20)
        }
        .background(AppTheme.background)
        .navigationTitle(item.exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(text).foregroundStyle(.secondary)
        }
    }
}
