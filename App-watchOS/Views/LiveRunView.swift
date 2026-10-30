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
///
/// Inside the strides at the end of an easy run, the first page gives the whole
/// screen to the one thing that matters for the next 20 seconds: the seconds left,
/// large enough to read at a glance, and how many strides are done. Which step the
/// run is in, and the taps on the wrist that go with it, come from `WorkoutManager`
/// (see `RunCue`), so they're right whether or not the screen is awake.
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
    /// The full-screen card at a step change, as the recorder decided it.
    @State private var card: RunCue?

    /// Every step of the session, in order; empty for a free run.
    private var steps: [WorkoutStep] { workout.guided?.steps ?? [] }

    /// The step the athlete is currently in.
    private var activeStep: WorkoutStep? { workout.activeStep }

    /// Inside the strides: a stride, or the easy minute that sets one up. The page
    /// then shows the countdown and nothing else.
    private var strideStep: WorkoutStep? {
        guard let step = activeStep,
              step.kind == .stride || (step.kind == .recovery && step.seconds != nil) else { return nil }
        return step
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
        // A step began: the recorder has already tapped the wrist, here it's shown.
        .onChange(of: workout.cue) { _, cue in
            guard let cue, let seconds = cue.screenSeconds else { return }
            show(cue, for: seconds)
        }
        #if DEBUG
        .task {
            // `-demoStepCard YES`: rep 3 of an interval session. The still shows "Go";
            // with `-demoScroll` it plays get ready, Go, the run screen, then page 2.
            guard DemoMode.isOn, UserDefaults.standard.bool(forKey: "demoStepCard"),
                  let rep = steps.first(where: { $0.kind == .work && $0.repNumber == 3 }) else { return }
            let go = RunCue(title: repTitle(rep), detail: stepDetail(rep), note: "Go", tone: .go)
            guard UserDefaults.standard.bool(forKey: "demoScroll") else { card = go; return }
            card = RunCue(title: "\(repTitle(rep)) in 100 m", detail: stepDetail(rep), note: "Get ready", tone: .ready)
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

    /// Shows the cue the recorder decided on. The tap on the wrist has already
    /// happened there, so it's felt even with the screen asleep.
    private func show(_ next: RunCue, for seconds: Double) {
        withAnimation { card = next }
        AccessibilityNotification.Announcement("\(next.note). \(next.title). \(next.detail)").post()
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if card == next { withAnimation { card = nil } }
        }
    }

    /// "Rep 3 of 6", "Stride 2 of 6", or the block's name ("Threshold").
    private func repTitle(_ step: WorkoutStep) -> String {
        guard let n = step.repNumber, let total = step.repTotal, total > 1 else { return step.label }
        return "\(step.kind == .stride ? "Stride" : "Rep") \(n) of \(total)"
    }

    /// "1 km at 4:15/km", "400 m easy", "20 s quick and light".
    private func stepDetail(_ step: WorkoutStep) -> String {
        if step.kind == .stride { return "\(Int(step.seconds ?? 20)) s quick and light" }
        // The easy running after the last stride takes whatever is left of the run.
        if step.kind == .cooldown, step.distanceMeters < 1 { return "easy to the end" }
        let distance = Format.distanceCompact(step.distanceMeters)
        if step.kind == .recovery || step.kind == .cooldown || step.paceType == .easy { return "\(distance) easy" }
        return "\(distance) at \(step.targetPaceSecPerKm.map(Format.pace) ?? "race effort")"
    }

    /// Page 1: everything needed while running, on one screen. It never scrolls,
    /// so the Crown always reaches page 2; large text sizes shrink the numbers.
    /// Inside the strides it hands the whole page to the countdown.
    @ViewBuilder private var metricsPage: some View {
        if let stride = strideStep {
            strideFocus(stride)
        } else {
            runningMetrics
        }
    }

    /// The 20 seconds of a stride, and the easy minute before it, as big as the
    /// screen allows: there's no time to read anything else. The seconds left are
    /// the number, with a bar running down and a pip per stride under it.
    private func strideFocus(_ step: WorkoutStep) -> some View {
        let isStride = step.kind == .stride
        let total = step.repTotal ?? WorkoutSteps.strideCount
        let number = step.repNumber ?? 1
        // Counted down to 1, never 0: the step is over at zero, not showing it.
        let left = max(1, Int((workout.stepSecondsLeft ?? step.seconds ?? 0).rounded(.up)))
        return VStack(alignment: .leading, spacing: 2) {
            Text(isStride ? "STRIDE \(number) OF \(total)" : eyebrow)
                .font(.caption).fontWeight(.bold)
                .foregroundStyle(isStride ? .green : .accentColor)
            Text("\(left) s")
                .font(.system(size: 62, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .foregroundStyle(isStride ? .green : .primary)
            ProgressView(value: workout.stepProgress)
                .tint(isStride ? .green : .accentColor)
                .accessibilityHidden(true)
            // No pace during the stride itself: GPS needs longer than 20 s to tell
            // the truth, so what it would show is the pace from before the burst.
            // The one that's over gets its real pace, in the line above.
            Text(isStride ? "QUICK AND LIGHT" : "NEXT: STRIDE \(number) OF \(total)")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            stridePips(done: isStride ? number - 1 : number - 1, current: number, total: total)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isStride
            ? "Stride \(number) of \(total), \(left) seconds left, quick and light"
            : "Easy, \(left) seconds to stride \(number) of \(total)"
                + (workout.lastStridePace.map { ". Last stride \(Format.pace($0))" } ?? ""))
    }

    /// "EASY", with the pace the last stride actually came out at once there is one.
    private var eyebrow: String {
        guard let pace = workout.lastStridePace else { return "EASY" }
        return "EASY  ·  LAST \(Format.pace(pace))"
    }

    /// One pip per stride: done, the one being run, and the ones still to come.
    private func stridePips(done: Int, current: Int, total: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(1...max(1, total), id: \.self) { n in
                Capsule()
                    .fill(n <= done ? Color.green : n == current ? Color.green.opacity(0.5) : Color.secondary.opacity(0.3))
                    .frame(height: 5)
            }
        }
        .accessibilityHidden(true)
    }

    private var runningMetrics: some View {
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
                if activeStep?.kind == .work {
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
    /// A steady run shows the overall target instead of a per-step label. During the
    /// easy part of a run that ends with strides, how far it is until they start.
    private func stepBanner(_ step: WorkoutStep) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(step.label.isEmpty ? "Target" : step.label)
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.tint)
            Text(stridesComing(step) ?? (step.kind == .cooldown && step.distanceMeters < 1
                 ? "easy to the end"
                 : "\(Format.distanceCompact(step.distanceMeters)) @ \(step.targetPaceSecPerKm.map(Format.pace) ?? "--")"))
                .font(.footnote).monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    /// "Strides in 1.2 km", while the easy part before them is still running.
    private func stridesComing(_ step: WorkoutStep) -> String? {
        guard step.kind == .warmup, workout.guided?.nextStep?.seconds != nil,
              let left = workout.stepMetersLeft else { return nil }
        let total = steps.first { $0.kind == .stride }?.repTotal ?? WorkoutSteps.strideCount
        return "\(total) strides in \(Format.distanceCompact(left))"
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

/// A cue, full screen: what to do now, what it is, and how far along the session is.
private struct StepCardView: View {
    let card: RunCue

    /// Green to go, yellow to get ready, the accent colour otherwise.
    private var tint: Color {
        switch card.tone {
        case .go: .green
        case .ready: .yellow
        case .strides, .easy, .done, .info: .accentColor
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            if !card.note.isEmpty {
                Text(card.note)
                    .font(.headline)
                    .foregroundStyle(tint)
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
