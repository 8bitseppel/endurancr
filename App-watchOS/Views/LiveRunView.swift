import SwiftUI
import TrainingCore
import WatchKit

/// Live run screen on two vertical pages, moved between with the Digital Crown or
/// a swipe. The first holds what matters while running (time, heart rate, distance
/// and pace with their targets) and fits the screen without scrolling, so the
/// swipe always reaches the second page: Pause/Resume, Finish and GPS.
///
/// Pause/Resume also sits in the top corner on both pages, and a double tap
/// (pinching twice) presses it, so a run pauses without touching the screen.
///
/// When today's session is a planned workout, the screen shows step-aware targets:
/// the current step (e.g. "Rep 3/6") with its own target distance and pace, so an
/// interval session's targets advance automatically as each step's distance is
/// covered — no need to look up the plan mid-run. A free run (no plan) shows just
/// live pace and distance.
struct LiveRunView: View {
    @Bindable var workout: WorkoutManager
    /// Today's planned session, if this run follows the plan. `nil` = free run.
    var plannedWorkout: PlannedWorkout?
    /// Paces for the athlete's current fitness. `nil` = free run.
    var zones: PaceZones?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var page = Page.metrics
    enum Page { case metrics, details, controls }
    /// The full-screen card at a step change, or just before a rep.
    @State private var card: StepCard?
    /// The rep already announced with "get ready", so it's announced once.
    @State private var readiedStep: Int?

    /// Every step of the session, in order; empty for a free run.
    private var steps: [WorkoutStep] {
        guard let plannedWorkout, let zones else { return [] }
        return WorkoutSteps.steps(for: plannedWorkout, zones: zones)
    }

    /// The step the athlete is currently in, given how far they've run.
    private var activeStep: WorkoutStep? {
        guard let plannedWorkout, let zones else { return nil }
        return WorkoutSteps.activeStep(
            for: plannedWorkout, zones: zones, distanceCovered: workout.distanceMeters
        )
    }

