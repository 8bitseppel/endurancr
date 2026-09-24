import SwiftUI
import HealthKit
import TrainingCore

/// Lists recorded running workouts from Apple Health (most recent first). Tapping
/// one opens a detail view with its GPS route and stats.
struct RunHistoryView: View {
    let coordinator: PlanCoordinator

    @State private var workouts: [HKWorkout] = []
    @State private var loading = true

    var body: some View {
        List {
            if loading {
                HStack { Spacer(); ProgressView("Reading Health…"); Spacer() }
            } else if workouts.isEmpty {
                ContentUnavailableView(
                    "No runs yet",
                    systemImage: "figure.run",
                    description: Text("Runs recorded in the last 6 months show up here with their route and stats.")
                )
            } else {
                ForEach(workouts, id: \.uuid) { workout in
                    NavigationLink {
                        RunDetailView(workout: workout, coordinator: coordinator)
                    } label: {
                        row(workout)
                    }
                }
            }
        }
        .navigationTitle("Recent runs")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let since = Calendar.current.date(byAdding: .month, value: -6, to: .now) ?? .now
            workouts = await coordinator.health.recentRunningWorkouts(since: since)
            loading = false
        }
    }

    private func row(_ workout: HKWorkout) -> some View {
        let dist = coordinator.health.distanceMeters(for: workout)
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(Format.distance(dist)).fontWeight(.semibold)
                Spacer()
                Text(workout.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text(Format.duration(workout.duration))
                if dist > 0 {
                    Text("·").foregroundStyle(.secondary)
                    Text(Format.pace(workout.duration / (dist / 1_000)))
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// A recorded run's GPS route on a map plus its key stats.
struct RunDetailView: View {
    let workout: HKWorkout
    let coordinator: PlanCoordinator

    @State private var avgHR: Double?

    private var distanceMeters: Double { coordinator.health.distanceMeters(for: workout) }

    var body: some View {
        List {
            Section {
                RouteMapView(workout: workout, health: coordinator.health)
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
            }
            Section("Run") {
                LabeledContent("Distance", value: Format.distance(distanceMeters))
                LabeledContent("Duration", value: Format.duration(workout.duration))
                if distanceMeters > 0 {
                    LabeledContent("Avg pace", value: Format.pace(workout.duration / (distanceMeters / 1_000)))
                }
                if let avgHR {
                    LabeledContent("Avg heart rate", value: "\(Int(avgHR.rounded())) bpm")
                }
                if let kcal = coordinator.health.activeEnergyKilocalories(for: workout) {
                    LabeledContent("Active energy", value: "\(Int(kcal.rounded())) kcal")
                }
                LabeledContent("Date", value: workout.startDate.formatted(date: .abbreviated, time: .shortened))
            }
        }
        .navigationTitle(Format.distance(distanceMeters))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: workout.uuid) {
            avgHR = await coordinator.health.averageHeartRate(for: workout)
        }
    }
}
