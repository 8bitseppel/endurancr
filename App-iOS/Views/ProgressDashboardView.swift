import SwiftUI
import Charts
import TrainingCore

/// The training dashboard: race countdown, adherence, current-week progress,
/// fitness, weekly-volume chart, paces, and recovery status — everything the
/// athlete needs at a glance.
struct ProgressDashboardView: View {
    let coordinator: PlanCoordinator
    private let calculator = VDOTCalculator()
    @State private var showingGoalEditor = false
    @State private var showingDataManagement = false
    /// A target time the athlete is asked to confirm, from the outlook.
    @State private var pendingTarget: Double?
    @State private var recorder = PhoneWorkoutManager.shared
    @State private var showLiveRun = false
    @State private var showCompleteConfirm = false

    var body: some View {
        NavigationStack {
            List {
                if let plan = coordinator.displayPlan, let progress = coordinator.progress {
                    countdownSection(plan: plan, progress: progress)
                    goalReachedSection(plan: plan)
                    readinessSection(plan: plan, progress: progress)
                    todayRunSection
                    buddySection
                    outlookSection
                    fatigueSection
                    nextWorkoutSection(progress)
                    thisWeekSection(progress)
                    adherenceSection(progress)
                    fitnessSection(plan: plan, progress: progress)
                    volumeSection(plan)
                    pacesSection(plan)
                    planningSection
                } else {
                    ContentUnavailableView {
                        Label("No plan yet", systemImage: "flag.checkered")
                    } description: {
                        Text("Pick a race goal and endurancr builds a training plan you can adapt anytime.")
                    } actions: {
                        Button("Set your goal") { showingGoalEditor = true }
                            .buttonStyle(.borderedProminent)
                        Button("Import a backup") { showingDataManagement = true }
                    }
                    if !coordinator.achievedGoals().isEmpty {
                        Section {
                            NavigationLink {
                                AchievedGoalsView(coordinator: coordinator)
                            } label: {
                                Label("Achieved goals", systemImage: "trophy")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Progress")
            .demoAutoScroll()
            .refreshable { await coordinator.refreshAdaptation() }
            .sheet(isPresented: $showingGoalEditor) {
                GoalEditorView(coordinator: coordinator)
            }
            .sheet(isPresented: $showingDataManagement) {
                NavigationStack { DataManagementView(coordinator: coordinator) }
            }
            .navigationDestination(isPresented: $showLiveRun) {
                PhoneLiveRunView(recorder: recorder)
            }
            .confirmationDialog(
                "Mark this goal achieved?",
                isPresented: $showCompleteConfirm, titleVisibility: .visible
            ) {
                Button("Mark achieved") { coordinator.completeCurrentGoal() }
                Button("Not yet", role: .cancel) {}
            } message: {
                Text("Saves a summary of what you achieved and clears the plan so you can set a new goal. Recorded runs stay in Apple Health.")
            }
        }
    }

    // MARK: Goal reached

    /// Shown once race day arrives: confirm the goal is done and bank the summary.
    @ViewBuilder private func goalReachedSection(plan: TrainingPlan) -> some View {
        if coordinator.raceDayReached, coordinator.goalSaved {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Saved to your achieved goals").font(.headline)
                        if let end = coordinator.recoveryEnd {
                            Text("Your recovery days stay in the plan until \(end.formatted(.dateTime.weekday(.wide).day().month())). Set your next goal whenever you're ready.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "trophy").foregroundStyle(.tint)
                }
            }
        } else if coordinator.raceDayReached {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Race day reached", systemImage: "flag.checkered")
                        .font(.headline)
                    Text(coordinator.recoveryEnd.map { "You've reached race day for \(plan.goal.displayName). Save what you achieved; the recovery days stay in your plan until \($0.formatted(.dateTime.weekday(.wide).day().month()))." }
                         ?? "You've reached race day for \(plan.goal.displayName). Confirm it complete to save what you achieved.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button {
                        showCompleteConfirm = true
                    } label: {
                        Label("Mark goal achieved", systemImage: "trophy")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: Readiness

    /// A "you're good to go" banner when current fitness already meets the target,
    /// explaining that the plan holds fitness rather than building it.
    @ViewBuilder private func readinessSection(plan: TrainingPlan, progress: PlanProgress) -> some View {
        if progress.isReadyForGoal {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You're good to go").font(.subheadline).fontWeight(.semibold)
                        Text("Your fitness already meets your target for \(plan.goal.race.displayName). This plan holds your VDOT so you arrive at race day sharp.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                }
            }
        }
    }

    // MARK: Today's run

    /// A prominent "Start run" button, shown only on days with a scheduled run
    /// (hidden on rest days and days blanked by a vacation period).
    @ViewBuilder private var todayRunSection: some View {
        if let today = coordinator.workout(), today.type != .rest {
            Section {
                Button {
                    recorder.start(
                        goalName: coordinator.currentPlan?.goal.displayName ?? "",
                        workoutTitle: Format.workoutTitle(today.type),
                        targetPace: today.targetPaceSecPerKm,
                        plannedWorkout: today,
                        zones: coordinator.currentPlan?.paceZones
                    )
                    showLiveRun = true
                } label: {
                    HStack {
                        Label("Start run", systemImage: "figure.run")
                            .fontWeight(.semibold)
                        Spacer()
                        Text(Format.distance(today.distanceMeters))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Today · \(Format.workoutTitle(today.type))")
            } footer: {
                Text("Records on iPhone with GPS. Start on your Apple Watch instead to include heart rate.")
            }
        }
    }

    // MARK: Countdown

    private func countdownSection(plan: TrainingPlan, progress: PlanProgress) -> some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(progress.daysUntilRace)")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .contentTransition(.numericText())
                    Text("days to \(plan.goal.displayName)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(plan.goal.raceDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.headline)
                    if let n = progress.currentWeekNumber {
                        Text("Week \(n) of \(progress.totalWeeks)")
                            .font(.caption).foregroundStyle(.secondary)
                        if let phase = progress.currentWeekPhase {
                            Text(phase.displayName)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Fatigue

    // MARK: Buddy and outlook

    /// One friendly line on how training is going and what the plan does about it.
    @ViewBuilder private var buddySection: some View {
        if let buddy = coordinator.buddy, !buddy.message.isEmpty {
            Section {
                Label {
                    Text(buddy.message).font(.subheadline)
                } icon: {
                    Image(systemName: buddy.phase.symbol)
                        .foregroundStyle(.tint)
                }
            } header: {
                Text("How it's going")
            }
        }
    }

    /// The honest look at the goal: what today's fitness would run, what race day
    /// should look like at this rate, and how likely the target is.
    @ViewBuilder private var outlookSection: some View {
        if let outlook = coordinator.outlook, let plan = coordinator.currentPlan {
            Section {
                if let verdict = outlook.verdict {
                    // The title says it; the icon carries the colour (yellow text
                    // would be too faint on a light background).
                    Label {
                        Text(verdict.title).font(.headline)
                    } icon: {
                        Image(systemName: verdict.symbol).foregroundStyle(verdict.tint)
                    }
                }
                LabeledContent("If the race were today", value: GoalOutlook.rangeText(outlook.today))
                LabeledContent("Race day, at this rate", value: GoalOutlook.rangeText(outlook.raceDay))
                if let target = plan.goal.targetTimeSeconds {
                    LabeledContent("Your target", value: GoalOutlook.format(target))
                }
                if !outlook.reason.isEmpty {
                    Text(outlook.reason)
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let suggested = outlook.suggestedTargetSeconds {
                    Button("Make \(GoalOutlook.format(suggested)) my target") { pendingTarget = suggested }
                }
            } header: {
                Text("\(plan.goal.race.displayName) outlook")
            } footer: {
                Text("An estimate from your training, not a guarantee. A range, because predictions are never exact: for the marathon, about half of recreational runners finish 10 minutes or more slower than a formula from a shorter race says (Vickers & Vertosick 2016). Race day assumes training goes on like the last two weeks.")
            }
            .confirmationDialog(
                "Change your target time?",
                isPresented: Binding(get: { pendingTarget != nil }, set: { if !$0 { pendingTarget = nil } }),
                titleVisibility: .visible
            ) {
                Button("Make \(GoalOutlook.format(pendingTarget ?? 0)) my target") {
                    if let seconds = pendingTarget {
                        Task { try? await coordinator.adoptTarget(seconds: seconds) }
                    }
                    pendingTarget = nil
                }
                Button("Keep my target", role: .cancel) { pendingTarget = nil }
            } message: {
                Text("The plan is rebuilt for the new target. Your runs stay in Health, and you can change it back anytime in Edit goal.")
            }
        }
    }

    @ViewBuilder private var fatigueSection: some View {
        if let fatigue = coordinator.fatigue, fatigue.isFatigued {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recovery flag").font(.subheadline).fontWeight(.semibold)
                        Text(fatigue.summary.capitalizedFirst)
                            .font(.footnote).foregroundStyle(.secondary)
                        Text("Your next hard session has been eased to easy.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "heart.text.square")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: Next workout

    /// The next session after today's, since today's already has its own
    /// Start run section above.
    private func upcomingWorkout(_ progress: PlanProgress) -> PlannedWorkout? {
        guard let next = progress.nextWorkout, Calendar.current.isDateInToday(next.date) else {
            return progress.nextWorkout
        }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
        return coordinator.displayPlan?.allWorkouts
            .filter { $0.type != .rest && $0.date >= tomorrow }
            .min { $0.date < $1.date }
    }

    @ViewBuilder private func nextWorkoutSection(_ progress: PlanProgress) -> some View {
        if let next = upcomingWorkout(progress) {
            Section("Next workout") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(Format.workoutTitle(next.type))
                            .font(.title3.weight(.semibold))
                        Spacer()
                        Text(next.date.formatted(.dateTime.weekday(.wide).day().month()))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if next.type != .rest {
                        HStack(spacing: 6) {
                            Text(Format.distance(next.distanceMeters)).fontWeight(.semibold)
                            if let pace = next.targetPaceSecPerKm {
                                Text("·").foregroundStyle(.secondary)
                                Text(Format.paceRange(pace)).foregroundStyle(.secondary)
                            }
                        }
                        .font(.subheadline)
                    }
                    if !next.notes.isEmpty {
                        Text(next.notes)
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let structure = next.structure, let zones = coordinator.displayPlan?.paceZones {
                        WorkoutStepsView(structure: structure, zones: zones)
                            .padding(.top, 2)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: This week

    private func thisWeekSection(_ progress: PlanProgress) -> some View {
        Section("This week") {
            let done = progress.currentWeekCompletedMeters
            let planned = max(progress.currentWeekPlannedMeters, 1)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(Format.distance(done)).fontWeight(.semibold)
                    Text("of \(Format.distance(progress.currentWeekPlannedMeters))")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(percent(done / planned))
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                ProgressView(value: min(done / planned, 1))
                    .tint(.accentColor)
            }
        }
    }

    // MARK: Adherence

    @ViewBuilder private func adherenceSection(_ progress: PlanProgress) -> some View {
        Section {
            if progress.plannedToDateMeters <= 0 {
                // Nothing is due yet — showing "100%" here would be misleading. Say so
                // plainly and point at the first run instead of an empty adherence ring.
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(progress.completedDistanceMeters > 0 ? "No planned run due yet" : "Training hasn't started yet")
                            .font(.subheadline).fontWeight(.semibold)
                        if progress.completedDistanceMeters > 0, let next = progress.nextWorkout {
                            Text("Your \(Format.distance(progress.completedDistanceMeters)) so far count toward this week. Your first planned run is \(next.date.formatted(.dateTime.weekday(.wide).day().month())), and sticking to the plan is measured from then.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else if let next = progress.nextWorkout {
                            Text("Your first run is \(next.date.formatted(.dateTime.weekday(.wide).day().month())). Adherence starts tracking once a run is due.")
                                .font(.footnote).foregroundStyle(.secondary)
                        } else {
                            Text("Adherence starts tracking once a run is due.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "hourglass").foregroundStyle(.secondary)
                }
            } else {
                // Two different questions, kept apart so neither number reads as the
                // other: how far through the plan you are, and how much of what was
                // due so far you actually ran.
                bar("Through the plan",
                    detail: progress.currentWeekNumber.map { "Week \($0) of \(progress.totalWeeks)" } ?? "",
                    fraction: progress.overallCompletionFraction)
                bar("Runs done so far",
                    detail: "\(progress.workoutsCompleted) of \(progress.workoutsScheduledToDate) runs that were due",
                    fraction: progress.runsDoneFraction)
                LabeledContent("Distance so far",
                               value: "\(Format.distance(progress.completedDistanceMeters)) of \(Format.distance(progress.plannedToDateMeters))")
                    .font(.subheadline)
            }
        } header: {
            Text("Sticking to the plan")
        } footer: {
            if progress.plannedToDateMeters > 0 {
                Text("Only runs that were already due count. Today's run counts once you've done it.")
            }
        }
    }

    private func bar(_ title: String, detail: String, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).fontWeight(.semibold)
                Spacer()
                Text(percent(fraction)).foregroundStyle(.secondary).monospacedDigit()
            }
            ProgressView(value: min(max(fraction, 0), 1))
                .tint(.accentColor)
            if !detail.isEmpty {
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Fitness

    private func fitnessSection(plan: TrainingPlan, progress: PlanProgress) -> some View {
        Section {
            if let fitness = coordinator.inputs?.fitness {
                LabeledContent("Recent effort") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Format.distance(fitness.distanceMeters)) · \(Format.duration(fitness.timeSeconds))")
                            .fontWeight(.semibold)
                        Text("\(Format.pace(effortPace(fitness))) · \(fitness.date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            LabeledContent("VDOT", value: String(format: "%.1f", plan.vdot))
            if plan.enduranceHoldback > 0 {
                LabeledContent("For the \(plan.goal.race.displayName.lowercased())",
                               value: String(format: "%.1f", plan.raceVDOT))
            }
            if let required = progress.requiredVDOT {
                LabeledContent("VDOT for target", value: String(format: "%.1f", required))
                if progress.isReadyForGoal {
                    Label("You can already run this", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                }
            }
        } header: {
            Text("Fitness")
        } footer: {
            Text(fitnessFooter(plan))
        }
    }

    private func fitnessFooter(_ plan: TrainingPlan) -> String {
        var text = "Your recent effort is converted to a VDOT (Jack Tupper Daniels' single number for aerobic fitness) using the Daniels and Gilbert formula. Every training pace below is derived from it. Strong recorded runs raise it by at most 1 point every 3 weeks, hard sessions that keep coming in slower lower it by 1, and time off lowers it by Daniels' table."
        if plan.enduranceHoldbackBase > 0 {
            let full = Format.distance(EnduranceAdjustment.fullCreditMeters(goalMeters: plan.goal.race.meters))
            text += " Your effort was much shorter than a \(plan.goal.race.displayName.lowercased()), and it shows speed, not the endurance to go that far. So marathon pace and the projection use \(String(format: "%.1f", plan.enduranceHoldback)) VDOT less for now. Long runs earn it back, fully once you've run \(full)."
        }
        return text
    }

    /// Average pace (sec/km) of the recent effort that seeded the VDOT.
    private func effortPace(_ fitness: FitnessSnapshot) -> Double {
        guard fitness.distanceMeters > 0 else { return 0 }
        return fitness.timeSeconds / (fitness.distanceMeters / 1_000)
    }

    // MARK: Volume chart

    private func volumeSection(_ plan: TrainingPlan) -> some View {
        Section {
            Chart(plan.weeks, id: \.index) { week in
                BarMark(
                    x: .value("Week", week.index + 1),
                    y: .value("km", week.plannedVolumeMeters / 1_000)
                )
                .foregroundStyle(by: .value("Phase", week.phase.displayName))
            }
            .chartForegroundStyleScale(domain: phaseDomain(plan), range: phaseDomain(plan).map { name in plan.weeks.first { $0.phase.displayName == name }?.phase.tint ?? .blue })
            .frame(height: 200)
        } header: {
            Text("Weekly volume")
        } footer: {
            Text("Each week's total km sets the run lengths. It starts around half your peak and rises ≤8% per week, with an easier cutback every 4th week and two taper weeks before race day. Peak volume scales with race distance (about \(peakVolumeText(plan)) here). Inside a week, the long run is the single longest run, a set share of the week's total, capped at \(Format.distance(VDOTPlanGenerator.longRunCap(for: plan.goal.race))) for a \(plan.goal.race.displayName), and the remaining km are split evenly across your other running days as easy/quality sessions.")
        }
    }


    /// The phases this plan has, in order, so the legend lists only those.
    private func phaseDomain(_ plan: TrainingPlan) -> [String] {
        var seen: [String] = []
        for week in plan.weeks where !seen.contains(week.phase.displayName) { seen.append(week.phase.displayName) }
        return seen
    }

    private func peakVolumeText(_ plan: TrainingPlan) -> String {
        Format.distance(plan.peakVolumeMeters) + "/week"
    }

    // MARK: Paces

    private func pacesSection(_ plan: TrainingPlan) -> some View {
        Section {
            LabeledContent("Easy", value: Format.pace(plan.paceZones.easySecPerKm))
            LabeledContent("Marathon", value: Format.pace(plan.paceZones.marathonSecPerKm))
            LabeledContent("Threshold", value: Format.pace(plan.paceZones.thresholdSecPerKm))
            LabeledContent("Interval", value: Format.pace(plan.paceZones.intervalSecPerKm))
            LabeledContent("Repetition", value: Format.pace(plan.paceZones.repetitionSecPerKm))
        } header: {
            Text("Paces (min/km)")
        } footer: {
            Text("All five paces come from your VDOT (\(String(format: "%.1f", plan.vdot))\(plan.enduranceHoldback > 0 ? "; marathon pace from \(String(format: "%.1f", plan.raceVDOT)) until your long runs show the endurance" : "")). Easy builds aerobic base and is most of your volume; marathon is goal-race effort; threshold (\"comfortably hard\") lifts your lactate ceiling; interval develops top-end aerobic power; repetition sharpens speed and economy.")
        }
    }

    // MARK: Planning

    private var planningSection: some View {
        Section("Planning") {
            Button {
                showingGoalEditor = true
            } label: {
                Label("Edit goal & rules", systemImage: "target")
            }
            NavigationLink {
                RunHistoryView(coordinator: coordinator)
            } label: {
                Label("Recent runs", systemImage: "figure.run")
            }
            NavigationLink {
                AchievedGoalsView(coordinator: coordinator)
            } label: {
                Label("Achieved goals", systemImage: "trophy")
            }
            NavigationLink {
                UnavailabilityView(coordinator: coordinator)
            } label: {
                Label("Vacation & time off", systemImage: "airplane")
            }
            Button {
                showingDataManagement = true
            } label: {
                Label("Backup & restore", systemImage: "arrow.up.arrow.down.circle")
            }
        }
    }

    private func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}

private extension String {
    var capitalizedFirst: String { isEmpty ? self : prefix(1).uppercased() + dropFirst() }
}
