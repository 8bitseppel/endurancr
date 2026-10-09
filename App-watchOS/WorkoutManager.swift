import Foundation
import HealthKit
import CoreLocation
import TrainingCore

/// Records a running workout on Apple Watch using `HKWorkoutSession` +
/// `HKLiveWorkoutBuilder`, streaming live metrics and saving the finished
/// `HKWorkout` to HealthKit. GPS points from CoreLocation are accumulated into an
/// `HKWorkoutRouteBuilder` and attached to the workout, so the route shows up in the
/// Fitness/Health apps (and can be drawn in-app via MapKit).
///
/// The class lives on the main actor. HealthKit calls its delegates on its own
/// queues, so those callbacks are `nonisolated`, read what they need there, and hop
/// to the main actor in order (`onMain`). CoreLocation calls back on the thread
/// that created the manager, which is the main thread here.
///
/// The session is mirrored to the iPhone, which shows the run as a Live Activity
/// (see `MirroredRunManager` and `RunMirrorUpdate`). Auto-pause is the watch's own:
/// with Settings > Workout > Auto-Pause on, watchOS reports when the runner stops
/// and moves again, and the run screen shows it.
@MainActor
@Observable
final class WorkoutManager: NSObject {
    /// The one recorder, so a run can be picked up again after the app crashed
    /// (`recoverActiveRun`).
    static let shared = WorkoutManager()

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private let locationManager = CLLocationManager()
    /// When the last update went to the iPhone, to send about once a second.
    private var lastMirrorSent = Date.distantPast

    // Today's session, for the targets the iPhone's Live Activity shows. Nil for a free run.
    private var plannedWorkout: PlannedWorkout?
    private var zones: PaceZones?
    private var goalName = ""

    // Live, observable metrics.
    var isRunning = false
    var isPaused = false
    /// watchOS paused the run because the runner stopped (Auto-Pause in the
    /// watch's Workout settings), until they move again.
    var isAutoPaused = false
    var heartRate: Double = 0
    var activeEnergyKcal: Double = 0
    var distanceMeters: Double = 0
    var elapsedSeconds: TimeInterval = 0
    /// Number of GPS points captured so far (a simple "route is tracking" signal).
    var routePointCount = 0
    var lastError: String?
    /// True once the athlete has explicitly finished the run (tapped Finish), as
    /// opposed to navigating away. Drives whether a post-run summary is shown even
    /// for a zero-distance run.
    var didFinish = false

    /// The run's time at `date`, for a clock that ticks every second rather than
    /// only when HealthKit delivers new data. Paused time doesn't count.
    func elapsedTime(at date: Date) -> TimeInterval {
        builder?.elapsedTime(at: date) ?? elapsedSeconds
    }

    /// Current pace (sec/km) derived from distance and elapsed time.
    var paceSecPerKm: Double {
        guard distanceMeters > 0 else { return 0 }
        return elapsedSeconds / (distanceMeters / 1_000)
    }

    func start(plannedWorkout: PlannedWorkout? = nil, zones: PaceZones? = nil, goalName: String = "") {
        didFinish = false
        isAutoPaused = false
        self.plannedWorkout = plannedWorkout
        self.zones = zones
        self.goalName = goalName
        let config = HKWorkoutConfiguration()
        config.activityType = .running
        config.locationType = .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = attach(session)

            let startDate = Date()
            session.startActivity(with: startDate)
            builder.beginCollection(withStart: startDate) { [weak self] _, error in
                let message = error?.localizedDescription
                Self.onMain { if let message { self?.lastError = message } }
            }
            // Show the run on the iPhone too. Without it nearby the run just records here.
            session.startMirroringToCompanionDevice { _, _ in }
            isRunning = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Connects a new or recovered session: its live builder, a route builder and GPS.
    @discardableResult
    private func attach(_ session: HKWorkoutSession) -> HKLiveWorkoutBuilder {
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: session.workoutConfiguration)
        session.delegate = self
        builder.delegate = self
        self.session = session
        self.builder = builder
        self.routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
        beginLocationUpdates()
        return builder
    }

    /// Picks up a run that was still going when the app crashed or was closed by
    /// the system. watchOS keeps the workout session alive and relaunches the app;
    /// HealthKit hands the session back here. GPS points from before the crash
    /// aren't part of the route, the time, distance and heart rate are.
    func recoverActiveRun() {
        store.recoverActiveWorkoutSession { [weak self] session, _ in
            guard let session else { return }
            Self.onMain {
                guard let self, self.session == nil else { return }
                self.didFinish = false
                self.attach(session)
                self.isPaused = session.state == .paused
                self.isRunning = true
            }
        }
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }

