import SwiftUI
import UniformTypeIdentifiers
import TrainingCore

/// The full plan, grouped by week. On top, where the plan stands; each week says what
/// it's for and how far it is; past days show what was run, changed days what they
/// were and why; the longest runs are marked; and it ends with the race outlook.
/// Any day from today on can be held and dragged onto another day to swap the two
/// sessions. Tap a run to see its steps.
///
/// A plain scroll view rather than a List: List rows don't receive drops, and the
/// scroll view auto-scrolls while a day is dragged near its edges.
struct CalendarView: View {
    let coordinator: PlanCoordinator
    @State private var targetedDay: Date?
    @State private var expandedDay: Date?
    @State private var didScrollToToday = false
    /// The swap hint shows until the first swap.
    @AppStorage("plan.hasSwappedDays") private var hasSwappedDays = false

    var body: some View {
        NavigationStack {
            Group {
                if let plan = coordinator.displayPlan {
                    planList(plan, review: coordinator.review)
                } else {
                    ContentUnavailableView("No plan yet", systemImage: "calendar")
                }
            }
            .navigationTitle("Plan")
            // Inline, so the title and its subtitle look the same at the top of the
            // plan as anywhere in it.
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func planList(_ plan: TrainingPlan, review: PlanReview?) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Horizontal padding goes on each part, not the stack, so a pinned week
                // header spans the full width and nothing shows beside it.
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    PlanOverview(plan: plan, progress: coordinator.progress, showsHint: !hasSwappedDays)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .padding(.bottom, 20)
                    ForEach(plan.weeks, id: \.index) { week in
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                if let summary = review?.weeks[week.index] {
                                    weekIntro(summary, isCurrent: isCurrent(week))
                                        .padding(.bottom, 4)
                                }
                                ForEach(week.workouts) { workout in
                                    card(workout, zones: plan.paceZones, review: review?.day(workout.date),
                                         weekNote: review?.weeks[week.index]?.changeNote)
                                }
                            }
                            .padding(.horizontal)
                            .padding(.top, 4)
                            .padding(.bottom, 28)
                        } header: {
                            weekHeader(week, summary: review?.weeks[week.index]).id("week-\(week.index)")
                        }
                    }
                    if let outlook = coordinator.outlook {
                        RaceCard(goal: plan.goal, outlook: outlook)
                            .padding(.horizontal)
                            .padding(.bottom, 24)
                    }
                }
            }
            .navigationSubtitle(subtitle(coordinator.progress))
            // A solid bar, like the pinned week header under it: the days scrolling
            // past the header shouldn't show through the title blurred.
            .toolbarBackground(Color(.systemBackground), for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .refreshable { await coordinator.refreshAdaptation() }
            .task {
                // Open on the current week, its header at the top. Wait one layout pass
                // so the lazy stack can resolve the target.
                guard !didScrollToToday,
                      let current = plan.weeks.last(where: { $0.startDate <= .now }) else { return }
                didScrollToToday = true
                try? await Task.sleep(for: .milliseconds(50))
                let week = DemoMode.planWeek.map { $0 - 1 } ?? current.index
                guard week >= 0 else { return }
                proxy.scrollTo("week-\(week)", anchor: .top)
            }
        }
    }

    /// "Week 7 of 30 · 167 days to go", always visible under the title.
    private func subtitle(_ progress: PlanProgress?) -> String {
        guard let progress else { return "" }
        var parts: [String] = []
        if let n = progress.currentWeekNumber { parts.append("Week \(n) of \(progress.totalWeeks)") }
        if progress.daysUntilRace > 0 { parts.append("\(progress.daysUntilRace) days to go") }
        return parts.joined(separator: " · ")
    }

    private func isExpandable(_ workout: PlannedWorkout) -> Bool {
        (workout.structure != nil || !workout.notes.isEmpty) && workout.type != .rest
    }

    private func toggleExpanded(_ workout: PlannedWorkout, isExpanded: Bool) {
        guard isExpandable(workout) else { return }
        withAnimation(.snappy) { expandedDay = isExpanded ? nil : workout.date }
    }

    @ViewBuilder
    private func card(_ workout: PlannedWorkout, zones: PaceZones, review: PlanReview.Day?, weekNote: String?) -> some View {
        let cal = Calendar.current
        let isPast = cal.startOfDay(for: workout.date) < cal.startOfDay(for: .now)
        let isTargeted = targetedDay.map { cal.isDate($0, inSameDayAs: workout.date) } ?? false
        let isExpanded = expandedDay.map { cal.isDate($0, inSameDayAs: workout.date) } ?? false
        let base = DayCard(
            workout: workout, zones: zones, review: review, weekNote: weekNote, isPast: isPast,
            isToday: cal.isDateInToday(workout.date), isExpanded: isExpanded
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.accentColor, lineWidth: isTargeted ? 2 : 0)
        }
        .scaleEffect(isTargeted ? 1.02 : 1)
        .animation(.snappy(duration: 0.2), value: isTargeted)
        .contentShape(.rect(cornerRadius: 14))
        .onTapGesture { toggleExpanded(workout, isExpanded: isExpanded) }
        // VoiceOver: the card opens like a button, and days swap without dragging.
        .accessibilityAddTraits(isExpandable(workout) ? .isButton : [])
        .accessibilityAction { toggleExpanded(workout, isExpanded: isExpanded) }
        .accessibilityActions {
            if coordinator.canMove(workout) {
                ForEach([-1, 1], id: \.self) { offset in
                    if let other = cal.date(byAdding: .day, value: offset, to: workout.date) {
                        Button("Swap with \(other.formatted(.dateTime.weekday(.wide)))") {
                            withAnimation(.snappy) {
                                expandedDay = nil
                                coordinator.swapDays(workout.date, other)
                                hasSwappedDays = true
                            }
                        }
                    }
                }
            }
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
                        hasSwappedDays = true
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                })
        } else {
            base
        }
    }

    /// "Week 9 · Build" and the week's distance; from its first day on, how much of
    /// it is done, with a bar for the current week.
    private func weekHeader(_ week: TrainingWeek, summary: PlanReview.Week?) -> some View {
        let started = week.startDate <= .now
        let isCurrent = isCurrent(week)
        return VStack(spacing: 6) {
            HStack {
                Text("Week \(week.index + 1) · \(week.phase.displayName)")
                Spacer()
                if let summary, started, summary.plannedMeters > 0 {
                    Text("\(Self.km(summary.doneMeters)) of \(Self.km(summary.plannedMeters))")
                        .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                } else {
                    Text(Format.distance(week.plannedVolumeMeters))
                        .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            if isCurrent, let summary, summary.plannedMeters > 0 {
                ProgressView(value: min(1, summary.doneMeters / summary.plannedMeters))
                    .tint(week.phase.tint)
                    .accessibilityHidden(true)
            }
        }
        .font(.headline)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.background)
        .accessibilityElement(children: .combine)
    }

    private func isCurrent(_ week: TrainingWeek) -> Bool {
        week.startDate <= .now && (Calendar.current.date(byAdding: .day, value: 7, to: week.startDate) ?? .now) > .now
    }

    /// What the week is for, and how the plan changed its distance. The current week
    /// also says how training is going and why the paces changed.
    private func weekIntro(_ summary: PlanReview.Week, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.purpose)
                // The box below says why for the current week, so only the distance here.
                if let change = changeLine(summary, withNote: !(isCurrent && showsBuddyPhase)) {
                    Text(change).foregroundStyle(.tint)
                }
            }
            .font(.footnote).foregroundStyle(.secondary)
            if isCurrent, !buddyLines.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(buddyLines, id: \.text) { line in
                        Label {
                            Text(line.text).font(.subheadline)
                        } icon: {
                            Image(systemName: line.symbol).foregroundStyle(.tint)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 12))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 2)
    }

    /// How training is going (when the plan is doing something about it) and why the
    /// paces changed.
    private var showsBuddyPhase: Bool {
        guard let buddy = coordinator.buddy, !buddy.message.isEmpty else { return false }
        switch buddy.phase {
        case .holding, .rebuilding, .easingBack: return true
        case .onTrack, .starting: return false
        }
    }

    private var buddyLines: [(text: String, symbol: String)] {
        var lines: [(text: String, symbol: String)] = []
        if showsBuddyPhase, let buddy = coordinator.buddy { lines.append((buddy.message, buddy.phase.symbol)) }
        if let reason = coordinator.pacing?.reason {
            lines.append((reason, coordinator.pacing?.isFaster == true ? "hare" : "tortoise"))
        }
        return lines
    }

    /// "Shortened from 52 km. No step up this time, the last weeks were a little lighter."
    private func changeLine(_ summary: PlanReview.Week, withNote: Bool) -> String? {
        let note = withNote ? summary.changeNote : nil
        let distance = summary.originalMeters.map { original in
            original > summary.plannedMeters ? "Shortened from \(Self.km(original))" : "Up from \(Self.km(original))"
        }
        switch (distance, note) {
        case let (d?, note?): return "\(d). \(note)."
        case let (d?, nil): return d + "."
        case let (nil, note?): return note + "."
        case (nil, nil): return nil
        }
    }

    /// Whole kilometres: "24 km".
    static func km(_ meters: Double) -> String { "\(Int((meters / 1_000).rounded())) km" }
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
/// Past days show what was run; changed days what they were and why.
private struct DayCard: View {
    let workout: PlannedWorkout
    let zones: PaceZones
    var review: PlanReview.Day? = nil
    /// Said once in the week's line, so not repeated on the card.
    var weekNote: String? = nil
    var isPast = false
    var isToday = false
    var isExpanded = false

