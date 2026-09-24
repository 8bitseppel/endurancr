import Foundation
import HealthKit
import CoreLocation
import ActivityKit
import TrainingCore

/// Records a running workout on iPhone — no Apple Watch required — using
/// background CoreLocation for distance/pace/elevation and `HKWorkoutBuilder` +
/// `HKWorkoutRouteBuilder` to save the finished run (and its GPS route) to
/// HealthKit. It also drives a Live Activity so time/distance/pace show on the
/// Lock Screen and Dynamic Island while the phone is locked.
///
/// Unlike watchOS there is no `HKWorkoutSession`/`HKLiveWorkoutBuilder` on iOS, so
/// distance is derived from GPS fixes and elapsed time from a wall-clock timer
/// (which keeps counting while the app is suspended). Heart rate isn't available
/// without a watch, so it's omitted. `CLLocationManager` is created on the main
/// run loop, so its delegate callbacks arrive on the main thread and observable
/// state is mutated there directly.
@Observable
final class PhoneWorkoutManager: NSObject, @unchecked Sendable {
    private let store = HKHealthStore()
    private var builder: HKWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private let locationManager = CLLocationManager()
    private var activity: Activity<RunActivityAttributes>?

    private var startDate: Date?
    private var lastLocation: CLLocation?
    private var lastAltitude: CLLocationDistance?
    private var timer: Timer?
    /// Observers for the Live Activity control buttons, live only while a run is
    /// active so only the running manager reacts.
    private var controlObservers: [NSObjectProtocol] = []
    /// Moving-time accounting that survives pauses: completed running segments plus
    /// the current one. `elapsedSeconds` = `accumulatedSeconds` + time since
    /// `segmentStart` (only while not paused), so paused time never counts.
    private var accumulatedSeconds: TimeInterval = 0
    private var segmentStart: Date?
    /// Rolling (timestamp, cumulative distance) samples used for current pace.
    private var paceWindow: [(t: TimeInterval, d: Double)] = []
    private let paceWindowSeconds: TimeInterval = 30

    // Fixed for this run (shown on the Live Activity).
    private var goalName = ""
    private var workoutTitle = "Run"
    private var targetPace: ClosedRange<Double>?
    /// Today's planned session + the athlete's paces, so the Live Activity can show
    /// step-aware targets that advance as each step's distance is covered. Nil = free run.
    private var plannedWorkout: PlannedWorkout?
    private var zones: PaceZones?

    // Live, observable metrics.
    var isRunning = false
    var isPaused = false
    var distanceMeters: Double = 0
    var elapsedSeconds: TimeInterval = 0
    /// Rolling pace over roughly the last 30s (sec/km).
    var currentPaceSecPerKm: Double = 0
    /// Total climb (m) from GPS altitude.
    var elevationGainMeters: Double = 0
    /// Number of GPS points captured so far (a simple "route is tracking" signal).
    var routePointCount = 0
    var lastError: String?

    /// The target pace window for today's workout, if any.
    var targetPaceRange: ClosedRange<Double>? { targetPace }

    /// Average pace over the whole run (sec/km), derived from distance and time.
    var averagePaceSecPerKm: Double {
        guard distanceMeters > 0 else { return 0 }
        return elapsedSeconds / (distanceMeters / 1_000)
    }

    /// Whether current pace sits inside the planned window (nil when no target/pace).
    var isOnTarget: Bool? {
        guard let targetPace, currentPaceSecPerKm > 0 else { return nil }
        return targetPace.contains(currentPaceSecPerKm)
    }

    /// Overall planned distance for today's session (m); 0 for a free run.
    var plannedDistanceMeters: Double { plannedWorkout?.distanceMeters ?? 0 }

    /// The step the athlete is currently in, for step-aware targets that advance as
    /// each step's distance is covered. `nil` for a free run.
    var activeStep: WorkoutStep? {
        guard let plannedWorkout, let zones else { return nil }
        return WorkoutSteps.activeStep(
            for: plannedWorkout, zones: zones, distanceCovered: distanceMeters
        )
    }

    func start(
        goalName: String = "", workoutTitle: String = "Run",
        targetPace: ClosedRange<Double>? = nil,
        plannedWorkout: PlannedWorkout? = nil, vdot: Double? = nil
    ) {
        guard !isRunning else { return }
        self.goalName = goalName
        self.workoutTitle = workoutTitle
        self.targetPace = targetPace
        self.plannedWorkout = plannedWorkout
        self.zones = vdot.map { VDOTCalculator().paceZones(forVDOT: $0) }

        let config = HKWorkoutConfiguration()
        config.activityType = .running
        config.locationType = .outdoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        self.builder = builder
        self.routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: nil)

        let start = Date()
        startDate = start
        segmentStart = start
        accumulatedSeconds = 0
        lastLocation = nil
        lastAltitude = nil
        paceWindow = []
        distanceMeters = 0
        elapsedSeconds = 0
        currentPaceSecPerKm = 0
        elevationGainMeters = 0
        routePointCount = 0
        lastError = nil
        isPaused = false

