import SwiftUI
import SwiftData
import TrainingCore

/// Top-level container: requests HealthKit access, then shows the tabbed
/// experience. The dashboard is always the front page — with no plan yet it
/// presents a friendly "Set your goal" empty state rather than gating the whole
/// app behind onboarding.
struct RootView: View {
    @Environment(HealthKitService.self) private var health
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var coordinator: PlanCoordinator?
    // Tracks a genuine trip to the background so we only re-adapt when the app is
    // truly reopened — not on the .inactive blips from sheets or Control Center.
    @State private var wasBackgrounded = false

    var body: some View {
        Group {
            if let coordinator {
                // Before a goal exists, the coach card carries the "Set your goal"
                // empty state on its own. Once a goal is set, surface the tab bar
                // (coach card as the landing tab) so the analytical views are one
                // tap away at the bottom.
                if coordinator.inputs != nil {
                    MainTabView(coordinator: coordinator)
                } else {
                    CoachView(coordinator: coordinator)
                }
            } else {
                ProgressView("Loading…")
            }
        }
        .task {
            if coordinator == nil {
                coordinator = PlanCoordinator(context: context, health: health)
            }
            await health.requestAuthorization()
            await coordinator?.refreshAdaptation()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                wasBackgrounded = true
            case .active where wasBackgrounded:
                // Reopened after a real background trip: pull in any runs recorded
                // meanwhile and re-adapt the plan (paces, fatigue, missed sessions).
                wasBackgrounded = false
                Task { await coordinator?.refreshAdaptation() }
            default:
                break
            }
        }
    }
}

struct MainTabView: View {
    let coordinator: PlanCoordinator

    var body: some View {
        TabView {
            TodayView(coordinator: coordinator)
                .tabItem { Label("Today", systemImage: "figure.run") }
            ProgressDashboardView(coordinator: coordinator)
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
            CalendarView(coordinator: coordinator)
                .tabItem { Label("Plan", systemImage: "calendar") }
            HowItWorksView()
                .tabItem { Label("How it works", systemImage: "book") }
        }
    }
}
