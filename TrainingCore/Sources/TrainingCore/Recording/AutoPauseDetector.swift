import Foundation

/// Pauses a run while the runner stands still (a traffic light, a crossing, a
/// shoelace) and resumes it once they move again, from GPS speed alone.
///
/// It pauses after `stopSeconds` below `stopSpeed`, dated back to when the runner
/// slowed down, so the time standing never counts. It resumes after `goSeconds` at
/// `goSpeed` or faster, dated back to when they set off. The gap between the two
/// speeds keeps a slow shuffle from flicking it on and off.
public struct AutoPauseDetector: Sendable, Equatable {
    /// Below a slow walk (about 24 min/km): standing, or GPS jitter while standing.
    public static let stopSpeed = 0.7
    /// A brisk walk (about 12 min/km) or faster: moving again.
    public static let goSpeed = 1.4
    public static let stopSeconds: TimeInterval = 5
    public static let goSeconds: TimeInterval = 2

    public enum Change: Sendable, Equatable {
        /// Pause the run, counting from this moment.
        case pause(since: Date)
        /// Resume the run, counting from this moment.
        case resume(since: Date)
    }

    public private(set) var isPaused = false
    private var slowSince: Date?
    private var fastSince: Date?

    public init() {}

    /// Feeds one GPS speed (m/s) and returns a change when there is one. A negative
    /// speed means the fix has none and is ignored.
    public mutating func update(speed: Double, at date: Date) -> Change? {
        guard speed >= 0 else { return nil }
        if isPaused {
            guard speed >= Self.goSpeed else { fastSince = nil; return nil }
            let since = fastSince ?? date
            fastSince = since
            guard date.timeIntervalSince(since) >= Self.goSeconds else { return nil }
            isPaused = false
            fastSince = nil
            return .resume(since: since)
        } else {
            guard speed < Self.stopSpeed else { slowSince = nil; return nil }
            let since = slowSince ?? date
            slowSince = since
            guard date.timeIntervalSince(since) >= Self.stopSeconds else { return nil }
            isPaused = true
            slowSince = nil
            return .pause(since: since)
        }
    }

    /// Starts over as moving, e.g. after the runner paused or resumed by hand.
    public mutating func reset() {
        self = AutoPauseDetector()
    }
}
