import Foundation
import TrainingCore

/// What a guided run says when a step begins: on the watch full screen with a tap
/// on the wrist (`RunCue.Tone.haptic`), on the iPhone out loud when spoken cues are
/// on (`RunCue.spoken`). Built by the recorder, not by the view: a stride has to be
/// announced when it starts whether or not the screen is awake.
///
/// Only where an effort begins or ends is anything felt or said, never while you're
/// running easy: a cue you can't act on is noise, and noise gets ignored. So the
/// warm-up, the jogs between reps and the cool-down are silent, and so is reaching
/// the planned distance, which is worth reading but nothing to react to.
///
/// What's left is told apart by feel or by ear, so a session can be run without looking:
///
/// - **Strides are starting:** two taps, the only double in the run. That block
///   opens with an easy minute, which is why it gets its own warning; an interval
///   or threshold set begins the moment its first effort does, and that tap says so.
/// - **A rep or a stride starts:** one firm tap, "Go".
/// - **A rep or a stride ends:** the tap that closes something, "Easy".
/// - **The last one is done:** success, "All done".
struct RunCue: Equatable, Identifiable {
    enum Tone: Equatable {
        /// The strides block begins: felt as two taps.
        case strides
        /// A rep or a stride starts now.
        case go
        /// A rep or a stride is over, run easy.
        case easy
        /// The last one is done.
        case done
        /// A rep is coming up. Shown and said, not felt: it lands while you're jogging.
        case ready
        /// Worth reading, nothing to react to (the planned distance is reached).
        case note
        /// Nothing to react to, just what this part of the run is.
        case info
    }

    let id = UUID()
    var title: String
    var detail: String
    var note: String
    var tone: Tone
    /// How long the cue takes over the screen, or `nil` when it shouldn't: inside
    /// the strides the countdown is the thing to look at, and a card over it would
    /// hide a quarter of a 20 s burst. The tap or the voice says it instead.
    var screenSeconds: Double? = 5
    /// What the iPhone says out loud, or `nil` for a cue that's only shown. Short,
    /// so it's over before the effort it announces is a second old.
    var spoken: String?

    static func == (a: RunCue, b: RunCue) -> Bool { a.id == b.id }
}

/// The cues of a guided session, the same on the watch and the iPhone.
enum RunCues {
    /// What's said when `step` begins, or `nil` for a step that starts without a
    /// word (the cool-down right after an "all done" card).
    static func cue(for step: WorkoutStep, in steps: [WorkoutStep]) -> RunCue? {
        let done = step.repNumber.map { $0 - 1 } ?? 0
        let strides = steps.first { $0.kind == .stride }?.repTotal
        switch step.kind {
        case .stride:
            // The first one says what to do, briefly: the page behind has the
            // countdown but no verb. After that no card at all, so nothing covers
            // the seconds and the pace.
            return RunCue(title: strideTitle(step), detail: "\(Int(step.seconds ?? 20)) s quick and light",
                          note: "Go", tone: .go, screenSeconds: step.repNumber == 1 ? 1.5 : nil, spoken: "Go.")
        case .recovery where step.seconds != nil && step.repNumber == 1:
            // The strides begin, but the first thing to do is keep running easy, so
            // that's the big line: "Strides now" over "easy for a minute" read as a
            // contradiction. The two taps say the strides have begun.
            let easy = Int(step.seconds ?? 60)
            return RunCue(title: "Easy \(easy) s",
                          detail: "Then \(step.repTotal ?? 6) × \(Int(WorkoutSteps.strideSeconds)) s quick and light",
                          note: "Strides next", tone: .strides, screenSeconds: 3,
                          spoken: easy == 60 ? "Strides. One easy minute first." : "Strides. \(easy) seconds easy first.")
        case .recovery where step.seconds != nil:
            // The stride just ended: felt, not read. The page counts the easy
            // minute down from here.
            return RunCue(title: "Easy \(Int(step.seconds ?? 60)) s", detail: "Next: \(strideTitle(step))",
                          note: "\(done) of \(step.repTotal ?? 6) strides done", tone: .easy, screenSeconds: nil,
                          spoken: "Easy.")
        case .cooldown where strides != nil:
            // The last stride is done; what's left of the run is easy.
            return RunCue(title: "All \(strides ?? 6) strides done", detail: "Easy to the end",
                          note: "Well run", tone: .done, spoken: "All done. Easy to the end.")
        case .work:
            return RunCue(title: repTitle(step), detail: stepDetail(step), note: "Go", tone: .go, spoken: "Go.")
        case .recovery where isLastRecovery(step, in: steps):
            // After the last rep: straight to the cool-down, counting its easy part in.
            let cooldown = steps.last { $0.kind == .cooldown }?.distanceMeters ?? 0
            return RunCue(title: cooldown > 0 ? "Cool-down" : "Easy to the end",
                          detail: "\(Format.distanceCompact(step.distanceMeters + cooldown)) easy",
                          note: "All \(step.repTotal ?? 1) done. Well run.", tone: .done,
                          spoken: "All done. Easy to the end.")
        case .recovery:
            let count = step.repNumber.flatMap { n in step.repTotal.map { "\(n) of \($0) done" } } ?? "Done"
            return RunCue(title: "Easy now", detail: stepDetail(step), note: count, tone: .easy, spoken: "Easy.")
        case .cooldown:
            // Already said after the last rep's easy part.
            if step.index > 0, isLastRecovery(steps[step.index - 1], in: steps) { return nil }
            let reps = steps.last { $0.kind == .work }?.repTotal ?? 1
            return RunCue(title: "Cool-down", detail: stepDetail(step),
                          note: reps > 1 ? "All \(reps) done. Well run." : "Done. Well run.", tone: .done,
                          spoken: "All done. Easy to the end.")
        case .warmup, .steady:
            return RunCue(title: step.label.isEmpty ? "Run" : step.label, detail: stepDetail(step),
                          note: "", tone: .info)
        }
    }

