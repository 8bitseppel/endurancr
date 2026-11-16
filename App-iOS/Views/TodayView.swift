import SwiftUI
import TrainingCore

/// The workout scheduled for today, with target paces and a prompt to record on Watch.
struct TodayView: View {
    /// Runs shorter than this don't warrant a post-run summary (stationary tests,
    /// accidental start/finish). 100 m is below any real run yet above GPS jitter.
    /// Kept in step with the watch's `WatchTodayView`.
    private static let minSummaryDistanceMeters: Double = 100

    let coordinator: PlanCoordinator
    @State private var recorder = PhoneWorkoutManager.shared
    @State private var calendar = PlanCalendar.shared
    @State private var confirmCalendarOff = false
    @State private var showLiveRun = false
    @State private var runSummary: RunSummaryData?
    @State private var showingGoalEditor = false
    @State private var showingDataManagement = false
    @State private var showDeleteConfirm = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingOther = false
    /// The run the summary was shown for, so it opens once per run.
    @State private var summarizedRun: UUID?
    #if DEBUG
    private static var demoRan = false
    #endif
    @AppStorage(RunSettings.spokenCuesKey) private var spokenCues = false
    @AppStorage(RunSettings.autoPauseKey) private var autoPause = false
    @AppStorage(RunSettings.zoneTapsKey) private var zoneTaps = false


