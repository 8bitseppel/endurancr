import SwiftUI
import TrainingCore

/// The full plan, grouped by week, with each week's phase and volume. Past days are
/// struck through; any day from today on can be held and dragged onto another day
/// to swap the two sessions.
struct CalendarView: View {
    let coordinator: PlanCoordinator
    @State private var targetedDay: Date?

    var body: some View {
        NavigationStack {
            List {
                if let plan = coordinator.displayPlan {
                    ForEach(plan.weeks, id: \.index) { week in
                        Section(header: weekHeader(week)) {
                            ForEach(week.workouts) { workout in
                                row(workout, zones: plan.paceZones)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("No plan yet", systemImage: "calendar")
                }
            }
            .navigationTitle("Plan")
            .refreshable { await coordinator.refreshAdaptation() }
            .toolbar {
                if coordinator.hasMovedDays {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Undo moves") {
                            Task { await coordinator.resetMovedDays() }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if coordinator.displayPlan != nil {
                    Text("Hold a day and drag it onto another to swap them.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .padding(.vertical, 8).frame(maxWidth: .infinity)
                        .background(.bar)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ workout: PlannedWorkout, zones: PaceZones) -> some View {
        let isPast = Calendar.current.startOfDay(for: workout.date) < Calendar.current.startOfDay(for: .now)
        let base = WorkoutRow(workout: workout, zones: zones, isPast: isPast)
        if coordinator.canMove(workout) {
            let key = workout.date.timeIntervalSince1970
            base
                .draggable(String(key)) {
                    WorkoutRow(workout: workout, zones: zones, isPast: false)
                        .padding().frame(width: 320)
                        .background(.background, in: .rect(cornerRadius: 12))
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let from = items.first.flatMap(Double.init).map(Date.init(timeIntervalSince1970:)),
                          !Calendar.current.isDate(from, inSameDayAs: workout.date) else { return false }
                    withAnimation { coordinator.swapDays(from, workout.date) }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    return true
                } isTargeted: { targeted in
                    if targeted { targetedDay = workout.date }
                    else if targetedDay == workout.date { targetedDay = nil }
                }
                .listRowBackground(targetedDay == workout.date ? Color.accentColor.opacity(0.18) : nil)
        } else {
            base
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
    var isPast = false

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
                    if let structure = workout.structure, !isPast {
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
        // Days already behind you are struck through and dimmed.
        .strikethrough(isPast)
        .opacity(isPast ? 0.5 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityHint(isPast ? "In the past" : "")
    }
}