    var body: some View {
        TabView(selection: $page) {
            metricsPage.tag(Page.metrics)
            detailsPage.tag(Page.details)
            controlsPage.tag(Page.controls)
        }
        .tabViewStyle(.verticalPage)
        .demoTurnPages($page, through: UserDefaults.standard.bool(forKey: "demoStepCard") ? [] : [.details, .controls])
        .navigationTitle(workout.isAutoPaused ? "Auto-paused" : workout.isPaused ? "Paused" : "Running")
        .navigationBarTitleDisplayMode(.inline)
        // Leaving the screen would leave the run recording with no way back to it;
        // Finish is the way out.
        .navigationBarBackButtonHidden(true)
        .onChange(of: isLuminanceReduced) { _, dimmed in
            // Wrist down: show the numbers, not the buttons, as Apple's Workout app does.
            if dimmed { page = .metrics }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    togglePause()
                } label: {
                    Image(systemName: workout.isPaused ? "play.fill" : "pause.fill")
                }
                .tint(workout.isPaused ? .green : .yellow)
                .accessibilityLabel(workout.isPaused ? "Resume" : "Pause")
                // Double tap: pinch index finger and thumb twice.
                .handGestureShortcut(.primaryAction)
            }
        }
        .onChange(of: workout.isRunning) { _, running in
            // Finished from the iPhone's Live Activity: close like Finish here.
            if !running { dismiss() }
        }
        .overlay {
            if let card {
                StepCardView(card: card)
                    .onTapGesture { withAnimation { self.card = nil } }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .onChange(of: activeStep?.index) { old, new in
            // A new step began: say what's next, full screen, with a tap you can tell
            // apart without looking (a rep starts, a break starts, all reps done).
            guard let old, let new, old != new, let step = activeStep else { return }
            announce(step)
        }
        .onChange(of: workout.distanceMeters) { old, distance in
            readyNextRep(at: distance)
            // The planned distance reached: one tap and a note, nothing more.
            if let planned = plannedWorkout, planned.distanceMeters > 0,
               old < planned.distanceMeters, distance >= planned.distanceMeters {
                WKInterfaceDevice.current().play(.success)
                show(StepCard(title: "Plan done",
                              detail: "\(Format.workoutTitle(planned.type)), \(Format.distance(planned.distanceMeters))",
                              note: "", tint: .green, haptic: .success))
            }
        }
        #if DEBUG
        .task {
            // `-demoStepCard YES`: rep 3 of an interval session. The still shows "Go";
            // with `-demoScroll` it plays get ready, Go, the run screen, then page 2.
            guard DemoMode.isOn, UserDefaults.standard.bool(forKey: "demoStepCard"),
                  let rep = steps.first(where: { $0.kind == .work && $0.repNumber == 3 }) else { return }
            let go = card(for: rep)
            guard UserDefaults.standard.bool(forKey: "demoScroll") else { card = go; return }
            card = StepCard(title: "\(repTitle(rep)) in 100 m", detail: stepDetail(rep), note: "Get ready",
                            tint: .yellow, haptic: .notification)
            try? await Task.sleep(for: .seconds(3))
            withAnimation { card = go }
            try? await Task.sleep(for: .seconds(3))
            withAnimation { card = nil }
            try? await Task.sleep(for: .seconds(3))
            withAnimation { page = .details }
            try? await Task.sleep(for: .seconds(3))
            withAnimation { page = .controls }
            try? await Task.sleep(for: .seconds(3))
            withAnimation { page = .metrics }
        }
        #endif
        .onChange(of: workout.isAutoPaused) { _, paused in
            // watchOS's Auto-Pause, felt at the traffic light without looking.
            WKInterfaceDevice.current().play(paused ? .stop : .start)
        }
    }

    // MARK: Step guidance

    private func announce(_ step: WorkoutStep) {
        // The last rep's easy part already said "All done"; the cool-down after it
        // starts without another card.
        if step.kind == .cooldown, step.index > 0, isLastRecovery(steps[step.index - 1]) { return }
        let next = card(for: step)
        WKInterfaceDevice.current().play(next.haptic)
        show(next)
    }

    /// Just before a rep: "Rep 3 of 6 in 100 m", so it doesn't come as a surprise.
    private func readyNextRep(at distance: Double) {
        guard let step = activeStep, step.kind != .work,
              step.index + 1 < steps.count else { return }
        let rep = steps[step.index + 1]
        guard rep.kind == .work, readiedStep != rep.index else { return }
        let lead = min(100, step.distanceMeters / 2)
        let left = step.startMeters + step.distanceMeters - distance
        guard left <= lead else { return }
        readiedStep = rep.index
        WKInterfaceDevice.current().play(.notification)
        // Rounded to 10 m: "in 70 m", not "in 74 m".
        let meters = max(10, Int((left / 10).rounded()) * 10)
        show(StepCard(title: "\(repTitle(rep)) in \(meters) m",
                      detail: stepDetail(rep), note: "Get ready", tint: .yellow, haptic: .notification))
    }

    private func show(_ next: StepCard) {
        #if DEBUG
        if DemoMode.isOn { print("[step] at \(Int(workout.distanceMeters)) m, tap \(next.haptic.rawValue): \(next.note) | \(next.title) | \(next.detail)") }
        #endif
        withAnimation { card = next }
        AccessibilityNotification.Announcement("\(next.title). \(next.detail). \(next.note)").post()
        Task {
            try? await Task.sleep(for: .seconds(5))
            if card == next { withAnimation { card = nil } }
        }
    }

    private func card(for step: WorkoutStep) -> StepCard {
        switch step.kind {
        case .work:
            return StepCard(title: repTitle(step), detail: stepDetail(step), note: "Go", tint: .green, haptic: .start)
        case .recovery where isLastRecovery(step):
            // After the last rep: straight to the cool-down, counting its easy part in.
            let cooldown = steps.last { $0.kind == .cooldown }?.distanceMeters ?? 0
            // Strides end an easy run, which has no cool-down of its own.
            return StepCard(title: cooldown > 0 ? "Cool-down" : "Easy to the end", detail: "\(Format.distanceCompact(step.distanceMeters + cooldown)) easy",
                            note: "All \(step.repTotal ?? 1) done. Well run.", tint: .accentColor, haptic: .success)
        case .recovery:
            let done = step.repNumber.flatMap { n in step.repTotal.map { "\(n) of \($0) done" } } ?? "Done"
            return StepCard(title: "Easy now", detail: stepDetail(step), note: done, tint: .accentColor, haptic: .directionDown)
        case .cooldown:
            let reps = steps.last { $0.kind == .work }?.repTotal ?? 1
            return StepCard(title: "Cool-down", detail: stepDetail(step),
                            note: reps > 1 ? "All \(reps) done. Well run." : "Done. Well run.",
                            tint: .accentColor, haptic: .success)
        case .warmup, .steady:
            return StepCard(title: step.label.isEmpty ? "Run" : step.label, detail: stepDetail(step), note: "",
                            tint: .accentColor, haptic: .click)
        }
    }

    /// The easy part after the last rep, when nothing but easy running follows.
    private func isLastRecovery(_ step: WorkoutStep) -> Bool {
        step.kind == .recovery && step.repNumber == step.repTotal
            && !steps.dropFirst(step.index + 1).contains { $0.kind == .work }
    }

    /// "Rep 3 of 6", "Stride 2 of 6", or the block's name ("Threshold").
    private func repTitle(_ step: WorkoutStep) -> String {
        guard let n = step.repNumber, let total = step.repTotal, total > 1 else { return step.label }
        return "\(step.label.hasPrefix("Stride") ? "Stride" : "Rep") \(n) of \(total)"
    }

    /// "1 km at 4:15/km", "400 m easy".
    private func stepDetail(_ step: WorkoutStep) -> String {
        let distance = Format.distanceCompact(step.distanceMeters)
        if step.kind == .recovery || step.kind == .cooldown || step.paceType == .easy { return "\(distance) easy" }
        return "\(distance) at \(step.targetPaceSecPerKm.map(Format.pace) ?? "race effort")"
    }

    /// Page 1: everything needed while running, on one screen. It never scrolls,
    /// so the Crown always reaches page 2; large text sizes shrink the numbers.
    private var metricsPage: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                clock
                Spacer(minLength: 4)
                heartRate
            }

            if let step = activeStep, let plannedWorkout {
                if !step.label.isEmpty { stepBanner(step) }
                metricPair(
                    "Distance", Format.distance(workout.distanceMeters),
                    "Target", Format.distance(plannedWorkout.distanceMeters)
                )
                metricPair(
                    "Pace", Format.pace(workout.paceSecPerKm),
                    "Target", step.targetPaceSecPerKm.map(Format.pace) ?? "--",
                    valueTint: paceTint(target: step.targetPaceSecPerKm)
                )
            } else {
                // Free run: no plan, so just live pace and distance.
                metric("Distance", Format.distance(workout.distanceMeters), tint: .accentColor)
                metric("Pace", Format.pace(workout.paceSecPerKm), tint: .primary)
            }
        }
        // Numbers shrink a little before the page has to scroll.
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 4)
    }

    /// The run's time, ticking every second from HealthKit's own count (paused
    /// time excluded), also in Always On.
    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = workout.elapsedTime(at: context.date)
            Text(Format.duration(seconds))
                .font(.system(.title, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(workout.isPaused || workout.isAutoPaused ? .yellow : .primary)
                .accessibilityLabel("Time \(Duration.seconds(seconds.rounded()).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide)))")
        }
    }

    /// Page 2: the rest worth knowing mid-run, two columns, no scrolling: the averages,
    /// the last kilometre and the one in progress (the rep in progress during intervals),
    /// the climb and what's left of the plan. Page 1 stays the numbers that matter most.
    private var detailsPage: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            GridRow {
                detail("Avg pace", workout.averagePaceSecPerKm > 0 ? Format.pace(workout.averagePaceSecPerKm) : "--")
                detail("Avg HR", workout.averageHeartRate > 0 ? "\(Int(workout.averageHeartRate))" : "--")
            }
            GridRow {
                detail("Last km", workout.lastKmSeconds.map(Format.duration) ?? "--")
                // During a rep: the rep's pace so far; otherwise the kilometre in progress.
                if activeStep?.kind == .work, !(activeStep?.label.hasPrefix("Stride") ?? false) {
                    detail("This rep", workout.thisRepPaceSecPerKm.map(Format.pace) ?? "--",
                           tint: paceTint(target: activeStep?.targetPaceSecPerKm, pace: workout.thisRepPaceSecPerKm))
                } else {
                    detail("This km", workout.thisKmPaceSecPerKm.map(Format.pace) ?? "--")
                }
            }
            GridRow {
                detail("Climb", "\(Int(workout.elevationGainMeters.rounded())) m")
                toGo
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 4)
    }

    /// What's left of today's run, with the time it'll be done at today's pace; once
    /// the planned distance is run, "Done", then how far beyond it. A free run has no
    /// target, so its cadence shows instead.
    @ViewBuilder private var toGo: some View {
        if let planned = plannedWorkout?.distanceMeters, planned > 0 {
            let left = planned - workout.distanceMeters
            if left > 0 {
                let pace = workout.averagePaceSecPerKm
                let done = pace > 0 ? Date.now.addingTimeInterval(left / 1_000 * pace) : nil
                detail(done.map { "To go \($0.formatted(date: .omitted, time: .shortened))" } ?? "To go",
                       Format.distance(left))
            } else if -left < 500 {
                detail("Plan", "Done", tint: .green)
            } else {
                detail("Beyond plan", "+" + Format.distance(-left), tint: .green)
            }
        } else {
            detail("Cadence", workout.cadence > 0 ? "\(Int(workout.cadence.rounded()))" : "--")
        }
    }

    private func detail(_ label: String, _ value: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased()).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Page 3: the controls and GPS.
    private var controlsPage: some View {
        VStack(spacing: 8) {
            controls
            gpsStatus
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
    }

    /// The current step: its label ("Rep 3/6"), step distance, and step target pace.
    /// A steady run shows the overall target instead of a per-step label.
    private func stepBanner(_ step: WorkoutStep) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(step.label.isEmpty ? "Target" : step.label)
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.tint)
            Text("\(Format.distanceCompact(step.distanceMeters)) @ \(step.targetPaceSecPerKm.map(Format.pace) ?? "--")")
                .font(.footnote).monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func paceTint(target: Double?, pace: Double? = nil) -> Color {
        let pace = pace ?? workout.paceSecPerKm
        guard let target, pace > 0 else { return .green }
        // Within ±5 s/km of the step target reads as on-pace.
        return abs(pace - target) <= 5 ? .green : .orange
    }

    private var controls: some View {
        VStack(spacing: 8) {
            Button {
                togglePause()
            } label: {
                Label(workout.isPaused ? "Resume" : "Pause",
                      systemImage: workout.isPaused ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .tint(workout.isPaused ? .green : .yellow)
            .controlSize(.large)

            // Held for a second, so a brush of the wrist doesn't end the run.
            HoldToFinishButton {
                workout.end()   // the screen closes when the run stops (onChange above)
            }
        }
    }

    private func togglePause() {
        WKInterfaceDevice.current().play(.click)
        workout.isPaused ? workout.resume() : workout.pause()
    }

    private var heartRate: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Image(systemName: "heart.fill").foregroundStyle(.red).font(.footnote)
            Text(workout.heartRate > 0 ? "\(Int(workout.heartRate))" : "--")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(workout.heartRate > 0 ? "Heart rate \(Int(workout.heartRate)) beats per minute" : "Heart rate acquiring")
    }

    private func metric(_ label: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value)")
    }

    /// A live value alongside its target, so pace/target and distance/target sit
    /// on one row and read at a glance.
    private func metricPair(
        _ label: String, _ value: String,
        _ targetLabel: String, _ targetValue: String,
        valueTint: Color = .accentColor
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label.uppercased()).font(.caption2).foregroundStyle(.secondary)
                Text(value)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .monospacedDigit().foregroundStyle(valueTint)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(targetLabel.uppercased()).font(.caption2).foregroundStyle(.secondary)
                Text(targetValue)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
        }
        // One VoiceOver stop: "Pace 6:42/km, target 6:42/km".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value), \(targetLabel.lowercased()) \(targetValue)")
    }

    private var gpsStatus: some View {
        Label(
            workout.routePointCount > 0 ? "GPS \(workout.routePointCount) pts" : "GPS acquiring…",
            systemImage: "location.fill"
        )
        .font(.caption2)
        .foregroundStyle(workout.routePointCount > 0 ? Color.secondary : Color.orange)
    }
}