        builder.beginCollection(withStart: start) { [weak self] _, error in
            if let error { DispatchQueue.main.async { self?.lastError = error.localizedDescription } }
        }

        beginLocationUpdates()
        startTimer()
        startLiveActivity()
        observeLiveActivityControls()
        isRunning = true
    }

    /// Subscribes to the Live Activity button notifications. The intents post these
    /// from the app's process, so we can drive pause/resume/finish straight from the
    /// Lock Screen or Dynamic Island. Callbacks are marshalled to the main queue
    /// since they mutate observable state and the timer.
    private func observeLiveActivityControls() {
        removeLiveActivityControls()
        let center = NotificationCenter.default
        controlObservers = [
            center.addObserver(forName: .runPauseRequested, object: nil, queue: .main) { [weak self] _ in
                self?.pause()
            },
            center.addObserver(forName: .runResumeRequested, object: nil, queue: .main) { [weak self] _ in
                self?.resume()
            },
            center.addObserver(forName: .runFinishRequested, object: nil, queue: .main) { [weak self] _ in
                self?.end()
            },
        ]
    }

    private func removeLiveActivityControls() {
        for observer in controlObservers { NotificationCenter.default.removeObserver(observer) }
        controlObservers = []
    }

    /// Freezes the clock and stops accruing distance until `resume()`. The paused gap
    /// is excluded from both moving time and distance, and a `.pause` event is added
    /// to the workout so Health reflects the split.
    func pause() {
        guard isRunning, !isPaused, let seg = segmentStart else { return }
        accumulatedSeconds += Date().timeIntervalSince(seg)
        elapsedSeconds = accumulatedSeconds
        segmentStart = nil
        isPaused = true
        timer?.invalidate(); timer = nil
        locationManager.stopUpdatingLocation()
        lastLocation = nil          // so the distance across the paused gap isn't counted
        paceWindow = []
        currentPaceSecPerKm = 0
        addWorkoutEvent(.pause)
        updateLiveActivity()
    }

    /// Resumes timing, distance, and GPS after a `pause()`.
    func resume() {
        guard isRunning, isPaused else { return }
        segmentStart = Date()
        isPaused = false
        addWorkoutEvent(.resume)
        locationManager.startUpdatingLocation()
        startTimer()
        updateLiveActivity()
    }

    private func addWorkoutEvent(_ type: HKWorkoutEventType) {
        guard let builder else { return }
        let event = HKWorkoutEvent(
            type: type, dateInterval: DateInterval(start: Date(), duration: 0), metadata: nil
        )
        builder.addWorkoutEvents([event]) { [weak self] _, error in
            if let error { DispatchQueue.main.async { self?.lastError = error.localizedDescription } }
        }
    }

    func end() {
        guard isRunning else { return }
        timer?.invalidate()
        timer = nil
        isPaused = false
        segmentStart = nil
        locationManager.stopUpdatingLocation()
        removeLiveActivityControls()
        endLiveActivity()

        guard let builder, let startDate else {
            isRunning = false
            return
        }
        let end = Date()

        // Attach the total running distance so the saved workout carries it (HealthKit
        // otherwise derives distance only from samples we add).
        var samples: [HKSample] = []
        if distanceMeters > 0 {
            samples.append(HKQuantitySample(
                type: HKQuantityType(.distanceWalkingRunning),
                quantity: HKQuantity(unit: .meter(), doubleValue: distanceMeters),
                start: startDate, end: end
            ))
        }

        let finalize: () -> Void = { [weak self] in
            builder.endCollection(withEnd: end) { _, _ in
                builder.finishWorkout { workout, error in
                    if let error { DispatchQueue.main.async { self?.lastError = error.localizedDescription } }
                    guard let self, let workout, let routeBuilder = self.routeBuilder else {
                        DispatchQueue.main.async { self?.isRunning = false }
                        return
                    }
                    routeBuilder.finishRoute(with: workout, metadata: nil) { _, routeError in
                        if let routeError {
                            DispatchQueue.main.async { self.lastError = routeError.localizedDescription }
                        }
                        DispatchQueue.main.async {
                            self.routeBuilder = nil
                            self.isRunning = false
                        }
                    }
                }
            }
        }

        if samples.isEmpty {
            finalize()
        } else {
            builder.add(samples) { [weak self] _, error in
                if let error { DispatchQueue.main.async { self?.lastError = error.localizedDescription } }
                finalize()
            }
        }
    }

    // MARK: Timer / location

    private func startTimer() {
        DispatchQueue.main.async {
            self.timer?.invalidate()
            self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self, !self.isPaused, let seg = self.segmentStart else { return }
                self.elapsedSeconds = self.accumulatedSeconds + Date().timeIntervalSince(seg)
                self.updateLiveActivity()
            }
        }
    }

    private func beginLocationUpdates() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .fitness
        // Keep tracking with the screen off / app backgrounded (blue status bar).
        // Requires the `location` UIBackgroundMode in Info.plist.
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    /// Recomputes rolling current pace from the ~30s distance window.
    private func recomputeCurrentPace(now: TimeInterval) {
        paceWindow.append((now, distanceMeters))
        let cutoff = now - paceWindowSeconds
        // Drop stale samples but keep one just before the cutoff as a clean baseline.
        while paceWindow.count > 2 && paceWindow[1].t < cutoff {
            paceWindow.removeFirst()
        }
        guard let first = paceWindow.first, let last = paceWindow.last else { return }
        let dd = last.d - first.d
        let dt = last.t - first.t
        // Need a little movement and time span for a meaningful reading.
        if dd > 5, dt > 3 {
            currentPaceSecPerKm = dt / (dd / 1_000)
        }
    }

    // MARK: Live Activity

    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = RunActivityAttributes(
            goalName: goalName,
            workoutTitle: workoutTitle,
            targetPaceLower: targetPace?.lowerBound,
            targetPaceUpper: targetPace?.upperBound
        )
        let initial = currentContentState()
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: initial, staleDate: nil),
                pushType: nil
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func currentContentState() -> RunActivityAttributes.ContentState {
        // Resolve the active step for how far we've run, so interval targets advance
        // automatically. Steady/free runs leave the step fields empty.
        var stepLabel = ""
        var stepPace: Double = 0
        var stepDistance: Double = 0
        if let step = activeStep, step.kind != .steady {
            stepLabel = step.label
            stepPace = step.targetPaceSecPerKm ?? 0
            stepDistance = step.distanceMeters
        }
        return RunActivityAttributes.ContentState(
            elapsedSeconds: elapsedSeconds,
            distanceMeters: distanceMeters,
            currentPaceSecPerKm: currentPaceSecPerKm,
            averagePaceSecPerKm: averagePaceSecPerKm,
            elevationGainMeters: elevationGainMeters,
            isPaused: isPaused,
            targetDistanceMeters: plannedWorkout?.distanceMeters ?? 0,
            stepLabel: stepLabel,
            stepTargetPaceSecPerKm: stepPace,
            stepTargetDistanceMeters: stepDistance
        )
    }

    private func updateLiveActivity() {
        guard let activity else { return }
        let state = currentContentState()
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    private func endLiveActivity() {
        guard let activity else { return }
        let final = currentContentState()
        Task {
            await activity.end(
                ActivityContent(state: final, staleDate: nil),
                dismissalPolicy: .after(.now + 5)
            )
        }
        self.activity = nil
    }
}

