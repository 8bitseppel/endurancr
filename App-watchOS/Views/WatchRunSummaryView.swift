import SwiftUI
import TrainingCore
import WatchKit

/// What a just-finished run did, shown on the watch after Finish. Mirrors the
/// iPhone's post-run summary within the watch's glance model: a save confirmation,
/// the run's headline stats, and where the run leaves the athlete for the week
/// ("5.0 km of week 6, target 42 km"). The weekly numbers are computed on-watch
/// from the synced plan plus HealthKit, so the watch needs nothing extra pushed
/// from the phone.
struct WatchRunSummary: Identifiable {
    let id = UUID()
    var distanceMeters: Double
    var durationSeconds: Double
    /// Whether the workout finished saving to HealthKit without a recorded error.
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

    var hasWeek: Bool { weekTargetMeters > 0 }
}

struct WatchRunSummaryView: View {
    let summary: WatchRunSummary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                saveStatus

                VStack(spacing: 0) {
                    Text(Format.distance(summary.distanceMeters))
                        .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.cyan)
                    Text("DISTANCE")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                HStack(alignment: .firstTextBaseline) {
                    stat("TIME", Format.duration(summary.durationSeconds))
                    Spacer(minLength: 8)
                    stat("PACE", Format.pace(summary.averagePaceSecPerKm), tint: .green)
                }

                if summary.hasWeek {
                    weeklyProgress
                }

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
        }
        .navigationTitle("Run complete")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { WKInterfaceDevice.current().play(.success) }
    }

    private var saveStatus: some View {
        Label(summary.saved ? "Saved to Health" : "Not saved to Health",
              systemImage: summary.saved ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(summary.saved ? .green : .orange)
    }

    private var weeklyProgress: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(summary.weekNumber.map { "Week \($0)" } ?? "This week")
                .font(.headline)
            ProgressView(value: summary.weekFraction)
                .tint(.orange)
            Text("\(Format.distance(summary.weekCompletedMeters)) of \(Format.distance(summary.weekTargetMeters))")
                .font(.caption).monospacedDigit()
                .foregroundStyle(.secondary)
            Text(summary.weekRemainingMeters > 0
                 ? "\(Format.distance(summary.weekRemainingMeters)) to go"
                 : "Target met - nice work")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private func stat(_ label: String, _ value: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }
}
