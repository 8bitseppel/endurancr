import SwiftUI
import TrainingCore

/// A run recorded on iPhone, from Start to the summary, on one screen that changes in
/// place, as on the watch: the run, the finish, the treadmill's distance after an
/// indoor run. Then `onFinished` hands over to the summary, which opens at once and
/// says "Saving to Health" until the save is done. Nothing waits for Health.
///
/// The metrics an athlete asked to see mid-run: current pace + target pace,
/// distance + target distance. For a structured session the target pace/distance
/// track the current step (e.g. "Rep 3/6"), advancing as each step completes. Inside
/// the strides, and in the jogs between reps, the top of the screen turns into a
/// countdown, as on the watch. No heart rate: that needs a watch.
struct PhoneLiveRunView: View {
    @Bindable var recorder: PhoneWorkoutManager
    /// Called once the finish has played (and, indoors, the treadmill's distance
    /// was given), for the summary to open.
    var onFinished: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = Phase.running
    @State private var banner: RunCue?
    /// What the run came to, as it was when Finish was held.
    @State private var final: (distance: Double, seconds: Double) = (0, 0)

    enum Phase { case running, finishing, treadmill }

    /// The current step's target pace (sec/km), when this run follows a structured
    /// plan; `nil` falls back to the overall planned window.
    private var stepTargetPace: Double? {
        guard let step = recorder.activeStep, step.kind != .steady else { return nil }
        return step.targetPaceSecPerKm
    }

    /// The steps that get the countdown: a stride, the easy minute that sets one
    /// up, and the jog between interval reps. In all three the one thing worth
    /// reading is how long until the next effort.
    private var focusStep: WorkoutStep? {
        guard let step = recorder.activeStep else { return nil }
        switch step.kind {
        case .stride: return step
        case .recovery: return (step.repTotal ?? 1) > 1 || step.seconds != nil ? step : nil
        default: return nil
        }
    }

