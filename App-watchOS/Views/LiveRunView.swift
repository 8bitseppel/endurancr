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
        .navigationTitle(workout.isAutoPaused ? "Auto-paused" : workout.isPaused ? "Paused" : "Running")
        .navigationBarTitleDisplayMode(.inline)
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
        .demoFlipPages($page)
    }

    /// Page 1: everything needed while running, sized to fit without scrolling.
    private var metricsPage: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(Format.duration(workout.elapsedSeconds))
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(workout.isPaused || workout.isAutoPaused ? .yellow : .primary)
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
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 4)
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
                workout.end()
                dismiss()
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
    /// In demo screen recordings, shows the second page and comes back, the way a
    /// runner would turn the Digital Crown. Does nothing otherwise.
    func demoFlipPages(_ page: Binding<LiveRunView.Page>) -> some View {
        #if DEBUG
        task {
            guard DemoMode.isOn, UserDefaults.standard.bool(forKey: "demoScroll") else { return }
            try? await Task.sleep(for: .seconds(5))
            withAnimation { page.wrappedValue = .controls }
            try? await Task.sleep(for: .seconds(5))
            withAnimation { page.wrappedValue = .metrics }
        }
        #else
        self
        #endif
    }
}