    /// Just before a rep: "Rep 3 of 6 in 70 m", so it doesn't come as a surprise.
    /// Strides need no warning: the easy minute before each counts itself down.
    /// `nil` when no rep is close, or this one was announced already.
    static func ready(_ guided: GuidedRun, distance: Double, readied: Int?) -> RunCue? {
        guard guided.step.kind != .work, guided.step.seconds == nil,
              let rep = guided.nextStep, rep.kind == .work, readied != rep.index,
              let left = guided.remainingMeters(distance: distance),
              left <= min(100, guided.step.distanceMeters / 2) else { return nil }
        // Rounded to 10 m: "in 70 m", not "in 74 m".
        let meters = max(10, Int((left / 10).rounded()) * 10)
        // Between reps the page is already counting the metres down, so the tap is
        // enough: a card over it would hide the number it's announcing.
        let covers = guided.step.kind != .recovery || (guided.step.repTotal ?? 1) <= 1
        return RunCue(title: "\(repTitle(rep)) in \(meters) m", detail: stepDetail(rep),
                      note: "Get ready", tone: .ready, screenSeconds: covers ? 5 : nil,
                      spoken: "\(repTitle(rep)) in \(meters) metres.")
    }

    /// The easy part after the last rep, when nothing but easy running follows.
    static func isLastRecovery(_ step: WorkoutStep, in steps: [WorkoutStep]) -> Bool {
        step.kind == .recovery && step.repNumber == step.repTotal
            && !steps.dropFirst(step.index + 1).contains { $0.kind == .work }
    }

    /// "Rep 3 of 6", or the block's name ("Threshold").
    static func repTitle(_ step: WorkoutStep) -> String {
        guard let n = step.repNumber, let total = step.repTotal, total > 1 else { return step.label }
        return "Rep \(n) of \(total)"
    }

    /// "Stride 3 of 6", for the stride itself or the easy minute before it.
    static func strideTitle(_ step: WorkoutStep) -> String {
        "Stride \(step.repNumber ?? 1) of \(step.repTotal ?? WorkoutSteps.strideCount)"
    }

    /// "1 km at 4:15/km", "400 m easy".
    static func stepDetail(_ step: WorkoutStep) -> String {
        if step.kind == .cooldown, step.distanceMeters < 1 { return "easy to the end" }
        let distance = Format.distanceCompact(step.distanceMeters)
        if step.kind == .recovery || step.kind == .cooldown || step.paceType == .easy { return "\(distance) easy" }
        return "\(distance) at \(step.targetPaceSecPerKm.map(Format.pace) ?? "race effort")"
    }
}
