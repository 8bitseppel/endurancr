import SwiftUI
import SwiftData
import TrainingCore

@main
struct EndurancrWatchApp: App {
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
        default:
            WatchTodayView()
        }
        #else
        WatchTodayView()
        #endif
    }
}

#if DEBUG
private extension WorkoutManager {
    /// A run in progress for Simulator screenshots (see `DemoMode`).
    static var demo: WorkoutManager {
        let workout = WorkoutManager()
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

private extension WatchRunSummary {
    static var demo: WatchRunSummary {
        let run = DemoMode.finishedRun
        return WatchRunSummary(distanceMeters: run.meters, durationSeconds: run.seconds, saved: true,
                               weekNumber: run.week, weekCompletedMeters: run.weekDone,
                               weekTargetMeters: run.weekTarget)
    }
}
#endif
