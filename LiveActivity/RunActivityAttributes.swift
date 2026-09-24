import Foundation
import ActivityKit

/// Data model shared between the iOS app (which drives the run) and the widget
/// extension (which renders the Lock Screen + Dynamic Island). It lives here
/// rather than in `Shared/` because ActivityKit is unavailable on watchOS, so it
/// must not be compiled into the watch target.
struct RunActivityAttributes: ActivityAttributes {
    /// The live, changing metrics pushed to the Live Activity ~once per second.
    public struct ContentState: Codable, Hashable {
        var elapsedSeconds: TimeInterval
        var distanceMeters: Double
        var currentPaceSecPerKm: Double
        var averagePaceSecPerKm: Double
        var elevationGainMeters: Double
        /// Whether the run is currently paused, so the Live Activity can show the
        /// right control (Pause vs Resume) and a paused indicator.
        var isPaused: Bool = false
        /// Overall target distance for the session (m); 0 for a free run.
        var targetDistanceMeters: Double = 0
        /// Current step label, e.g. "Rep 3/6" or "Warm-up"; "" for a steady/free run.
        var stepLabel: String = ""
        /// Target pace for the current step (sec/km); 0 when none.
        var stepTargetPaceSecPerKm: Double = 0
        /// Distance of the current step (m); 0 for a steady/free run.
        var stepTargetDistanceMeters: Double = 0
    }

    /// Fixed for the life of the activity.
    var goalName: String
    var workoutTitle: String
    /// Today's planned pace window (sec/km), if this run has a target.
    var targetPaceLower: Double?
    var targetPaceUpper: Double?
}

extension RunActivityAttributes.ContentState {
    /// Whether current pace is within the planned window (nil when no target).
    func isOnTarget(lower: Double?, upper: Double?) -> Bool? {
        guard let lower, let upper, currentPaceSecPerKm > 0 else { return nil }
        return currentPaceSecPerKm >= lower && currentPaceSecPerKm <= upper
    }
}

/// Foundation-only formatting shared by the app and the widget, so the widget
/// extension doesn't need to pull in TrainingCore and the app's `Format`.
enum RunMetricFormat {
    static func distance(_ meters: Double) -> String {
        String(format: "%.2f km", meters / 1_000)
    }

    static func pace(_ secPerKm: Double) -> String {
        guard secPerKm.isFinite, secPerKm > 0 else { return "--" }
        let t = Int(secPerKm.rounded())
        return String(format: "%d:%02d/km", t / 60, t % 60)
    }

    static func duration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                     : String(format: "%d:%02d", m, sec)
    }

    static func elevation(_ meters: Double) -> String {
        String(format: "%.0f m", meters)
    }

    static func paceRange(lower: Double?, upper: Double?) -> String {
        guard let lower, let upper else { return "--" }
        let lo = Int(lower.rounded()), hi = Int(upper.rounded())
        return String(format: "%d:%02d-%d:%02d/km", lo / 60, lo % 60, hi / 60, hi % 60)
    }
}
