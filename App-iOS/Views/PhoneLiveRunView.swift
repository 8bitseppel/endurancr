import SwiftUI
import TrainingCore

/// Live metrics during a run recorded on iPhone, with an End control that
/// finalizes and saves the workout (and its GPS route) to HealthKit. The same
/// metrics also appear on the Lock Screen / Dynamic Island via the Live Activity.
/// No heart rate — that needs a watch.
///
/// The metrics an athlete asked to see mid-run: current pace + target pace,
/// distance + target distance. For a structured session the target pace/distance
/// track the current step (e.g. "Rep 3/6"), advancing as each step completes. No
/// climb, no average pace.
struct PhoneLiveRunView: View {
    @Bindable var recorder: PhoneWorkoutManager
    @Environment(\.dismiss) private var dismiss

    /// The current step's target pace (sec/km), when this run follows a structured
    /// plan; `nil` falls back to the overall planned window.
    private var stepTargetPace: Double? {
        guard let step = recorder.activeStep, step.kind != .steady else { return nil }
        return step.targetPaceSecPerKm
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(recorder.isPaused ? "Paused" : "Running")
                    .font(Brand.rounded(.largeTitle))
                    .accessibilityAddTraits(.isHeader)

                // The time, big, as on the watch.
                VStack(alignment: .leading, spacing: 2) {
                    Text("Time").brandEyebrow()
                    Text(Format.duration(recorder.elapsedSeconds))
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                .brandCard(cornerRadius: 30, padding: 22)

                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        tile("Distance", Format.distance(recorder.distanceMeters),
                             detail: recorder.plannedDistanceMeters > 0 ? "of \(Format.distance(recorder.plannedDistanceMeters))" : nil)
                        paceTile
                    }
                    GridRow {
                        if let target = stepTargetPace {
                            tile("Target pace", Format.pace(target), detail: nil)
                        } else if let target = recorder.targetPaceRange {
                            tile("Target pace", Format.paceRange(target), detail: nil)
                        } else {
                            tile("Target pace", "--", detail: nil)
                        }
                        if let step = recorder.activeStep, step.kind != .steady {
                            // A stride and the easy minute before it run on the clock:
                            // the seconds left are what the step is, not its metres.
                            tile("Step", step.label,
                                 detail: recorder.stepSecondsLeft.map { "\(max(1, Int($0.rounded(.up)))) s left" }
                                     ?? Format.distanceCompact(step.distanceMeters))
                        } else {
                            tile("GPS", recorder.routePointCount > 0 ? "\(recorder.routePointCount)" : "…",
                                 detail: recorder.routePointCount > 0 ? "points" : "acquiring")
                        }
                    }
                }

                if let error = recorder.lastError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }

                VStack(spacing: 12) {
                    Button {
                        recorder.isPaused ? recorder.resume() : recorder.pause()
                    } label: {
                        Label(recorder.isPaused ? "Resume" : "Pause", systemImage: recorder.isPaused ? "play.fill" : "pause.fill")
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Brand.buttonPurple)
                    // Held for a second, so a touch in the pocket doesn't end the run.
                    PhoneHoldToFinishButton {
                        recorder.end()
                        dismiss()
                    }
                }
                .controlSize(.large)
                .padding(.top, 4)

                Text(recorder.isPaused
                    ? "Paused. Time and distance are on hold. Resume to keep recording, or Finish to save to Health."
                    : "Keep your phone with you. Tracking continues with the screen off, and your stats show on the Lock Screen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background { BrandBackground() }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onChange(of: recorder.isRunning) { _, running in
            // The run can also be finished from the Live Activity (Lock Screen /
            // Dynamic Island); close this screen when that happens.
            if !running { dismiss() }
        }
    }

    /// Current pace, green on target and orange off it; the symbol and VoiceOver
    /// say what the colour says.
    private var paceTile: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pace").brandEyebrow()
            HStack(spacing: 6) {
                Text(Format.pace(recorder.currentPaceSecPerKm))
                    .font(Brand.rounded(.title2)).monospacedDigit()
                    .minimumScaleFactor(0.6).lineLimit(1)
                if let onTarget = recorder.isOnTarget {
                    Image(systemName: onTarget ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.subheadline)
                }
            }
            .foregroundStyle(paceTint)
            Text(recorder.isOnTarget.map { $0 ? "On target" : "Off target" } ?? "Now")
                .font(.caption).foregroundStyle(.secondary)
        }
        .brandCard(cornerRadius: 22, padding: 16)
        .accessibilityElement(children: .combine)
    }

    private func tile(_ title: String, _ value: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).brandEyebrow()
            Text(value)
                .font(Brand.rounded(.title2)).monospacedDigit()
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(detail ?? " ").font(.caption).foregroundStyle(.secondary)
        }
        .brandCard(cornerRadius: 22, padding: 16)
        .accessibilityElement(children: .combine)
    }

    private var paceTint: Color {
        switch recorder.isOnTarget {
        case .some(true): return .green
        case .some(false): return .orange
        case .none: return .primary
        }
    }
}

/// Finish run, held for a second: a ring fills around the button while it's held, and
/// the run ends when it's full. Letting go early does nothing. VoiceOver gets a plain
/// Finish action, as holding is hard there.
struct PhoneHoldToFinishButton: View {
    let onFinish: () -> Void
    @State private var holding = false
    @State private var progress: CGFloat = 0

    var body: some View {
        Label(holding ? "Keep holding" : "Hold to finish run", systemImage: "stop.fill")
            .font(.title3.weight(.semibold))
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, minHeight: 56)
            .glassEffect(.regular.tint(.red.opacity(holding ? 0.25 : 0.1)), in: .capsule)
            .overlay {
                Capsule()
                    .trim(from: 0, to: progress)
                    .stroke(.red, style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
            .contentShape(.capsule)
            .onLongPressGesture(minimumDuration: 1, maximumDistance: 30) {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onFinish()
            } onPressingChanged: { pressing in
                holding = pressing
                if pressing {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
