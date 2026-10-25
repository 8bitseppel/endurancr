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
    @Environment(\.scenePhase) private var scenePhase
    /// Today, refreshed when the app comes back, so a watch app kept in memory
    /// overnight shows this morning's session, not yesterday's.
    @State private var today = Calendar.current.startOfDay(for: .now)
    // Observes the store so a plan synced from the iPhone refreshes the view live.
    @Query(sort: \StoredPlan.updatedAt, order: .reverse) private var storedPlans: [StoredPlan]
    @State private var workout = WorkoutManager.shared
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
    /// What was run today, once there's a run, from the same plan review as on iPhone.
    @State private var todayReview: PlanReview.Day?
    /// Why a run couldn't start, e.g. no Health access.
    @State private var startError: String?
    /// "Another session", from the More button.
    @State private var homePage = HomePage.today
    enum HomePage { case today, another }

    var body: some View {
        NavigationStack {
            // Everything that matters, Start included, on one screen. Only very large
            // text sizes fall back to scrolling.
            // Page 1 is today's run and Start, nothing else. "Another session" is the
            // page below, a turn of the Crown away, as on the run screen.
            TabView(selection: $homePage) {
                ViewThatFits(in: .vertical) {
                    home(compact: false)
                    home(compact: true)
                    ScrollView { home(compact: false) }
                }
                .tag(HomePage.today)
                if let plan = currentPlan, !workout.isRunning {
                    OtherSessionView(plan: plan) { offer in
                        homePage = .today
                        start(offer.workout, zones: plan.paceZones)
                        if let from = offer.movesFrom { PlanSync.shared.requestSwap(today: .now, from: from) }
                    }
                    .tag(HomePage.another)
                }
            }
            .tabViewStyle(.verticalPage)
            .demoTurnPage($homePage, to: .another)
            .containerBackground(Color.accentColor.opacity(0.45).gradient, for: .navigation)
            .task(id: "\(storedPlans.first?.updatedAt.timeIntervalSince1970 ?? 0)-\(today.timeIntervalSince1970)") {
                await loadWeekProgress()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { today = Calendar.current.startOfDay(for: .now) }
            }
            #if DEBUG
            .task { if DemoMode.isOn, UserDefaults.standard.bool(forKey: "demoOffersOpen") { homePage = .another } }
            #endif
            .navigationDestination(isPresented: $showLiveRun) {
                LiveRunView(workout: workout, plannedWorkout: runWorkout, zones: runZones)
            }
            .onChange(of: workout.saveState) { _, state in
                // Summarize once Health has the finished run (or refused it), with
                // the saved workout's own time and distance. A stationary or
                // accidental run stays silent.
                guard state == .saved || state == .failed, workout.didFinish else { return }
                let distance = workout.savedDistanceMeters ?? workout.distanceMeters
                guard distance >= Self.minSummaryDistanceMeters else { return }
                let duration = workout.savedDuration ?? workout.elapsedSeconds
                let saved = state == .saved
                let prior = weekCompletedAtStart
                let plan = currentPlan
                let reps = workout.reps
                Task {
                    var summary = await Self.makeSummary(
                        plan: plan, health: health,
                        distance: distance, duration: duration,
                        saved: saved, priorWeekCompleted: prior
                    )
                    summary.reps = reps
                    runSummary = summary
                }
            }
            .onChange(of: workout.isRunning, initial: true) { _, running in
                // A run recovered after a crash: back to its run screen.
                if running, !showLiveRun { captureToday(); showLiveRun = true }
            }
            .alert("Couldn't start the run", isPresented: Binding(
                get: { startError != nil }, set: { if !$0 { startError = nil } }
            )) {
                Button("OK") { startError = nil }
            } message: {
                Text("\(startError ?? "") Check that endurancr may use Health in the Settings app.")
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
        case .workout(let planned) where (todayReview?.ranMeters ?? 0) > 0:
            // Run already: what was run, against what was planned. Start stays.
            let day = todayReview!
            VStack(alignment: .leading, spacing: 0) {
                Label(day.status == .done ? "Done today" : "Run today",
                      systemImage: day.status == .done ? "checkmark.circle.fill" : "circle.lefthalf.filled")
                    .font(.headline)
                    .foregroundStyle(day.status == .done ? .green : .orange)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(Format.distance(day.ranMeters))
                    .font(.system(compact ? .title3 : .title2, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("\(Format.workoutTitle(planned.type)), planned \(Format.distance(planned.distanceMeters))")
                    .font(.footnote).foregroundStyle(.secondary)
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
            .accessibilityElement(children: .combine)
            .frame(maxWidth: .infinity, alignment: .leading)
            weekRing(compact: compact)
        case .workout(let planned):
            VStack(alignment: .leading, spacing: 0) {
                Text(Format.workoutTitle(planned.type))
                    .font(.headline).foregroundStyle(.tint)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(Format.distance(planned.distanceMeters))
                    .font(.system(compact ? .title3 : .title2, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                // A guided session says what it holds: "6 × 1 km", "With 6 × 20 s strides".
                Text(Format.sessionSummary(planned) ?? Format.paceRange(planned.targetPaceSecPerKm))
                    .font(.footnote).monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                // Why the plan changed today, from the iPhone (e.g. shorter while
                // easing back in after a break).
                if let note = Self.adaptationNote(planned), !compact {
                    Text(note)
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Today, \(Format.workoutTitle(planned.type)), \(Format.distance(planned.distanceMeters))"
                                + (Self.adaptationNote(planned).map { ", \($0)" } ?? ""))
            .frame(maxWidth: .infinity, alignment: .leading)
            weekRing(compact: compact)
        case .rest(let note):
            message("Rest day", note.isEmpty ? "Recover well." : note, systemImage: "moon.zzz.fill")
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
        todayReview = PlanReview.make(plan: plan, original: nil, completedRuns: runs, asOf: .now).day(.now)
    }

    /// Captures today's session and its paces so the run screen can show step-aware
    /// targets; nil for a free run.
    private func captureToday() {
        if case .workout(let planned) = state, let plan = currentPlan {
            runWorkout = planned
            runZones = plan.paceZones
        } else {
            runWorkout = nil
            runZones = nil
        }
    }

    /// "Start intervals" when the watch will guide reps; "Start Run" otherwise.
    private var startTitle: String {
        guard case .workout(let planned) = state, WorkoutSteps.isGuided(planned) else { return "Start Run" }
        if let s = planned.structure, s.reps > 1 { return "Start intervals" }
        return WorkoutSteps.hasStrides(planned) ? "Start Run" : "Start session"
    }

    /// Starts a session other than today's planned one, from "Another session".
    private func start(_ planned: PlannedWorkout, zones: PaceZones) {
        runWorkout = planned
        runZones = zones
        beginRun()
    }

    private func beginRun() {
        guard workout.start(plannedWorkout: runWorkout, zones: runZones,
                            goalName: currentPlan?.goal.name ?? "") else {
            startError = workout.lastError ?? "The run couldn't start."
            return
        }
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
    }

    private var startButton: some View {
        Button {
            // A run is already going (e.g. the screen was left): back to it.
            if workout.isRunning { showLiveRun = true; return }
            captureToday()
            beginRun()
        } label: {
            Label(startTitle, systemImage: "figure.run")
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
        /// A rest day, with the plan's reason (e.g. the iPhone made it an easier week).
        case rest(note: String)
        case noSessionToday
        case noGoal
    }

    /// The workout's note when the plan adapted it, not the plan's standard
    /// description of the session type.
    static func adaptationNote(_ workout: PlannedWorkout) -> String? {
        guard !VDOTPlanGenerator.isStandardNote(workout.notes) else { return nil }
        return PlanReview.reason(of: workout.notes)
    }

    private var state: TodayState {
        guard let plan = currentPlan else { return .noGoal }
        guard let planned = plan.allWorkouts.first(where: {
            Calendar.current.isDate($0.date, inSameDayAs: today)
        }) else { return .noSessionToday }
        return planned.type == .rest ? .rest(note: planned.notes) : .workout(planned)
    }

    private var currentPlan: TrainingPlan? {
        storedPlans.first?.plan
    }
}