extension View {
    /// In demo screen recordings, moves to the second page and back the way the
    /// watch does when the Crown is turned: it sets the page and lets the paged
    /// view run its own transition (the blur from page to page). Nothing otherwise.
    /// Like `demoTurnPage`, through every page in turn, then back to the first.
    func demoTurnPages<Page: Hashable>(_ page: Binding<Page>, through pages: [Page]) -> some View {
        #if DEBUG
        task {
            guard DemoMode.isOn, UserDefaults.standard.bool(forKey: "demoScroll") else { return }
            let first = page.wrappedValue
            for next in pages where next != first {
                try? await Task.sleep(for: .seconds(3.5))
                withAnimation { page.wrappedValue = next }
            }
            try? await Task.sleep(for: .seconds(3.5))
            withAnimation { page.wrappedValue = first }
        }
        #else
        self
        #endif
    }

    func demoTurnPage<Page: Hashable>(_ page: Binding<Page>, to second: Page, unless skip: Bool = false) -> some View {
        #if DEBUG
        task {
            guard DemoMode.isOn, UserDefaults.standard.bool(forKey: "demoScroll"), !skip else { return }
            let first = page.wrappedValue
            try? await Task.sleep(for: .seconds(4))
            withAnimation { page.wrappedValue = second }
            try? await Task.sleep(for: .seconds(4.5))
            withAnimation { page.wrappedValue = first }
        }
        #else
        self
        #endif
    }
}

