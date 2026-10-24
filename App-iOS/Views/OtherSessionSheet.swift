import SwiftUI
import TrainingCore

/// "Another session" on iPhone: what can be started today instead of today's run, and
/// why intervals aren't offered when they aren't (`SessionOffers`).
struct OtherSessionSheet: View {
    let offers: SessionOffers
    let onStart: (SessionOffers.Offer) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(offers.offers) { offer in
                        Button { onStart(offer) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: offer.workout.type.symbol)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(offer.workout.type.tint.gradient, in: .circle)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(offer.title).font(Brand.rounded(.headline))
                                    Text(offer.detail)
                                        .font(.subheadline).foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "play.fill").foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                            }
                            .brandCard(tint: offer.workout.type.tint)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Starts this run now")
                    }
                    if let reason = offers.reason {
                        Label(reason, systemImage: "info.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                    if offers.offers.contains(where: { $0.movesFrom != nil }) {
                        Text("Starting this week's session moves it to today, and today's run to its day, so nothing is done twice.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                    Text("Only sessions that fit your current fitness and this week: at most two hard sessions a week, never two hard days side by side, and intervals within Jack Tupper Daniels' limits.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding(20)
            }
            .background { BrandBackground() }
            .navigationTitle("Another session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
