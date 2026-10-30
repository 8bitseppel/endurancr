import Foundation
import HealthKit
import WatchKit
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
    // The second run page: the run's averages, climb, cadence and last km.
    var averageHeartRate: Double = 0
    /// Metres climbed, from the GPS altitude (barometer included on the watch).
    var elevationGainMeters: Double = 0
    /// Steps per minute over the last 30 seconds; 0 until there's enough.
    var cadence: Double = 0
    /// Time for the last full kilometre; `nil` before the first.
    var lastKmSeconds: Double?
    /// The pace of the kilometre in progress so far, once 100 m of it are run.
    var thisKmPaceSecPerKm: Double? {
        #if DEBUG
        if let demoThisKm { return demoThisKm }
        #endif
        let meters = distanceMeters - (nextKmMark - 1_000)
        let seconds = elapsedSeconds - lastKmMarkSeconds
        return meters >= 100 && seconds > 0 ? seconds / (meters / 1_000) : nil
    }

    /// During a rep: its average pace so far (`GuidedRun`), the fairest "am I on pace".
    var thisRepPaceSecPerKm: Double? {
        #if DEBUG
        if let demoThisRep { return demoThisRep }
        #endif
        return guided?.currentPace(distance: distanceMeters, elapsed: elapsedSeconds)
    }

    #if DEBUG
    var demoThisKm: Double?
    var demoThisRep: Double?
    #endif
    private var lastAltitude: Double?
    private var stepWindow: [(seconds: Double, steps: Double)] = []
    private var nextKmMark: Double = 1_000
    private var lastKmMarkSeconds: Double = 0
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

    /// Whether the finished run reached Apple Health. The summary waits for this
    /// instead of guessing from `lastError`, which also collects GPS hiccups.
    enum SaveState: Equatable { case idle, saving, saved, failed }
    private(set) var saveState = SaveState.idle
    /// The saved workout's own time and distance, once HealthKit has it.
    private(set) var savedDuration: TimeInterval?
    private(set) var savedDistanceMeters: Double?
    /// Latest running speed (m/s) from the watch's sensors, for the live pace.
    private var currentSpeed: Double = 0
    /// The reps of the run just finished, for the summary.
    private(set) var reps: [RepSplit] = []

    // MARK: Step guidance

    /// Follows today's session step by step and records every rep and stride as it
    /// ends. `nil` for a free run or a run at one steady pace.
    ///
    /// It lives here rather than on the run screen because a stride is 20 s long and
    /// the wrist has to be tapped when it starts and when it ends, whether or not the
    /// screen is awake. The screen only draws the cue the recorder decided on.
    private(set) var guided: GuidedRun?
    /// The step the athlete is in now; `nil` for a free run.
    var activeStep: WorkoutStep? { guided?.step }
    /// The step the screen should show full screen right now.
    private(set) var cue: RunCue?
    /// The rep already announced with "get ready", so it's announced once.
    private var readiedStep: Int?
    /// Moves the session on once a second, so steps that run on the clock (strides,
    /// the easy minute before each) end on time and not when GPS next reports in.
    private var ticker: Timer?
    /// A run picked up after the app was relaunched: the next reading says which
    /// step it's in.
    private var isRecovering = false
    /// "Plan done" is said once a run.
    private var saidPlanDone = false

    /// Seconds left of a step run by the clock: a stride, or the easy minute before
    /// one. `nil` for a step run by distance.
    var stepSecondsLeft: Double? { guided?.remainingSeconds(elapsed: elapsedSeconds) }
    /// Metres left of a step run by distance; `nil` for a timed step or the last one.
    var stepMetersLeft: Double? { guided?.remainingMeters(distance: distanceMeters) }
    /// How far through the current step, 0 to 1, for the ring around a stride.
    var stepProgress: Double { guided?.progress(distance: distanceMeters, elapsed: elapsedSeconds) ?? 0 }
    /// The pace of the last stride that was run, once it's over and can be measured
    /// honestly; `nil` before the first one is done.
    var lastStridePace: Double? {
        guided.flatMap { RepReport.strides($0.reps).last?.paceSecPerKm }
    }

    /// How many strides are done, of how many, during a run with strides.
    var stridesDone: (done: Int, total: Int)? {
        guard let guided, let total = guided.steps.first(where: { $0.kind == .stride })?.repTotal else { return nil }
        return (RepReport.strides(guided.reps).count, total)
    }

    #if DEBUG
    /// The demo's running speed, so its live pace reads as on target.
    func setDemoSpeed(_ metersPerSecond: Double) { currentSpeed = metersPerSecond }

    /// Points a still demo run at today's session, at the step its distance says, so
    /// the screen shows the same targets a real run would.
    func demoGuide(_ planned: PlannedWorkout, _ zones: PaceZones) {
        plannedWorkout = planned
        self.zones = zones
        var run = GuidedRun(workout: planned, zones: zones)
        run.seek(distance: distanceMeters, elapsed: elapsedSeconds)
        guided = run
    }

    /// Runs a session from a simulation instead of from HealthKit, through the same
    /// step engine, cues and taps as a real run (`IntervalRunSimulation`).
    func demoStart(plannedWorkout: PlannedWorkout, zones: PaceZones) {
        resetLiveState()
        self.plannedWorkout = plannedWorkout
        self.zones = zones
        guided = GuidedRun(workout: plannedWorkout, zones: zones)
        isRunning = true
    }

    func demoAdvance(distance: Double, elapsed: Double, speed: Double, heartRate: Double) {
        distanceMeters = distance
        elapsedSeconds = elapsed
        currentSpeed = speed
        self.heartRate = heartRate
        advanceSteps(at: Date())
        checkPlanDone()
    }

    func demoFinish() {
        guided?.finish(distance: distanceMeters, elapsed: elapsedSeconds, date: Date())
        reps = guided?.reps ?? []
        isRunning = false
    }
    #endif

    /// The run's time at `date`, for a clock that ticks every second rather than
    /// only when HealthKit delivers new data. Paused time doesn't count.
    func elapsedTime(at date: Date) -> TimeInterval {
        builder?.elapsedTime(at: date) ?? elapsedSeconds
    }

    /// Pace right now (sec/km), from the watch's running speed; the average until
    /// the first speed reading arrives. 0 while standing still.
    var paceSecPerKm: Double {
        if currentSpeed > 0.5 { return 1_000 / currentSpeed }
        return currentSpeed > 0 ? 0 : averagePaceSecPerKm
    }

    /// Average pace over the whole run (sec/km).
    var averagePaceSecPerKm: Double {
        guard distanceMeters > 0 else { return 0 }
        return elapsedSeconds / (distanceMeters / 1_000)
    }

    /// Starts recording. Returns false (with `lastError` set) when HealthKit
    /// refuses, e.g. without Health access, so no empty run screen opens.
    @discardableResult
    func start(plannedWorkout: PlannedWorkout? = nil, zones: PaceZones? = nil, goalName: String = "") -> Bool {
        if isRunning { return true }                 // already running: keep it
        guard session == nil, saveState != .saving else {
            lastError = "The last run is still being saved. Try again in a moment."
            return false
        }
        resetLiveState()
        self.plannedWorkout = plannedWorkout
        self.zones = zones
        self.goalName = goalName
        guided = plannedWorkout.flatMap { w in zones.map { GuidedRun(workout: w, zones: $0) } }
        startTicking()
        RunContext(plannedWorkout: plannedWorkout, zones: zones, goalName: goalName).save()
        let config = HKWorkoutConfiguration()
        config.activityType = .running
        config.locationType = .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = attach(session)

            // Prepare, then mirror to the iPhone, then start, as Apple's sample does.
            // Without the iPhone nearby the run just records here.
            session.prepare()
            session.startMirroringToCompanionDevice { _, _ in }
            let startDate = Date()
            session.startActivity(with: startDate)
            builder.beginCollection(withStart: startDate) { [weak self] _, error in
                let message = error?.localizedDescription
                Self.onMain { if let message { self?.lastError = message } }
            }
            isRunning = true
            return true
        } catch {
            lastError = error.localizedDescription
            RunContext.clear()
            return false
        }
    }

    /// Clears the last run's numbers, so a new or recovered run starts from zero.
    private func resetLiveState() {
        didFinish = false
        isPaused = false
        isAutoPaused = false
        heartRate = 0
        averageHeartRate = 0
        elevationGainMeters = 0
        cadence = 0
        lastKmSeconds = nil
        lastAltitude = nil
        stepWindow = []
        nextKmMark = 1_000
        lastKmMarkSeconds = 0
        activeEnergyKcal = 0
        distanceMeters = 0
        elapsedSeconds = 0
        currentSpeed = 0
        routePointCount = 0
        lastError = nil
        saveState = .idle
        savedDuration = nil
        savedDistanceMeters = nil
        reps = []
        guided = nil
        cue = nil
        readiedStep = nil
        saidPlanDone = false
    }

    /// Connects a new or recovered session: its live builder, a route builder and GPS.
    @discardableResult
    private func attach(_ session: HKWorkoutSession) -> HKLiveWorkoutBuilder {
        let builder = session.associatedWorkoutBuilder()
        let dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: session.workoutConfiguration)
        dataSource.enableCollection(for: HKQuantityType(.stepCount), predicate: nil)
        builder.dataSource = dataSource
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
                self.resetLiveState()
                // Today's session and goal, saved when the run started.
                let context = RunContext.load()
                self.plannedWorkout = context?.plannedWorkout
                self.zones = context?.zones
                self.goalName = context?.goalName ?? ""
                self.guided = context?.plannedWorkout.flatMap { w in
                    context?.zones.map { GuidedRun(workout: w, zones: $0) }
                }
                self.isRecovering = self.guided != nil
                self.startTicking()
                self.attach(session)
                // Show the recovered run on the iPhone again.
                session.startMirroringToCompanionDevice { _, _ in }
                self.isPaused = session.state == .paused
                self.isRunning = true
            }
        }
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }

    // MARK: Step guidance

    /// Once a second, while the run is going: steps that run on the clock end on
    /// time. HealthKit only delivers data when it has some, which isn't often
    /// enough for a 20 s stride.
    private func startTicking() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard isRunning else { ticker?.invalidate(); ticker = nil; return }
        elapsedSeconds = elapsedTime(at: .now)
        advanceSteps(at: Date())
        checkPlanDone()
    }

    /// Ends the step that's over, taps the wrist and says what's next. Runs both on
    /// every tick and whenever new data arrives, so a stride ends on its 20th second
    /// and a rep ends on its last metre.
    private func advanceSteps(at date: Date) {
        guard var run = guided, !isPaused, !isAutoPaused else { return }
        if isRecovering, distanceMeters > 0 {
            // Relaunched mid-run: pick up at the step the distance says, rather than
            // starting the session again from the warm-up.
            isRecovering = false
            run.seek(distance: distanceMeters, elapsed: elapsedSeconds)
        }
        let entered = run.update(distance: distanceMeters, elapsed: elapsedSeconds,
                                 date: date, heartRate: heartRate)
        guided = run
        if entered.isEmpty {
            readyNextRep()
        } else {
            for step in entered { announce(step) }
        }
    }

    /// Today's distance reached: one tap and a note, nothing more. It waits for the
    /// session's last step, so it can't cut in between strides.
    private func checkPlanDone() {
        guard !saidPlanDone, isRunning, let planned = plannedWorkout, planned.distanceMeters > 0,
              distanceMeters >= planned.distanceMeters else { return }
        if let guided, guided.index < guided.steps.count - 1 { return }
        saidPlanDone = true
        play(.done)
        cue = RunCue(title: "Plan done",
                     detail: "\(Format.workoutTitle(planned.type)), \(Format.distance(planned.distanceMeters))",
                     note: "", tone: .done)
    }

    /// A step began: tap the wrist and hand the screen what to say.
    private func announce(_ step: WorkoutStep) {
        guard let next = buildCue(for: step) else { return }
        play(next.tone)
        cue = next
        #if DEBUG
        if DemoMode.isOn {
            print("[step] at \(Int(distanceMeters)) m, \(Int(elapsedSeconds)) s, \(next.tone.haptic.times)× \(next.tone.haptic.type.rawValue): \(next.note) | \(next.title) | \(next.detail)")
        }
        #endif
    }

    private func play(_ tone: RunCue.Tone) {
        let (type, times) = tone.haptic
        WKInterfaceDevice.current().play(type)
        guard times > 1 else { return }
        // A second tap, far enough behind the first to be felt as two.
        for i in 1..<times {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45 * Double(i)) {
                WKInterfaceDevice.current().play(type)
            }
        }
    }

    /// What the screen says when `step` begins, or `nil` for a step that starts
    /// without a word (the cool-down right after an "all done" card).
    private func buildCue(for step: WorkoutStep) -> RunCue? {
        let steps = guided?.steps ?? []
        let done = step.repNumber.map { $0 - 1 } ?? 0
        switch step.kind {
        case .stride:
            // The first one says what to do, briefly: the page behind has the
            // countdown but no verb. After that no card at all, so nothing covers
            // the seconds and the pace.
            return RunCue(title: strideTitle(step), detail: "\(Int(step.seconds ?? 20)) s quick and light",
                          note: "Go", tone: .go, screenSeconds: step.repNumber == 1 ? 1.5 : nil)
        case .recovery where step.seconds != nil && step.repNumber == 1:
            // The strides begin, but the first thing to do is keep running easy, so
            // that's the big line: "Strides now" over "easy for a minute" read as a
            // contradiction. The two taps say the strides have begun.
            return RunCue(title: "Easy \(Int(step.seconds ?? 60)) s",
                          detail: "Then \(step.repTotal ?? 6) × \(Int(WorkoutSteps.strideSeconds)) s quick and light",
                          note: "Strides next", tone: .strides, screenSeconds: 3)
        case .recovery where step.seconds != nil:
            // The stride just ended: felt, not read. The page counts the easy
            // minute down from here.
            return RunCue(title: "Easy \(Int(step.seconds ?? 60)) s", detail: "Next: \(strideTitle(step))",
                          note: "\(done) of \(step.repTotal ?? 6) strides done", tone: .easy, screenSeconds: nil)
        case .cooldown where strideTotal != nil:
            // The last stride is done; what's left of the run is easy.
            return RunCue(title: "All \(strideTotal ?? 6) strides done", detail: "Easy to the end",
                          note: "Well run", tone: .done)
        case .work:
            return RunCue(title: repTitle(step), detail: stepDetail(step), note: "Go", tone: .go)
        case .recovery where isLastRecovery(step, in: steps):
            // After the last rep: straight to the cool-down, counting its easy part in.
            let cooldown = steps.last { $0.kind == .cooldown }?.distanceMeters ?? 0
            return RunCue(title: cooldown > 0 ? "Cool-down" : "Easy to the end",
                          detail: "\(Format.distanceCompact(step.distanceMeters + cooldown)) easy",
                          note: "All \(step.repTotal ?? 1) done. Well run.", tone: .done)
        case .recovery:
            let count = step.repNumber.flatMap { n in step.repTotal.map { "\(n) of \($0) done" } } ?? "Done"
            return RunCue(title: "Easy now", detail: stepDetail(step), note: count, tone: .easy)
        case .cooldown:
            // Already said after the last rep's easy part.
            if step.index > 0, isLastRecovery(steps[step.index - 1], in: steps) { return nil }
            let reps = steps.last { $0.kind == .work }?.repTotal ?? 1
            return RunCue(title: "Cool-down", detail: stepDetail(step),
                          note: reps > 1 ? "All \(reps) done. Well run." : "Done. Well run.", tone: .done)
        case .warmup, .steady:
            return RunCue(title: step.label.isEmpty ? "Run" : step.label, detail: stepDetail(step),
                          note: "", tone: .info)
        }
    }

    /// Just before a rep: "Rep 3 of 6 in 70 m", so it doesn't come as a surprise.
    /// Strides need no warning: the easy minute before each counts itself down.
    private func readyNextRep() {
        guard let guided, guided.step.kind != .work, guided.step.seconds == nil,
              let rep = guided.nextStep, rep.kind == .work, readiedStep != rep.index,
              let left = guided.remainingMeters(distance: distanceMeters) else { return }
        guard left <= min(100, guided.step.distanceMeters / 2) else { return }
        readiedStep = rep.index
        // Rounded to 10 m: "in 70 m", not "in 74 m".
        let meters = max(10, Int((left / 10).rounded()) * 10)
        // Between reps the page is already counting the metres down, so the tap is
        // enough: a card over it would hide the number it's announcing.
        let covers = guided.step.kind != .recovery || (guided.step.repTotal ?? 1) <= 1
        let next = RunCue(title: "\(repTitle(rep)) in \(meters) m", detail: stepDetail(rep),
                          note: "Get ready", tone: .ready, screenSeconds: covers ? 5 : nil)
        play(next.tone)
        cue = next
        #if DEBUG
        if DemoMode.isOn { print("[step] at \(Int(distanceMeters)) m, \(Int(elapsedSeconds)) s, 1× notification: Get ready | \(next.title) | \(next.detail)") }
        #endif
    }

    /// How many strides the session has, when it has any.
    private var strideTotal: Int? {
        guided?.steps.first { $0.kind == .stride }?.repTotal
    }

    /// The easy part after the last rep, when nothing but easy running follows.
    private func isLastRecovery(_ step: WorkoutStep, in steps: [WorkoutStep]) -> Bool {
        step.kind == .recovery && step.repNumber == step.repTotal
            && !steps.dropFirst(step.index + 1).contains { $0.kind == .work }
    }

    /// "Rep 3 of 6", or the block's name ("Threshold").
    private func repTitle(_ step: WorkoutStep) -> String {
        guard let n = step.repNumber, let total = step.repTotal, total > 1 else { return step.label }
        return "Rep \(n) of \(total)"
    }

    /// "Stride 3 of 6", for the stride itself or the easy minute before it.
    private func strideTitle(_ step: WorkoutStep) -> String {
        "Stride \(step.repNumber ?? 1) of \(step.repTotal ?? WorkoutSteps.strideCount)"
    }

    /// "1 km at 4:15/km", "400 m easy".
    private func stepDetail(_ step: WorkoutStep) -> String {
        if step.kind == .cooldown, step.distanceMeters < 1 { return "easy to the end" }
        let distance = Format.distanceCompact(step.distanceMeters)
        if step.kind == .recovery || step.kind == .cooldown || step.paceType == .easy { return "\(distance) easy" }
        return "\(distance) at \(step.targetPaceSecPerKm.map(Format.pace) ?? "race effort")"
    }

    /// Sends the current numbers to the iPhone, at most about once a second.
    private func sendToPhone(force: Bool = false) {
        guard isRunning, let session, force || Date().timeIntervalSince(lastMirrorSent) >= 1 else { return }
        lastMirrorSent = Date()
        let step = activeStep
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
            averagePaceSecPerKm: averagePaceSecPerKm,
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
        ticker?.invalidate()
        ticker = nil
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
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    /// Saves the finished workout and attaches the recorded route to it. HealthKit
    /// leaves paused intervals out of the saved workout's duration by itself.
    private func saveWorkout(endingAt date: Date) async {
        guard let builder else { return }
        let routeBuilder = self.routeBuilder
        self.routeBuilder = nil   // no more GPS points go in once the run is over
        saveState = .saving
        RunContext.clear()
        defer {
            session = nil
            self.builder = nil
        }
        do {
            try await saveReps(to: builder, endingAt: date)
            // The climb, as Apple Health's own elevation gain for the run.
            if elevationGainMeters > 0 {
                try await builder.addMetadata([HKMetadataKeyElevationAscended: HKQuantity(unit: .meter(), doubleValue: elevationGainMeters)])
            }
            try await builder.endCollection(at: date)
            guard let workout = try await builder.finishWorkout() else {
                saveState = .failed
                return
            }
            savedDuration = workout.duration
            savedDistanceMeters = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?
                .sumQuantity()?.doubleValue(for: .meter())
            saveState = .saved
            // The workout is in Health now; a missing route doesn't undo that.
            _ = try? await routeBuilder?.finishRoute(with: workout, metadata: nil)
        } catch {
            lastError = error.localizedDescription
            saveState = .failed
        }
    }
}