// MARK: - CLLocationManagerDelegate

extension PhoneWorkoutManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Ignore any fixes buffered around a pause so the gap isn't counted.
        guard !isPaused else { return }
        // Keep only accurate fixes so distance/route aren't polluted by noise. 20 m
        // is a converged outdoor fix; the old 50 m let early scatter through and a run
        // begun sitting still immediately showed ~40 m of phantom distance.
        let filtered = locations.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 20 }
        guard !filtered.isEmpty else { return }

        for location in filtered {
            // Drop stale/cached fixes CoreLocation replays at startup.
            if -location.timestamp.timeIntervalSinceNow > 5 { continue }

            if let previous = lastLocation {
                let step = location.distance(from: previous)
                let dt = location.timestamp.timeIntervalSince(previous.timestamp)
                let impliedSpeed = dt > 0 ? step / dt : .greatestFiniteMagnitude
                // Count distance only while actually moving. Standing still still
                // produces GPS jitter; prefer the Doppler speed (reliably near zero at
                // rest) and fall back to the step-derived speed when it's unavailable.
                // 0.7 m/s is below a slow walk; the 12 m/s cap drops single-fix glitches
                // faster than any runner.
                let speed = location.speed >= 0 ? location.speed : impliedSpeed
                if speed >= 0.7, impliedSpeed <= 12 {
                    distanceMeters += step
                }
            }
            lastLocation = location

            // Elevation gain from GPS altitude, guarded by vertical accuracy and a
            // small threshold so noise doesn't inflate the climb.
            if location.verticalAccuracy > 0, location.verticalAccuracy <= 10 {
                if let lastAltitude {
                    let climb = location.altitude - lastAltitude
                    if climb > 0.5 { elevationGainMeters += climb }
                }
                lastAltitude = location.altitude
            }
        }

        recomputeCurrentPace(now: Date().timeIntervalSince1970)
        routePointCount += filtered.count

        if let routeBuilder {
            routeBuilder.insertRouteData(filtered) { [weak self] _, error in
                if let error { DispatchQueue.main.async { self?.lastError = error.localizedDescription } }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A transient location failure shouldn't kill the run; just note it.
        DispatchQueue.main.async { self.lastError = error.localizedDescription }
    }
}
