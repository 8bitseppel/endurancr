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
    enum Page { case metrics, controls }

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
            controlsPage.tag(Page.controls)
        }
        .tabViewStyle(.verticalPage)
        .demoTurnPage($page, to: .controls)
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
        .onChange(of: activeStep?.index) { old, new in
            // A new interval step began (e.g. warm-up -> first rep): a success tap so
            // the athlete feels the transition without looking at the watch.
            if old != nil, new != nil, old != new {
                WKInterfaceDevice.current().play(.success)
            }
        }
        .onChange(of: workout.isAutoPaused) { _, paused in
            // watchOS's Auto-Pause, felt at the traffic light without looking.
            WKInterfaceDevice.current().play(paused ? .stop : .start)
        }
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

    /// Page 2: the controls and GPS.
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

    private func paceTint(target: Double?) -> Color {
        guard let target, workout.paceSecPerKm > 0 else { return .green }
        // Within ±5 s/km of the step target reads as on-pace.
        return abs(workout.paceSecPerKm - target) <= 5 ? .green : .orange
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

            Button(role: .destructive) {
                workout.end()   // the screen closes when the run stops (onChange above)
            } label: {
                Label("Finish", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
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
    func demoTurnPage<Page: Hashable>(_ page: Binding<Page>, to second: Page) -> some View {
        #if DEBUG
        task {
            guard DemoMode.isOn, UserDefaults.standard.bool(forKey: "demoScroll") else { return }
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
