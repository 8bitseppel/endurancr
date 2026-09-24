import Foundation
import HealthKit
import CoreLocation

/// Records a running workout on Apple Watch using `HKWorkoutSession` +
/// `HKLiveWorkoutBuilder`, streaming live metrics and saving the finished
/// `HKWorkout` to HealthKit. GPS points from CoreLocation are accumulated into an
/// `HKWorkoutRouteBuilder` and attached to the workout, so the route shows up in the
/// Fitness/Health apps (and can be drawn in-app via MapKit). Delegate callbacks
/// arrive off the main thread, so UI state is updated on the main queue.
@Observable
final class WorkoutManager: NSObject, @unchecked Sendable {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private let locationManager = CLLocationManager()

    // Live, observable metrics.
    var isRunning = false
    var isPaused = false
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

    func start() {
        didFinish = false
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
            DispatchQueue.main.async { self.isRunning = true }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }

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
        case .running: DispatchQueue.main.async { self.isPaused = false }
        case .paused: DispatchQueue.main.async { self.isPaused = true }
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
        DispatchQueue.main.async { self.elapsedSeconds = builder.elapsedTime }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
