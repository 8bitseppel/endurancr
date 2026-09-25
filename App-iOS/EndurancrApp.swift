import SwiftUI
import SwiftData

@main
struct EndurancrApp: App {
    @State private var health = HealthKitService()
    let container: ModelContainer

    init() {
        container = StoredPlan.makeContainer()
        DemoMode.seed(container)
        PlanSync.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(health)
                .modelContainer(container)
        }
    }
}
