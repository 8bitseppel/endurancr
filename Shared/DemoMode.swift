import Foundation
import SwiftData
import SwiftUI
import TrainingCore

/// Sample data for Simulator screenshots, switched on with the `-demo` launch
/// argument in Debug builds only. It seeds a marathon plan six weeks in, answers
/// HealthKit queries with runs that follow that plan, and skips the Health
/// permission sheet. Release builds compile it out, so it can't reach TestFlight.
///
/// `-demoScreen <name>` opens a specific screen: `welcome` (no goal yet), `goal`
/// (the goal form, filled in), `run` (live run), `summary` (post-run summary),
/// `progress` or `plan` (iPhone tabs). `-demoScroll YES` slowly scrolls the
/// screen down and back up, for recording.
enum DemoMode {
    static var isOn: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-demo")
        #else
        false
        #endif
    }

    static var screen: String? {
        guard isOn else { return nil }
        return UserDefaults.standard.string(forKey: "demoScreen")
    }

    /// The welcome and goal screens start before any plan exists.
    static var seedsPlan: Bool { screen != "welcome" && screen != "goal" }

    /// Values the goal form opens with on the `goal` screen.
    static var goalPrefill: PlanInputs? { screen == "goal" ? inputs : nil }

    static var inputs: PlanInputs {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        // Monday six weeks ago, so week 1 is a full week.
        let thisMonday = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        let start = calendar.date(byAdding: .day, value: -42, to: thisMonday)!
        let race = calendar.date(byAdding: .day, value: 160, to: today)!
        let goal = Goal(
            name: "Hamburg Marathon",
            race: .marathon,
            raceDate: race,
            targetTimeSeconds: 3 * 3600 + 45 * 60,
            daysPerWeek: 5,
            restWeekdays: [2]
        )
        // A 10K in 49:30 about two months ago.
        let fitness = FitnessSnapshot(
            distanceMeters: 10_000,
            timeSeconds: 49 * 60 + 30,
            date: calendar.date(byAdding: .day, value: -60, to: today)!
        )
        return PlanInputs(goal: goal, fitness: fitness, startDate: start)
    }

    static var plan: TrainingPlan? {
        let inputs = inputs
        return try? VDOTPlanGenerator().makePlan(
            goal: inputs.goal, fitness: inputs.fitness,
            startDate: inputs.startDate, calendar: .current
        )
    }

    /// Today's planned session, for the live run screens.
    static var todaysWorkout: PlannedWorkout? {
        plan?.allWorkouts.first { Calendar.current.isDateInToday($0.date) && $0.type != .rest }
    }

    /// Today's run as finished, for the summary screens: distance, time, week
    /// number, and the week's distance so far (including this run) and target.
    static var finishedRun: (meters: Double, seconds: Double, week: Int, weekDone: Double, weekTarget: Double) {
        let week = plan?.weeks.last { $0.startDate <= .now }
        let meters = (todaysWorkout?.distanceMeters ?? 10_000) * 0.985
        let pace = todaysWorkout?.targetPaceSecPerKm.map { ($0.lowerBound + $0.upperBound) / 2 } ?? 350
        let before = runs
            .filter { run in week.map { run.date >= $0.startDate } ?? false }
            .reduce(0) { $0 + $1.distanceMeters }
        return (meters, meters / 1_000 * pace, (week?.index ?? 0) + 1,
                before + meters, week?.plannedVolumeMeters ?? 0)
    }

    /// Runs that followed the plan up to yesterday, a little off here and there.
    /// A few easy runs are skipped; long runs never are, since the app would
    /// move a missed one into this week.
    static var runs: [CompletedRun] {
        guard let plan else { return [] }
        let today = Calendar.current.startOfDay(for: .now)
        return plan.allWorkouts.enumerated().compactMap { index, workout in
            let skipped = workout.type == .easy && index % 9 == 4
            guard workout.type != .rest, workout.date < today, !skipped else { return nil }
            let pace = workout.targetPaceSecPerKm.map { ($0.lowerBound + $0.upperBound) / 2 } ?? 330
            let distance = workout.distanceMeters * (index % 3 == 0 ? 1.02 : 0.99)
            return CompletedRun(
                date: workout.date.addingTimeInterval(7 * 3600),
                distanceMeters: distance,
                durationSeconds: distance / 1_000 * pace,
                averageHeartRate: 138 + Double(index % 5) * 3
            )
        }
    }

    /// Replaces whatever plan is stored with the demo plan.
    @MainActor
    static func seed(_ container: ModelContainer) {
        guard isOn else { return }
        let context = container.mainContext
        try? context.delete(model: StoredPlan.self)
        if seedsPlan { context.insert(StoredPlan(inputs: inputs)) }
        try? context.save()
    }
}

