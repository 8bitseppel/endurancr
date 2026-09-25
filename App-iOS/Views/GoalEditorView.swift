import SwiftUI
import TrainingCore

/// Editable goal form — the onboarding form reused for editing. Pre-fills from the
/// current goal when one exists; on save it (re)generates the plan and re-applies
/// adaptation. Used both to set the first goal and to edit an existing one.
struct GoalEditorView: View {
    let coordinator: PlanCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var raceKind: RaceKind
    @State private var raceDate: Date
    @State private var startDate: Date
    @State private var daysPerWeek: Int
    @State private var restWeekdays: Set<Int>
    @State private var skipHolidays: Bool

    @State private var hasTarget: Bool
    @State private var targetHours: Int
    @State private var targetMinutes: Int
    @State private var targetSeconds: Int

    // Recent effort used to estimate fitness (VDOT). Either typed in via the
    // pickers below, or pulled from a real HealthKit run (`healthRun`), which wins
    // when set because it carries the run's exact distance and time.
    @State private var recentKind: RaceKind
    @State private var recentMinutes: Int
    @State private var recentSeconds: Int
    @State private var healthRun: CompletedRun?
    @State private var showingPickHealthRun = false

    @State private var draftPeriods: [UnavailablePeriod]
    @State private var showingAddVacation = false
    @State private var error: String?
    @State private var showReplaceConfirm = false
    @State private var showDeleteConfirm = false

    /// Which date row currently has its inline calendar expanded (nil = none).
    /// Selecting a day collapses it and, for the start date, jumps to race day.
    @State private var editingDate: DateField?
    enum DateField { case start, race }

    /// Focus for the goal-name field, so a keyboard "Done" button can dismiss it.
    @FocusState private var nameFocused: Bool

    enum RaceKind: String, CaseIterable, Identifiable {
        case fiveK = "5K", tenK = "10K", half = "Half", marathon = "Marathon"
        var id: String { rawValue }
        var distance: RaceDistance {
            switch self {
            case .fiveK: return .fiveK
            case .tenK: return .tenK
            case .half: return .halfMarathon
            case .marathon: return .marathon
            }
        }
        init(distance: RaceDistance) {
            switch distance {
            case .fiveK: self = .fiveK
            case .tenK: self = .tenK
            case .halfMarathon: self = .half
            default: self = .marathon
            }
        }
        /// Best-effort mapping of a stored fitness distance back to a picker choice.
        init(meters: Double?) {
            switch meters {
            case .some(let m) where m == RaceDistance.fiveK.meters: self = .fiveK
            case .some(let m) where m == RaceDistance.halfMarathon.meters: self = .half
            case .some(let m) where m == RaceDistance.marathon.meters: self = .marathon
            default: self = .tenK
            }
        }
    }

