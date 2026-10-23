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
        workout.distanceMeters = ((planned?.distanceMeters ?? 9_600) * 0.66 / 10).rounded() * 10
        workout.elapsedSeconds = (workout.distanceMeters / 1_000 * pace).rounded()
        workout.heartRate = 142
        workout.routePointCount = 412
        workout.isRunning = true
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
    /// `-demoStrides YES` runs a 3.5 km easy run with strides instead.
    private let planned = UserDefaults.standard.bool(forKey: "demoStrides")
        ? PlannedWorkout(date: .now, type: .easy, distanceMeters: 3_500, notes: VDOTPlanGenerator.stridesNote)
        : PlannedWorkout(
            date: .now, type: .interval, distanceMeters: 5_600,
            structure: WorkoutStructure(warmupMeters: 1_000, reps: 6, workMeters: 400, recoveryMeters: 200,
                                        cooldownMeters: 1_000, workType: .interval, recoveryType: .easy)
        )

    var body: some View {
        NavigationStack {
            LiveRunView(workout: workout, plannedWorkout: planned, zones: zones)
        }
        .task {
            workout.isRunning = true
            workout.heartRate = 150
            while workout.distanceMeters < planned.distanceMeters {
                try? await Task.sleep(for: .milliseconds(100))
                let step = WorkoutSteps.activeStep(for: planned, zones: zones, distanceCovered: workout.distanceMeters)
                workout.distanceMeters += 4
                workout.elapsedSeconds += 4 * (step?.targetPaceSecPerKm ?? 330) / 1_000
            }
            print("[sim] finished at \(Int(workout.distanceMeters)) m")
        }
    }
}

private extension WatchRunSummary {
    static var demo: WatchRunSummary {
        let run = DemoMode.finishedRun
        return WatchRunSummary(distanceMeters: run.meters, durationSeconds: run.seconds, saved: true,
                               weekNumber: run.week, weekCompletedMeters: run.weekDone,
                               weekTargetMeters: run.weekTarget)
    }
}
#endif