    /// Sends the current numbers to the iPhone, at most about once a second.
    private func sendToPhone(force: Bool = false) {
        guard let session, force || Date().timeIntervalSince(lastMirrorSent) >= 1 else { return }
        lastMirrorSent = Date()
        var step: WorkoutStep?
        if let plannedWorkout, let zones {
            step = WorkoutSteps.activeStep(for: plannedWorkout, zones: zones, distanceCovered: distanceMeters)
        }
        let structured = step.map { $0.kind != .steady } ?? false
        let update = RunMirrorUpdate(
            workoutTitle: plannedWorkout.map { Format.workoutTitle($0.type) } ?? "Run",
            goalName: goalName,
            targetPaceLower: plannedWorkout?.targetPaceSecPerKm?.lowerBound,
            targetPaceUpper: plannedWorkout?.targetPaceSecPerKm?.upperBound,
            targetDistanceMeters: plannedWorkout?.distanceMeters ?? 0,
            elapsedSeconds: elapsedTime(at: .now),
            distanceMeters: distanceMeters,
            heartRate: heartRate,
            paceSecPerKm: paceSecPerKm,
            isPaused: isPaused || isAutoPaused,
            stepLabel: structured ? step?.label ?? "" : "",
            stepTargetPaceSecPerKm: structured ? step?.targetPaceSecPerKm ?? 0 : 0,
            stepTargetDistanceMeters: structured ? step?.distanceMeters ?? 0 : 0
        )
        guard let data = update.encoded() else { return }
        session.sendToRemoteWorkoutSession(data: data) { _, _ in }
    }

    func end() {
        // Set synchronously so the view's dismiss handler sees the explicit finish
        // even for a zero-distance run.
        didFinish = true
        locationManager.stopUpdatingLocation()
        session?.end()
        isRunning = false
    }

    /// Runs `work` on the main actor, after anything queued before it, so session
    /// state changes arrive in the order HealthKit reported them.
    nonisolated private static func onMain(_ work: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated(work) }
    }

    // MARK: Location / route

    private func beginLocationUpdates() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    /// Saves the finished workout and attaches the recorded route to it. HealthKit
    /// leaves paused intervals out of the saved workout's duration by itself.
    private func saveWorkout(endingAt date: Date) async {
        guard let builder else { return }
        let routeBuilder = self.routeBuilder
        self.routeBuilder = nil   // no more GPS points go in once the run is over
        do {
            try await builder.endCollection(at: date)
            guard let workout = try await builder.finishWorkout() else { return }
            try await routeBuilder?.finishRoute(with: workout, metadata: nil)
        } catch {
            lastError = error.localizedDescription
        }
    }
}

/// One statistic the live builder collected, read where HealthKit delivered it.
private enum LiveMetric: Sendable {
    case heartRate(Double), energy(Double), distance(Double)

    init?(_ statistics: HKStatistics?) {
        guard let statistics else { return nil }
        switch statistics.quantityType {
        case HKQuantityType(.heartRate):
            guard let bpm = statistics.mostRecentQuantity()?.doubleValue(for: .count().unitDivided(by: .minute())) else { return nil }
            self = .heartRate(bpm)
        case HKQuantityType(.activeEnergyBurned):
            guard let kcal = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) else { return nil }
            self = .energy(kcal)
        case HKQuantityType(.distanceWalkingRunning):
            guard let meters = statistics.sumQuantity()?.doubleValue(for: .meter()) else { return nil }
            self = .distance(meters)
        default:
            return nil
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Self.onMain { [weak self] in
            guard let self else { return }
            switch toState {
            case .running:
                isPaused = false
                sendToPhone(force: true)
            case .paused:
                isPaused = true
                sendToPhone(force: true)
            case .ended:
                // Finished here, or with Finish on the iPhone's Live Activity.
                didFinish = true
                isRunning = false
                locationManager.stopUpdatingLocation()
                Task { await self.saveWorkout(endingAt: date) }
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Self.onMain { [weak self] in self?.lastError = message }
    }

    /// watchOS's Auto-Pause: it reports when the runner stops and moves again,
    /// only if Auto-Pause is on in the watch's Workout settings.
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didGenerate event: HKWorkoutEvent) {
        let type = event.type
        guard type == .motionPaused || type == .motionResumed else { return }
        Self.onMain { [weak self] in
            self?.isAutoPaused = type == .motionPaused
            self?.sendToPhone(force: true)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {}
}

// MARK: - CLLocationManagerDelegate

extension WorkoutManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // The manager was created on the main thread, so it calls back there.
        MainActor.assumeIsolated {
            // Keep only reasonably accurate fixes so the route isn't polluted by noise.
            let filtered = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 50 }
            guard !filtered.isEmpty, let routeBuilder else { return }
            routeBuilder.insertRouteData(filtered) { [weak self] _, error in
                let message = error?.localizedDescription
                Self.onMain { if let message { self?.lastError = message } }
            }
            routePointCount += filtered.count
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A transient location failure shouldn't kill the run; just note it.
        let message = error.localizedDescription
        MainActor.assumeIsolated { lastError = message }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ builder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let metrics = collectedTypes.compactMap { type in
            (type as? HKQuantityType).flatMap { LiveMetric(builder.statistics(for: $0)) }
        }
        let elapsed = builder.elapsedTime
        Self.onMain { [weak self] in
            guard let self else { return }
            for metric in metrics {
                switch metric {
                case .heartRate(let bpm): heartRate = bpm
                case .energy(let kcal): activeEnergyKcal = kcal
                case .distance(let meters): distanceMeters = meters
                }
            }
            elapsedSeconds = elapsed
            sendToPhone()
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