    var body: some View {
        ZStack {
            switch phase {
            case .running:
                running
                    .transition(.opacity)
            case .finishing:
                PhoneFinishView(distance: final.distance, seconds: final.seconds)
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            case .treadmill:
                PhoneTreadmillDistanceView(estimate: final.distance) { meters in
                    recorder.confirmMachineDistance(meters)
                    finish()
                }
                .transition(.opacity)
            }
        }
        .background { BrandBackground() }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onChange(of: recorder.isRunning) { _, running in
            // Held Finish here, or finished from the Live Activity.
            guard !running, phase == .running else { return }
            guard recorder.didFinish else { dismiss(); return }
            final = (recorder.distanceMeters, recorder.elapsedSeconds)
            withAnimation(.smooth(duration: 0.45)) { phase = .finishing }
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                if recorder.needsMachineDistance {
                    withAnimation(.smooth(duration: 0.4)) { phase = .treadmill }
                } else {
                    finish()
                }
            }
        }
        .onChange(of: recorder.needsMachineDistance) { _, needed in
            // Answered elsewhere, or saved with the step counter's after two minutes.
            if !needed, phase == .treadmill { finish() }
        }
        .onChange(of: recorder.cue) { _, cue in
            guard let cue, let seconds = cue.screenSeconds else { return }
            withAnimation(reduceMotion ? nil : .spring(duration: 0.35)) { banner = cue }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                if banner == cue { withAnimation { banner = nil } }
            }
        }
    }

    private func finish() {
        dismiss()
        onFinished()
    }

    private var running: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(recorder.isAutoPaused ? "Auto-paused" : recorder.isPaused ? "Paused" : recorder.isIndoor ? "Indoor run" : "Running")
                    .font(Brand.rounded(.largeTitle))
                    .accessibilityAddTraits(.isHeader)

                if let banner {
                    cueCard(banner)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if let step = focusStep {
                    focusCard(step)
                } else {
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
                }

                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        tile("Distance", Format.distance(recorder.distanceMeters),
                             detail: recorder.plannedDistanceMeters > 0 ? "of \(Format.distance(recorder.plannedDistanceMeters))" : nil)
                        paceTile
                    }
                    GridRow {
                        if let target = stepTargetPace {
                            tile(recorder.isIndoor ? "Target speed" : "Target pace", paceText(target), detail: nil)
                        } else if let target = recorder.targetPaceRange {
                            tile(recorder.isIndoor ? "Target speed" : "Target pace",
                                 recorder.isIndoor ? "\(Format.speed(target.upperBound)) to \(Format.speed(target.lowerBound))" : Format.paceRange(target),
                                 detail: nil)
                        } else {
                            tile(recorder.isIndoor ? "Target speed" : "Target pace", "--", detail: nil)
                        }
                        if focusStep != nil {
                            tile("Time", Format.duration(recorder.elapsedSeconds), detail: nil)
                        } else if let step = recorder.activeStep, step.kind != .steady {
                            tile("Step", step.label, detail: Format.distanceCompact(step.distanceMeters))
                        } else if recorder.isIndoor {
                            tile("Distance from", "Steps", detail: "the treadmill's at the end")
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
                    }
                }
                .controlSize(.large)
                .padding(.top, 4)

                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private var footnote: String {
        if recorder.isAutoPaused { return "Paused because you stopped. It goes on by itself when you run again." }
        if recorder.isPaused { return "Paused. Time and distance are on hold. Resume to keep recording, or Finish to save to Health." }
        if recorder.isIndoor {
            return "GPS is off. Keep your iPhone on you, in a pocket or on an armband, so it can count your steps. After the run you give the distance the treadmill shows."
        }
        return "Keep your phone with you. Tracking continues with the screen off, and your stats show on the Lock Screen."
    }

    /// A pace as this run shows it: min/km outside, km/h on a treadmill.
    private func paceText(_ secPerKm: Double) -> String {
        recorder.isIndoor ? Format.speed(secPerKm) : Format.pace(secPerKm)
    }

    /// What a step change says, for a few seconds at the top: the voice says it too
    /// when spoken cues are on.
    private func cueCard(_ cue: RunCue) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !cue.note.isEmpty {
                Text(cue.note.uppercased()).brandEyebrow()
            }
            Text(cue.title)
                .font(Brand.rounded(.title))
                .minimumScaleFactor(0.7)
            Text(cue.detail).font(.headline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .brandCard(tint: cueTint(cue.tone), cornerRadius: 26, padding: 18)
        .accessibilityElement(children: .combine)
    }

    private func cueTint(_ tone: RunCue.Tone) -> Color? {
        switch tone {
        case .go: .green
        case .ready: .yellow
        default: nil
        }
    }

    /// The 20 seconds of a stride, the easy minute before it, and the jog between
    /// interval reps, as big as the screen allows, as on the watch: what's left of
    /// the step, a bar running down, the pace against its target during a stride,
    /// and a pip per rep or stride.
    private func focusCard(_ step: WorkoutStep) -> some View {
        let isStride = step.kind == .stride
        let timed = step.seconds != nil
        let total = step.repTotal ?? WorkoutSteps.strideCount
        let number = step.repNumber ?? 1
        // A timed step counts down to 1, never 0; a jog counts the metres to the next rep.
        let left = timed
            ? "\(max(1, Int((recorder.stepSecondsLeft ?? step.seconds ?? 0).rounded(.up)))) s"
            : Format.distanceCompact(max(0, recorder.stepMetersLeft ?? step.distanceMeters))
        let tint: Color = isStride ? .green : Brand.buttonPurple
        let title = isStride ? "Stride \(number) of \(total)"
            : timed ? "Easy, then stride \(number) of \(total)"
            : "Easy, then rep \(min(number + 1, total)) of \(total)"
        return VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).brandEyebrow()
            Text(left)
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .foregroundStyle(isStride ? .green : .primary)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            ProgressView(value: recorder.stepProgress)
                .tint(tint)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline) {
                if isStride {
                    let pace = recorder.thisRepPaceSecPerKm ?? recorder.currentPaceSecPerKm
                    // Green near the stride's pace, orange well off it, with a 15 s/km
                    // band as on the watch: 20 s run by feel needs no tighter one.
                    focusValue(recorder.isIndoor ? "Speed" : "Pace", paceText(pace),
                               tint: step.targetPaceSecPerKm.map { abs(pace - $0) <= 15 } == false ? .orange : .green)
                    focusValue("Target", step.targetPaceSecPerKm.map(paceText) ?? "--")
                } else if timed, let last = recorder.lastStridePace {
                    focusValue("Last stride", paceText(last))
                    focusValue("Time", Format.duration(recorder.elapsedSeconds))
                } else {
                    focusValue("Time", Format.duration(recorder.elapsedSeconds))
                }
            }
            HStack(spacing: 4) {
                let done = number - (isStride || timed ? 1 : 0)
                let current = isStride ? number : number + 1
                ForEach(1...max(1, total), id: \.self) { n in
                    Capsule()
                        .fill(n <= done ? tint : n == current ? tint.opacity(0.45) : Color.secondary.opacity(0.25))
                        .frame(height: 6)
                }
            }
            .accessibilityHidden(true)
        }
        .brandCard(cornerRadius: 30, padding: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(left) left")
    }

    private func focusValue(_ label: String, _ value: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(Brand.rounded(.title3)).monospacedDigit().foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Current pace, green on target and orange off it; the symbol and VoiceOver
    /// say what the colour says. Indoors it's the speed, in km/h.
    private var paceTile: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recorder.isIndoor ? "Speed" : "Pace").brandEyebrow()
            HStack(spacing: 6) {
                Text(paceText(recorder.currentPaceSecPerKm))
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
                .lineLimit(1).minimumScaleFactor(0.8)
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

/// The moment after Finish, as on the watch: a check drawing itself into a ring,
/// and what the run came to. It holds for a second and a half before the summary,
/// so the end of a run feels like an ending rather than a screen vanishing.
private struct PhoneFinishView: View {
    let distance: Double
    let seconds: Double
    @State private var ring: CGFloat = 0
    @State private var check: CGFloat = 0
    @State private var shown = false

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().stroke(.green.opacity(0.25), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: ring)
                    .stroke(.green, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                PhoneCheckShape()
                    .trim(from: 0, to: check)
                    .stroke(.green, style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round))
                    .frame(width: 76, height: 58)
            }
            .frame(width: 170, height: 170)
            VStack(spacing: 4) {
                Text(Format.distance(distance))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(Format.duration(seconds))
                    .font(Brand.rounded(.title2))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Run finished, \(Format.distance(distance)) in \(Format.duration(seconds))")
        .task {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.easeOut(duration: 0.45)) { ring = 1 }
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.spring(duration: 0.45, bounce: 0.3)) { check = 1 }
            try? await Task.sleep(for: .seconds(0.15))
            withAnimation(.smooth(duration: 0.4)) { shown = true }
        }
    }
}

