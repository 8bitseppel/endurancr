import SwiftUI
import SwiftData
import TrainingCore
import WatchKit

@main
struct EndurancrWatchApp: App {
    @WKApplicationDelegateAdaptor private var appDelegate: WatchAppDelegate
    @State private var health = HealthKitService()
    let container: ModelContainer

    init() {
        container = StoredPlan.makeContainer()
        DemoMode.seed(container)
        PlanSync.shared.container = container
        PlanSync.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            root
                .environment(health)
                .modelContainer(container)
                .fontDesign(.rounded)
                .task { await health.requestAuthorization() }
        }
    }

    @ViewBuilder
    private var root: some View {
        #if DEBUG
        switch DemoMode.screen {
        case "run" where UserDefaults.standard.string(forKey: "demoRunStep") != nil:
            // An interval session mid-rep or mid-jog, with no card over the page.
            NavigationStack {
                LiveRunView(workout: .demoIntervals, plannedWorkout: WorkoutManager.demoIntervalWorkout,
                            zones: DemoMode.plan?.paceZones)
            }
        case "run" where UserDefaults.standard.bool(forKey: "demoStepCard"):
            // An interval session at the start of rep 3, for the intervals video.
            NavigationStack {
                LiveRunView(workout: .demoIntervals, plannedWorkout: WorkoutManager.demoIntervalWorkout,
                            zones: DemoMode.plan?.paceZones)
            }
        case "run":
            NavigationStack {
                LiveRunView(workout: .demo, plannedWorkout: DemoMode.todaysWorkout,
                            zones: DemoMode.plan.map { VDOTCalculator().paceZones(forVDOT: $0.vdot) })
            }
        case "summary":
            NavigationStack { WatchRunSummaryView(summary: .demo) }
        case "intervals":
            IntervalRunSimulation()
        default:
            WatchTodayView()
        }
        #else
        WatchTodayView()
        #endif
    }
}

/// watchOS relaunches the app when a run was going and the app crashed; this
/// hands the still-running workout back to the recorder.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handleActiveWorkoutRecovery() {
        WorkoutManager.shared.recoverActiveRun()
    }
}

#if DEBUG
private extension WorkoutManager {
    /// A run in progress for Simulator screenshots (see `DemoMode`).
    static var demo: WorkoutManager {
        let workout = WorkoutManager()  // not `shared`: a demo run never records
        // Two thirds into today's run, right on its target pace.
        let planned = DemoMode.todaysWorkout
        let pace = planned?.targetPaceSecPerKm.map { ($0.lowerBound + $0.upperBound) / 2 } ?? 363
        // `-demoToGo done` / `beyond`: at the planned distance, or 6 km past it.
        let share: Double = switch UserDefaults.standard.string(forKey: "demoToGo") {
        case "done": 1.01
        case "beyond": 1 + 6_000 / (planned?.distanceMeters ?? 9_600)
        default: 0.66
        }
        workout.distanceMeters = ((planned?.distanceMeters ?? 9_600) * share / 10).rounded() * 10
        workout.elapsedSeconds = (workout.distanceMeters / 1_000 * pace).rounded()
        workout.heartRate = 142
        workout.averageHeartRate = 139
        workout.elevationGainMeters = 46
        workout.cadence = 172
        workout.lastKmSeconds = (pace - 4).rounded()
        workout.demoThisKm = pace - 9
        // `-demoPace fast` / `slow`: 25 s/km faster than the easy window, or gently
        // slower than it, to show how each reads on an easy run.
        let shown: Double = switch UserDefaults.standard.string(forKey: "demoPace") {
        case "fast": (planned?.targetPaceSecPerKm?.lowerBound ?? pace) - 25
        case "slow": (planned?.targetPaceSecPerKm?.upperBound ?? pace) + 18
        default: pace
        }
        workout.setDemoSpeed(1_000 / shown)
        workout.routePointCount = 412
        workout.isRunning = true
        if let planned, let zones = DemoMode.plan?.paceZones { workout.demoGuide(planned, zones) }
        return workout
    }
}

