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
    /// The plan, built once each time the stored one changes. Building it means
    /// generating every week of it from the inputs, and the screen reads it many
    /// times per redraw, so reading `storedPlans.first?.plan` directly rebuilt the
    /// whole plan each time.
    @State private var plan: TrainingPlan?
    /// Whether this week's numbers have come back from Health once. Until then the
    /// ring is a placeholder of the same size, so nothing jumps when they arrive.
    @State private var weekLoaded = false
    @State private var workout = WorkoutManager.shared
    @State private var showLiveRun = false
    // Captured at start so the live run screen can show step-aware targets. Nil for
    // a free run (no goal / rest day / nothing scheduled).
    @State private var runWorkout: PlannedWorkout?
    @State private var runZones: PaceZones?
    // The week's completed volume when the run started, so the summary can show
    // "before + this run" without waiting for Health to have the run.
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
                if !workout.isRunning {
                    OtherSessionView(plan: currentPlan, today: todaysWorkout) { offer in
                        homePage = .today
                        if let plan = currentPlan { start(offer.workout, zones: plan.paceZones) }
                        if let from = offer.movesFrom { PlanSync.shared.requestSwap(today: .now, from: from) }
                    } onIndoor: {
                        homePage = .today
                        captureToday()
                        beginRun(indoor: true)
                    }
                    .tag(HomePage.another)
                }
            }
            .tabViewStyle(.verticalPage)
            .demoTurnPage($homePage, to: .another)
            .containerBackground(Color.accentColor.opacity(0.45).gradient, for: .navigation)
            .task(id: "\(storedPlans.first?.updatedAt.timeIntervalSince1970 ?? 0)-\(today.timeIntervalSince1970)") {
                reloadPlan()
                await loadWeekProgress()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { today = Calendar.current.startOfDay(for: .now) }
            }
            #if DEBUG
            .task { if DemoMode.isOn, UserDefaults.standard.bool(forKey: "demoOffersOpen") { homePage = .another } }
            #endif
            .navigationDestination(isPresented: $showLiveRun) {
                RunFlowView(workout: workout, plannedWorkout: runWorkout, zones: runZones,
                            makeSummary: summaryFromWatch)
            }
            .onChange(of: showLiveRun) { _, shown in
                // Back from a run: this week again, with the run in it.
                if !shown { Task { await loadWeekProgress() } }
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

        }
    }

    /// The summary at the moment the run ends, from what the watch already knows:
    /// the run's own numbers, its reps, and the week as it was before the run plus
    /// this one. No Health read, so it opens at once; the save confirms afterwards.
    /// `nil` for a run too short to be a real one (an accidental start).
    private func summaryFromWatch() -> WatchRunSummary? {
        let distance = workout.distanceMeters
        guard distance >= Self.minSummaryDistanceMeters else { return nil }
        return WatchRunSummary(
            distanceMeters: distance, durationSeconds: workout.elapsedSeconds, saved: true,
            weekNumber: weekProgress?.currentWeekNumber,
            weekCompletedMeters: weekCompletedAtStart + distance,
            weekTargetMeters: weekProgress?.currentWeekPlannedMeters ?? 0,
            reps: workout.reps)
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
        if !weekLoaded {
            // Skeleton: the ring and its two lines at their real size, so the
            // header and Start don't move when the week arrives.
            HStack(spacing: 8) {
                Circle().strokeBorder(.secondary.opacity(0.35), lineWidth: 4)
                    .frame(width: 24, height: 24)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    if !compact {
                        Capsule().fill(.secondary.opacity(0.35)).frame(width: 52, height: 9)
                    }
                    Capsule().fill(.secondary.opacity(0.25)).frame(width: 84, height: 7)
                }
                Spacer(minLength: 0)
            }
            .phaseAnimator([0.55, 1]) { content, opacity in content.opacity(opacity) } animation: { _ in
                .easeInOut(duration: 0.9)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading this week")
        } else if let weekProgress, weekProgress.currentWeekPlannedMeters > 0 {
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
        guard let plan = currentPlan else { weekProgress = nil; weekLoaded = true; return }
        let runs = await Self.weekRuns(plan: plan, health: health)
        let progress = PlanProgress.make(plan: plan, completedRuns: runs, asOf: .now)
        let review = PlanReview.make(plan: plan, original: nil, completedRuns: runs, asOf: .now).day(.now)
        // One animation for both, so "Done today" and the ring arrive together.
        withAnimation(.smooth) {
            weekProgress = progress
            todayReview = review
            weekLoaded = true
        }
    }

    /// The runs the watch shows anything about: this week's. The ring is this week,
    /// "Done today" is today, and neither needs heart rate. Reading every run since
    /// the plan began, with its heart rate, is what made the home screen wait.
    static func weekRuns(plan: TrainingPlan, health: HealthKitService) async -> [CompletedRun] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let week = plan.weeks.last { calendar.startOfDay(for: $0.startDate) <= today }
        let since = week.map { calendar.startOfDay(for: $0.startDate) }
            ?? calendar.date(byAdding: .day, value: -7, to: today)!
        return await health.fetchRuns(since: since, heartRate: false)
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

    /// Prepares the run and opens the countdown; the run itself begins when the
    /// countdown ends (`RunFlowView`).
    private func beginRun(indoor: Bool = false) {
        guard workout.prepare(plannedWorkout: runWorkout, zones: runZones,
                              goalName: currentPlan?.goal.name ?? "", indoor: indoor) else {
            startError = workout.lastError ?? "The run couldn't start."
            return
        }
        showLiveRun = true
        // This week's completed volume before the run, so the post-run summary has
        // a true baseline (the run isn't in Health yet). Already on screen: no read.
        weekCompletedAtStart = weekProgress?.currentWeekCompletedMeters ?? 0
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

    private var currentPlan: TrainingPlan? { plan }

    /// Today's planned run, if there is one.
    private var todaysWorkout: PlannedWorkout? {
        if case .workout(let planned) = state { return planned }
        return nil
    }

    /// Rebuilds the cached plan from the store.
    private func reloadPlan() {
        plan = storedPlans.first?.plan
    }
}
