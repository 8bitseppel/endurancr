import SwiftUI
import UniformTypeIdentifiers
import TrainingCore

/// The full plan, grouped by week, with each week's phase and volume. Past days are
/// struck through; any day from today on can be held and dragged onto another day
/// to swap the two sessions. Tap a run to see its steps.
///
/// A plain scroll view rather than a List: List rows don't receive drops, and the
/// scroll view auto-scrolls while a day is dragged near its edges.
struct CalendarView: View {
    let coordinator: PlanCoordinator
    @State private var targetedDay: Date?
    @State private var expandedDay: Date?
    @State private var didScrollToToday = false

    var body: some View {
        NavigationStack {
            Group {
                if let plan = coordinator.displayPlan {
                    planList(plan)
                } else {
                    ContentUnavailableView("No plan yet", systemImage: "calendar")
                }
            }
            .navigationTitle("Plan")
            .toolbar {
                if coordinator.hasMovedDays {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Undo moves") {
                            Task { await coordinator.resetMovedDays() }
                        }
                    }
                }
            }
        }
    }

    private func planList(_ plan: TrainingPlan) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6, pinnedViews: .sectionHeaders) {
                    Text("Hold a day and drag it onto another to swap them.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                    ForEach(plan.weeks, id: \.index) { week in
                        Section {
                            ForEach(week.workouts) { workout in
                                card(workout, zones: plan.paceZones)
                            }
                        } header: {
                            weekHeader(week)
                        }
                        .id(week.index)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .refreshable { await coordinator.refreshAdaptation() }
            .onAppear {
                // Open on the current week, not week 1.
                guard !didScrollToToday,
                      let current = plan.weeks.last(where: { $0.startDate <= .now }) else { return }
                didScrollToToday = true
                proxy.scrollTo(current.index, anchor: .top)
            }
        }
    }

    @ViewBuilder
    private func card(_ workout: PlannedWorkout, zones: PaceZones) -> some View {
        let cal = Calendar.current
        let isPast = cal.startOfDay(for: workout.date) < cal.startOfDay(for: .now)
        let isTargeted = targetedDay.map { cal.isDate($0, inSameDayAs: workout.date) } ?? false
        let isExpanded = expandedDay.map { cal.isDate($0, inSameDayAs: workout.date) } ?? false
        let base = DayCard(
            workout: workout, zones: zones, isPast: isPast,
            isToday: cal.isDateInToday(workout.date), isExpanded: isExpanded
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.accentColor, lineWidth: isTargeted ? 2 : 0)
        }
        .scaleEffect(isTargeted ? 1.02 : 1)
        .animation(.snappy(duration: 0.2), value: isTargeted)
        .contentShape(.rect(cornerRadius: 14))
        .onTapGesture {
            guard workout.structure != nil || !workout.notes.isEmpty, workout.type != .rest else { return }
            withAnimation(.snappy) { expandedDay = isExpanded ? nil : workout.date }
        }

        if coordinator.canMove(workout) {
            base
                .draggable(String(workout.date.timeIntervalSince1970)) {
                    DayCard(workout: workout, zones: zones, isPast: false, isToday: false, isExpanded: false)
                        .frame(width: 340)
                        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14))
                }
                .onDrop(of: [.plainText], delegate: SwapDropDelegate(day: workout.date, targetedDay: $targetedDay) { from in
                    withAnimation(.snappy) {
                        expandedDay = nil
                        coordinator.swapDays(from, workout.date)
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                })
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
        .font(.subheadline.weight(.semibold))
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.background)
    }
}

/// Accepts a dragged day and swaps it with this one. A delegate rather than
/// `dropDestination` so the drop reads as a move (no green "+" copy badge).
private struct SwapDropDelegate: DropDelegate {
    let day: Date
    @Binding var targetedDay: Date?
    let onSwap: @MainActor (Date) -> Void

    func dropEntered(info: DropInfo) {
        targetedDay = day
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func dropExited(info: DropInfo) {
        if targetedDay.map({ Calendar.current.isDate($0, inSameDayAs: day) }) ?? false { targetedDay = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        targetedDay = nil
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        let target = day
        _ = provider.loadObject(ofClass: String.self) { string, _ in
            guard let from = string.flatMap(Double.init).map(Date.init(timeIntervalSince1970:)),
                  !Calendar.current.isDate(from, inSameDayAs: target) else { return }
            Task { @MainActor in onSwap(from) }
        }
        return true
    }
}

/// One day of the plan: date on the left, session in the middle, distance on the right.
private struct DayCard: View {
    let workout: PlannedWorkout
    let zones: PaceZones
    var isPast = false
    var isToday = false
    var isExpanded = false

    private var isRest: Bool { workout.type == .rest }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Text(workout.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.caption2.weight(.semibold)).textCase(.uppercase)
                        .foregroundStyle(isToday ? Color.accentColor : .secondary)
                    Text(workout.date.formatted(.dateTime.day()))
                        .font(.title3.weight(.semibold)).monospacedDigit()
                }
                .frame(width: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isRest && !workout.notes.isEmpty ? workout.notes : Format.workoutTitle(workout.type))
                        .font(isRest ? .subheadline : .body.weight(.medium))
                        .foregroundStyle(isRest ? .secondary : .primary)
                        .lineLimit(2)
                    if !isRest, let pace = workout.targetPaceSecPerKm {
                        Text(Format.paceRange(pace))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                if isRest {
                    Image(systemName: Format.restSymbol(note: workout.notes))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Format.distance(workout.distanceMeters))
                            .font(.body.weight(.semibold)).monospacedDigit()
                        if let time = Format.estimatedDuration(distanceMeters: workout.distanceMeters, pace: workout.targetPaceSecPerKm) {
                            Text("~\(time)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    if !workout.notes.isEmpty {
                        Text(workout.notes)
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let structure = workout.structure {
                        WorkoutStepsView(structure: structure, zones: zones)
                    }
                }
                .padding(.leading, 52)
                .transition(.opacity)
            }
        }
        .padding(.vertical, isRest ? 8 : 10)
        .padding(.horizontal, 12)
        .background(
            isRest ? AnyShapeStyle(.clear) : AnyShapeStyle(.fill.tertiary),
            in: .rect(cornerRadius: 14)
        )
        .overlay {
            if isRest {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        // Days already behind you are struck through and dimmed.
        .strikethrough(isPast)
        .opacity(isPast ? 0.45 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(isPast ? "In the past" : "")
    }

    private var accessibilityText: String {
        let date = workout.date.formatted(.dateTime.weekday(.abbreviated).day().month())
        let title = isRest && !workout.notes.isEmpty ? workout.notes : Format.workoutTitle(workout.type)
        return isRest ? "\(date), \(title)" : "\(date), \(title), \(Format.distance(workout.distanceMeters))"
    }
}
