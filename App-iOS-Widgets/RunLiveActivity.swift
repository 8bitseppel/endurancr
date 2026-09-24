import ActivityKit
import WidgetKit
import AppIntents
import SwiftUI

/// Renders the running Live Activity on the Lock Screen, in the Dynamic Island,
/// and in StandBy. Driven by `PhoneWorkoutManager` in the app via ActivityKit.
///
/// The four metrics an athlete actually wants mid-run: current pace + target pace,
/// distance + target distance. For a structured session the target pace/distance
/// track the *current step* (e.g. "Rep 3/6"), advancing automatically as each
/// step's distance is covered. No climb, no average pace — they were noise.
///
/// The Pause/Resume and Finish controls are interactive App Intent buttons, so a
/// run can be controlled without opening the app (works even on the Lock Screen).
struct RunLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            LockScreenView(context: context)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .activityBackgroundTint(Color(white: 0.08))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    labeled("Time", RunMetricFormat.duration(context.state.elapsedSeconds))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    labeled("Distance", RunMetricFormat.distance(context.state.distanceMeters))
                }
                DynamicIslandExpandedRegion(.center) {
                    Image(systemName: context.state.isPaused ? "pause.circle.fill" : "figure.run")
                        .foregroundStyle(context.state.isPaused ? .yellow : .green)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        if !context.state.stepLabel.isEmpty {
                            Text(context.state.stepLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        HStack {
                            labeled("Pace", RunMetricFormat.pace(context.state.currentPaceSecPerKm))
                            Spacer()
                            labeled("Target", targetPace(context))
                        }
                        controls(isPaused: context.state.isPaused)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "figure.run")
                    .foregroundStyle(context.state.isPaused ? .yellow : .green)
            } compactTrailing: {
                Text(RunMetricFormat.distance(context.state.distanceMeters))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "figure.run")
                    .foregroundStyle(context.state.isPaused ? .yellow : .green)
            }
            .widgetURL(URL(string: "endurancr://run"))
        }
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit()
        }
    }

    @ViewBuilder
    private func controls(isPaused: Bool) -> some View {
        RunControls(isPaused: isPaused)
    }
}

/// The target pace to display: the current step's target when structured, else the
/// overall planned window, else nothing.
private func targetPace(_ context: ActivityViewContext<RunActivityAttributes>) -> String {
    if context.state.stepTargetPaceSecPerKm > 0 {
        return RunMetricFormat.pace(context.state.stepTargetPaceSecPerKm)
    }
    return RunMetricFormat.paceRange(
        lower: context.attributes.targetPaceLower,
        upper: context.attributes.targetPaceUpper
    )
}

/// Shared Pause/Resume + Finish controls for the Lock Screen and Dynamic Island.
/// NOTE: use `.bordered`, NOT `.glass`, here. Liquid Glass button styles don't render
/// visibly inside a Live Activity banner (glass needs a navigation-layer context; in
/// the banner the buttons collapse to near-invisible). Bordered stays clearly legible.
/// Only Finish, the notable action, carries a tint.
private struct RunControls: View {
    let isPaused: Bool

    var body: some View {
        HStack(spacing: 10) {
            if isPaused {
                Button(intent: ResumeRunIntent()) {
                    Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .tint(.white)
            } else {
                Button(intent: PauseRunIntent()) {
                    Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity)
                }
                .tint(.white)
            }
            Button(intent: FinishRunIntent()) {
                Label("Finish", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .tint(.red)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .font(.subheadline.weight(.semibold))
    }
}

/// The Lock Screen / StandBy banner.
private struct LockScreenView: View {
    let context: ActivityViewContext<RunActivityAttributes>

    /// Whether current pace sits on the step target (±5 s/km) or, absent a step, the
    /// planned window. `nil` when there's no target to judge against.
    private var onTarget: Bool? {
        if context.state.stepTargetPaceSecPerKm > 0, context.state.currentPaceSecPerKm > 0 {
            return abs(context.state.currentPaceSecPerKm - context.state.stepTargetPaceSecPerKm) <= 5
        }
        return context.state.isOnTarget(
            lower: context.attributes.targetPaceLower,
            upper: context.attributes.targetPaceUpper
        )
    }

    private var hasTargetPace: Bool {
        context.state.stepTargetPaceSecPerKm > 0 || context.attributes.targetPaceLower != nil
    }

    private var hasTargetDistance: Bool { context.state.targetDistanceMeters > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: run icon + title, step chip, and the elapsed time on the right.
            // Time lives here (not as a full metric slot) so the two big metrics below
            // stay balanced.
            HStack(spacing: 6) {
                Image(systemName: "figure.run")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(context.state.isPaused ? .yellow : .green)
                Text(context.attributes.workoutTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !context.state.stepLabel.isEmpty {
                    Text(context.state.stepLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.18), in: Capsule())
                }
                Spacer(minLength: 8)
                Text(context.state.isPaused ? "PAUSED"
                     : RunMetricFormat.duration(context.state.elapsedSeconds))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(context.state.isPaused ? .yellow : .secondary)
            }

            // Two equal columns: distance and pace, each with its target directly
            // underneath so the relationship is obvious at a glance.
            HStack(alignment: .top, spacing: 14) {
                metricBlock(
                    label: "Distance",
                    value: RunMetricFormat.distance(context.state.distanceMeters),
                    sub: hasTargetDistance
                        ? "of \(RunMetricFormat.distance(context.state.targetDistanceMeters))"
                        : nil
                )
                metricBlock(
                    label: "Pace",
                    value: RunMetricFormat.pace(context.state.currentPaceSecPerKm),
                    sub: hasTargetPace ? "target \(targetPace(context))" : nil,
                    tint: paceTint
                )
            }

            RunControls(isPaused: context.state.isPaused)
        }
    }

    private var paceTint: Color {
        switch onTarget {
        case .some(true): return .green
        case .some(false): return .orange
        case .none: return .primary
        }
    }

    private func metricBlock(label: String, value: String, sub: String?, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let sub {
                Text(sub)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
