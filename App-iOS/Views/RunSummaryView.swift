import SwiftUI
import TrainingCore

/// What a just-finished run did, shown as a sheet after Finish. Confirms the run
/// was saved and, crucially, where it leaves the athlete for the week: "5.0 km of
/// week 6 done", with what remains. The weekly numbers come from the plan's
/// progress after adaptation, so a short run's shortfall has already been
/// redistributed onto the week's remaining easy runs.
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
            List {
                Section {
                    stat("Distance", Format.distance(data.distanceMeters), tint: .accentColor)
                    stat("Time", Format.duration(data.durationSeconds))
                    stat("Average pace", Format.pace(data.averagePaceSecPerKm), tint: .green)
                } header: {
                    Label(data.saved ? "Saved to Health" : "Could not save to Health",
                          systemImage: data.saved ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(data.saved ? .green : .orange)
                        .font(.subheadline.weight(.semibold))
                        .textCase(nil)
                }

                if data.weekTargetMeters > 0 {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(weekLine)
                                .font(.headline)
                            ProgressView(value: data.weekFraction)
                                .tint(.accentColor)
                            Text(data.weekRemainingMeters > 0
                                 ? "\(Format.distance(data.weekRemainingMeters)) still to go this week"
                                 : "Week's target met. Nice work.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } footer: {
                        Text("A short run spreads onto this week's remaining easy runs; your long run and quality sessions keep their distance.")
                    }
                }
            }
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
        let done = Format.distance(data.weekCompletedMeters)
        let target = Format.distance(data.weekTargetMeters)
        if let n = data.weekNumber {
            return "\(done) of week \(n) done (target \(target))"
        }
        return "\(done) of \(target) done this week"
    }

    private func stat(_ label: String, _ value: String, tint: Color = .primary) -> some View {
        LabeledContent(label) {
            Text(value).font(.title3).monospacedDigit().foregroundStyle(tint)
        }
    }
}
