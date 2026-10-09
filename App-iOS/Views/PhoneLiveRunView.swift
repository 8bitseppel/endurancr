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
        List {
            Section {
                metric("Time", Format.duration(recorder.elapsedSeconds))
                metric("Distance", Format.distance(recorder.distanceMeters))
                if recorder.plannedDistanceMeters > 0 {
                    metric("Target distance", Format.distance(recorder.plannedDistanceMeters))
                }
                if let step = recorder.activeStep, step.kind != .steady {
                    metric("Step", "\(step.label) · \(Format.distanceCompact(step.distanceMeters))")
                }
                metric("Current pace", Format.pace(recorder.currentPaceSecPerKm), tint: paceTint)
                if let target = stepTargetPace {
                    metric("Target pace", Format.pace(target))
                } else if let target = recorder.targetPaceRange {
                    metric("Target pace", Format.paceRange(target))
                }
                metric("GPS", recorder.routePointCount > 0 ? "\(recorder.routePointCount) pts" : "acquiring…")
            }

            if let error = recorder.lastError {
                Section {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    recorder.isPaused ? recorder.resume() : recorder.pause()
                } label: {
                    if recorder.isPaused {
                        Label("Resume", systemImage: "play.fill")
                    } else {
                        Label("Pause", systemImage: "pause.fill")
                    }
                }
                Button(role: .destructive) {
                    recorder.end()
                    dismiss()
                } label: {
                    Label("Finish run", systemImage: "stop.fill")
                }
            } footer: {
                Text(recorder.isPaused
                    ? "Paused. Time and distance are on hold. Resume to keep recording, or Finish to save to Health."
                    : "Keep your phone with you. Tracking continues with the screen off, and your stats show on the Lock Screen.")
            }
        }
        .navigationTitle(recorder.isPaused ? "Paused" : "Running")
        .navigationBarBackButtonHidden(true)
        .onChange(of: recorder.isRunning) { _, running in
            // The run can also be finished from the Live Activity (Lock Screen /
            // Dynamic Island); close this screen when that happens.
            if !running { dismiss() }
        }
    }

    private var paceTint: Color {
        switch recorder.isOnTarget {
        case .some(true): return .green
        case .some(false): return .orange
        case .none: return .primary
        }
    }

    private func metric(_ label: String, _ value: String, tint: Color = .primary) -> some View {
        LabeledContent(label) {
            Text(value).font(.title3).monospacedDigit().foregroundStyle(tint)
        }
    }
}
