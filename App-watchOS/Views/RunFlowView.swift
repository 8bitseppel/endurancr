import SwiftUI
import TrainingCore
import WatchKit

/// A run from the tap on Start to the summary, on one screen that changes in place:
/// the run, the finish, the treadmill's distance after an indoor run, and the
/// summary. Nothing in between goes back to the home screen, and nothing
/// waits for Health: the summary opens from what the watch already knows, and only
/// its "Saving to Health" line waits for the save, changing in place when it's done.
struct RunFlowView: View {
    @Bindable var workout: WorkoutManager
    let plannedWorkout: PlannedWorkout?
    let zones: PaceZones?
    /// The summary, from the watch's own numbers. `nil` for a run too short to
    /// summarize (an accidental start), which only shows the finish.
    let makeSummary: () -> WatchRunSummary?
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase

    enum Phase: Equatable { case running, finishing, treadmill, summary }
    @State private var summary: WatchRunSummary?
    /// What the run came to, kept as it was the moment Finish was held, for the
    /// finish screen.
    @State private var final: (distance: Double, seconds: Double) = (0, 0)

    init(workout: WorkoutManager, plannedWorkout: PlannedWorkout?, zones: PaceZones?,
         makeSummary: @escaping () -> WatchRunSummary?) {
        self.workout = workout
        self.plannedWorkout = plannedWorkout
        self.zones = zones
        self.makeSummary = makeSummary
        _phase = State(initialValue: .running)
    }

    var body: some View {
        ZStack {
            switch phase {
            case .running:
                LiveRunView(workout: workout, plannedWorkout: plannedWorkout, zones: zones)
                    .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 0.92))))
            case .finishing:
                FinishView(distance: final.distance, seconds: final.seconds)
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            case .treadmill:
                TreadmillDistanceView(estimate: final.distance) { meters in
                    workout.confirmMachineDistance(meters)
                    if let meters { final.distance = meters }
                    showSummary()
                }
                .transition(.opacity)
            case .summary:
                if let summary {
                    WatchRunSummaryView(summary: summary, saveState: workout.saveState)
                        .transition(.opacity)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onChange(of: workout.isRunning) { _, running in
            // Held Finish here, or finished from the iPhone's Live Activity.
            guard !running, phase == .running, workout.didFinish else { return }
            final = (workout.distanceMeters, workout.elapsedTime(at: .now))
            withAnimation(.smooth(duration: 0.45)) { phase = .finishing }
            Task { await afterFinish() }
        }
        .onChange(of: workout.savedDistanceMeters) { _, saved in
            // Health's own figure, once the save is done, if it differs from the
            // live one (the last readings arrive with the save).
            guard let saved, saved > 0, var current = summary else { return }
            current.distanceMeters = saved
            summary = current
        }
    }

    /// The finish holds for a moment, long enough to read, then moves on.
    private func afterFinish() async {
        try? await Task.sleep(for: .seconds(1.6))
        if workout.isIndoor, final.distance > 0 {
            withAnimation(.smooth(duration: 0.4)) { phase = .treadmill }
        } else {
            showSummary()
        }
    }

    private func showSummary() {
        guard var built = makeSummary() else { dismiss(); return }
        // The week counted the live distance; a treadmill's number replaces it.
        built.weekCompletedMeters += final.distance - built.distanceMeters
        built.distanceMeters = final.distance
        built.durationSeconds = final.seconds
        summary = built
        withAnimation(.smooth(duration: 0.5)) { phase = .summary }
    }
}

/// The moment after Finish: a check drawing itself into a ring, and what the run
/// came to. It holds for a second and a half before the summary, so the end of a
/// run feels like an ending rather than a screen vanishing.
private struct FinishView: View {
    let distance: Double
    let seconds: Double
    @State private var ring: CGFloat = 0
    @State private var check: CGFloat = 0
    @State private var shown = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(.green.opacity(0.25), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: ring)
                    .stroke(.green, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                CheckShape()
                    .trim(from: 0, to: check)
                    .stroke(.green, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    .frame(width: 40, height: 30)
            }
            .frame(width: 92, height: 92)
            VStack(spacing: 0) {
                Text(Format.distance(distance))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                Text(Format.duration(seconds))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Run finished, \(Format.distance(distance)) in \(Format.duration(seconds))")
        .task {
            withAnimation(.easeOut(duration: 0.45)) { ring = 1 }
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.spring(duration: 0.45, bounce: 0.3)) { check = 1 }
            try? await Task.sleep(for: .seconds(0.15))
            withAnimation(.smooth(duration: 0.4)) { shown = true }
        }
    }
}

/// A tick, drawn from its short arm to its long one.
private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// After an indoor run: the distance the treadmill shows, set with the Crown. The
/// watch measures a treadmill from your arm swing, which can be off by a tenth; the
/// machine counts the belt, so its number is the one the plan should count.
private struct TreadmillDistanceView: View {
    let estimate: Double
    let onDone: (Double?) -> Void
    /// In tens of metres, so a turn of the Crown moves it by 0.01 km.
    @State private var tens: Double
    /// The Crown only turns a view that has focus, so the number takes it at once.
    @FocusState private var crownFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 40

    init(estimate: Double, onDone: @escaping (Double?) -> Void) {
        self.estimate = estimate
        self.onDone = onDone
        _tens = State(initialValue: (estimate / 10).rounded())
    }

    var body: some View {
        VStack(spacing: 6) {
            Text("Treadmill distance")
                .font(.headline)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(Format.distance(tens * 10))
                .font(.system(size: min(numberSize, 56), weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .focusable()
                .focused($crownFocused)
                .digitalCrownRotation($tens, from: 0, through: 10_000, by: 1,
                                      sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
                .accessibilityLabel("Treadmill distance")
                .accessibilityValue(Format.distance(tens * 10))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: tens += 1
                    case .decrement: tens = max(0, tens - 1)
                    default: break
                    }
                }
            // At the largest text sizes the hint goes, so Save stays on the screen;
            // the number and the Crown explain themselves.
            if !typeSize.isAccessibilitySize {
                Text("Turn the Crown to what the treadmill shows. The watch measured \(Format.distance(estimate)).")
                    .font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3).minimumScaleFactor(0.8)
            }
            Button {
                onDone(tens * 10)
            } label: {
                Text("Save").fontWeight(.semibold)
                    .foregroundStyle(WatchTodayView.plumInk)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.accentColor)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { crownFocused = true }
    }
}
