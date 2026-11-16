import SwiftUI
import TrainingCore

/// Says so when endurancr can't see all of the athlete's runs in Apple Health,
/// because Health never does: a run it won't hand over looks exactly like a run that
/// didn't happen, and the plan would mark the day missed without a word.
///
/// Two cases. Since iOS 27 Health can allow only the recent history, from a date
/// on (`HealthKitService.readableFrom`), and the plan started before it. Or no run
/// at all has come back since the plan started while run days have passed, which
/// is what Health looks like when reading workouts isn't allowed.
struct HealthAccessNote: View {
    let coordinator: PlanCoordinator
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let message {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text(message).font(.subheadline)
                } icon: {
                    Image(systemName: "heart.text.square").foregroundStyle(.tint)
                }
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Label("Open Settings", systemImage: "gear")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glass)
            }
            .brandCard()
        }
    }

    private var message: String? {
        guard let plan = coordinator.displayPlan else { return nil }
        let cal = Calendar.current
        let start = plan.trainingStart(calendar: cal) ?? cal.startOfDay(for: .now)
        let path = "Settings > Apps > Health > Data Access & Devices > endurancr"
        if let from = coordinator.health.readableFrom, from > start {
            return "Apple Health lets endurancr read your runs only from \(from.formatted(.dateTime.day().month(.wide))) on, so runs before that can't count in your plan. To allow your whole history: \(path)."
        }
        let missed = coordinator.review?.days.values.contains { $0.status == .missed } ?? false
        if coordinator.hasReadRuns, coordinator.recentRuns.isEmpty, missed {
            return "endurancr can't see any runs in Apple Health since your plan started. If you've been running, check that endurancr may read Workouts: \(path)."
        }
        return nil
    }
}
