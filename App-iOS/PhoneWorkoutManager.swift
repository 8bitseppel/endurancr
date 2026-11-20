import Foundation
import HealthKit
import CoreLocation
import ActivityKit
import CoreMotion
import TrainingCore

/// Records a running workout on iPhone — no Apple Watch required — using
/// background CoreLocation for distance/pace/elevation and `HKWorkoutBuilder` +
/// `HKWorkoutRouteBuilder` to save the finished run (and its GPS route) to
/// HealthKit. It also drives a Live Activity so time/distance/pace show on the
/// Lock Screen and Dynamic Island while the phone is locked.
///
/// Outdoors, distance is derived from GPS fixes and elapsed time from a wall-clock
/// timer (which keeps counting while the app is suspended); GPS in the background
/// keeps the app running. Indoors there's no GPS to do that, so the run is an
/// `HKWorkoutSession` (iOS 26), which keeps the app running as the watch's does,
/// and the distance comes from the step counter (`CMPedometer`), with the
/// treadmill's own number typed in at the end. Heart rate isn't available
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
    /// Indoors only: the session that keeps the app running with GPS off.
    private var session: HKWorkoutSession?
    private let pedometer = CMPedometer()
    /// Indoors: the step counter's distance, all of it, paused stretches included.
    private var stepMeters: Double = 0
    /// Indoors: the step counter's metres run while paused, which don't count.
    private var pausedStepMeters: Double = 0
    /// Indoors: the step counter's distance when the run was paused.
    private var stepMetersAtPause: Double?
    /// Indoors: when the step counter last counted a step. It goes quiet when you
    /// stop, rather than saying so, which is how auto-pause notices.
    private var lastStepDate: Date?
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
    /// Follows the session step by step and times every rep and stride, saved with
    /// the run (`RepSplit`). The timer below moves it on, so strides run on the clock.
    private var guided: GuidedRun?
    /// The reps of the run just finished, for the summary.
    private(set) var reps: [RepSplit] = []
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
    /// A run on a treadmill: no GPS and no route, speed in km/h, the treadmill's
    /// distance typed in at the end.
    private(set) var isIndoor = false
    /// Paused by itself, because you stopped (`RunSettings.autoPause`).
    private(set) var isAutoPaused = false
    /// When the runner came to a stop, for auto-pause.
    private var stillSince: Date?
    /// Set the moment Finish is held, so the run screen can play the finish even
    /// for a run too short to summarize.
    private(set) var didFinish = false
    /// Which run this is, so a summary is shown once per run.
    private(set) var runID = UUID()
    /// The full-screen line at a step change, as `RunCues` built it.
    private(set) var cue: RunCue?
    /// The rep already announced with "get ready", so it's announced once.
    private var readiedStep: Int?
    /// Indoors: the saved run is waiting for the treadmill's distance.
    private(set) var needsMachineDistance = false
    /// Indoors: the distance the treadmill showed, which the plan counts.
    private(set) var machineDistanceMeters: Double?
    private var machineDistanceWaiter: CheckedContinuation<Double?, Never>?

    /// Whether the finished run reached Apple Health. The summary waits for this
    /// instead of guessing from `lastError`, which also collects GPS hiccups.
    enum SaveState: Equatable { case idle, saving, saved, failed }
    private(set) var saveState = SaveState.idle
    /// The run's ID in Apple Health once it's saved, to change its shoes afterwards.
    private(set) var savedWorkoutID: UUID?

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
    /// the session goes on. `nil` for a free run.
    var activeStep: WorkoutStep? { guided?.step }

    /// Seconds left of a step run by the clock (a stride, or the easy minute before
    /// one); `nil` for a step run by distance.
    var stepSecondsLeft: Double? { guided?.remainingSeconds(elapsed: elapsedSeconds) }
    /// Metres left of a step run by distance; `nil` for a timed step or the last one.
    var stepMetersLeft: Double? { guided?.remainingMeters(distance: distanceMeters) }
    /// How far through the current step, 0 to 1.
    var stepProgress: Double { guided?.progress(distance: distanceMeters, elapsed: elapsedSeconds) ?? 0 }
    /// Every step of the session, in order; empty for a free run.
    var steps: [WorkoutStep] { guided?.steps ?? [] }
    /// The pace of the last stride that was run, once it's over; `nil` before the first.
    var lastStridePace: Double? {
        guided.flatMap { RepReport.strides($0.reps).last?.paceSecPerKm }
    }
    /// During a rep or a stride: its average pace so far, the fairest "am I on pace".
    var thisRepPaceSecPerKm: Double? { guided?.currentPace(distance: distanceMeters, elapsed: elapsedSeconds) }

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

    /// `-demoScreen phoneflow`: a guided session from a simulation, through the same
    /// steps, cues and finish as a real run, without HealthKit, GPS or the step
    /// counter. `-demoStrides YES` runs an easy run with strides, `-demoIndoor YES`
    /// runs it on a treadmill. Fast between the parts worth watching.
    func demoRun(plannedWorkout planned: PlannedWorkout, zones: PaceZones, indoor: Bool) async {
        self.plannedWorkout = planned
        targetPace = planned.targetPaceSecPerKm
        self.zones = zones
        guided = GuidedRun(workout: planned, zones: zones)
        isIndoor = indoor
        didFinish = false
        runID = UUID()
        cue = nil
        readiedStep = nil
        reps = []
        saveState = .idle
        machineDistanceMeters = nil
        isPaused = false
        isRunning = true
        let steps = WorkoutSteps.steps(for: planned, zones: zones)
        // From 200 m before the strides or the first rep.
        let hard = steps.first { $0.kind == .stride || $0.kind == .work || $0.seconds != nil }
        var distance = max(0, (hard?.startMeters ?? 0) - 200)
        var elapsed = distance / 1_000 * zones.easySecPerKm
        while distance < planned.distanceMeters + 300, elapsed < 36_000, isRunning {
            let step = activeStep
            let pace = (step?.targetPaceSecPerKm ?? zones.easySecPerKm) + (step?.kind == .stride && step?.repNumber == 4 ? 30 : 0)
            let tick = step?.kind == .stride ? 0.4 : (hard?.kind == .stride ? 6 : 3)
            distance += 1_000 / pace * tick
            elapsed += tick
            distanceMeters = distance
            elapsedSeconds = elapsed
            currentPaceSecPerKm = pace
            advanceSteps()
            try? await Task.sleep(for: .milliseconds(100))
            if activeStep?.kind == .cooldown, hard?.kind == .stride {
                try? await Task.sleep(for: .seconds(4))
                break
            }
        }
        guard isRunning else { return }
        guided?.finish(distance: distanceMeters, elapsed: elapsedSeconds, date: .now)
        reps = guided?.reps ?? []
        guided = nil
        didFinish = true
        saveState = .saving
        isRunning = false
        // `-demoTreadmillHold YES` keeps the treadmill screen up, for its screenshot.
        if indoor, !UserDefaults.standard.bool(forKey: "demoTreadmillHold") {
            let run = runID
            Task {
                // The treadmill's number, typed in a moment later, as a runner would.
                try? await Task.sleep(for: .seconds(5))
                if runID == run, needsMachineDistance { confirmMachineDistance((distanceMeters * 1.03 / 10).rounded() * 10) }
            }
        }
        if let machine = await awaitMachineDistance() { distanceMeters = machine }
        try? await Task.sleep(for: .seconds(2))
        saveState = .saved
    }
    #endif

    func start(
        goalName: String = "", workoutTitle: String = "Run",
        targetPace: ClosedRange<Double>? = nil,
        plannedWorkout: PlannedWorkout? = nil, zones: PaceZones? = nil, indoor: Bool = false
    ) {
        guard !isRunning, saveState != .saving else { return }
        self.goalName = goalName
        self.workoutTitle = workoutTitle
        self.targetPace = targetPace
        self.plannedWorkout = plannedWorkout
        self.zones = zones
        guided = plannedWorkout.flatMap { w in zones.map { GuidedRun(workout: w, zones: $0) } }
        reps = []
        isIndoor = indoor
        isAutoPaused = false
        stillSince = nil
        didFinish = false
        runID = UUID()
        savedWorkoutID = nil
        cue = nil
        readiedStep = nil
        needsMachineDistance = false
        machineDistanceMeters = nil
        stepMeters = 0
        pausedStepMeters = 0
        stepMetersAtPause = nil
        lastStepDate = indoor ? Date() : nil

        let config = HKWorkoutConfiguration()
        config.activityType = .running
        config.locationType = indoor ? .indoor : .outdoor
        let start = Date()

        if indoor {
            // A workout session keeps the app running with the screen locked, which
            // GPS does outdoors. Its live builder records what the iPhone measures;
            // the distance is the step counter's, or the treadmill's, added at the end.
            do {
                let session = try HKWorkoutSession(healthStore: store, configuration: config)
                let live = session.associatedWorkoutBuilder()
                let source = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
                source.disableCollection(for: HKQuantityType(.distanceWalkingRunning))
                live.dataSource = source
                self.session = session
                self.builder = live
                session.startActivity(with: start)
            } catch {
                lastError = error.localizedDescription
                return
            }
            routeBuilder = nil
        } else {
            builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
            routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
        }
        guard let builder else { return }

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

        if indoor { beginStepCounting(from: start) } else { beginLocationUpdates() }
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
    func pause() { pause(auto: false) }

    private func pause(auto: Bool) {
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
        stepMetersAtPause = stepMeters
        paceWindow = []
        currentPaceSecPerKm = 0
        isAutoPaused = auto
        if let session { session.pause() } else { addWorkoutEvent(auto ? .motionPaused : .pause) }
        if auto, RunSettings.spokenCues { SpokenCues.shared.say("Paused.") }
        updateLiveActivity()
    }

    /// Resumes timing, distance, and GPS after a `pause()`.
    func resume() { resume(auto: false) }

    private func resume(auto: Bool) {
        guard isRunning, isPaused else { return }
        segmentStart = Date()
        isPaused = false
        if let atPause = stepMetersAtPause { pausedStepMeters += stepMeters - atPause }
        stepMetersAtPause = nil
        stillSince = nil
        let wasAuto = isAutoPaused
        isAutoPaused = false
        if let session { session.resume() } else { addWorkoutEvent(wasAuto ? .motionResumed : .resume) }
        if auto, RunSettings.spokenCues { SpokenCues.shared.say("Running again.") }
        startTimer()
        updateLiveActivity()
    }

    /// Auto-pause (`RunSettings.autoPause`): after 8 s standing still the run
    /// pauses, and it goes on the moment you run again. Called with every reading of
    /// how fast you're going: the GPS speed outdoors, the step counter indoors.
    private func checkAutoPause(moving: Bool) {
        guard isRunning, RunSettings.autoPause else { return }
        if isAutoPaused {
            if moving { resume(auto: true) }
            return
        }
        guard !isPaused else { return }
        if moving {
            stillSince = nil
        } else if let since = stillSince {
            if Date().timeIntervalSince(since) >= 8 { pause(auto: true) }
        } else {
            stillSince = Date()
        }
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

    /// Ends the run. The screen moves on at once (`isRunning` goes false here); the
    /// save to Health follows in the background, with `saveState` saying how it went,
    /// so nothing has to wait for it. Indoors the save first waits for the
    /// treadmill's distance (`confirmMachineDistance`).
    func end() {
        guard isRunning else { return }
        let end = Date()
        if !isPaused, let seg = segmentStart { elapsedSeconds = accumulatedSeconds + end.timeIntervalSince(seg) }
        timer?.invalidate()
        timer = nil
        isPaused = false
        isAutoPaused = false
        segmentStart = nil
        locationManager.stopUpdatingLocation()
        pedometer.stopUpdates()
        removeLiveActivityControls()
        endLiveActivity()
        // The reps are settled now, so the summary can show them straight away.
        guided?.finish(distance: distanceMeters, elapsed: elapsedSeconds, date: end)
        reps = guided?.reps ?? []
        guided = nil
        didFinish = true

        guard let builder, let startDate else {
            isRunning = false
            return
        }
        saveState = .saving
        isRunning = false
        Task { await saveWorkout(builder: builder, start: startDate, end: end) }
    }

    /// The treadmill's distance, or `nil` to keep the step counter's. Saves the run.
    func confirmMachineDistance(_ meters: Double?) {
        if let meters, meters > 0 { machineDistanceMeters = meters }
        needsMachineDistance = false
        machineDistanceWaiter?.resume(returning: machineDistanceMeters)
        machineDistanceWaiter = nil
    }

    /// Waits for the treadmill's distance, for at most two minutes: a run left
    /// unanswered is saved with the step counter's distance rather than lost.
    private func awaitMachineDistance() async -> Double? {
        guard isIndoor, distanceMeters > 0, machineDistanceMeters == nil else { return machineDistanceMeters }
        needsMachineDistance = true
        let run = runID
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(120))
            guard let self, self.runID == run, self.needsMachineDistance else { return }
            self.confirmMachineDistance(nil)
        }
        return await withCheckedContinuation { machineDistanceWaiter = $0 }
    }

    /// Saves the finished run with its distance, then attaches the GPS route.
    private func saveWorkout(builder: HKWorkoutBuilder, start: Date, end: Date) async {
        let routeBuilder = self.routeBuilder
        self.routeBuilder = nil
        defer {
            if let session, session.state != .ended { session.end() }
            session = nil
            self.builder = nil
        }
        do {
            // Indoors the treadmill's number is the run's distance: it counts the belt.
            let machine = await awaitMachineDistance()
            if let machine { distanceMeters = machine }
            // Attach the total running distance so the saved workout carries it
            // (HealthKit otherwise derives distance only from samples we add).
            if distanceMeters > 0 {
                try await builder.addSamples([HKQuantitySample(
                    type: HKQuantityType(.distanceWalkingRunning),
                    quantity: HKQuantity(unit: .meter(), doubleValue: distanceMeters),
                    start: start, end: end
                )])
            }
            if let machine { try await builder.addMetadata(["EndurancrMachineDistance": machine]) }
            try await saveReps(to: builder)
            if let session { session.stopActivity(with: end) }
            try await builder.endCollection(at: end)
            if let workout = try await builder.finishWorkout() {
                savedWorkoutID = workout.uuid
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
    }

    /// The reps go into Health twice: as Apple's workout segments, which the Fitness
    /// app shows, and as one metadata entry endurancr reads back with their targets.
    private func saveReps(to builder: HKWorkoutBuilder) async throws {
        guard let json = RepReport.encode(reps) else { return }
        try await builder.addMetadata([RepReport.metadataKey: json])
        try await builder.addWorkoutEvents(reps.map { rep in
            HKWorkoutEvent(type: .segment, dateInterval: DateInterval(start: rep.start, end: max(rep.end, rep.start)),
                           metadata: ["EndurancrRep": rep.label])
        })
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
                self.advanceSteps()
                // No usable fix for 10 s (standing, or under cover): no pace, rather
                // than the last running pace still showing as on target.
                if !self.isIndoor, let fix = self.lastFixDate, Date().timeIntervalSince(fix) > 10 {
                    self.currentPaceSecPerKm = 0
                    self.checkAutoPause(moving: false)
                }
                if self.isIndoor, let step = self.lastStepDate, Date().timeIntervalSince(step) > 3 {
                    self.currentPaceSecPerKm = 0
                    self.checkAutoPause(moving: false)
                }
                // The Lock Screen clock counts by itself; new numbers every 5 s are enough.
                if Date().timeIntervalSince(self.lastActivityUpdate) >= 5 { self.updateLiveActivity() }
            }
        }
    }

    // MARK: Steps

    /// Ends the step that's over and says what's next, on every tick and every new
    /// distance, so a stride ends on its 20th second and a rep on its last metre.
    private func advanceSteps() {
        guard var run = guided, !isPaused else { return }
        let entered = run.update(distance: distanceMeters, elapsed: elapsedSeconds, date: Date(), heartRate: 0)
        guided = run
        if entered.isEmpty {
            if let next = RunCues.ready(run, distance: distanceMeters, readied: readiedStep) {
                readiedStep = run.nextStep?.index
                announce(next)
            }
        } else {
            for step in entered {
                if let next = RunCues.cue(for: step, in: run.steps) { announce(next) }
            }
        }
    }

    /// Hands the screen the cue and, with spoken cues on, says it.
    private func announce(_ next: RunCue) {
        cue = next
        if RunSettings.spokenCues, let words = next.spoken { SpokenCues.shared.say(words) }
        #if DEBUG
        if DemoMode.isOn { print("[step] at \(Int(distanceMeters)) m, \(Int(elapsedSeconds)) s: \(next.spoken ?? "(silent)") | \(next.title)") }
        #endif
    }

    // MARK: Step counter (indoors)

    /// Indoors the distance is the step counter's, which needs the iPhone on you:
    /// in a pocket, on an armband or in a hand. On the treadmill's console it counts
    /// nothing, which is why the treadmill's own number is asked for at the end.
    private func beginStepCounting(from start: Date) {
        guard CMPedometer.isDistanceAvailable() else { return }
        pedometer.startUpdates(from: start) { [weak self] data, _ in
            let meters = data?.distance?.doubleValue
            Self.onMain { if let meters { self?.stepped(to: meters) } }
        }
    }

    private func stepped(to meters: Double) {
        let moved = meters - stepMeters
        stepMeters = meters
        if moved > 0 { lastStepDate = Date() }
        checkAutoPause(moving: moved > 1)
        guard !isPaused else { return }
        distanceMeters = max(0, stepMeters - pausedStepMeters)
        recomputeCurrentPace(now: Date().timeIntervalSince1970)
        advanceSteps()
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
        // Standing still or running again, for auto-pause, paused or not.
        if let last = locations.last, last.speed >= 0, last.horizontalAccuracy >= 0, last.horizontalAccuracy <= 20 {
            checkAutoPause(moving: last.speed >= 1.0)
        }
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
        advanceSteps()
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
