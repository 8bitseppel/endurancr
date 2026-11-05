import EventKit
import SwiftUI
import TrainingCore

/// Puts the plan's runs into the iPhone's Calendar, in a calendar of their own
/// called "endurancr", so they can be shown, hidden or coloured like any other and
/// your own events are never touched.
///
/// The calendar follows the plan: each event carries its run's ID in its URL, so when
/// the plan adapts (a swap, an easier week, new paces) the events are moved, changed
/// or removed rather than piling up. Only today onwards is kept in step; past days are
/// left as they were, a record of what was planned. All-day events, no alerts: the
/// plan is a schedule to glance at, not something to be reminded of.
///
/// It needs full calendar access, not the lighter add-only kind: with add-only
/// access the app can't read back the events it made, so it could never move or
/// remove one, and the calendar would drift from the plan within a week.
@MainActor
@Observable
final class PlanCalendar {
    static let shared = PlanCalendar()

    private let store = EKEventStore()
    private static let enabledKey = "calendarSync"
    private static let calendarKey = "calendarIdentifier"
    private static let urlPrefix = "endurancr://run/"

    /// Whether the runs are being kept in Calendar.
    private(set) var isOn = UserDefaults.standard.bool(forKey: enabledKey)
    /// Why turning it on didn't work, for the alert.
    var problem: String?
    private var pending: Task<Void, Never>?

    /// `-demoCalendar YES`: the demo writes its plan to the Simulator's Calendar,
    /// to check the sync and take the screenshot. Demos leave Calendar alone otherwise.
    static var demoAllowed: Bool {
        #if DEBUG
        DemoMode.isOn && UserDefaults.standard.bool(forKey: "demoCalendar")
        #else
        false
        #endif
    }

    /// Asks for access, makes the "endurancr" calendar and fills it.
    func turnOn(plan: TrainingPlan?) async {
        do {
            guard try await store.requestFullAccessToEvents() else {
                problem = "endurancr wasn't given access to your calendars. You can allow it in Settings > Apps > endurancr > Calendars."
                return
            }
        } catch {
            problem = error.localizedDescription
            return
        }
        guard calendar(create: true) != nil else {
            problem = "Calendar couldn't make a calendar for your runs. Check that an account in Settings > Apps > Calendar allows new calendars."
            return
        }
        isOn = true
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        sync(plan, now: true)
    }

    /// Stops and removes the "endurancr" calendar with its events.
    func turnOff() {
        isOn = false
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        pending?.cancel()
        if let calendar = calendar(create: false) {
            try? store.removeCalendar(calendar, commit: true)
        }
        UserDefaults.standard.removeObject(forKey: Self.calendarKey)
    }

    /// Brings the calendar in line with the plan, a moment after the last change:
    /// the plan is worked out a few times in a row at launch and after a run, and
    /// one sync for all of them is enough. `nil` clears the coming runs.
    func sync(_ plan: TrainingPlan?, now: Bool = false) {
        guard isOn, !DemoMode.isOn || Self.demoAllowed,
              EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        pending?.cancel()
        pending = Task {
            if !now { try? await Task.sleep(for: .seconds(1.5)) }
            guard !Task.isCancelled else { return }
            apply(plan)
        }
    }