extension View {
    /// With `-demoScroll YES`, scrolls slowly to the bottom and back to the top
    /// once, so a screen recording shows everything on a long screen.
    func demoAutoScroll() -> some View {
        #if DEBUG
        modifier(DemoAutoScroll())
        #else
        self
        #endif
    }
}

#if DEBUG
private struct DemoAutoScroll: ViewModifier {
    @State private var position = ScrollPosition(edge: .top)
    @State private var top: CGFloat = 0
    @State private var bottom: CGFloat = 0

    func body(content: Content) -> some View {
        if DemoMode.isOn, UserDefaults.standard.bool(forKey: "demoScroll") {
            #if os(iOS)
            // Lists and Forms ignore scrollPosition, so drive UIKit directly.
            content.background(UIKitScroller())
            #else
            content
                .scrollPosition($position)
                .onScrollGeometryChange(for: [CGFloat].self) { geometry in
                    [-geometry.contentInsets.top,
                     geometry.contentSize.height + geometry.contentInsets.bottom - geometry.containerSize.height]
                } action: { _, bounds in
                    top = bounds[0]
                    bottom = max(bounds[0], bounds[1])
                }
                .task {
                    await DemoAutoScroll.run { y in position.scrollTo(y: y) } bounds: { (top, bottom) }
                }
            #endif
        } else {
            content
        }
    }

    /// Waits, glides to the bottom, pauses, and glides back to the top.
    @MainActor
    static func run(scroll: (CGFloat) -> Void, bounds: () -> (CGFloat, CGFloat)) async {
        try? await Task.sleep(for: .seconds(3.5))
        let (top, bottom) = bounds()
        await glide(from: top, to: bottom, seconds: 5, scroll: scroll)
        try? await Task.sleep(for: .seconds(1.5))
        await glide(from: bottom, to: top, seconds: 3, scroll: scroll)
    }

    /// Moves the offset about every frame with an ease in and out. The position
    /// comes from the clock, not a step count, so a late frame doesn't stutter.
    @MainActor
    private static func glide(from start: CGFloat, to end: CGFloat, seconds: Double, scroll: (CGFloat) -> Void) async {
        let clock = ContinuousClock()
        let began = clock.now
        var t = 0.0
        while t < 1 {
            let elapsed = began.duration(to: clock.now)
            let done = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            t = min(1, done / seconds)
            let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            scroll(start + (end - start) * eased)
            try? await Task.sleep(for: .milliseconds(8))
        }
    }
}

#if os(iOS)
/// Finds the tallest scroll view on screen and scrolls it.
private struct UIKitScroller: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.5))
            guard let scrollView = view.window.flatMap(Self.mainScrollView) else { return }
            await DemoAutoScroll.run { y in
                scrollView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
            } bounds: {
                let inset = scrollView.adjustedContentInset
                let bottom = scrollView.contentSize.height + inset.bottom - scrollView.bounds.height
                return (-inset.top, max(-inset.top, bottom))
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private static func mainScrollView(in root: UIView) -> UIScrollView? {
        var best: UIScrollView?
        func visit(_ view: UIView) {
            if let scroll = view as? UIScrollView, scroll.contentSize.height > (best?.contentSize.height ?? 0) {
                best = scroll
            }
            view.subviews.forEach(visit)
        }
        visit(root)
        return best
    }
}
#endif
#endif