    init(coordinator: PlanCoordinator) {
        self.coordinator = coordinator
        let inputs = coordinator.inputs ?? DemoMode.goalPrefill
        let goal = inputs?.goal
        let fitness = inputs?.fitness

        _name = State(initialValue: goal?.name ?? "")
        _raceKind = State(initialValue: RaceKind(distance: goal?.race ?? .marathon))
        _raceDate = State(initialValue: goal?.raceDate
            ?? Calendar.current.date(byAdding: .month, value: 6, to: .now) ?? .now)
        _startDate = State(initialValue: inputs?.startDate
            ?? Calendar.current.startOfDay(for: .now))
        _daysPerWeek = State(initialValue: goal?.daysPerWeek ?? 5)
        _restWeekdays = State(initialValue: goal?.restWeekdays ?? [])
        _skipHolidays = State(initialValue: goal?.skipHolidays ?? true)

        let target = Int(goal?.targetTimeSeconds ?? 0)
        _hasTarget = State(initialValue: goal?.targetTimeSeconds != nil)
        _targetHours = State(initialValue: target / 3600)
        _targetMinutes = State(initialValue: (target % 3600) / 60)
        _targetSeconds = State(initialValue: target % 60)

        _recentKind = State(initialValue: RaceKind(meters: fitness?.distanceMeters))
        let ft = Int(fitness?.timeSeconds ?? 50 * 60)
        _recentMinutes = State(initialValue: ft / 60)
        _recentSeconds = State(initialValue: ft % 60)

        // A stored fitness estimate carries a run's *exact* distance and time. The
        // manual pickers can only express the four standard race distances, so a
        // non-preset distance (e.g. a 12 km Health run) would otherwise reopen as the
        // nearest preset (10 km) and be silently downgraded on the next save. Restore
        // it as a "recent run" so the exact figures show and survive a re-save.
        if let fitness, !Self.isPresetDistance(fitness.distanceMeters) {
            _healthRun = State(initialValue: CompletedRun(
                date: fitness.date, distanceMeters: fitness.distanceMeters, durationSeconds: fitness.timeSeconds
            ))
        } else {
            _healthRun = State(initialValue: nil)
        }

        _draftPeriods = State(initialValue: goal?.unavailablePeriods ?? [])
    }

    /// Whether `meters` is exactly one of the four race presets the manual distance
    /// picker can express. A non-preset distance only comes from a real recorded run.
    private static func isPresetDistance(_ meters: Double) -> Bool {
        [RaceDistance.fiveK, .tenK, .halfMarathon, .marathon].contains { $0.meters == meters }
    }

    private var isEditing: Bool { coordinator.inputs != nil }
    private var allowedDays: Int { 7 - restWeekdays.count }
    private var recentTotalSeconds: Int { recentMinutes * 60 + recentSeconds }
    private var hasRecentEffort: Bool { healthRun != nil || recentTotalSeconds > 0 }
    private var canSave: Bool { daysPerWeek <= allowedDays && allowedDays >= 3 && hasRecentEffort }