    private func apply(_ plan: TrainingPlan?) {
        guard let calendar = calendar(create: true) else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let end = cal.date(byAdding: .day, value: 1,
                           to: plan.map { cal.startOfDay(for: $0.goal.raceDate) } ?? today)!
        // Everything we put there from today on, by run ID; a year ahead covers any
        // plan, and catches a race day that moved earlier.
        let horizon = max(end, cal.date(byAdding: .year, value: 1, to: today)!)
        let existing = store.events(matching: store.predicateForEvents(withStart: today, end: horizon, calendars: [calendar]))
        var byID: [String: EKEvent] = [:]
        for event in existing {
            guard let key = event.url?.absoluteString, key.hasPrefix(Self.urlPrefix) else { continue }
            if byID[key] != nil { try? store.remove(event, span: .thisEvent, commit: false) } else { byID[key] = event }
        }

        var wanted = Set<String>()
        for workout in plan?.allWorkouts ?? [] where workout.type.isRunning {
            let day = cal.startOfDay(for: workout.date)
            guard day >= today else { continue }
            let key = Self.urlPrefix + workout.id.uuidString
            wanted.insert(key)
            let event = byID[key] ?? EKEvent(eventStore: store)
            let title = Self.title(workout)
            let notes = Self.notes(workout, plan: plan!)
            let changed = event.calendar != calendar || event.title != title || event.notes != notes
                || !event.isAllDay || event.startDate.map { cal.startOfDay(for: $0) } != day
            guard changed else { continue }
            event.calendar = calendar
            event.title = title
            event.notes = notes
            event.isAllDay = true
            event.startDate = day
            event.endDate = day
            event.url = URL(string: key)
            event.alarms = nil
            event.availability = .free
            try? store.save(event, span: .thisEvent, commit: false)
        }
        for (key, event) in byID where !wanted.contains(key) {
            try? store.remove(event, span: .thisEvent, commit: false)
        }
        try? store.commit()
    }

    /// The "endurancr" calendar, made the first time, in the account new events go to
    /// (iCloud for most), or on this iPhone only when that account can't take one.
    private func calendar(create: Bool) -> EKCalendar? {
        if let id = UserDefaults.standard.string(forKey: Self.calendarKey),
           let found = store.calendar(withIdentifier: id) {
            return found
        }
        guard create else { return nil }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "endurancr"
        calendar.cgColor = UIColor(red: 0.42, green: 0.26, blue: 0.70, alpha: 1).cgColor
        let sources = [store.defaultCalendarForNewEvents?.source]
            + store.sources.filter { $0.sourceType == .calDAV }
            + store.sources.filter { $0.sourceType == .local }
        for source in sources.compactMap({ $0 }) {
            calendar.source = source
            if (try? store.saveCalendar(calendar, commit: true)) != nil {
                UserDefaults.standard.set(calendar.calendarIdentifier, forKey: Self.calendarKey)
                return calendar
            }
        }
        return nil
    }

    /// "Intervals · 6 × 1 km", "Long run · 15 km", "Race day · Hamburg Marathon".
    static func title(_ workout: PlannedWorkout) -> String {
        let kind = Format.workoutTitle(workout.type)
        if workout.type == .raceDay { return "\(kind) · \(Format.distance(workout.distanceMeters))" }
        // Strides are part of an easy run: its distance first, the strides after.
        if WorkoutSteps.hasStrides(workout) {
            return "\(kind) · \(Format.distance(workout.distanceMeters)) + strides"
        }
        if let summary = Format.sessionSummary(workout) {
            return "\(kind) · \(summary)"
        }
        return "\(kind) · \(Format.distance(workout.distanceMeters))"
    }

    /// The run's distance, paces and steps, as on Today, and where it comes from.
    static func notes(_ workout: PlannedWorkout, plan: TrainingPlan) -> String {
        var lines = ["\(Format.distance(workout.distanceMeters)), \(Format.paceRange(workout.targetPaceSecPerKm))"]
        if let structure = workout.structure {
            let steps = Format.workoutSteps(structure, zones: plan.paceZones)
            lines.append(steps.map { "\($0.label) \($0.detail)" }.joined(separator: "\n"))
        }
        if !workout.notes.isEmpty, !VDOTPlanGenerator.isStandardNote(workout.notes) {
            lines.append(workout.notes)
        }
        lines.append("From your endurancr plan for \(plan.goal.displayName). It follows the plan: when the plan changes, this changes with it, so edits made here are replaced.")
        return lines.joined(separator: "\n\n")
    }
}