extension WorkoutManager {
    /// The reps go into Health twice: as Apple's workout segments, which the Fitness
    /// app shows, and as one metadata entry endurancr reads back with their targets.
    fileprivate func saveReps(to builder: HKWorkoutBuilder, endingAt date: Date) async throws {
        guided?.finish(distance: distanceMeters, elapsed: elapsedSeconds, date: date)
        reps = guided?.reps ?? []
        guided = nil
        ticker?.invalidate()
        ticker = nil
        guard let json = RepReport.encode(reps) else { return }
        try await builder.addMetadata([RepReport.metadataKey: json])
        let segments = reps.map { rep in
            HKWorkoutEvent(type: .segment, dateInterval: DateInterval(start: rep.start, end: max(rep.end, rep.start)),
                           metadata: ["EndurancrRep": rep.label])
        }
        try await builder.addWorkoutEvents(segments)
    }
}

/// Today's session and goal for a run in progress, kept on disk so a run
/// recovered after a crash still shows (and mirrors) its targets.
private struct RunContext: Codable {
    var plannedWorkout: PlannedWorkout?
    var zones: PaceZones?
    var goalName: String

    private static let key = "activeRunContext"

    func save() { UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: Self.key) }

    static func load() -> RunContext? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(RunContext.self, from: $0) }
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

