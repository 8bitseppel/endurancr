import SwiftUI
import SwiftData
import ActivityKit

@main
struct EndurancrApp: App {
    @State private var health = HealthKitService()
    let container: ModelContainer

    init() {
        container = StoredPlan.makeContainer()
        DemoMode.seed(container)
        PlanSync.shared.activate()
        MirroredRunManager.shared.listen()
        // A run can't survive the app being closed, so any Live Activity still
        // showing is left over from one and its buttons would do nothing.
        let leftovers = Activity<RunActivityAttributes>.activities.map(\.id)
        Task {
            for activity in Activity<RunActivityAttributes>.activities where leftovers.contains(activity.id) {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(health)
                .modelContainer(container)
        }
    }
}
