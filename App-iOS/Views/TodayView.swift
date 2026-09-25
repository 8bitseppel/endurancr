import SwiftUI
import TrainingCore

/// The workout scheduled for today, with target paces and a prompt to record on Watch.
struct TodayView: View {
    /// Runs shorter than this don't warrant a post-run summary (stationary tests,
    /// accidental start/finish). 100 m is below any real run yet above GPS jitter.
    /// Kept in step with the watch's `WatchTodayView`.
    private static let minSummaryDistanceMeters: Double = 100

    let coordinator: PlanCoordinator
    @State private var recorder = PhoneWorkoutManager()
    @State private var showLiveRun = false
    @State private var runSummary: RunSummaryData?
    @State private var showingGoalEditor = false
    @State private var showingDataManagement = false
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            List {
                if let workout = coordinator.workout() {
                    Section("Today · \(Format.workoutTitle(workout.type))") {
                        if workout.type == .rest {
                            Label(
                                workout.notes.isEmpty ? "Rest day. Recover well." : workout.notes,
                                systemImage: Format.restSymbol(note: workout.notes)
                            )
                        } else {
                            LabeledContent("Distance", value: Format.distance(workout.distanceMeters))
                            LabeledContent("Target pace", value: Format.paceRange(workout.targetPaceSecPerKm))
                            if let time = Format.estimatedDuration(distanceMeters: workout.distanceMeters, pace: workout.targetPaceSecPerKm) {
                                LabeledContent("Est. time", value: "~\(time)")
                            }
                            if !workout.notes.isEmpty {
                                Text(workout.notes).font(.callout).foregroundStyle(.secondary)
                            }
                            if let structure = workout.structure, let zones = coordinator.displayPlan?.paceZones {
                                WorkoutStepsView(structure: structure, zones: zones)
                                    .padding(.top, 2)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("Nothing scheduled today", systemImage: "checkmark.circle")
                }

                // Record a run on the iPhone itself (GPS), available any day. Starting
                // on an Apple Watch instead adds heart rate.
                Section {
                    Button {
                        let today = coordinator.workout()
                        recorder.start(
                            goalName: coordinator.currentPlan?.goal.displayName ?? "",
                            workoutTitle: today.map { Format.workoutTitle($0.type) } ?? "Run",
                            targetPace: today?.targetPaceSecPerKm,
                            plannedWorkout: today?.type == .rest ? nil : today,
                            zones: coordinator.currentPlan?.paceZones
                        )
                        showLiveRun = true
                    } label: {
                        Label("Start run", systemImage: "figure.run")
                    }
                } footer: {
                    Text("Records on iPhone with GPS. Start on your Apple Watch instead to include heart rate.")
                }

                if let goal = coordinator.currentPlan?.goal {
                    Section(goal.displayName) {
                        LabeledContent("Race", value: goal.race.displayName)
                        LabeledContent("Date", value: goal.raceDate.formatted(date: .abbreviated, time: .omitted))
                        LabeledContent("Days to go", value: "\(daysToGo(goal.raceDate))")
                    }
                }
            }
            .navigationTitle("Today")
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
            .onChange(of: showLiveRun) { wasShowing, showing in
                // The run screen closed after a finish (here or from the Live Activity).
                // Snapshot what was just run, re-adapt from Health, then show a summary
                // with where the week now stands.
                guard wasShowing, !showing, recorder.distanceMeters >= Self.minSummaryDistanceMeters else { return }
                let distance = recorder.distanceMeters
                let duration = recorder.elapsedSeconds
                let saved = recorder.lastError == nil
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

    private func daysToGo(_ date: Date) -> Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: date)
        ).day
        return max(0, days ?? 0)
    }
}
