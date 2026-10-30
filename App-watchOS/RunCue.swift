import TrainingCore
import WatchKit

/// What the run screen says full screen when a step begins, and the tap on the wrist
/// that comes with it. Built by `WorkoutManager`, not by the view: the wrist has to
/// be tapped when a stride starts whether or not the screen is awake, and the view
/// only draws when it is.
///
/// The wrist is only tapped where an effort begins or ends, never while you're
/// running easy: a tap you can't act on is noise, and noise gets ignored. So the
/// warm-up, the jogs between reps and the cool-down are silent, and so is reaching
/// the planned distance, which is worth reading but nothing to react to.
///
/// What's left is told apart by feel, so a session can be run without looking:
///
/// - **Strides are starting:** two taps, the only double in the run. That block
///   opens with an easy minute, which is why it gets its own warning; an interval
///   or threshold set begins the moment its first effort does, and that tap says so.
/// - **A rep or a stride starts:** one firm tap (`.start`).
/// - **A rep or a stride ends:** `.stop`, the tap that closes something.
/// - **The last one is done:** `.success`.
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
        /// A rep is coming up. Shown, not felt: it lands while you're jogging.
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
    /// hide a quarter of a 20 s burst. The tap on the wrist says it instead.
    var screenSeconds: Double? = 5

    static func == (a: RunCue, b: RunCue) -> Bool { a.id == b.id }
}

extension RunCue.Tone {
    /// The tap for this cue, and how many of them; `nil` for the cues that are only
    /// shown, because they arrive while you're running easy.
    var haptic: (type: WKHapticType, times: Int)? {
        switch self {
        case .strides: (.notification, 2)
        case .go: (.start, 1)
        case .easy: (.stop, 1)
        case .done: (.success, 1)
        case .ready, .note, .info: nil
        }
    }
}
