import SwiftUI
import TrainingCore
import WatchKit

/// Live run screen. Big-type metrics with the Pause/Resume and Finish controls
/// right on the same scroll view, so they are always reachable (an earlier paged
/// layout hid them behind a swipe the metrics scroll view swallowed).
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

    /// The step the athlete is currently in, given how far they've run.
    private var activeStep: WorkoutStep? {
        guard let plannedWorkout, let zones else { return nil }
        return WorkoutSteps.activeStep(
            for: plannedWorkout, zones: zones, distanceCovered: workout.distanceMeters
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(Format.duration(workout.elapsedSeconds))
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(workout.isPaused ? .yellow : .primary)

                heartRate

                if let step = activeStep, let plannedWorkout {
                    stepBanner(step)
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
                    metric("Distance", Format.distance(workout.distanceMeters), tint: .cyan)
                    metric("Pace", Format.pace(workout.paceSecPerKm), tint: .green)
                }

                gpsStatus

                controls
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
        .navigationTitle(workout.isPaused ? "Paused" : "Running")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: activeStep?.index) { old, new in
            // A new interval step began (e.g. warm-up -> first rep): a success tap so
            // the athlete feels the transition without looking at the watch.
            if old != nil, new != nil, old != new {
                WKInterfaceDevice.current().play(.success)
            }
        }
    }

    /// The current step: its label ("Rep 3/6"), step distance, and step target pace.
    /// A steady run shows the overall target instead of a per-step label.
    private func stepBanner(_ step: WorkoutStep) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(step.label.isEmpty ? "Target" : step.label)
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.orange)
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
                WKInterfaceDevice.current().play(.click)
                workout.isPaused ? workout.resume() : workout.pause()
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

    private var heartRate: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "heart.fill").foregroundStyle(.red).font(.title3)
            if workout.heartRate > 0 {
                Text("\(Int(workout.heartRate))")
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                Text("bpm").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("acquiring…").font(.title3).foregroundStyle(.secondary)
            }
        }
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
        valueTint: Color = .cyan
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