    private var isRest: Bool { workout.type == .rest }
    /// The reason for a change, shown on the card rather than only when it's open.
    private var showsNoteInline: Bool {
        review?.isChanged == true && !isRest && !workout.notes.isEmpty && workout.notes != weekNote
    }

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

                VStack(alignment: .leading, spacing: 3) {
                    if let tag {
                        Label(tag.text, systemImage: tag.symbol)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(tag.tint)
                    }
                    Text(isRest && !workout.notes.isEmpty ? workout.notes : Format.workoutTitle(workout.type))
                        .font(isRest ? .subheadline : .body.weight(.medium))
                        .foregroundStyle(isRest ? .secondary : .primary)
                        .lineLimit(2)
                    if let was = wasText {
                        Text(was)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if showsNoteInline {
                        Text(workout.notes)
                            .font(.caption).foregroundStyle(.tint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let ran = ranText {
                        Label(ran.text, systemImage: ran.symbol)
                            .font(.caption)
                            .foregroundStyle(ran.tint)
                    } else if !isRest, let pace = workout.targetPaceSecPerKm {
                        if let was = review?.originalPace {
                            (Text(Format.paceRange(pace)) + Text(", was \(Format.paceRange(was))").foregroundStyle(.tint))
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(Format.paceRange(pace))
                                .font(.caption).foregroundStyle(.secondary)
                        }
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
                        if !isPast, let time = Format.estimatedDuration(distanceMeters: workout.distanceMeters, pace: workout.targetPaceSecPerKm) {
                            Text("~\(time)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    if !workout.notes.isEmpty, !showsNoteInline {
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
            } else if review?.milestone == .longestRun, !isPast {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
            }
        }
        // Days behind you are dimmed; what was run says how they went.
        .opacity(isPast ? 0.6 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(isPast ? "In the past" : "")
    }

    /// A short tag above the title: a change, or a milestone.
    private var tag: (text: String, symbol: String, tint: Color)? {
        // A change the week's line already explains needs no tag; "Was" says enough.
        if review?.isChanged == true, !isPast, weekNote == nil || showsNoteInline {
            return ("Adjusted", "arrow.triangle.2.circlepath", .accentColor)
        }
        switch review?.milestone {
        case .longestRun: return ("Longest run of the plan", "flag.fill", .accentColor)
        case .taperBegins: return ("Taper begins", "arrow.down.right", .green)
        case nil: return nil
        }
    }

    /// "Was Long Run, 20.0 km" for a changed day.
    private var wasText: String? {
        guard let review, review.isChanged, !isPast,
              let type = review.originalType, let meters = review.originalMeters else { return nil }
        guard type.isRunning else { return "Was a rest day" }
        return type == workout.type
            ? "Was \(Format.distance(meters))"
            : "Was \(Format.workoutTitle(type)), \(Format.distance(meters))"
    }

    /// What was run that day, once it's done or past.
    private var ranText: (text: String, symbol: String, tint: Color)? {
        guard let review else { return nil }
        let ran = review.ranPaceSecPerKm.map { "Ran \(Format.distance(review.ranMeters)) at \(Format.pace($0))" }
        switch review.status {
        case .done: return (ran ?? "Done", "checkmark.circle.fill", .green)
        case .shorter: return (ran ?? "Shorter", "circle.lefthalf.filled", .secondary)
        case .missed: return ("Missed", "xmark.circle", .secondary)
        case .extra: return ran.map { ($0, "plus.circle", .secondary) }
        case .upcoming, .today, .rest: return nil
        }
    }

    private var accessibilityText: String {
        let date = workout.date.formatted(.dateTime.weekday(.abbreviated).day().month())
        let title = isRest && !workout.notes.isEmpty ? workout.notes : Format.workoutTitle(workout.type)
        var parts = [date]
        if let tag { parts.append(tag.text) }
        parts.append(isRest ? title : "\(title), \(Format.distance(workout.distanceMeters))")
        if let wasText { parts.append(wasText) }
        if showsNoteInline { parts.append(workout.notes) }
        if !isPast, let was = review?.originalPace { parts.append("pace was \(Format.paceRange(was))") }
        if let ranText { parts.append(ranText.text) }
        return parts.joined(separator: ", ")
    }
}

/// The whole plan at a glance: a bar of the phases with the current week marked.
private struct PlanOverview: View {
    let plan: TrainingPlan
    let progress: PlanProgress?
    let showsHint: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The week and days to go are in the subtitle; this is the whole plan.
            Text("\(plan.weeks.count) weeks to \(plan.goal.displayName)")
                .font(.headline)
            phaseBar
            if showsHint {
                Label("Hold a day and drag it onto another to swap them.", systemImage: "hand.draw")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: .rect(cornerRadius: 16))
    }

    /// One segment per week in its phase's colour, weeks already behind you full,
    /// later ones lighter, the current one taller.
    private var phaseBar: some View {
        let current = (progress?.currentWeekNumber ?? 0) - 1
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 2) {
                ForEach(plan.weeks, id: \.index) { week in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(week.phase.tint.opacity(week.index <= current ? 1 : 0.35))
                        .frame(height: week.index == current ? 14 : 8)
                }
            }
            HStack(spacing: 10) {
                ForEach(phases, id: \.self) { phase in
                    HStack(spacing: 4) {
                        Circle().fill(phase.tint).frame(width: 6, height: 6)
                        Text(phase.displayName)
                    }
                }
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phaseSummary)
    }

    /// The phases this plan has, in order.
    private var phases: [TrainingPhase] {
        var seen: [TrainingPhase] = []
        for week in plan.weeks where !seen.contains(week.phase) { seen.append(week.phase) }
        return seen
    }

    private var phaseSummary: String {
        phases.map { phase in
            let n = plan.weeks.filter { $0.phase == phase }.count
            return "\(phase.displayName), \(n) \(n == 1 ? "week" : "weeks")"
        }.joined(separator: ", ")
    }

}

/// The end of the plan: the race, and what to expect on the day.
private struct RaceCard: View {
    let goal: Goal
    let outlook: GoalOutlook

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(goal.displayName, systemImage: "flag.checkered")
                .font(.headline)
            Text(goal.raceDate.formatted(date: .complete, time: .omitted))
                .font(.subheadline).foregroundStyle(.secondary)
            if let verdict = outlook.verdict {
                Label {
                    Text(verdict.title).font(.subheadline.weight(.semibold))
                } icon: {
                    Image(systemName: verdict.symbol).foregroundStyle(verdict.tint)
                }
            }
            LabeledContent("Race day, at this rate", value: GoalOutlook.rangeText(outlook.raceDay))
                .font(.subheadline)
            if let target = goal.targetTimeSeconds {
                LabeledContent("Your target", value: GoalOutlook.format(target))
                    .font(.subheadline)
            }
            Text("More in Progress.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
