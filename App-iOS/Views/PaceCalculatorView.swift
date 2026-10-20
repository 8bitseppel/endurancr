import StoreKit
import SwiftUI
import TrainingCore

/// What the pace calculator was set to, to start a plan from it.
struct PaceCalculatorInputs {
    var effort: RaceDistance
    var effortSeconds: Double
    var goal: RaceDistance
    var raceDate: Date
}

/// Enter a recent race and a goal; see your VDOT, the five training paces, a
/// race-day range and the plan endurancr would build, all from the same TrainingCore
/// engine. The App Clip and the app share it: in the clip Apple's overlay offers the
/// full app, in the app the button starts a plan from these inputs.
struct PaceCalculatorView: View {
    enum Action {
        /// The App Clip: offer the full app.
        case offerApp
        /// The app without a plan: start one from these inputs.
        case createPlan((PaceCalculatorInputs) -> Void)
        /// The app with a plan running: just the numbers.
        case none
    }
    var action: Action = .offerApp

    @State private var effort: RaceDistance = .tenK
    @State private var hours = 0
    @State private var minutes = 54
    @State private var seconds = 0
    @State private var goal: RaceDistance = .marathon
    @State private var raceDate = Calendar.current.date(byAdding: .weekOfYear, value: 24, to: .now) ?? .now
    @State private var showsAppOverlay = false
    /// The overlay comes up on its own once; after that only from the button.
    @State private var hasOfferedApp = false
    @ScaledMetric(relativeTo: .largeTitle) private var vdotSize: CGFloat = 76

    private static let distances: [RaceDistance] = [.fiveK, .tenK, .halfMarathon, .marathon]

