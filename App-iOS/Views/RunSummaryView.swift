import SwiftUI
import TrainingCore

/// What a just-finished run did, shown as a sheet after Finish. Confirms the run
/// was saved and, crucially, where it leaves the athlete for the week: "5.0 km of
/// week 6 done", with what remains. The weekly numbers come from the plan's
/// progress after adaptation. A short run's shortfall isn't made up on the days
/// after; lighter weeks shape the coming ones instead (`TrainingBuddy`).
struct RunSummaryData: Identifiable {
    let id = UUID()
    var distanceMeters: Double
    var durationSeconds: Double
    /// Whether the workout finished saving to HealthKit without error.
    var saved: Bool
    /// 1-based week number, when the run falls inside the plan.
    var weekNumber: Int?
    var weekCompletedMeters: Double
    var weekTargetMeters: Double

    var averagePaceSecPerKm: Double {
        guard distanceMeters > 0 else { return 0 }
        return durationSeconds / (distanceMeters / 1_000)
    }

    var weekRemainingMeters: Double { max(0, weekTargetMeters - weekCompletedMeters) }

    var weekFraction: Double {
        guard weekTargetMeters > 0 else { return 0 }
        return min(1, max(0, weekCompletedMeters / weekTargetMeters))
    }
}

struct RunSummaryView: View {
    let data: RunSummaryData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(data.saved ? "Saved to Health" : "Could not save to Health",
                              systemImage: data.saved ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(data.saved ? .green : .orange)
                        Text(Format.distance(data.distanceMeters))
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        HStack(spacing: 12) {
                            stat("Time", Format.duration(data.durationSeconds))
                            stat("Average pace", Format.pace(data.averagePaceSecPerKm))
                        }
                    }
                    .brandCard(tint: .green, cornerRadius: 30, padding: 22)
                    .accessibilityElement(children: .combine)

                    if data.weekTargetMeters > 0 {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(data.weekNumber.map { "Week \($0)" } ?? "This week").brandEyebrow()
                            Text(weekLine).font(Brand.rounded(.headline))
                            ProgressView(value: data.weekFraction)
                                .tint(Brand.buttonPurple)
                            Text(data.weekRemainingMeters > 0
                                 ? "\(Format.distance(data.weekRemainingMeters)) still to go this week"
                                 : "Week's target met. Nice work.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .brandCard()
                        .accessibilityElement(children: .combine)

                        Text("A shorter run isn't made up on the days after. If the weeks keep coming in lighter, the plan builds from what you ran.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background { BrandBackground() }
            .navigationTitle("Run complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var weekLine: String {
        "\(Format.distance(data.weekCompletedMeters)) of \(Format.distance(data.weekTargetMeters)) done"
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(Brand.rounded(.title3, weight: .semibold)).monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}
