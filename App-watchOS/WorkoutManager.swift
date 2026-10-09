import Foundation
import HealthKit
import CoreLocation
import TrainingCore

/// Records a running workout on Apple Watch using `HKWorkoutSession` +
/// `HKLiveWorkoutBuilder`, streaming live metrics and saving the finished
/// `HKWorkout` to HealthKit. GPS points from CoreLocation are accumulated into an
/// `HKWorkoutRouteBuilder` and attached to the workout, so the route shows up in the
/// Fitness/Health apps (and can be drawn in-app via MapKit). Delegate callbacks
/// arrive off the main thread, so UI state is updated on the main queue.
///
/// The session is mirrored to the iPhone, which shows the run as a Live Activity
/// (see `MirroredRunManager` and `RunMirrorUpdate`). Auto-pause is the watch's own:
/// with Settings > Workout > Auto-Pause on, watchOS reports when the runner stops
/// and moves again, and the run screen shows it.
@Observable
final class WorkoutManager: NSObject, @unchecked Sendable {
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
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            self.routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: nil)

            beginLocationUpdates()

            let startDate = Date()
            session.startActivity(with: startDate)
            builder.beginCollection(withStart: startDate) { [weak self] _, error in
                if let error { DispatchQueue.main.async { self?.lastError = error.localizedDescription } }
            }
            // Show the run on the iPhone too. Without it nearby the run just records here.
            session.startMirroringToCompanionDevice { _, _ in }
            DispatchQueue.main.async { self.isRunning = true }
        } catch {
            lastError = error.localizedDescription
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
            elapsedSeconds: elapsedSeconds,
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
        DispatchQueue.main.async { self.isRunning = false }
    }

    // MARK: Location / route

    private func beginLocationUpdates() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    private func updateMetrics(from statistics: HKStatistics?) {
        guard let statistics else { return }
        DispatchQueue.main.async {
            switch statistics.quantityType {
            case HKQuantityType(.heartRate):
                let unit = HKUnit.count().unitDivided(by: .minute())
                self.heartRate = statistics.mostRecentQuantity()?.doubleValue(for: unit) ?? self.heartRate
            case HKQuantityType(.activeEnergyBurned):
                self.activeEnergyKcal = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? self.activeEnergyKcal
            case HKQuantityType(.distanceWalkingRunning):
                self.distanceMeters = statistics.sumQuantity()?.doubleValue(for: .meter()) ?? self.distanceMeters
            default:
                break
            }
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        // Mirror the session's paused/running state to the UI.
        switch toState {
        case .running: DispatchQueue.main.async { self.isPaused = false; self.sendToPhone(force: true) }
        case .paused: DispatchQueue.main.async { self.isPaused = true; self.sendToPhone(force: true) }
        case .ended:
            // Finished here, or with Finish on the iPhone's Live Activity.
            DispatchQueue.main.async {
                self.didFinish = true
                self.isRunning = false
                self.locationManager.stopUpdatingLocation()
            }
        default: break
        }

        // When the session ends, finalize collection, save the workout, and attach
        // the recorded GPS route to it. HealthKit excludes paused intervals from the
        // saved workout's duration automatically.
        guard toState == .ended, let builder else { return }
        builder.endCollection(withEnd: date) { [weak self] _, _ in
            builder.finishWorkout { workout, error in
                if let error { DispatchQueue.main.async { self?.lastError = error.localizedDescription } }
                guard let self, let workout, let routeBuilder = self.routeBuilder else { return }
                routeBuilder.finishRoute(with: workout, metadata: nil) { _, routeError in
                    if let routeError { DispatchQueue.main.async { self.lastError = routeError.localizedDescription } }
                    self.routeBuilder = nil
                }
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { self.lastError = error.localizedDescription }
    }

    /// watchOS's Auto-Pause: it reports when the runner stops and moves again,
    /// only if Auto-Pause is on in the watch's Workout settings.
    func workoutSession(_ workoutSession: HKWorkoutSession, didGenerate event: HKWorkoutEvent) {
        switch event.type {
        case .motionPaused: DispatchQueue.main.async { self.isAutoPaused = true; self.sendToPhone(force: true) }
        case .motionResumed: DispatchQueue.main.async { self.isAutoPaused = false; self.sendToPhone(force: true) }
        default: break
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {}
}

// MARK: - CLLocationManagerDelegate

extension WorkoutManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Keep only reasonably accurate fixes so the route isn't polluted by noise.
        let filtered = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 50 }
        guard !filtered.isEmpty, let routeBuilder else { return }
        routeBuilder.insertRouteData(filtered) { [weak self] _, error in
            if let error { DispatchQueue.main.async { self?.lastError = error.localizedDescription } }
        }
        DispatchQueue.main.async { self.routePointCount += filtered.count }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A transient location failure shouldn't kill the run; just note it.
        DispatchQueue.main.async { self.lastError = error.localizedDescription }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ builder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }
            updateMetrics(from: builder.statistics(for: quantityType))
        }
        DispatchQueue.main.async {
            self.elapsedSeconds = builder.elapsedTime
            self.sendToPhone()
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