/// A tick, drawn from its short arm to its long one.
private struct PhoneCheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// After an indoor run: the distance the treadmill shows, typed in. The step counter
/// can be off by a lot on a belt, and counts nothing with the iPhone on the console;
/// the machine counts the belt, so its number is the one the plan should count.
private struct PhoneTreadmillDistanceView: View {
    let estimate: Double
    let onDone: (Double?) -> Void
    @State private var text: String
    @FocusState private var focused: Bool

    init(estimate: Double, onDone: @escaping (Double?) -> Void) {
        self.estimate = estimate
        self.onDone = onDone
        _text = State(initialValue: estimate > 0 ? String(format: "%.2f", estimate / 1_000) : "")
    }

    /// What was typed, in metres; a comma works as well as a point.
    private var meters: Double? {
        Double(text.replacingOccurrences(of: ",", with: ".")).map { $0 * 1_000 }.flatMap { $0 > 0 ? $0 : nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Treadmill distance")
                .font(Brand.rounded(.largeTitle))
                .accessibilityAddTraits(.isHeader)
            Text(estimate > 0
                 ? "Type in the distance the treadmill shows. Your steps came to \(Format.distance(estimate))."
                 : "Type in the distance the treadmill shows.")
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("0.00", text: $text)
                    .keyboardType(.decimalPad)
                    .focused($focused)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .accessibilityLabel("Treadmill distance in kilometres")
                Text("km").font(Brand.rounded(.title)).foregroundStyle(.secondary)
            }
            .brandCard(cornerRadius: 30, padding: 22)
            Button {
                onDone(meters)
            } label: {
                Text("Save").font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Brand.buttonPurple)
            .controlSize(.large)
            .disabled(meters == nil && estimate <= 0)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .onAppear { focused = true }
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