/// One statistic the live builder collected, read where HealthKit delivered it.
private enum LiveMetric: Sendable {
    case heartRate(Double, average: Double?), energy(Double), distance(Double), speed(Double), steps(Double)

    init?(_ statistics: HKStatistics?) {
        guard let statistics else { return nil }
        switch statistics.quantityType {
        case HKQuantityType(.heartRate):
            let unit = HKUnit.count().unitDivided(by: .minute())
            guard let bpm = statistics.mostRecentQuantity()?.doubleValue(for: unit) else { return nil }
            self = .heartRate(bpm, average: statistics.averageQuantity()?.doubleValue(for: unit))
        case HKQuantityType(.stepCount):
            guard let steps = statistics.sumQuantity()?.doubleValue(for: .count()) else { return nil }
            self = .steps(steps)
        case HKQuantityType(.activeEnergyBurned):
            guard let kcal = statistics.sumQuantity()?.doubleValue(for: .kilocalorie()) else { return nil }
            self = .energy(kcal)
        case HKQuantityType(.distanceWalkingRunning):
            guard let meters = statistics.sumQuantity()?.doubleValue(for: .meter()) else { return nil }
            self = .distance(meters)
        case HKQuantityType(.runningSpeed):
            guard let speed = statistics.mostRecentQuantity()?.doubleValue(for: .meter().unitDivided(by: .second())) else { return nil }
            self = .speed(speed)
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
                isAutoPaused = false
                sendToPhone(force: true)
            case .paused:
                isPaused = true
                sendToPhone(force: true)
            case .ended:
                // Finished here, or with Finish on the iPhone's Live Activity.
                didFinish = true
                isRunning = false
                isAutoPaused = false
                ticker?.invalidate()
                ticker = nil
                locationManager.stopUpdatingLocation()
                Task { await self.saveWorkout(endingAt: date) }
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Self.onMain { [weak self] in
            guard let self else { return }
            lastError = message
            // HealthKit stopped the session (e.g. no Health access): end the run
            // instead of leaving an empty run screen up.
            if isRunning, session?.state != .running, session?.state != .paused {
                isRunning = false
                locationManager.stopUpdatingLocation()
                RunContext.clear()
                session = nil
                builder = nil
            }
        }
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
            // Paused (by hand or by Auto-Pause): the route waits too.
            guard !filtered.isEmpty, !isPaused, !isAutoPaused, let routeBuilder else { return }
            routeBuilder.insertRouteData(filtered) { [weak self] _, error in
                let message = error?.localizedDescription
                Self.onMain { if let message { self?.lastError = message } }
            }
            routePointCount += filtered.count
            // Climb: rises of more than 1 m, so GPS noise on the flat doesn't add up.
            for location in filtered where location.verticalAccuracy >= 0 && location.verticalAccuracy <= 10 {
                guard let last = lastAltitude else { lastAltitude = location.altitude; continue }
                let rise = location.altitude - last
                if rise > 1 { elevationGainMeters += rise; lastAltitude = location.altitude }
                else if rise < -1 { lastAltitude = location.altitude }
            }
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
                case .heartRate(let bpm, let average):
                    heartRate = bpm
                    if let average { averageHeartRate = average }
                case .steps(let steps):
                    stepWindow.append((elapsed, steps))
                    stepWindow.removeAll { elapsed - $0.seconds > 30 }
                    if let first = stepWindow.first, elapsed - first.seconds >= 10 {
                        cadence = (steps - first.steps) / (elapsed - first.seconds) * 60
                    }
                case .energy(let kcal): activeEnergyKcal = kcal
                case .distance(let meters): distanceMeters = meters
                case .speed(let speed): currentSpeed = speed
                }
            }
            elapsedSeconds = elapsed
            // Each full kilometre: the time it took.
            while distanceMeters >= nextKmMark {
                lastKmSeconds = elapsed - lastKmMarkSeconds
                lastKmMarkSeconds = elapsed
                nextKmMark += 1_000
            }
            advanceSteps(at: Date())
            checkPlanDone()
            sendToPhone()
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
