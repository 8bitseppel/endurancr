import SwiftUI
import TrainingCore

/// "Another session": what can be started today instead of today's run (this week's
/// hard session moved to today, an interval session of the plan's size, strides), and
/// why intervals aren't offered when they aren't. Opened from the More button on the
/// home screen, so the home screen stays one run and one Start.
struct OtherSessionView: View {
    let plan: TrainingPlan
    let onStart: (SessionOffers.Offer) -> Void
    @Environment(HealthKitService.self) private var health
    @State private var offers: SessionOffers?

    var body: some View {
        List {
            if let offers {
                ForEach(offers.offers) { offer in
                    Button { onStart(offer) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(offer.title).font(.headline)
                            Text(offer.detail)
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                if let reason = offers.reason {
                    // Readable text, not a disabled row: VoiceOver and AssistiveTouch
                    // reach it, and it says why.
                    Label(reason, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                } else if offers.offers.isEmpty {
                    Text("Today's run is the session: start it from the home screen.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Another session")
        .task { offers = await load() }
    }

    /// The same rules as on the iPhone, from this watch's own Health data: recent
    /// runs (with their reps), easing back after a break, and resting heart rate.
    private func load() async -> SessionOffers {
        #if DEBUG
        if DemoMode.isOn, let demo = DemoMode.sessionOffers { return demo }
        #endif
        let since = Calendar.current.date(byAdding: .day, value: -35, to: .now)!
        let runs = await health.fetchRuns(since: since)
        let resting = await health.fetchRestingHeartRates(since: since)
        let fatigued = FatigueAnalyzer().assess(restingHeartRates: resting, completedRuns: runs, asOf: .now).isFatigued
        let easing = TrainingBuddy().status(plan: plan, completedRuns: runs, asOf: .now).isEasingBack
        return SessionOffers.make(plan: plan, runs: runs, isEasingBack: easing, isFatigued: fatigued, asOf: .now)
    }
}