    /// What the buddy says about the week, with the step up when one is offered.
    @ViewBuilder private var buddyCard: some View {
        if let buddy = coordinator.buddy, !buddy.message.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text(buddy.message).font(.subheadline)
                } icon: {
                    Image(systemName: buddy.phase.symbol).foregroundStyle(.tint)
                }
                // Offered, never done for you: the weeks ahead start from
                // what you've been running if you say so.
                if let step = buddy.stepUp {
                    Button {
                        coordinator.stepUp(step)
                    } label: {
                        Label("Plan from \(Int((step.weeklyMeters / 1_000).rounded())) km a week", systemImage: "arrow.up.right")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glass)
                }
            }
            .brandCard()
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    // First: when Health hides runs, everything below is off.
                    HealthAccessNote(coordinator: coordinator)
                    if let workout = coordinator.workout() {
                        todayCard(workout)
                    } else {
                        ContentUnavailableView("Nothing scheduled today", systemImage: "checkmark.circle")
                            .brandCard()
                    }
                    startButton
                    // An offer to act on (a step up) comes right under Start, where
                    // it's seen; a plain note about the week stays at the bottom.
                    if coordinator.buddy?.stepUp != nil { buddyCard }
                    if let plan = coordinator.displayPlan {
                        weekStrip(plan)
                        if let next = nextRun(plan) { nextRunCard(next) }
                    }
                    if coordinator.buddy?.stepUp == nil { buddyCard }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background { BrandBackground() }
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Remove your runs from Calendar?", isPresented: $confirmCalendarOff, titleVisibility: .visible) {
                Button("Remove the endurancr calendar", role: .destructive) { calendar.turnOff() }
                Button("Keep it", role: .cancel) {}
            } message: {
                Text("The endurancr calendar and its runs are removed from Calendar on all your devices. Your plan stays as it is.")
            }
            .alert("Couldn't add your runs to Calendar", isPresented: Binding(
                get: { calendar.problem != nil }, set: { if !$0 { calendar.problem = nil } }
            )) {
                Button("OK") { calendar.problem = nil }
            } message: {
                Text(calendar.problem ?? "")
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingGoalEditor = true
                        } label: {
                            Label(coordinator.inputs == nil ? "Set your goal" : "Edit goal & rules", systemImage: "target")
                        }
                        Button {
                            showingDataManagement = true
                        } label: {
                            Label("Storage & backup", systemImage: "arrow.up.arrow.down.circle")
                        }
                        if coordinator.inputs != nil {
                            // A toggle, so the menu shows a check while it's on.
                            Toggle(isOn: Binding(
                                get: { calendar.isOn },
                                set: { on in
                                    if on {
                                        Task { await calendar.turnOn(plan: coordinator.displayPlan) }
                                    } else {
                                        // Removing a calendar reaches every device on the
                                        // account, so it's asked first.
                                        confirmCalendarOff = true
                                    }
                                }
                            )) {
                                Label("Runs in Calendar", systemImage: "calendar")
                            }
                        }
                        Section("Runs") {
                            Toggle(isOn: $spokenCues) {
                                Label("Spoken cues", systemImage: "speaker.wave.2")
                            }
                            Toggle(isOn: $autoPause) {
                                Label("Auto-pause on iPhone", systemImage: "pause.circle")
                            }
                            Toggle(isOn: $zoneTaps) {
                                Label("Zone taps on Apple Watch", systemImage: "heart.circle")
                            }
                        }
                        if coordinator.inputs != nil {
                            Divider()
                            Button(role: .destructive) {
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete goal", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .navigationDestination(isPresented: $showLiveRun) {
                PhoneLiveRunView(recorder: recorder, onFinished: presentSummary)
            }
            .onChange(of: zoneTaps) { _, on in PlanSync.shared.setZoneTaps(on) }
            .onChange(of: recorder.saveState) { _, state in
                // The run is in Health now, or Health refused it. A run finished while
                // its screen wasn't showing (from the Live Activity, on another tab)
                // gets its summary now; then the plan re-adapts and the summary's week
                // follows.
                guard state == .saved || state == .failed else { return }
                if summarizedRun != recorder.runID, !recorder.needsMachineDistance { presentSummary() }
                guard runSummary != nil else { return }
                let run = recorder.runID
                Task {
                    await coordinator.refreshAdaptation()
                    guard summarizedRun == run, var shown = runSummary else { return }
                    let p = coordinator.progress
                    shown.weekNumber = p?.currentWeekNumber ?? shown.weekNumber
                    // HealthKit's save may not be visible to the re-read yet, so never
                    // less than what the summary already said.
                    shown.weekCompletedMeters = max(p?.currentWeekCompletedMeters ?? 0, shown.weekCompletedMeters)
                    shown.weekTargetMeters = p?.currentWeekPlannedMeters ?? shown.weekTargetMeters
                    runSummary = shown
                }
            }
            .sheet(item: $runSummary) { RunSummaryView(data: $0, saveState: recorder.saveState) }
            #if DEBUG
            .task {
                // `-demoScreen phoneflow`: a guided run on iPhone, Start to summary.
                // Once, and not tied to this screen, which goes when the run's opens.
                guard DemoMode.isOn, DemoMode.screen == "phoneflow", !Self.demoRan,
                      let zones = coordinator.currentPlan?.paceZones else { return }
                Self.demoRan = true
                let strides = UserDefaults.standard.bool(forKey: "demoStrides")
                let planned = strides
                    ? PlannedWorkout(date: .now, type: .easy, distanceMeters: 3_500, notes: VDOTPlanGenerator.stridesNote)
                    : PlannedWorkout(date: .now, type: .interval, distanceMeters: 5_600,
                                     structure: WorkoutStructure(warmupMeters: 1_000, reps: 6, workMeters: 400, recoveryMeters: 200,
                                                                 cooldownMeters: 1_000, workType: .interval, recoveryType: .easy))
                showLiveRun = true
                let recorder = recorder
                Task {
                    await recorder.demoRun(plannedWorkout: planned, zones: zones,
                                           indoor: UserDefaults.standard.bool(forKey: "demoIndoor"))
                }
            }
            #endif
            .sheet(isPresented: $showingOther) {
                OtherSessionSheet(offers: offers, today: todaysRun, onStart: start, onIndoor: startIndoor)
            }
            #if DEBUG
            // `-demoOffersOpen YES`: "Another session" open, for screenshots.
            .task { if DemoMode.isOn, UserDefaults.standard.bool(forKey: "demoOffersOpen") { showingOther = true } }
            #endif
            .sheet(isPresented: $showingGoalEditor) { GoalEditorView(coordinator: coordinator) }
            .sheet(isPresented: $showingDataManagement) {
                NavigationStack { DataManagementView(coordinator: coordinator) }
            }
            .confirmationDialog(
                "Delete this goal?",
                isPresented: $showDeleteConfirm, titleVisibility: .visible
            ) {
                Button("Delete goal", role: .destructive) { coordinator.deletePlan() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes your plan and training rules. Recorded runs stay in Apple Health.")
            }
            .refreshable { await coordinator.refreshAdaptation() }
        }
    }

    // MARK: Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today")
                .font(Brand.rounded(.largeTitle))
                .accessibilityAddTraits(.isHeader)
            if let goal = coordinator.currentPlan?.goal {
                Text(headerLine(goal))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }

    private func headerLine(_ goal: Goal) -> String {
        let days = daysToGo(goal.raceDate)
        var parts = [goal.displayName, days == 0 ? "race day" : "\(days) days to go"]
        if let week = coordinator.progress?.currentWeekNumber, let total = coordinator.progress?.totalWeeks {
            parts.append("week \(week) of \(total)")
        }
        return parts.joined(separator: " · ")
    }

    /// Today's run, big, in its colour. Once it's run: what was run today.
    @ViewBuilder
    private func todayCard(_ workout: PlannedWorkout) -> some View {
        if workout.type.isRunning, let day = coordinator.review?.day(.now), day.ranMeters > 0 {
            doneCard(workout, day: day)
        } else {
            plannedCard(workout)
        }
    }

    /// Today's run done (or begun): the distance run, against what was planned. Start
    /// run stays below, for a second run.
    private func doneCard(_ workout: PlannedWorkout, day: PlanReview.Day) -> some View {
        let done = day.status == .done
        return VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(done ? "Done today" : "Run today")
            } icon: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle.lefthalf.filled")
                    .foregroundStyle(done ? .green : .orange)
            }
            .brandEyebrow()
            Text(Format.distance(day.ranMeters))
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("\(Format.workoutTitle(workout.type)), planned \(Format.distance(workout.distanceMeters))")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                if let pace = day.ranPaceSecPerKm { metric("Pace", Format.pace(pace)) }
                metric("Time", Format.duration(day.ranSeconds))
            }
            if !day.reps.isEmpty { RepsView(reps: day.reps) }
        }
        .brandCard(tint: done ? .green : workout.type.tint, cornerRadius: 30, padding: 22)
        .accessibilityElement(children: .combine)
    }

    private func plannedCard(_ workout: PlannedWorkout) -> some View {
        let tint = workout.type.tint
        let extra = workout.type == .rest ? coordinator.review?.day(.now).flatMap { $0.ranMeters > 0 ? $0 : nil } : nil
        return VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(extra == nil ? Format.workoutTitle(workout.type) : "Extra run")
            } icon: {
                // The colour on the icon only: coloured text would be faint on the card.
                Image(systemName: extra == nil ? (workout.type == .rest ? Format.restSymbol(note: workout.notes) : workout.type.symbol) : "checkmark.seal.fill")
                    .foregroundStyle(extra == nil ? tint : .green)
            }
            .brandEyebrow()

            if let extra {
                Text(Format.distance(extra.ranMeters))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(["It counts toward this week.", Format.extraRunEffort(extra.effort).map { $0 + "." }]
                        .compactMap { $0 }.joined(separator: " "))
                    .font(.callout).foregroundStyle(.secondary)
            } else if workout.type == .rest {
                Text("Rest day")
                    .font(Brand.rounded(.largeTitle))
                Text(workout.notes.isEmpty ? "Rest is training too, so let the work sink in." : workout.notes)
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text(Format.distance(workout.distanceMeters))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                HStack(spacing: 10) {
                    metric("Pace", Format.paceRange(workout.targetPaceSecPerKm))
                    if let time = Format.estimatedDuration(distanceMeters: workout.distanceMeters, pace: workout.targetPaceSecPerKm) {
                        metric("Time", "~\(time)")
                    }
                }
                if !workout.notes.isEmpty {
                    Text(workout.notes).font(.callout).foregroundStyle(.secondary)
                }
                if let structure = workout.structure, let zones = coordinator.displayPlan?.paceZones {
                    WorkoutStepsView(structure: structure, zones: zones)
                }
            }
        }
        .brandCard(tint: extra == nil ? tint : .green, cornerRadius: 30, padding: 22)
        .accessibilityElement(children: .combine)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(Brand.rounded(.headline, weight: .semibold)).monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    /// Record a run on the iPhone itself (GPS), available any day. Starting on an
    /// Apple Watch instead adds heart rate.
    private var startButton: some View {
        let today = coordinator.workout()
        return VStack(spacing: 8) {
            Button {
                recorder.start(
                    goalName: coordinator.currentPlan?.goal.displayName ?? "",
                    workoutTitle: today.map { Format.workoutTitle($0.type) } ?? "Run",
                    targetPace: today?.targetPaceSecPerKm,
                    plannedWorkout: today?.type == .rest ? nil : today,
                    zones: coordinator.currentPlan?.paceZones
                )
                showLiveRun = true
            } label: {
                Label("Start run", systemImage: "play.fill")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .tint(Brand.buttonPurple)
            .controlSize(.large)
            Text("Records on iPhone with GPS. Start on your Apple Watch instead to include heart rate.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            // Always there: the indoor run is offered even when nothing else is.
            Button("Start another session") { showingOther = true }
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 44)   // a full tap target for one line of text
                .contentShape(.rect)
        }
    }

    /// "Another session": offered when there's something to offer or a reason to give.
    private var offers: SessionOffers? {
        #if DEBUG
        if let demo = DemoMode.sessionOffers { return demo }
        #endif
        guard let offers = coordinator.sessionOffers, !offers.offers.isEmpty || offers.reason != nil else { return nil }
        return offers
    }

    /// Today's run, unless today is a rest day.
    private var todaysRun: PlannedWorkout? {
        coordinator.workout().flatMap { $0.type == .rest ? nil : $0 }
    }

    /// The summary of the run just finished, at once: from what the iPhone measured,
    /// with the week as it stood plus this run. "Saving to Health" turns into "Saved"
    /// in place, and the week is brought up to date once the plan has re-adapted.
    private func presentSummary() {
        guard summarizedRun != recorder.runID else { return }
        summarizedRun = recorder.runID
        let distance = recorder.machineDistanceMeters ?? recorder.distanceMeters
        guard distance >= Self.minSummaryDistanceMeters else { return }
        let p = coordinator.progress
        runSummary = RunSummaryData(
            distanceMeters: distance,
            durationSeconds: recorder.elapsedSeconds,
            saved: recorder.saveState == .saved,
            weekNumber: p?.currentWeekNumber,
            weekCompletedMeters: (p?.currentWeekCompletedMeters ?? 0) + distance,
            weekTargetMeters: p?.currentWeekPlannedMeters ?? 0,
            reps: recorder.reps
        )
    }

    /// Today's run, or a free run, on a treadmill.
    private func startIndoor() {
        showingOther = false
        let today = todaysRun
        recorder.start(
            goalName: coordinator.currentPlan?.goal.displayName ?? "",
            workoutTitle: today.map { Format.workoutTitle($0.type) } ?? "Indoor run",
            targetPace: today?.targetPaceSecPerKm,
            plannedWorkout: today,
            zones: coordinator.currentPlan?.paceZones,
            indoor: true
        )
        showLiveRun = true
    }

    private func start(_ offer: SessionOffers.Offer) {
        showingOther = false
        coordinator.adopt(offer)
        recorder.start(
            goalName: coordinator.currentPlan?.goal.displayName ?? "",
            workoutTitle: Format.workoutTitle(offer.workout.type),
            targetPace: offer.workout.targetPaceSecPerKm,
            plannedWorkout: offer.workout,
            zones: coordinator.currentPlan?.paceZones
        )
        showLiveRun = true
    }

    /// This week at a glance: a circle for every day, in the run's colour.
    private func weekStrip(_ plan: TrainingPlan) -> some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let week = plan.weeks.first { week in
            let start = calendar.startOfDay(for: week.startDate)
            return start <= today && today < calendar.date(byAdding: .day, value: 7, to: start)!
        }
        let days: [Date] = week.map { w in
            (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: w.startDate)) }
        } ?? []
        let progress = coordinator.progress
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week").brandEyebrow()
                Spacer()
                if let progress {
                    Text("\(Format.distance(progress.currentWeekCompletedMeters)) of \(Format.distance(progress.currentWeekPlannedMeters))")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
            }
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { day in
                    WeekDayDot(
                        date: day,
                        workout: week?.workouts.first { calendar.isDate($0.date, inSameDayAs: day) },
                        review: coordinator.review?.day(day),
                        isToday: day == today
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .brandCard()
    }

    private func nextRun(_ plan: TrainingPlan) -> PlannedWorkout? {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
        return plan.allWorkouts.first { $0.date >= tomorrow && $0.type.isRunning }
    }

    private func nextRunCard(_ workout: PlannedWorkout) -> some View {
        HStack(spacing: 14) {
            Image(systemName: workout.type.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(workout.type.tint.opacity(colorScheme == .dark ? 0.4 : 1).gradient, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Next · \(nextDayName(workout.date))").brandEyebrow()
                Text(Format.workoutTitle(workout.type)).font(Brand.rounded(.headline))
                Text("\(Format.distance(workout.distanceMeters)) · \(Format.paceRange(workout.targetPaceSecPerKm))")
                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .brandCard()
        .accessibilityElement(children: .combine)
    }

    private func nextDayName(_ date: Date) -> String {
        Calendar.current.isDateInTomorrow(date) ? "Tomorrow" : date.formatted(.dateTime.weekday(.wide))
    }

    private func daysToGo(_ date: Date) -> Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: date)
        ).day
        return max(0, days ?? 0)
    }
}

