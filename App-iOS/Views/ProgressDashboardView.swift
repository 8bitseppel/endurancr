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
    @State private var recorder = PhoneWorkoutManager()
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
        if coordinator.raceDayReached {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Race day reached", systemImage: "flag.checkered")
                        .font(.headline)
                    Text("You've reached race day for \(plan.goal.displayName). Confirm it complete to save what you achieved.")
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
                        vdot: coordinator.currentPlan?.vdot
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
                        .font(.system(size: 44, weight: .bold, design: .rounded))
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
                            Text(phase.rawValue.capitalized)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Fatigue

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
                        Text("Training hasn't started yet").font(.subheadline).fontWeight(.semibold)
                        if let next = progress.nextWorkout {
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
            LabeledContent("Projected \(plan.goal.race.displayName)", value: projectedTime(plan))
            if let target = plan.goal.targetTimeSeconds {
                LabeledContent("Target", value: Format.duration(target))
            }
            if let required = progress.requiredVDOT {
                LabeledContent("VDOT for target", value: String(format: "%.1f", required))
                if progress.isReadyForGoal {
                    Label("You can already run this", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                } else if let gap = progress.vdotToGoal {
                    Label("About \(String(format: "%.1f", gap)) VDOT to go", systemImage: "arrow.up.forward")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }
        } header: {
            Text("Fitness")
        } footer: {
            Text("Your recent effort is converted to a VDOT (Jack Tupper Daniels' single number for aerobic fitness) using the Daniels and Gilbert formula. Every training pace below and your projected finish time are derived from it. Strong recorded runs nudge the VDOT up a little at a time.")
        }
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
                .foregroundStyle(by: .value("Phase", week.phase.rawValue))
            }
            .frame(height: 200)
        } header: {
            Text("Weekly volume")
        } footer: {
            Text("Each week's total km sets the run lengths. It starts around half your peak and rises ≤8% per week, with an easier cutback every 4th week and two taper weeks before race day. Peak volume scales with race distance (about \(peakVolumeText(plan)) here). Inside a week, the long run is the single longest run, a set share of the week's total, capped at \(Format.distance(VDOTPlanGenerator.longRunCap(for: plan.goal.race))) for a \(plan.goal.race.displayName), and the remaining km are split evenly across your other running days as easy/quality sessions.")
        }
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
            Text("All five paces come from your VDOT (\(String(format: "%.1f", plan.vdot))). Easy builds aerobic base and is most of your volume; marathon is goal-race effort; threshold (\"comfortably hard\") lifts your lactate ceiling; interval develops top-end aerobic power; repetition sharpens speed and economy.")
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

    private func projectedTime(_ plan: TrainingPlan) -> String {
        let seconds = calculator.predictedTimeSeconds(distanceMeters: plan.goal.race.meters, vdot: plan.vdot)
        return Format.duration(seconds)
    }

    private func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}

private extension String {
    var capitalizedFirst: String { isEmpty ? self : prefix(1).uppercased() + dropFirst() }
}
