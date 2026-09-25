import SwiftUI
import SwiftData
import TrainingCore

/// Watch home: shows today's planned workout (read from the shared SwiftData
/// store) and starts a recorded run. With no goal set, it invites a free run
/// rather than implying a session was missed.
struct WatchTodayView: View {
    /// Runs shorter than this don't warrant a post-run summary (stationary tests,
    /// accidental start/finish). 100 m is below any real run yet above GPS jitter.
    private static let minSummaryDistanceMeters: Double = 100
    /// Dark plum label on the light lilac accent, as on endurancr.app.
    static let plumInk = Color(red: 0x24 / 255, green: 0x10 / 255, blue: 0x30 / 255)

    @Environment(HealthKitService.self) private var health
    // Observes the store so a plan synced from the iPhone refreshes the view live.
    @Query(sort: \StoredPlan.updatedAt, order: .reverse) private var storedPlans: [StoredPlan]
    @State private var workout = WorkoutManager()
    @State private var showLiveRun = false
    // Captured at start so the live run screen can show step-aware targets. Nil for
    // a free run (no goal / rest day / nothing scheduled).
    @State private var runWorkout: PlannedWorkout?
    @State private var runZones: PaceZones?
    // Post-run summary shown after Finish, and the week's completed volume captured
    // at run start so the summary can never show less than "prior + this run" while
    // HealthKit's save is still settling.
    @State private var runSummary: WatchRunSummary?
    @State private var weekCompletedAtStart: Double = 0
    // This week's planned vs. completed volume for the home screen ring.
    @State private var weekProgress: PlanProgress?

    var body: some View {
        NavigationStack {
            // Everything that matters, Start included, on one screen. Only very large
            // text sizes fall back to scrolling.
            ViewThatFits(in: .vertical) {
                home(compact: false)
                home(compact: true)
                ScrollView { home(compact: false) }
            }
            .containerBackground(Color.accentColor.opacity(0.45).gradient, for: .navigation)
            .task(id: storedPlans.first?.updatedAt) { await loadWeekProgress() }
            .navigationDestination(isPresented: $showLiveRun) {
                LiveRunView(workout: workout, plannedWorkout: runWorkout, zones: runZones)
            }
            .onChange(of: showLiveRun) { wasShowing, showing in
                // The run screen closed. Summarize only an explicit Finish (a back
                // swipe leaves didFinish false) of a run that actually covered ground
                // - a stationary or accidental run stays silent.
                guard wasShowing, !showing, workout.didFinish,
                      workout.distanceMeters >= Self.minSummaryDistanceMeters else { return }
                let distance = workout.distanceMeters
                let duration = workout.elapsedSeconds
                let saved = workout.lastError == nil
                let prior = weekCompletedAtStart
                let plan = currentPlan
                Task {
                    runSummary = await Self.makeSummary(
                        plan: plan, health: health,
                        distance: distance, duration: duration,
                        saved: saved, priorWeekCompleted: prior
                    )
                }
            }
            .sheet(item: $runSummary, onDismiss: { Task { await loadWeekProgress() } }) { summary in
                NavigationStack { WatchRunSummaryView(summary: summary) }
            }
        }
    }

    /// Builds the post-run summary. Weekly numbers come from `PlanProgress` computed
    /// on-watch; the completed figure is floored at `priorWeekCompleted + distance`
    /// so a not-yet-visible HealthKit save never makes the week appear to shrink.
    /// A free run (no plan) yields stats only, no weekly section.
    private static func makeSummary(
        plan: TrainingPlan?, health: HealthKitService,
        distance: Double, duration: Double,
        saved: Bool, priorWeekCompleted: Double
    ) async -> WatchRunSummary {
        guard let plan else {
            return WatchRunSummary(distanceMeters: distance, durationSeconds: duration,
                                   saved: saved, weekNumber: nil,
                                   weekCompletedMeters: 0, weekTargetMeters: 0)
        }
        let since = plan.weeks.first?.startDate
            ?? Calendar.current.date(byAdding: .month, value: -1, to: .now)!
        let runs = await health.fetchRuns(since: since)
        let progress = PlanProgress.make(plan: plan, completedRuns: runs, asOf: .now)
        return WatchRunSummary(
            distanceMeters: distance, durationSeconds: duration, saved: saved,
            weekNumber: progress.currentWeekNumber,
            weekCompletedMeters: max(progress.currentWeekCompletedMeters, priorWeekCompleted + distance),
            weekTargetMeters: progress.currentWeekPlannedMeters
        )
    }

