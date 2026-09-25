import SwiftUI
import TrainingCore

/// The whole app, distilled to one screen: today's training as a coach card.
///
/// A quiet header carries the only "dashboard" you need (race, countdown, week);
/// the card names today's session with a warm coaching note and one big Start.
/// Everything analytical (charts, VDOT, adherence) and every setting lives one tap
/// away behind the toolbar menu, so the front stays about the run you do today.
struct CoachView: View {
    let coordinator: PlanCoordinator
    @State private var recorder = PhoneWorkoutManager()
    @State private var showLiveRun = false
    @State private var showingGoalEditor = false
    @State private var showingProgress = false
    @State private var showingWeek = false
    @State private var showingHowItWorks = false
    @State private var showingDataManagement = false

    var body: some View {
        NavigationStack {
            Group {
                if let plan = coordinator.displayPlan, let progress = coordinator.progress {
                    plannedContent(plan: plan, progress: progress)
                } else {
                    emptyState
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarMenu }
            .navigationDestination(isPresented: $showLiveRun) {
                PhoneLiveRunView(recorder: recorder)
            }
            .sheet(isPresented: $showingGoalEditor) { GoalEditorView(coordinator: coordinator) }
            .sheet(isPresented: $showingProgress) { ProgressDashboardView(coordinator: coordinator) }
            .sheet(isPresented: $showingWeek) { CalendarView(coordinator: coordinator) }
            .sheet(isPresented: $showingHowItWorks) { NavigationStack { HowItWorksView() } }
            .sheet(isPresented: $showingDataManagement) {
                NavigationStack { DataManagementView(coordinator: coordinator) }
            }
        }
    }

    // MARK: Planned content

    @ViewBuilder
    private func plannedContent(plan: TrainingPlan, progress: PlanProgress) -> some View {
        let today = coordinator.workout()
        ScrollView {
            VStack(spacing: 28) {
                header(plan: plan, progress: progress)
                todayCard(today)
                if let today, today.type != .rest {
                    startButton(plan: plan, workout: today)
                }
                Button {
                    showingWeek = true
                } label: {
                    Text("·  peek at the week  ·")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await coordinator.refreshAdaptation() }
    }

    private func header(plan: TrainingPlan, progress: PlanProgress) -> some View {
        VStack(spacing: 4) {
            Text(plan.goal.displayName)
                .font(.headline)
            Text(headerSubtitle(progress))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }

    private func headerSubtitle(_ progress: PlanProgress) -> String {
        let days = progress.daysUntilRace == 0 ? "Race day" : "\(progress.daysUntilRace) days to go"
        if let week = progress.currentWeekNumber {
            return "\(days) · Week \(week) of \(progress.totalWeeks)"
        }
        return days
    }

    private func todayCard(_ workout: PlannedWorkout?) -> some View {
        VStack(spacing: 12) {
            Text("Today")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                Text(Format.workoutTitle(workout?.type ?? .rest))
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                if let workout, workout.type != .rest {
                    Text(Format.distance(workout.distanceMeters))
                        .font(.title2)
                    if let pace = workout.targetPaceSecPerKm {
                        Text(Format.paceRange(pace))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(coachingNote(for: workout))
                    .font(.callout)
                    .italic()
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private func startButton(plan: TrainingPlan, workout: PlannedWorkout) -> some View {
        Button {
            recorder.start(
                goalName: plan.goal.displayName,
                workoutTitle: Format.workoutTitle(workout.type),
                targetPace: workout.targetPaceSecPerKm,
                plannedWorkout: workout.type == .rest ? nil : workout,
                zones: plan.paceZones
            )
            showLiveRun = true
        } label: {
            Label("Start run", systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    /// A warm, human line for today's session — the workout's own note (e.g. an
    /// eased or rescheduled session, or a vacation label) when it has one,
    /// otherwise a friendly default for the type.
    private func coachingNote(for workout: PlannedWorkout?) -> String {
        if let notes = workout?.notes, !notes.isEmpty { return notes }
        switch workout?.type ?? .rest {
        case .rest: return "Rest is training too, so let today's work sink in."
        case .easy: return "Keep it easy, and you should be able to hold a conversation."
        case .longRun: return "Settle in. Steady and relaxed; time on your feet is the point."
        case .marathonPace: return "Lock into goal pace and let it feel like second nature."
        case .threshold: return "Comfortably hard, controlled, never a race."
        case .interval: return "Strong, focused reps. Recover fully between them."
        case .repetitionSpeed: return "Quick and light, short and sharp."
        case .raceDay: return "This is the one. Trust your training and enjoy it."
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Ready when you are", systemImage: "flag.checkered")
        } description: {
            Text("Pick a race goal and endurancr hands you one training a day, all the way to the start line.")
        } actions: {
            Button("Set your goal") { showingGoalEditor = true }
                .buttonStyle(.borderedProminent)
            Button("Import a backup") { showingDataManagement = true }
        }
    }

    // MARK: Menu

    @ToolbarContentBuilder
    private var toolbarMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    showingProgress = true
                } label: {
                    Label("Progress & stats", systemImage: "chart.line.uptrend.xyaxis")
                }
                Button {
                    showingWeek = true
                } label: {
                    Label("Full plan", systemImage: "calendar")
                }
                Divider()
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
                Button {
                    showingHowItWorks = true
                } label: {
                    Label("How it works", systemImage: "book")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}
