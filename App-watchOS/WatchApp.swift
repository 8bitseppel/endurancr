import SwiftUI
import SwiftData

@main
struct EndurancrWatchApp: App {
    @State private var health = HealthKitService()
    let container: ModelContainer

    init() {
        container = StoredPlan.makeContainer()
        PlanSync.shared.container = container
        PlanSync.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchTodayView()
                .environment(health)
                .modelContainer(container)
                .task { await health.requestAuthorization() }
        }
    }
}
