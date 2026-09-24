import SwiftUI
import TrainingCore

/// The full plan, grouped by week, with each week's phase and volume.
struct CalendarView: View {
    let coordinator: PlanCoordinator

    var body: some View {
        NavigationStack {
            List {
                if let plan = coordinator.displayPlan {
                    ForEach(plan.weeks, id: \.index) { week in
                        Section(header: weekHeader(week)) {
                            ForEach(week.workouts) { workout in
                                WorkoutRow(workout: workout, zones: plan.paceZones)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("No plan yet", systemImage: "calendar")
                }
            }
            .navigationTitle("Plan")
            .refreshable { await coordinator.refreshAdaptation() }
        }
    }

    private func weekHeader(_ week: TrainingWeek) -> some View {
        HStack {
            Text("Week \(week.index + 1) · \(week.phase.rawValue.capitalized)")
            Spacer()
            Text(Format.distance(week.plannedVolumeMeters))
                .foregroundStyle(.secondary)
        }
    }
}

private struct WorkoutRow: View {
    let workout: PlannedWorkout
    let zones: PaceZones

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(workout.date.formatted(.dateTime.weekday(.abbreviated).day().month()))
                    .font(.caption).foregroundStyle(.secondary)
                Text(workout.type == .rest && !workout.notes.isEmpty ? workout.notes : Format.workoutTitle(workout.type))
                    .font(.body)
                if workout.type != .rest {
                    if let pace = workout.targetPaceSecPerKm {
                        Text(Format.paceRange(pace))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !workout.notes.isEmpty {
                        Text(workout.notes)
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let structure = workout.structure {
                        WorkoutStepsView(structure: structure, zones: zones)
                            .padding(.top, 1)
                    }
                }
            }
            Spacer()
            if workout.type != .rest {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.distance(workout.distanceMeters))
                    if let time = Format.estimatedDuration(distanceMeters: workout.distanceMeters, pace: workout.targetPaceSecPerKm) {
                        Text("~\(time)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Image(systemName: Format.restSymbol(note: workout.notes))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