    /// `compact` is the tighter layout for the smallest watches.
    private func home(compact: Bool) -> some View {
        VStack(spacing: 4) {
            header(compact: compact)
            Spacer(minLength: 0)
            startButton
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func header(compact: Bool) -> some View {
        switch state {
        case .workout(let planned):
            VStack(alignment: .leading, spacing: 0) {
                Text(Format.workoutTitle(planned.type))
                    .font(.headline).foregroundStyle(.tint)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(Format.distance(planned.distanceMeters))
                    .font(.system(compact ? .title3 : .title2, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(Format.paceRange(planned.targetPaceSecPerKm))
                    .font(.footnote).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Today, \(Format.workoutTitle(planned.type)), \(Format.distance(planned.distanceMeters))")
            .frame(maxWidth: .infinity, alignment: .leading)
            weekRing(compact: compact)
        case .rest:
            message("Rest day", "Recover well.", systemImage: "moon.zzz.fill")
            weekRing(compact: compact)
        case .noSessionToday:
            message("Nothing scheduled", "Start a free run anytime.", systemImage: "calendar")
            weekRing(compact: compact)
        case .noGoal:
            message("No goal yet", "Set a goal on your iPhone, or just start a free run.",
                    systemImage: "flag.fill")
        }
    }

    private func message(_ title: String, _ detail: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.tint)
            Text(detail).font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// This week's completed volume against the plan, as a small ring plus numbers.
    @ViewBuilder
    private func weekRing(compact: Bool) -> some View {
        if let weekProgress, weekProgress.currentWeekPlannedMeters > 0 {
            let fraction = min(1, weekProgress.currentWeekCompletedMeters / weekProgress.currentWeekPlannedMeters)
            HStack(spacing: 8) {
                Gauge(value: fraction) {
                    EmptyView()
                } currentValueLabel: {
                    Text("\(Int((fraction * 100).rounded()))")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(.accentColor)
                .scaleEffect(0.7)
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 0) {
                    if !compact {
                        Text(weekProgress.currentWeekNumber.map { "Week \($0)" } ?? "This week")
                            .font(.footnote.weight(.semibold))
                    }
                    Text("\(Format.distance(weekProgress.currentWeekCompletedMeters)) of \(Format.distance(weekProgress.currentWeekPlannedMeters))")
                        .font(.caption2).monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func loadWeekProgress() async {
        guard let plan = currentPlan else { weekProgress = nil; return }
        let since = plan.weeks.first?.startDate
            ?? Calendar.current.date(byAdding: .month, value: -1, to: .now)!
        let runs = await health.fetchRuns(since: since)
        weekProgress = PlanProgress.make(plan: plan, completedRuns: runs, asOf: .now)
    }

    private var startButton: some View {
        Button {
            // Capture today's session and its paces so the run screen can show
            // step-aware targets; leave nil for a free run.
            if case .workout(let planned) = state, let plan = currentPlan {
                runWorkout = planned
                runZones = VDOTCalculator().paceZones(forVDOT: plan.vdot)
            } else {
                runWorkout = nil
                runZones = nil
            }
            workout.start()
            showLiveRun = true
            // Record this week's completed volume *before* the run so the post-run
            // summary has a true prior baseline (the run isn't in HealthKit yet).
            let plan = currentPlan
            Task {
                guard let plan else { weekCompletedAtStart = 0; return }
                let since = plan.weeks.first?.startDate
                    ?? Calendar.current.date(byAdding: .month, value: -1, to: .now)!
                let runs = await health.fetchRuns(since: since)
                weekCompletedAtStart = PlanProgress.make(plan: plan, completedRuns: runs, asOf: .now)
                    .currentWeekCompletedMeters
            }
        } label: {
            Label("Start Run", systemImage: "figure.run")
                .fontWeight(.semibold)
                .foregroundStyle(Self.plumInk)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .tint(.accentColor)
        .controlSize(.large)
    }

    private enum TodayState {
        case workout(PlannedWorkout)
        case rest
        case noSessionToday
        case noGoal
    }

    private var state: TodayState {
        guard let plan = currentPlan else { return .noGoal }
        guard let planned = plan.allWorkouts.first(where: {
            Calendar.current.isDate($0.date, inSameDayAs: .now)
        }) else { return .noSessionToday }
        return planned.type == .rest ? .rest : .workout(planned)
    }

    private var currentPlan: TrainingPlan? {
        storedPlans.first?.plan
    }
}
