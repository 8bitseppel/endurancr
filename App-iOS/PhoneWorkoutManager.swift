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
/// without a watch, so it's omitted. The class lives on the main actor:
/// `CLLocationManager` is created there and calls back there, and HealthKit's
/// completion handlers hop back with `onMain`.
@MainActor
@Observable
final class PhoneWorkoutManager: NSObject {
    /// The one recorder for the whole app, so every tab shows the same run and a
    /// run survives the tabs being rebuilt (e.g. a goal deleted mid-run).
    static let shared = PhoneWorkoutManager()

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
    /// When the last accepted GPS fix arrived, so a stop shows no pace.
    private var lastFixDate: Date?
    /// When the Live Activity last got new numbers; it's updated every few seconds.
    private var lastActivityUpdate = Date.distantPast

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

    /// Whether the finished run reached Apple Health. The summary waits for this
    /// instead of guessing from `lastError`, which also collects GPS hiccups.
    enum SaveState: Equatable { case idle, saving, saved, failed }
    private(set) var saveState = SaveState.idle

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

    #if DEBUG
    /// Fills in a run in progress for Simulator screenshots (see `DemoMode`),
    /// without touching HealthKit, location or the Live Activity.
    func showDemoRun(plannedWorkout: PlannedWorkout, vdot: Double) {
        self.plannedWorkout = plannedWorkout
        self.targetPace = plannedWorkout.targetPaceSecPerKm
        self.zones = VDOTCalculator().paceZones(forVDOT: vdot)
        // Two thirds into the run, right on its target pace.
        currentPaceSecPerKm = targetPace.map { ($0.lowerBound + $0.upperBound) / 2 } ?? 348
        distanceMeters = (plannedWorkout.distanceMeters * 0.66 / 10).rounded() * 10
        elapsedSeconds = (distanceMeters / 1_000 * currentPaceSecPerKm).rounded()
        routePointCount = 412
        isRunning = true
    }
    #endif

    func start(
        goalName: String = "", workoutTitle: String = "Run",
        targetPace: ClosedRange<Double>? = nil,
        plannedWorkout: PlannedWorkout? = nil, zones: PaceZones? = nil
    ) {
        guard !isRunning else { return }
        self.goalName = goalName
        self.workoutTitle = workoutTitle
        self.targetPace = targetPace
        self.plannedWorkout = plannedWorkout
        self.zones = zones

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
        lastFixDate = nil
        saveState = .idle

        builder.beginCollection(withStart: start) { [weak self] _, error in
            let message = error?.localizedDescription
            Self.onMain { if let message { self?.lastError = message } }
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
                MainActor.assumeIsolated { self?.pause() }
            },
            center.addObserver(forName: .runResumeRequested, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resume() }
            },
            center.addObserver(forName: .runFinishRequested, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.end() }
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
        // GPS keeps running while paused (fixes are ignored): stopping it would let
        // iOS suspend the app in the background, and a Resume from the Lock Screen
        // couldn't start it again.
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
        startTimer()
        updateLiveActivity()
    }

    private func addWorkoutEvent(_ type: HKWorkoutEventType) {
        guard let builder else { return }
        let event = HKWorkoutEvent(
            type: type, dateInterval: DateInterval(start: Date(), duration: 0), metadata: nil
        )
        builder.addWorkoutEvents([event]) { [weak self] _, error in
            let message = error?.localizedDescription
            Self.onMain { if let message { self?.lastError = message } }
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

        Task { await saveWorkout(builder: builder, samples: samples, end: end) }
    }

    /// Saves the finished run with its distance, then attaches the GPS route.
    private func saveWorkout(builder: HKWorkoutBuilder, samples: [HKSample], end: Date) async {
        let routeBuilder = self.routeBuilder
        self.routeBuilder = nil
        saveState = .saving
        do {
            if !samples.isEmpty { try await builder.addSamples(samples) }
            try await builder.endCollection(at: end)
            if let workout = try await builder.finishWorkout() {
                saveState = .saved
                // The workout is in Health now; a missing route doesn't undo that.
                _ = try? await routeBuilder?.finishRoute(with: workout, metadata: nil)
            } else {
                saveState = .failed
            }
        } catch {
            lastError = error.localizedDescription
            saveState = .failed
        }
        isRunning = false
    }

    /// Runs `work` on the main actor, after anything queued before it.
    nonisolated private static func onMain(_ work: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated(work) }
    }

    // MARK: Timer / location

    private func startTimer() {
        timer?.invalidate()
        // A main run loop timer, so it fires on the main actor.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isPaused, let seg = self.segmentStart else { return }
                self.elapsedSeconds = self.accumulatedSeconds + Date().timeIntervalSince(seg)
                // No usable fix for 10 s (standing, or under cover): no pace, rather
                // than the last running pace still showing as on target.
                if let fix = self.lastFixDate, Date().timeIntervalSince(fix) > 10 {
                    self.currentPaceSecPerKm = 0
                }
                // The Lock Screen clock counts by itself; new numbers every 5 s are enough.
                if Date().timeIntervalSince(self.lastActivityUpdate) >= 5 { self.updateLiveActivity() }
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
        // Need a little movement and time span for a meaningful reading; barely
        // moving over a long span is standing, so no pace.
        if dd > 5, dt > 3 {
            currentPaceSecPerKm = dt / (dd / 1_000)
        } else if dt > 10 {
            currentPaceSecPerKm = 0
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
            stepTargetDistanceMeters: stepDistance,
            clockStart: isPaused ? nil : Date().addingTimeInterval(-elapsedSeconds)
        )
    }

    private func updateLiveActivity() {
        guard let activity else { return }
        lastActivityUpdate = Date()
        let state = currentContentState()
        let id = activity.id
        Task { await Self.liveActivity(id)?.update(ActivityContent(state: state, staleDate: nil)) }
    }

    /// The running Live Activity with this id. Looked up inside each task rather
    /// than sent into it, since `Activity` isn't `Sendable`.
    nonisolated private static func liveActivity(_ id: String) -> Activity<RunActivityAttributes>? {
        Activity<RunActivityAttributes>.activities.first { $0.id == id }
    }

    private func endLiveActivity() {
        guard let activity else { return }
        let final = currentContentState()
        let id = activity.id
        Task {
            await Self.liveActivity(id)?.end(
                ActivityContent(state: final, staleDate: nil),
                dismissalPolicy: .after(.now + 5)
            )
        }
        self.activity = nil
    }
}

// MARK: - CLLocationManagerDelegate

// Created on the main thread, so CoreLocation calls back there; `@preconcurrency`
// checks that at run time.
extension PhoneWorkoutManager: @preconcurrency CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Ignore any fixes buffered around a pause so the gap isn't counted.
        guard !isPaused else { return }
        // Keep only accurate fixes so distance/route aren't polluted by noise. 20 m
        // is a converged outdoor fix; the old 50 m let early scatter through and a run
        // begun sitting still immediately showed ~40 m of phantom distance.
        // Stale/cached fixes CoreLocation replays at startup are dropped too, from
        // the distance and from the saved route alike.
        let filtered = locations.filter {
            $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 20 && -$0.timestamp.timeIntervalSinceNow <= 5
        }
        guard !filtered.isEmpty else { return }
        lastFixDate = Date()

        for location in filtered {

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
                let message = error?.localizedDescription
                Self.onMain { if let message { self?.lastError = message } }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A transient location failure shouldn't kill the run; just note it.
        lastError = error.localizedDescription
    }
}