    /// Screenshots open on the results without Apple's overlay over them.
    private static var isScreenshot: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-clipResults")
        #else
        false
        #endif
    }
    private let calculator = VDOTCalculator()

    private var timeSeconds: Double { Double(hours * 3600 + minutes * 60 + seconds) }

    /// The plan the app would build from this effort today, `nil` while the inputs
    /// can't make one (no time yet, or race day too close).
    private var plan: TrainingPlan? {
        guard timeSeconds > 0 else { return nil }
        let fitness = FitnessSnapshot(distanceMeters: effort.meters, timeSeconds: timeSeconds, date: .now)
        return try? VDOTPlanGenerator().makePlan(
            goal: Goal(race: goal, raceDate: raceDate, daysPerWeek: 5),
            fitness: fitness, startDate: .now, calendar: .current)
    }

    var body: some View {
        // Worked out once per change of the inputs, not for every use below.
        let plan = self.plan
        return ZStack {
            BrandBackground()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        header
                        inputCard
                        if let plan {
                            results(plan)
                                .id("results")
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                        if isClip { footer }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                    .animation(.smooth, value: plan?.vdot)
                }
                .task {
                    #if DEBUG
                    // `-clipResults` opens on the results, for screenshots.
                    if ProcessInfo.processInfo.arguments.contains("-clipResults") {
                        try? await Task.sleep(for: .milliseconds(300))
                        proxy.scrollTo("results", anchor: .top)
                    }
                    #endif
                }
            }
        }
        .preferredColorScheme(.dark)
        .appStoreOverlay(isPresented: $showsAppOverlay) {
            SKOverlay.AppClipConfiguration(position: .bottom)
        }
    }

    private var isClip: Bool {
        if case .offerApp = action { true } else { false }
    }

    // MARK: Parts

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.run")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .glassEffect(.regular.tint(.accentColor.opacity(0.4)), in: .circle)
                .accessibilityHidden(true)
            Text("What pace should you train at?")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Your paces from one recent race, with the VDOT method of Jack Tupper Daniels.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(.top, 8)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A recent race or all-out run").font(.headline)
            Picker("Distance", selection: $effort) {
                ForEach(Self.distances, id: \.self) { Text(short($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack(spacing: 0) {
                wheel($hours, range: 0..<6, unit: "h", label: "Hours")
                wheel($minutes, range: 0..<60, unit: "min", label: "Minutes")
                wheel($seconds, range: 0..<60, unit: "s", label: "Seconds")
            }
            .frame(height: 110)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Time")

            Divider().overlay(.white.opacity(0.2))

            Text("Your goal").font(.headline)
            Picker("Goal race", selection: $goal) {
                ForEach(Self.distances, id: \.self) { Text(short($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            DatePicker("Race day", selection: $raceDate,
                       in: (Calendar.current.date(byAdding: .day, value: VDOTPlanGenerator.minimumDays, to: .now) ?? .now)...,
                       displayedComponents: .date)
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .foregroundStyle(.white)
    }

    private func results(_ plan: TrainingPlan) -> some View {
        let zones = plan.paceZones
        let buddy = TrainingBuddy().status(plan: plan, completedRuns: [], asOf: .now)
        let outlook = GoalOutlook.make(plan: plan, buddy: buddy, completedRuns: [], asOf: .now)
        return VStack(spacing: 16) {
            // VDOT, big.
            VStack(spacing: 4) {
                Text("Your VDOT").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                Text(plan.vdot, format: .number.precision(.fractionLength(1)))
                    .font(.system(size: vdotSize, weight: .bold, design: .rounded))
                    .contentTransition(.numericText(value: plan.vdot))
                    .monospacedDigit()
                if plan.enduranceHoldback > 0 {
                    Text("Marathon pace uses \(plan.raceVDOT, format: .number.precision(.fractionLength(1))) until your long runs show the endurance.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .glassEffect(.regular.tint(.accentColor.opacity(0.25)), in: .rect(cornerRadius: 26))

            // The five paces.
            GlassEffectContainer(spacing: 10) {
                // A plain Grid: in a lazy one the first row went missing after a jump.
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        paceTile("Easy", zones.easySecPerKm, color: .teal, note: "Most of your running")
                        paceTile("Marathon", zones.marathonSecPerKm, color: .blue, note: "Steady, all day")
                    }
                    GridRow {
                        paceTile("Threshold", zones.thresholdSecPerKm, color: .indigo, note: "Comfortably hard")
                        paceTile("Interval", zones.intervalSecPerKm, color: .purple, note: "Hard, 3 to 5 min")
                    }
                    GridRow {
                        paceTile("Repetition", zones.repetitionSecPerKm, color: .pink, note: "Quick and light")
                        raceTile(outlook)
                    }
                }
            }

            planPreview(plan)

            switch action {
            case .offerApp:
                actionButton("Get the full plan, free", systemImage: "arrow.down.app") {
                    showsAppOverlay = true
                }
                // Offer the app once you've read down to here, not over the results.
                .onScrollVisibilityChange(threshold: 0.8) { visible in
                    if visible, !hasOfferedApp, !Self.isScreenshot {
                        hasOfferedApp = true
                        showsAppOverlay = true
                    }
                }
            case .createPlan(let create):
                actionButton("Create this plan", systemImage: "calendar.badge.plus") {
                    create(PaceCalculatorInputs(effort: effort, effortSeconds: timeSeconds, goal: goal, raceDate: raceDate))
                }
            case .none:
                EmptyView()
            }
        }
        .foregroundStyle(.white)
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glassProminent)
        // The deep purple of the background, so the white title reads clearly.
        .tint(Color(red: 0.42, green: 0.26, blue: 0.70))
        .controlSize(.large)
    }

    private func paceTile(_ title: String, _ secPerKm: Double, color: Color, note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).font(.subheadline.weight(.semibold))
            }
            Text(Format.pace(secPerKm))
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText(value: secPerKm))
            Text(note).font(.caption).foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(.regular.tint(color.opacity(0.18)), in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    private func raceTile(_ outlook: GoalOutlook) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "flag.checkered").font(.caption)
                Text("Race day").font(.subheadline.weight(.semibold))
            }
            Text("\(GoalOutlook.format(outlook.raceDay.lowerBound)) to \(GoalOutlook.format(outlook.raceDay.upperBound))")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text("If you train to the plan").font(.caption).foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(.regular.tint(.green.opacity(0.18)), in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    /// The plan the app would build: its weeks and phases, the longest run, and the
    /// sessions from the books.
    private func planPreview(_ plan: TrainingPlan) -> some View {
        let weeks = plan.weeksToRace
        let longest = plan.allWorkouts.filter { $0.type == .longRun }.map(\.distanceMeters).max() ?? 0
        let marathonPace = plan.allWorkouts.filter { $0.type == .marathonPace || $0.structure?.workType == .marathonPace }.count
        let tuneUp = plan.allWorkouts.first { $0.type == .timeTrial }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Your \(weeks.count)-week plan").font(.headline)
            HStack(spacing: 2) {
                ForEach(weeks, id: \.index) { week in
                    RoundedRectangle(cornerRadius: 2).fill(week.phase.tint).frame(height: 10)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                bullet("arrow.up.right", "Builds to a long run of \(Int((longest / 1_000).rounded())) km")
                if marathonPace > 0 { bullet("metronome", "\(marathonPace) marathon-pace runs and finishes") }
                if let tuneUp, let s = tuneUp.structure {
                    bullet("flag.2.crossed", "A \(Format.distanceCompact(s.workMeters)) tune-up race that sets your paces")
                }
                if isClip {
                    bullet("arrow.triangle.2.circlepath", "Adapts to the runs you really do, like a running buddy")
                    bullet("applewatch", "Records on Apple Watch or iPhone, saved to Apple Health")
                }
            }
            .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Color.accentColor).frame(width: 24)
        }
    }

    private var footer: some View {
        Text("Free, no account, no ads. Your runs stay in Apple Health.")
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.6))
            .multilineTextAlignment(.center)
            .padding(.bottom, 80)   // room for the App Store overlay
    }

    private func wheel(_ value: Binding<Int>, range: Range<Int>, unit: String, label: String) -> some View {
        Picker(label, selection: value) {
            ForEach(range, id: \.self) { Text("\($0) \(unit)").tag($0) }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
    }

    private func short(_ race: RaceDistance) -> String {
        switch race {
        case .fiveK: "5K"
        case .tenK: "10K"
        case .halfMarathon: "Half"
        case .marathon: "Marathon"
        case .custom: race.displayName
        }
    }
}

/// A slow, living gradient in the app's purples and blues.
private struct BrandBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate / 6
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [Float(0.5 + 0.15 * sin(t)), Float(0.45 + 0.12 * cos(t * 0.8))], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: [
                    .black, Color(red: 0.16, green: 0.08, blue: 0.32), .black,
                    Color(red: 0.10, green: 0.12, blue: 0.36), Color(red: 0.42, green: 0.26, blue: 0.70), Color(red: 0.06, green: 0.22, blue: 0.34),
                    .black, Color(red: 0.12, green: 0.06, blue: 0.24), .black,
                ]
            )
        }
        .ignoresSafeArea()
    }
}