/// `-demoScreen intervals`: an interval session run at 40 m/s from the start, to
/// check the step cards and taps in the Simulator (which has no real GPS distance).
/// 1 km warm-up, 6 × 400 m with 200 m easy, 1 km cool-down (or strides, see below).
private struct IntervalRunSimulation: View {
    @State private var workout = WorkoutManager()
    private let zones = DemoMode.plan.map { VDOTCalculator().paceZones(forVDOT: $0.vdot) }
        ?? VDOTCalculator().paceZones(forVDOT: 45)
    /// `-demoStrides YES` runs a 3.5 km easy run with strides instead, and
    /// `-demoSession threshold` / `marathon` the other guided kinds.
    private let planned: PlannedWorkout = {
        if UserDefaults.standard.bool(forKey: "demoStrides") {
            return PlannedWorkout(date: .now, type: .easy, distanceMeters: 3_500, notes: VDOTPlanGenerator.stridesNote)
        }
        switch UserDefaults.standard.string(forKey: "demoSession") {
        case "threshold":
            // 2 km warm-up, 6 km continuous at threshold, 1.5 km cool-down.
            return PlannedWorkout(
                date: .now, type: .threshold, distanceMeters: 9_500,
                structure: WorkoutStructure(warmupMeters: 2_000, reps: 1, workMeters: 6_000, recoveryMeters: 0,
                                            cooldownMeters: 1_500, workType: .threshold, recoveryType: .easy))
        case "marathon":
            // A long run that finishes at marathon pace, as peak weeks do.
            return PlannedWorkout(
                date: .now, type: .longRun, distanceMeters: 18_000,
                structure: WorkoutStructure(warmupMeters: 11_000, reps: 1, workMeters: 6_000, recoveryMeters: 0,
                                            cooldownMeters: 1_000, workType: .marathonPace, recoveryType: .easy))
        default:
            return PlannedWorkout(
                date: .now, type: .interval, distanceMeters: 5_600,
                structure: WorkoutStructure(warmupMeters: 1_000, reps: 6, workMeters: 400, recoveryMeters: 200,
                                            cooldownMeters: 1_000, workType: .interval, recoveryType: .easy))
        }
    }()

    @State private var summary: WatchRunSummary?

    /// `-demoTextSize ax`: renders at an accessibility text size, which the watch
    /// Simulator can't be set to, to check the run screen still fits one page.
    private var textSize: DynamicTypeSize? {
        UserDefaults.standard.string(forKey: "demoTextSize") == "ax" ? .accessibility3 : nil
    }