/// What the run screen says, full screen, at a step change.
struct StepCard: Equatable {
    var title: String
    var detail: String
    var note: String
    var tint: Color
    var haptic: WKHapticType
}

private struct StepCardView: View {
    let card: StepCard

    var body: some View {
        VStack(spacing: 6) {
            if !card.note.isEmpty {
                Text(card.note)
                    .font(.headline)
                    .foregroundStyle(card.tint)
            }
            Text(card.title)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
            Text(card.detail)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .lineLimit(2)
        .minimumScaleFactor(0.7)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThickMaterial)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Closes")
    }
}

/// Finish, held for a second: a ring fills around the button while it's held, and the
/// run ends when it's full, with a tap on the wrist. Letting go early does nothing.
/// VoiceOver gets a plain Finish action, as holding is hard there.
struct HoldToFinishButton: View {
    let onFinish: () -> Void
    @State private var holding = false
    @State private var progress: CGFloat = 0

    var body: some View {
        Label(holding ? "Keep holding" : "Hold to finish", systemImage: "stop.fill")
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(.red.opacity(holding ? 0.45 : 0.3), in: .capsule)
            .overlay {
                Capsule()
                    .trim(from: 0, to: progress)
                    .stroke(.red, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
            .contentShape(.capsule)
            .onLongPressGesture(minimumDuration: 1, maximumDistance: 20) {
                WKInterfaceDevice.current().play(.success)
                onFinish()
            } onPressingChanged: { pressing in
                holding = pressing
                if pressing {
                    WKInterfaceDevice.current().play(.click)
                    withAnimation(.linear(duration: 1)) { progress = 1 }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Finish run")
            .accessibilityHint("Hold for one second to finish")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onFinish() }
    }
}
