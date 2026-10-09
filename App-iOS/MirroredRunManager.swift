import Foundation
import HealthKit
import ActivityKit
import UIKit

/// Shows a run recorded on Apple Watch on this iPhone. When the watch starts a run
/// it mirrors its `HKWorkoutSession` here (HealthKit launches the app in the
/// background if needed) and sends a `RunMirrorUpdate` every second or so. This
/// turns them into the same Live Activity a phone run has, and its Pause, Resume
/// and Finish buttons act on the watch's session. The watch keeps recording and
/// saving the run; nothing is saved here.
///
/// A Live Activity can only be started while the app is in the foreground, so if
/// the run began with the app closed, it appears the next time endurancr is opened
/// during the run. Delegate callbacks arrive off the main thread, so state is
/// changed on the main queue, as in `PhoneWorkoutManager`.
@Observable
final class MirroredRunManager: NSObject, @unchecked Sendable {
    static let shared = MirroredRunManager()

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var activity: Activity<RunActivityAttributes>?
    private var observers: [NSObjectProtocol] = []

    /// The latest numbers from the watch, while a mirrored run is going.
    private(set) var latest: RunMirrorUpdate?

    /// Starts listening for runs the watch mirrors. HealthKit asks for this to be set
    /// as soon as the app launches, so it's called from the app's `init`.
    func listen() {
        store.workoutSessionMirroringStartHandler = { [weak self] session in
            DispatchQueue.main.async { self?.attach(session) }
        }
        // A run that began with the app in the background gets its Live Activity
        // once the app comes forward.
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.activity == nil, let latest = self.latest else { return }
            self.startLiveActivity(latest)
        }
    }

    private func attach(_ session: HKWorkoutSession) {
        self.session = session
        session.delegate = self
        observeControls()
    }

    private func detach() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        endLiveActivity()
        session = nil
        latest = nil
    }

    /// The Live Activity's buttons post these from the app's process (see
    /// `RunControlIntents`). A phone run listens to the same ones while it records.
    private func observeControls() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .runPauseRequested, object: nil, queue: .main) { [weak self] _ in
                self?.session?.pause()
            },
            center.addObserver(forName: .runResumeRequested, object: nil, queue: .main) { [weak self] _ in
                self?.session?.resume()
            },
            center.addObserver(forName: .runFinishRequested, object: nil, queue: .main) { [weak self] _ in
                self?.session?.end()
            },
        ]
    }

    private func receive(_ update: RunMirrorUpdate) {
        latest = update
        if activity == nil {
            startLiveActivity(update)
        } else if let activity {
            let state = Self.contentState(update)
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
        }
    }

    // MARK: Live Activity

    private func startLiveActivity(_ update: RunMirrorUpdate) {
        // Always called on the main queue.
        let inForeground = MainActor.assumeIsolated { UIApplication.shared.applicationState != .background }
        guard ActivityAuthorizationInfo().areActivitiesEnabled, inForeground else { return }
        let attributes = RunActivityAttributes(
            goalName: update.goalName,
            workoutTitle: update.workoutTitle,
            targetPaceLower: update.targetPaceLower,
            targetPaceUpper: update.targetPaceUpper
        )
        activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: Self.contentState(update), staleDate: nil),
            pushType: nil
        )
    }

    private func endLiveActivity() {
        guard let activity else { return }
        let final = latest.map(Self.contentState)
        Task {
            await activity.end(final.map { ActivityContent(state: $0, staleDate: nil) },
                               dismissalPolicy: .after(.now + 5))
        }
        self.activity = nil
    }

    private static func contentState(_ update: RunMirrorUpdate) -> RunActivityAttributes.ContentState {
        RunActivityAttributes.ContentState(
            elapsedSeconds: update.elapsedSeconds,
            distanceMeters: update.distanceMeters,
            currentPaceSecPerKm: update.paceSecPerKm,
            averagePaceSecPerKm: update.paceSecPerKm,
            elevationGainMeters: 0,
            isPaused: update.isPaused,
            targetDistanceMeters: update.targetDistanceMeters,
            stepLabel: update.stepLabel,
            stepTargetPaceSecPerKm: update.stepTargetPaceSecPerKm,
            stepTargetDistanceMeters: update.stepTargetDistanceMeters,
            heartRate: update.heartRate
        )
    }
}

// MARK: - HKWorkoutSessionDelegate

extension MirroredRunManager: HKWorkoutSessionDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        guard toState == .ended || toState == .stopped else { return }
        DispatchQueue.main.async { self.detach() }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}

    func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        guard let update = data.last.flatMap(RunMirrorUpdate.decode) else { return }
        DispatchQueue.main.async { self.receive(update) }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        DispatchQueue.main.async { self.detach() }
    }
}