    var body: some View {
        NavigationStack {
            if let summary {
                WatchRunSummaryView(summary: summary)
            } else {
                LiveRunView(workout: workout, plannedWorkout: planned, zones: zones)
            }
        }
        .environment(\.dynamicTypeSize, textSize ?? .large)
        .task {
            // The real step engine, cues and taps: only the sensors are simulated.
            // Each tick of 100 ms is a few seconds of running, so a session plays
            // out in under a minute. Reps 1 to 4 on pace, 5 and 6 15 s/km slower.
            let strides = UserDefaults.standard.bool(forKey: "demoStrides")
            // Strides run on the clock, so the demo runs them near real time to
            // show the countdown, and skips through the easy minutes between. The
            // easy part before the block starts 200 m from its end.
            let secondsPerTick = { (step: WorkoutStep?) -> Double in
                // Fine enough that a rep ends within a few metres of its mark, as it
                // does in a real run where readings arrive about every second.
                guard strides else { return 3 }
                return step?.kind == .stride ? 0.4 : 6
            }
            workout.demoStart(plannedWorkout: planned, zones: zones)
            var elapsed = 0.0
            var distance = 0.0
            // The demo starts 200 m before the part worth watching: the strides, or
            // the block of a threshold or marathon-pace run.
            let steps = WorkoutSteps.steps(for: planned, zones: zones)
            if strides || UserDefaults.standard.string(forKey: "demoSession") != nil,
               let hard = steps.first(where: { $0.kind == .stride || $0.kind == .work || $0.seconds != nil }) {
                distance = max(0, hard.startMeters - 200)
                elapsed = distance / 1_000 * zones.easySecPerKm
            }
            while distance < planned.distanceMeters, elapsed < 36_000 {
                let step = workout.activeStep
                // Reps 5 and 6 come in slower, and stride 4 is run a touch too hard,
                // so the demo shows the pace off target as well as on it.
                var slower = step?.kind == .work && (step?.repNumber ?? 0) >= 5 ? 15.0 : 0
                if step?.kind == .stride, step?.repNumber == 4 { slower = 30 }
                let pace = (step?.targetPaceSecPerKm ?? zones.easySecPerKm) + slower
                let speed = 1_000 / pace
                let tick = secondsPerTick(step)
                distance += speed * tick
                elapsed += tick
                workout.demoAdvance(distance: distance, elapsed: elapsed, speed: speed, heartRate: 150)
                try? await Task.sleep(for: .milliseconds(100))
                // Past the last stride there's nothing left to guide: hold on the
                // "all done" card, then finish.
                if strides, workout.activeStep?.kind == .cooldown {
                    try? await Task.sleep(for: .seconds(4))
                    break
                }
            }
            workout.demoFinish()
            let reps = workout.reps
            print("[sim] finished at \(Int(workout.distanceMeters)) m, \(Int(workout.elapsedSeconds)) s")
            for rep in reps {
                print("[rep] \(rep.label) \(Int(rep.meters)) m \(Int(rep.seconds)) s \(rep.paceSecPerKm.map(Format.pace) ?? "--") \(rep.verdict.map { "\($0)" } ?? "by feel")")
            }
            print("[summary] \(RepReport.summary(reps) ?? "")")
            summary = WatchRunSummary(distanceMeters: workout.distanceMeters, durationSeconds: workout.elapsedSeconds,
                                      saved: true, weekNumber: nil, weekCompletedMeters: 0, weekTargetMeters: 0,
                                      reps: reps)
        }
    }
}

private extension WorkoutManager {
    /// 2 km warm-up, 6 × 1 km with 400 m easy, 2 km cool-down.
    static let demoIntervalWorkout = PlannedWorkout(
        date: .now, type: .interval, distanceMeters: 2_000 + 6 * 1_400 + 2_000,
        structure: WorkoutStructure(warmupMeters: 2_000, reps: 6, workMeters: 1_000, recoveryMeters: 400,
                                    cooldownMeters: 2_000, workType: .interval, recoveryType: .easy)
    )

    /// Just past the start of rep 3, on its pace. With `-demoRunStep recovery`,
    /// jogging between reps 3 and 4 instead, where the page counts the metres down.
    static var demoIntervals: WorkoutManager {
        let workout = WorkoutManager()
        let pace = DemoMode.plan?.paceZones.intervalSecPerKm ?? 300
        let jogging = UserDefaults.standard.string(forKey: "demoRunStep") == "recovery"
        workout.distanceMeters = 2_000 + 2 * 1_400 + (jogging ? 1_000 + 160 : 60)
        workout.elapsedSeconds = 2 * 360 + 2 * (pace + 0.4 * 360)
            + (jogging ? pace + 0.16 * 360 : 0.06 * pace)
        workout.heartRate = 168
        workout.averageHeartRate = 156
        workout.elevationGainMeters = 22
        workout.lastKmSeconds = (pace + 0.4 * 360).rounded()
        workout.setDemoSpeed(1_000 / (jogging ? 360 : pace - 1))
        workout.demoThisRep = jogging ? nil : pace - 2
        workout.heartRate = jogging ? 148 : 168
        workout.routePointCount = 640
        workout.isRunning = true
        if let zones = DemoMode.plan?.paceZones { workout.demoGuide(demoIntervalWorkout, zones) }
        return workout
    }
}

private extension WatchRunSummary {
    static var demo: WatchRunSummary {
        let run = DemoMode.finishedRun
        return WatchRunSummary(distanceMeters: run.meters, durationSeconds: run.seconds, saved: true,
                               weekNumber: run.week, weekCompletedMeters: run.weekDone,
                               weekTargetMeters: run.weekTarget, reps: DemoMode.reps)
    }
}
#endif
