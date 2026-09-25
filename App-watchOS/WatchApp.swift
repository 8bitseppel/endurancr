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
        workout.distanceMeters = 6_420
        workout.elapsedSeconds = 37 * 60 + 14
        workout.heartRate = 142
        workout.routePointCount = 412
        workout.isRunning = true
        return workout
    }
}

private extension WatchRunSummary {
    static var demo: WatchRunSummary {
        WatchRunSummary(distanceMeters: 10_040, durationSeconds: 58 * 60 + 12, saved: true,
                        weekNumber: 7, weekCompletedMeters: 24_600, weekTargetMeters: 38_100)
    }
}
#endif
