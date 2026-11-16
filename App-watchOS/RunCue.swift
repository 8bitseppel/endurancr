import WatchKit

/// How each cue is felt on the wrist (`RunCues` builds them). One tap per effort
/// boundary, two when the strides begin, nothing for the cues that are only shown,
/// because they arrive while you're running easy.
extension RunCue.Tone {
    /// The tap for this cue, and how many of them; `nil` for the cues that are only shown.
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