/// One day in the week strip: done runs filled in their colour, missed ones crossed
/// out, coming runs as a soft circle, rest days as a dot, today outlined.
private struct WeekDayDot: View {
    let date: Date
    let workout: PlannedWorkout?
    let review: PlanReview.Day?
    let isToday: Bool

    private var status: PlanReview.Status? { review?.status }
    private var tint: Color { status == .extra ? .green : (workout?.type.tint ?? .gray) }
    private var isRun: Bool { workout?.type.isRunning ?? false }
    @Environment(\.colorScheme) private var colorScheme
    /// Softer at night, where full colours on black glare.
    private var strength: Double { colorScheme == .dark ? 0.4 : 1 }

    var body: some View {
        VStack(spacing: 6) {
            Text(date.formatted(.dateTime.weekday(.narrow)))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isToday ? .primary : .secondary)
            ZStack {
                switch status {
                case .done?, .shorter?, .extra?:
                    Circle().fill(tint.opacity(strength).gradient)
                    Image(systemName: status == .extra ? "plus" : "checkmark")
                        .font(.caption.weight(.bold)).foregroundStyle(.white)
                case .missed?:
                    Circle().strokeBorder(.secondary.opacity(0.5), lineWidth: 1.5)
                    Image(systemName: "xmark").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                default:
                    if isRun {
                        Circle().fill(tint.opacity((isToday ? 0.45 : 0.25) * strength))
                    } else {
                        Circle().fill(.secondary.opacity(0.35)).frame(width: 7, height: 7)
                    }
                }
                if isToday {
                    Circle().strokeBorder(Color.primary, lineWidth: 2)
                }
            }
            .frame(width: 34, height: 34)
            Text(distanceText)
                .font(.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var distanceText: String {
        if let ran = review?.ranMeters, ran > 0 { return String(format: "%.0f", ran / 1_000) }
        guard isRun, let m = workout?.distanceMeters else { return " " }
        return String(format: "%.0f", m / 1_000)
    }

    private var accessibilityText: String {
        let day = date.formatted(.dateTime.weekday(.wide))
        let what = isRun ? "\(Format.workoutTitle(workout!.type)), \(Format.distance(workout!.distanceMeters))" : "rest"
        let state: String = switch status {
        case .done?, .shorter?: "done"
        case .missed?: "missed"
        case .extra?: "extra run"
        default: isToday ? "today" : ""
        }
        return [day, what, state].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