    var body: some View {
        NavigationStack {
            Form {
                goalSection
                restDaysSection
                targetSection
                recentEffortSection
                vacationSection
                if isEditing {
                    Section {
                        Button("Delete goal", role: .destructive) { showDeleteConfirm = true }
                            .frame(maxWidth: .infinity)
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(isEditing ? "Edit Goal" : "New Plan")
            .navigationBarTitleDisplayMode(.inline)
            .demoAutoScroll()
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if isEditing { showReplaceConfirm = true } else { save() }
                    }
                    .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { nameFocused = false }
                }
            }
            .confirmationDialog(
                "Replace your current plan?",
                isPresented: $showReplaceConfirm, titleVisibility: .visible
            ) {
                Button("Replace plan", role: .destructive) { save() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This rebuilds your training plan from the updated goal and rules. Recorded runs stay in Health.")
            }
            .confirmationDialog(
                "Delete this goal?",
                isPresented: $showDeleteConfirm, titleVisibility: .visible
            ) {
                Button("Delete goal", role: .destructive) {
                    coordinator.deletePlan()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes your plan and training rules. Recorded runs stay in Apple Health.")
            }
            // Pushed within this editor's own navigation stack rather than a
            // sheet-over-a-sheet (which dismisses the editor on some iOS versions).
            .navigationDestination(isPresented: $showingPickHealthRun) {
                PickHealthRunView(coordinator: coordinator) { healthRun = $0 }
            }
            // Same reason as above: pushed rather than presented as a sheet on top
            // of this editor's own sheet, which collapsed the whole stack back to
            // the "Set your goal" screen on some iOS versions.
            .navigationDestination(isPresented: $showingAddVacation) {
                AddDraftVacationView { draftPeriods.append($0) }
            }
        }
    }

    // MARK: Sections

    private var goalSection: some View {
        Section {
            TextField("Goal name", text: $name)
                .focused($nameFocused)
                .submitLabel(.done)
                .onSubmit { nameFocused = false }
            Picker("Race", selection: $raceKind) {
                ForEach(RaceKind.allCases) { Text($0.rawValue).tag($0) }
            }
            dateRow("Start training", date: startDate, field: .start)
            if editingDate == .start {
                DatePicker("Start training", selection: $startDate, in: ...raceDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .onChange(of: startDate) {
                        // A day was tapped — collapse and jump straight to race day.
                        withAnimation { editingDate = .race }
                    }
            }
            dateRow("Race day", date: raceDate, field: .race)
            if editingDate == .race {
                DatePicker("Race day", selection: $raceDate, in: startDate..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .onChange(of: raceDate) {
                        withAnimation { editingDate = nil }
                    }
            }
            Stepper("Run \(daysPerWeek) days/week", value: $daysPerWeek, in: 3...max(3, min(6, allowedDays)))
        } header: {
            Text("Your goal")
        } footer: {
            Text("Name it whatever you like (e.g. \"Hamburg Marathon\"). Training starts on the start date, so pick a future day to begin later. Race day must be at least \(VDOTPlanGenerator.minimumDays) days (two weeks) after your start so there's room to build a proper plan.")
        }
    }

    private var restDaysSection: some View {
        Section {
            let symbols = Calendar.current.shortWeekdaySymbols  // index 0 = Sunday
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    let weekday = i + 1  // Calendar weekday (1 = Sun … 7 = Sat)
                    let blocked = restWeekdays.contains(weekday)
                    Button {
                        toggleRestDay(weekday)
                    } label: {
                        Text(symbols[i].prefix(2))
                            .font(.caption).fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(blocked ? Color.accentColor : Color(.secondarySystemBackground))
                            .foregroundStyle(blocked ? .white : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)

            Toggle("Skip Christmas & New Year", isOn: $skipHolidays)
        } header: {
            Text("Days you don't want to train")
        } footer: {
            if allowedDays < 3 {
                Text("Leave at least 3 days open to run.").foregroundStyle(.red)
            } else {
                Text("Tap weekdays you'll never run. At most \(allowedDays) running days/week. Skipping the holidays blanks Dec 24 to 26 and Dec 31 to Jan 1 wherever your plan crosses them.")
            }
        }
    }

    private var targetSection: some View {
        Section {
            Toggle("Set a target time", isOn: $hasTarget)
            if hasTarget {
                HStack {
                    Text("Target")
                    Spacer()
                    Picker("h", selection: $targetHours) {
                        ForEach(0..<10) { Text("\($0)h").tag($0) }
                    }.labelsHidden()
                    Picker("m", selection: $targetMinutes) {
                        ForEach(0..<60) { Text(String(format: "%02dm", $0)).tag($0) }
                    }.labelsHidden()
                    Picker("s", selection: $targetSeconds) {
                        ForEach(0..<60) { Text(String(format: "%02ds", $0)).tag($0) }
                    }.labelsHidden()
                }
            }
        } header: {
            Text("Target time (optional)")
        } footer: {
            Text("Nudges race-day pace toward your goal. Leave off to pace purely from current fitness.")
        }
    }

    private var recentEffortSection: some View {
        Section {
            Text("A recent race or hard run, used to set your training paces.")
                .font(.footnote).foregroundStyle(.secondary)

            if let run = healthRun {
                LabeledContent("From Health") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(Format.distance(run.distanceMeters)) · \(Format.duration(run.durationSeconds))")
                            .fontWeight(.semibold)
                        Text("\(Format.pace(run.averagePaceSecPerKm)) · \(run.date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("Enter time manually instead") { healthRun = nil }
            } else {
                Picker("Distance", selection: $recentKind) {
                    ForEach(RaceKind.allCases) { Text($0.rawValue).tag($0) }
                }
                HStack {
                    Text("Time")
                    Spacer()
                    Picker("min", selection: $recentMinutes) {
                        ForEach(0..<300) { Text("\($0) min").tag($0) }
                    }.labelsHidden()
                    Picker("sec", selection: $recentSeconds) {
                        ForEach(0..<60) { Text(String(format: "%02d sec", $0)).tag($0) }
                    }.labelsHidden()
                }
                if HealthKitService.isAvailable {
                    Button {
                        showingPickHealthRun = true
                    } label: {
                        Label("Use a recent run from Health", systemImage: "heart.text.square")
                    }
                }
            }
        } header: {
            Text("Recent effort")
        }
    }

    private var vacationSection: some View {
        Section {
            ForEach(draftPeriods.sorted { $0.start < $1.start }) { period in
                VStack(alignment: .leading, spacing: 2) {
                    Text(period.reason.isEmpty ? "Unavailable" : period.reason)
                    Text("\(period.start.formatted(date: .abbreviated, time: .omitted)) to \(period.end.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .onDelete { offsets in
                let sorted = draftPeriods.sorted { $0.start < $1.start }
                let ids = Set(offsets.map { sorted[$0].id })
                draftPeriods.removeAll { ids.contains($0.id) }
            }
            Button {
                showingAddVacation = true
            } label: {
                Label("Add time off", systemImage: "plus")
            }
        } header: {
            Text("Vacation & time off")
        } footer: {
            Text("Optional. Block out trips or breaks. You can change these anytime later. Rest weekdays above repeat every week.")
        }
    }

    /// A tappable date row that expands/collapses its inline calendar. Tapping the
    /// row toggles editing for that field (and closes any other open calendar).
    private func dateRow(_ label: String, date: Date, field: DateField) -> some View {
        Button {
            withAnimation { editingDate = (editingDate == field) ? nil : field }
        } label: {
            HStack {
                Text(label).foregroundStyle(.primary)
                Spacer()
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(editingDate == field ? Color.accentColor : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func toggleRestDay(_ weekday: Int) {
        if restWeekdays.contains(weekday) {
            restWeekdays.remove(weekday)
        } else {
            restWeekdays.insert(weekday)
        }
        // Keep running days within what the rules leave free.
        if daysPerWeek > allowedDays { daysPerWeek = max(3, allowedDays) }
    }

    private func save() {
        error = nil
        let target = Double(targetHours * 3600 + targetMinutes * 60 + targetSeconds)
        let goal = Goal(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            race: raceKind.distance,
            raceDate: raceDate,
            targetTimeSeconds: hasTarget && target > 0 ? target : nil,
            daysPerWeek: daysPerWeek,
            restWeekdays: restWeekdays,
            unavailablePeriods: draftPeriods,
            skipHolidays: skipHolidays
        )
        // A chosen HealthKit run wins — it carries the run's exact distance, time,
        // and date; otherwise fall back to the manually entered preset + time.
        let fitness: FitnessSnapshot
        if let run = healthRun {
            fitness = FitnessSnapshot(
                distanceMeters: run.distanceMeters,
                timeSeconds: run.durationSeconds,
                date: run.date
            )
        } else {
            fitness = FitnessSnapshot(
                distanceMeters: recentKind.distance.meters,
                timeSeconds: Double(recentTotalSeconds),
                date: .now
            )
        }
        do {
            if isEditing {
                try coordinator.update(goal: goal, fitness: fitness, startDate: startDate)
            } else {
                try coordinator.createPlan(goal: goal, fitness: fitness, startDate: startDate)
            }
            dismiss()
            Task { await coordinator.recalculate() }
        } catch let PlanError.raceTooSoon(days, minimum) {
            error = "Only \(days) days between your start and race, but you need at least \(minimum). Move your start earlier or the race later."
        } catch let PlanError.daysPerWeekExceedsAvailable(requested, available) {
            error = "You blocked \(7 - available) days, so at most \(available) running days/week (you picked \(requested))."
        } catch {
            self.error = "Couldn't build a plan: \(error.localizedDescription)"
        }
    }
}

/// Lets the user pick one of their recent HealthKit runs to seed the fitness
/// estimate, instead of typing a distance and time. Runs are read on-device via
/// `PlanCoordinator.recentHealthRuns()`; the strongest (highest-VDOT) run is
/// flagged as the best estimate. Reports the chosen run back via a closure.
private struct PickHealthRunView: View {
    let coordinator: PlanCoordinator
    let onPick: (CompletedRun) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var runs: [CompletedRun] = []
    @State private var loading = true
    private let calculator = VDOTCalculator()

    /// The id of the highest-VDOT run — the best single-run fitness estimate.
    private var bestRunID: CompletedRun.ID? {
        runs.max {
            calculator.vdot(distanceMeters: $0.distanceMeters, timeSeconds: $0.durationSeconds)
                < calculator.vdot(distanceMeters: $1.distanceMeters, timeSeconds: $1.durationSeconds)
        }?.id
    }

    var body: some View {
        Group {
            if loading {
                ProgressView("Reading Health…")
            } else if runs.isEmpty {
                ContentUnavailableView(
                    "No recent runs",
                    systemImage: "figure.run",
                    description: Text("No running workouts in the last few months. Record a run, or enter a time manually.")
                )
            } else {
                List(runs) { run in
                    Button {
                        onPick(run)
                        dismiss()
                    } label: {
                        runRow(run)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Recent runs")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            runs = await coordinator.recentHealthRuns()
            loading = false
        }
    }

    private func runRow(_ run: CompletedRun) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(Format.distance(run.distanceMeters)) · \(Format.duration(run.durationSeconds))")
                        .fontWeight(.semibold)
                    if run.id == bestRunID {
                        Text("Best estimate")
                            .font(.caption2).fontWeight(.semibold)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                Text("\(Format.pace(run.averagePaceSecPerKm)) · \(run.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

/// Lightweight add-a-period sheet that reports the new period back via a closure,
/// so it works during plan creation (before any plan is stored) as well as editing.
private struct AddDraftVacationView: View {
    let onAdd: (UnavailablePeriod) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reason = "Vacation"
    @State private var start = Date.now
    @State private var end = Calendar.current.date(byAdding: .day, value: 6, to: .now) ?? .now

    @State private var editingDate: EditingDate?
    enum EditingDate { case from, to }

    @FocusState private var reasonFocused: Bool

    var body: some View {
        Form {
            Section("Reason") {
                TextField("e.g. Vacation, work trip", text: $reason)
                    .focused($reasonFocused)
                    .submitLabel(.done)
                    .onSubmit { reasonFocused = false }
            }
            Section("Dates") {
                dateRow("From", date: start, field: .from)
                if editingDate == .from {
                    DatePicker("From", selection: $start, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .onChange(of: start) {
                            // A day was tapped — collapse and jump straight to the end date.
                            withAnimation { editingDate = .to }
                        }
                }
                dateRow("To", date: end, field: .to)
                if editingDate == .to {
                    DatePicker("To", selection: $end, in: start..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .onChange(of: end) {
                            withAnimation { editingDate = nil }
                        }
                }
            }
        }
        .navigationTitle("Add Time Off")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { reasonFocused = false }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    let label = reason.trimmingCharacters(in: .whitespaces)
                    let (lo, hi) = start <= end ? (start, end) : (end, start)
                    onAdd(UnavailablePeriod(start: lo, end: hi, reason: label.isEmpty ? "Unavailable" : label))
                    dismiss()
                }
            }
        }
    }

    private func dateRow(_ label: String, date: Date, field: EditingDate) -> some View {
        Button {
            withAnimation { editingDate = (editingDate == field) ? nil : field }
        } label: {
            HStack {
                Text(label).foregroundStyle(.primary)
                Spacer()
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(editingDate == field ? Color.accentColor : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
