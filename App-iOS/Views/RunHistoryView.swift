import SwiftUI
import HealthKit
import TrainingCore

/// Lists recorded running workouts from Apple Health (most recent first). Tapping
/// one opens a detail view with its GPS route and stats. Recordings with hardly any
/// running in them aren't listed, and a run recorded twice (watch and iPhone) says
/// which one counts, as in `CompletedRun.cleaned`.
struct RunHistoryView: View {
    let coordinator: PlanCoordinator

    @State private var workouts: [HKWorkout] = []
    @State private var hiddenCount = 0
    /// Start times of the runs that count; one of two overlapping recordings doesn't.
    @State private var counted: Set<String> = []
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
                Section {
                    ForEach(workouts, id: \.uuid) { workout in
                        NavigationLink {
                            RunDetailView(workout: workout, coordinator: coordinator)
                        } label: {
                            row(workout)
                        }
                    }
                } footer: {
                    if hiddenCount > 0 {
                        Text("\(hiddenCount) \(hiddenCount == 1 ? "recording" : "recordings") with hardly any running (under 200 m or a minute) \(hiddenCount == 1 ? "isn't" : "aren't") shown or counted.")
                    }
                }
            }
        }
        .navigationTitle("Recent runs")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let since = Calendar.current.date(byAdding: .month, value: -6, to: .now) ?? .now
            let all = await coordinator.health.recentRunningWorkouts(since: since)
            workouts = all.filter { coordinator.health.distanceMeters(for: $0) >= 200 && $0.duration >= 60 }
            hiddenCount = all.count - workouts.count
            counted = Set(CompletedRun.cleaned(workouts.map(run)).map(Self.key))
            loading = false
        }
    }

    private static func key(_ run: CompletedRun) -> String {
        "\(run.date.timeIntervalSince1970)|\(Int(run.distanceMeters))"
    }

    private func run(_ workout: HKWorkout) -> CompletedRun {
        CompletedRun(date: workout.startDate, distanceMeters: coordinator.health.distanceMeters(for: workout),
                     durationSeconds: workout.duration)
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
                Text("·").foregroundStyle(.secondary)
                Text(workout.sourceRevision.source.name)
            }
            .font(.caption).foregroundStyle(.secondary)
            if !counted.contains(Self.key(run(workout))) {
                Text("Recorded at the same time as another recording, so the run counts once")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
                LabeledContent("Recorded by", value: workout.sourceRevision.source.name)
            }
        }
        .navigationTitle(Format.distance(distanceMeters))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: workout.uuid) {
            avgHR = await coordinator.health.averageHeartRate(for: workout)
        }
    }
}
