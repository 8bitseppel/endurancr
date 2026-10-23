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
    /// The reps of an interval session, as they were run.
    var reps: [RepSplit] = []

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
    @State private var page: Page = {
        #if DEBUG
        // `-demoRepsPage YES`: open on the reps, for screenshots.
        if DemoMode.isOn, UserDefaults.standard.bool(forKey: "demoRepsPage") { return .reps }
        #endif
        return .run
    }()
    enum Page { case run, reps, week }

    var body: some View {
        TabView(selection: $page) {
            runPage.tag(Page.run)
            if !summary.reps.isEmpty {
                ScrollView { repsPage }.tag(Page.reps)
            }
            weekPage.tag(Page.week)
        }
        .tabViewStyle(.verticalPage)
        .demoTurnPage($page, to: .week)
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

    /// Page 2 after an interval session: every rep's pace against its target.
    private var repsPage: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("REPS").font(.caption2).foregroundStyle(.secondary)
            ForEach(Array(summary.reps.enumerated()), id: \.offset) { _, rep in
                HStack {
                    Text(rep.total > 1 ? "\(rep.number)" : rep.label)
                        .font(.footnote.weight(.semibold))
                    Spacer()
                    Text(rep.paceSecPerKm.map(Format.pace) ?? "--")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Self.tint(rep.verdict))
                }
                .accessibilityElement(children: .combine)
            }
            if let text = RepReport.summary(summary.reps) {
                Text(text)
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 4)
    }

    /// Green on pace, orange slower, blue faster, as on the iPhone.
    static func tint(_ verdict: RepSplit.Verdict?) -> Color {
        switch verdict {
        case .onPace?: .green
        case .slower?: .orange
        case .faster?: .blue
        case nil: .primary
        }
    }

    /// The last page: what's left this week, and Done.
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
