import SwiftUI
import TrainingCore

/// "Another session": what can be started today instead of today's run (this week's
/// hard session moved to today, an interval session of the plan's size, strides), and
/// why intervals aren't offered when they aren't. The home screen's second page, a
/// turn of the Crown below today's run, so the home screen stays one run and one Start.
struct OtherSessionView: View {
    /// `nil` without a goal: then only the indoor run is offered.
    let plan: TrainingPlan?
    /// Today's planned run, which the indoor run follows when there is one.
    let today: PlannedWorkout?
    let onStart: (SessionOffers.Offer) -> Void
    /// Today's run, or a free run, on a treadmill: no GPS.
    let onIndoor: () -> Void
    @Environment(HealthKitService.self) private var health
    @State private var offers: SessionOffers?

    var body: some View {
        List {
            Text("Another session")
                .font(.headline)
                .foregroundStyle(.tint)
                .listRowBackground(Color.clear)
                .accessibilityAddTraits(.isHeader)
            // First, since it's the same run in another place rather than another
            // run, and it needs no plan at all.
            Button(action: onIndoor) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Indoor run", systemImage: "figure.run.treadmill")
                        .font(.headline)
                    Text(today.map { "Today's \(Format.workoutTitle($0.type).lowercased()) on a treadmill, no GPS" }
                         ?? "A free run on a treadmill, no GPS")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            if plan == nil {
                EmptyView()
            } else if let offers {
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

        .task { if let plan { offers = await load(plan) } }
    }

    /// The same rules as on the iPhone, from this watch's own Health data: recent
    /// runs (with their reps), easing back after a break, and resting heart rate.
    private func load(_ plan: TrainingPlan) async -> SessionOffers {
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
