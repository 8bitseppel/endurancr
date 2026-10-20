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
    @State private var showLiveRun = false
    @State private var runSummary: RunSummaryData?
    @State private var showingGoalEditor = false
    @State private var showingDataManagement = false
    @State private var showDeleteConfirm = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if let workout = coordinator.workout() {
                        todayCard(workout)
                    } else {
                        ContentUnavailableView("Nothing scheduled today", systemImage: "checkmark.circle")
                            .brandCard()
                    }
                    startButton
                    if let plan = coordinator.displayPlan {
                        weekStrip(plan)
                        if let next = nextRun(plan) { nextRunCard(next) }
                    }
                    if let buddy = coordinator.buddy, !buddy.message.isEmpty {
                        Label {
                            Text(buddy.message).font(.subheadline)
                        } icon: {
                            Image(systemName: buddy.phase.symbol).foregroundStyle(.tint)
                        }
                        .brandCard()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background { BrandBackground() }
            .navigationBarTitleDisplayMode(.inline)
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
                PhoneLiveRunView(recorder: recorder)
            }
            .onChange(of: recorder.saveState) { _, state in
                // A run finished (here, on another tab or from the Live Activity) and
                // Health has it, or refused it. Snapshot what was just run, re-adapt
                // from Health, then show a summary with where the week now stands.
                guard state == .saved || state == .failed,
                      recorder.distanceMeters >= Self.minSummaryDistanceMeters else { return }
                let distance = recorder.distanceMeters
                let duration = recorder.elapsedSeconds
                let saved = state == .saved
                // Week completed before this run. HealthKit's save is async and may not
                // be visible to the re-fetch yet, so never show less than this.
                let priorWeek = coordinator.progress?.currentWeekCompletedMeters ?? 0
                Task {
                    await coordinator.refreshAdaptation()
                    let p = coordinator.progress
                    let weekCompleted = max(p?.currentWeekCompletedMeters ?? 0, priorWeek + distance)
                    runSummary = RunSummaryData(
                        distanceMeters: distance,
                        durationSeconds: duration,
                        saved: saved,
                        weekNumber: p?.currentWeekNumber,
                        weekCompletedMeters: weekCompleted,
                        weekTargetMeters: p?.currentWeekPlannedMeters ?? 0
                    )
                }
            }
            .sheet(item: $runSummary) { RunSummaryView(data: $0) }
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

    /// Today's run, big, in its colour.
    private func todayCard(_ workout: PlannedWorkout) -> some View {
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
        }
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
