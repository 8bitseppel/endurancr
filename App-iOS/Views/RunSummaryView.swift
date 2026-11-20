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
    /// The reps of an interval session, as they were run.
    var reps: [RepSplit] = []
    /// When the run started, for the shoes it counts for.
    var date: Date = .now

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
    /// The save as it happens: the summary opens before Health has the run, and
    /// "Saving to Health" turns into "Saved to Health" in place. `nil` uses `data.saved`.
    var saveState: PhoneWorkoutManager.SaveState? = nil
    /// The run's ID in Apple Health, once saved, so its shoes can be changed.
    var workoutID: UUID? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var shoes = ShoeStore.shared
    /// A pair chosen before the save was done, put on the run once it is.
    @State private var pendingShoe: UUID??

    /// The pair this run counts for: the one chosen here, or the default.
    private var runShoe: Shoe? {
        if let pendingShoe { return shoes.log.shoe(pendingShoe) }
        if let workoutID { return shoes.shoe(forWorkout: workoutID, date: data.date) }
        return shoes.log.shoe(shoes.log.defaultID(at: data.date))
    }

    private func pick(_ id: UUID?) {
        guard let workoutID else { pendingShoe = .some(id); return }
        let run = CompletedRun(date: data.date, distanceMeters: data.distanceMeters,
                               durationSeconds: data.durationSeconds, workoutID: workoutID)
        shoes.change { $0.assign(run, to: id) }
        pendingShoe = nil
    }

    private var saving: Bool { saveState == .saving || (saveState == .idle && !data.saved) }
    private var saved: Bool { saveState.map { $0 == .saved } ?? data.saved }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Group {
                            if saving {
                                Label {
                                    Text("Saving to Health")
                                } icon: {
                                    ProgressView().controlSize(.small)
                                }
                                .foregroundStyle(.secondary)
                            } else {
                                Label(saved ? "Saved to Health" : "Could not save to Health",
                                      systemImage: saved ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(saved ? .green : .orange)
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                        .contentTransition(.opacity)
                        .animation(.smooth, value: saving)
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

                    // Only with shoes added: then the run counts for the default pair,
                    // and here it can go to another.
                    if !shoes.log.active.isEmpty {
                        HStack {
                            ShoeMenu(title: "Shoes", selected: runShoe, onPick: pick)
                            Spacer()
                            if let pair = runShoe {
                                // This run included, also before Health has been read again.
                                let counted = workoutID.map { id in shoes.runs.contains { $0.workoutID == id } } ?? false
                                Text(Format.distance(shoes.meters(of: pair) + (counted ? 0 : data.distanceMeters)))
                                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .brandCard(cornerRadius: 22, padding: 16)
                    }

                    if !data.reps.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(RepsView.title(for: data.reps)).brandEyebrow()
                            RepsView(reps: data.reps)
                        }
                        .brandCard()
                    }

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
            .onChange(of: workoutID) { _, saved in
                // Chosen while the save was still going: put it on the run now.
                if saved != nil, let pendingShoe { pick(pendingShoe) }
            }
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
