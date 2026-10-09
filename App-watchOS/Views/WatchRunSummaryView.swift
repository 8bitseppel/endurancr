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

/// Two vertical pages, like the run screen: the run itself first (saved, distance,
/// time, pace), then the week and Done a Crown turn or swipe below.
struct WatchRunSummaryView: View {
    let summary: WatchRunSummary
    @Environment(\.dismiss) private var dismiss
    @State private var page = Page.run
    enum Page { case run, week }

    var body: some View {
        CrownPages(selection: $page, first: .run, second: .week) {
            runPage
        } secondPage: {
            weekPage
        }
        .navigationTitle("Run complete")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { WKInterfaceDevice.current().play(.success) }
    }

    /// Page 1: what the run did. It fits without scrolling at the usual text sizes;
    /// only the largest accessibility sizes fall back to a scroll.
    private var runPage: some View {
        ViewThatFits(in: .vertical) {
            runStats
            ScrollView { runStats }
        }
    }

    private var runStats: some View {
        VStack(spacing: 10) {
            saveStatus

            VStack(spacing: 0) {
                Text(Format.distance(summary.distanceMeters))
                    .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.tint)
                Text("DISTANCE")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                stat("TIME", Format.duration(summary.durationSeconds))
                Spacer(minLength: 8)
                stat("PACE", Format.pace(summary.averagePaceSecPerKm), tint: .green)
            }
        }
        // Numbers shrink a little before the page has to scroll.
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal, 4)
    }

    /// Page 2: what's left this week, and Done.
    private var weekPage: some View {
        VStack(spacing: 10) {
            if summary.hasWeek {
                weeklyProgress
            }
            Button { dismiss() } label: {
                Text("Done")
                    .fontWeight(.semibold)
                    .foregroundStyle(WatchTodayView.plumInk)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.accentColor)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
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
                .tint(.accentColor)
            Text("\(Format.distance(summary.weekCompletedMeters)) of \(Format.distance(summary.weekTargetMeters))")
                .font(.caption).monospacedDigit()
                .foregroundStyle(.secondary)
            Text(summary.weekRemainingMeters > 0
                 ? "\(Format.distance(summary.weekRemainingMeters)) to go"
                 : "Target met. Nice work.")
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label.capitalized) \(value)")
    }
}
