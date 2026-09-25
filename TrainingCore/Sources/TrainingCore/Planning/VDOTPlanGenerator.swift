import Foundation

/// Generates a periodized plan from a VDOT estimate using Daniels-style paces and
/// a back-planned Base → Build → Peak → Taper → Race progression.
///
/// Volume ramps geometrically (≤ ~8%/week) with a cutback every 4th progression
/// week, and every week stays within 10% of the highest weekly volume reached so
/// far (the "10% rule"). Long-run distance is a phase-dependent fraction of weekly
/// volume, capped per race distance.
public struct VDOTPlanGenerator: PlanGenerator {
    public init() {}

    private let calculator = VDOTCalculator()

    /// The shortest plan endurancr will build: fewer than two weeks between the
    /// start date and race day leaves no room to periodize, so it's rejected.
    public static let minimumDays = 14
    private let minimumDays = VDOTPlanGenerator.minimumDays

    public func makePlan(
        goal: Goal,
        fitness: FitnessSnapshot,
        startDate: Date,
        calendar: Calendar = .current
    ) throws -> TrainingPlan {
        guard fitness.distanceMeters > 0, fitness.timeSeconds > 0 else {
            throw PlanError.invalidFitness
        }

        // Rest-weekday rules must leave room for the requested running days.
        let blockedWeekdays = goal.restWeekdays.filter { (1...7).contains($0) }
        let availableDays = 7 - blockedWeekdays.count
        guard goal.daysPerWeek <= availableDays else {
            throw PlanError.daysPerWeekExceedsAvailable(requested: goal.daysPerWeek, available: availableDays)
        }

        let start0 = calendar.startOfDay(for: startDate)
        let race0 = calendar.startOfDay(for: goal.raceDate)
        let days = calendar.dateComponents([.day], from: start0, to: race0).day ?? 0
        guard days >= minimumDays else {
            throw PlanError.raceTooSoon(daysAvailable: days, minimum: minimumDays)
        }

        let vdot = calculator.vdot(distanceMeters: fitness.distanceMeters, timeSeconds: fitness.timeSeconds)
        let zones = calculator.paceZones(forVDOT: vdot)

        // If the athlete set a target time and their current VDOT already meets the
        // VDOT that time requires, they're "good to go": build a maintenance plan
        // that holds fitness (steady volume, one quality session, a weekly long run)
        // rather than a progressive build toward a fitness they already have.
        let requiredVDOT = goal.targetTimeSeconds.map {
            calculator.vdot(distanceMeters: goal.race.meters, timeSeconds: $0)
        }
        let isMaintenance = requiredVDOT.map { vdot >= $0 } ?? false

        // Anchor every week to Monday so the plan reads as Monday–Sunday calendar
        // weeks (the ISO "Kalenderwoche" the athlete sees on any calendar), instead
        // of 7-day blocks counted off the start date. Week 0 is the week that
        // contains the start date and may begin partway through it when training
        // starts mid-week; the pre-start days carry no session.
        let firstWeekStart = Self.startOfWeek(start0, calendar: calendar)
        let raceWeekStart = Self.startOfWeek(race0, calendar: calendar)
        let total = (calendar.dateComponents([.day], from: firstWeekStart, to: raceWeekStart).day ?? 0) / 7 + 1
        let raceOffsetInWeek = calendar.dateComponents([.day], from: raceWeekStart, to: race0).day ?? 0  // 0...6 (Mon…Sun)

        let dpw = min(6, max(3, goal.daysPerWeek))
        let peakVol = Self.peakWeeklyVolume(for: goal.race)
        let cap = Self.longRunCap(for: goal.race)
        let progressionVolumes = Self.progressionVolumes(count: max(0, total - 3), peak: peakVol)

        var weeks: [TrainingWeek] = []
        for i in 0..<total {
            let weekStart = calendar.date(byAdding: .day, value: i * 7, to: firstWeekStart)!
            let phase = isMaintenance
                ? Self.maintenancePhase(weekIndex: i, total: total)
                : Self.phase(weekIndex: i, total: total)
            // Week 0 only starts training on the athlete's chosen start day; earlier
            // days of that Monday–Sunday week are left blank (before the plan begins).
            let earliestOffset = i == 0 ? (calendar.dateComponents([.day], from: firstWeekStart, to: start0).day ?? 0) : 0
            let workouts: [PlannedWorkout]
            if phase == .raceWeek {
                workouts = raceWeekWorkouts(
                    weekStart: weekStart, raceOffset: raceOffsetInWeek,
                    goal: goal, vdot: vdot, zones: zones, calendar: calendar
                )
            } else {
                let volume = isMaintenance
                    ? Self.maintenanceVolume(weekPhase: phase, race: goal.race)
                    : Self.weeklyVolume(
                        weekIndex: i, total: total, phase: phase,
                        progression: progressionVolumes, peak: peakVol
                    )
                workouts = trainingWeekWorkouts(
                    weekStart: weekStart, phase: phase, volume: volume,
                    daysPerWeek: dpw, longRunCap: cap, earliestOffset: earliestOffset,
                    goal: goal, zones: zones, calendar: calendar
                )
            }
            weeks.append(TrainingWeek(index: i, startDate: weekStart, phase: phase, workouts: workouts))
        }

        return TrainingPlan(goal: goal, vdot: vdot, paceZones: zones, weeks: weeks, isMaintenance: isMaintenance)
    }

    // MARK: Periodization

    /// The Monday on or before `date`, so weeks align to Monday–Sunday calendar
    /// weeks regardless of the calendar's `firstWeekday` (which is Sunday in en_US).
    public static func startOfWeek(_ date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: start)  // 1 = Sun … 7 = Sat
        let daysSinceMonday = (weekday + 5) % 7                  // Mon→0, Tue→1, … Sun→6
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: start)!
    }

    /// Phase for a maintenance week: steady `.maintenance` throughout, a light
    /// `.taper` the week before the race, and the race week itself. Fitness is
    /// already at goal, so there's no base→build→peak progression.
    static func maintenancePhase(weekIndex i: Int, total: Int) -> TrainingPhase {
        if i == total - 1 { return .raceWeek }
        if total >= 2, i == total - 2 { return .taper }
        return .maintenance
    }

    /// Steady weekly volume for a maintenance plan — constant across the block
    /// (holds fitness), with a lighter unload on the pre-race taper week.
    static func maintenanceVolume(weekPhase phase: TrainingPhase, race: RaceDistance) -> Double {
        let hold = 0.80 * peakWeeklyVolume(for: race)
        return phase == .taper ? 0.60 * hold : hold
    }

    static func phase(weekIndex i: Int, total: Int) -> TrainingPhase {
        if i == total - 1 { return .raceWeek }
        if i >= max(0, total - 3) { return .taper }
        let progression = max(1, total - 3)
        let baseEnd = Int(Double(progression) * 0.40)
        let buildEnd = Int(Double(progression) * 0.75)
        if i < baseEnd { return .base }
        if i < buildEnd { return .build }
        return .peak
    }

    /// Weekly running volume for progression weeks: geometric ramp with cutbacks,
    /// where trend does NOT advance on a cutback week (so the rebound week stays
    /// within 10% of the prior peak).
    static func progressionVolumes(count: Int, peak: Double) -> [Double] {
        guard count > 0 else { return [] }
        let start = 0.55 * peak
        var out: [Double] = []
        var trend = start
        for j in 0..<count {
            let isCutback = ((j + 1) % 4 == 0)
            if j == 0 {
                out.append(trend)
            } else if isCutback {
                out.append(trend * 0.70)
            } else {
                trend = min(peak, trend * 1.08)
                out.append(trend)
            }
        }
        return out
    }

    static func weeklyVolume(
        weekIndex i: Int, total: Int, phase: TrainingPhase,
        progression: [Double], peak: Double
    ) -> Double {
        switch phase {
        case .base, .build, .peak, .maintenance:
            return i < progression.count ? progression[i] : peak
        case .taper:
            // Two taper weeks (total-3, total-2): 65% then 50% of peak.
            return i == total - 3 ? 0.65 * peak : 0.50 * peak
        case .raceWeek:
            return 0
        }
    }

    // MARK: Volume/pace tables

    static func peakWeeklyVolume(for race: RaceDistance) -> Double {
        switch race {
        case .marathon: return 70_000
        case .halfMarathon: return 55_000
        case .tenK: return 45_000
        case .fiveK: return 35_000
        case .custom(let m): return min(85_000, max(30_000, m * 1.6))
        }
    }

    public static func longRunCap(for race: RaceDistance) -> Double {
        switch race {
        case .marathon: return 32_000
        case .halfMarathon: return 24_000
        case .tenK: return 16_000
        case .fiveK: return 13_000
        case .custom(let m): return max(10_000, min(34_000, m * 0.9))
        }
    }

    private static func longRunFraction(for phase: TrainingPhase) -> Double {
        switch phase {
        case .peak: return 0.36
        case .build: return 0.33
        case .maintenance: return 0.32
        case .taper: return 0.30
        default: return 0.28
        }
    }

    /// Lays out a week's running days as day offsets from `weekStart` (0…6),
    /// honoring the athlete's blocked weekdays. Returns the sorted running-day
    /// offsets and which one carries the long run (a weekend day when one is free).
    static func weekLayout(
        weekStart: Date, daysPerWeek dpw: Int,
        restWeekdays: Set<Int>, earliestOffset: Int = 0, calendar: Calendar
    ) -> (runDays: [Int], longOffset: Int) {
        let blocked = restWeekdays.filter { (1...7).contains($0) }
        func weekday(_ offset: Int) -> Int {
            calendar.component(.weekday, from: calendar.date(byAdding: .day, value: offset, to: weekStart)!)
        }
        // A partial first week only offers the days on/after `earliestOffset`.
        let allowed = (max(0, earliestOffset)..<7).filter { !blocked.contains(weekday($0)) }
        let k = min(max(0, dpw), allowed.count)
        guard k > 0 else { return ([], -1) }

        // The long run is the week's single biggest effort, so it must never be
        // stacked against another run. Put it on the latest free weekend day —
        // Sunday preferred, so no session follows it that week; Saturday if Sunday is
        // blocked — else the latest running day.
        let weekendDays = allowed.filter { weekday($0) == 1 || weekday($0) == 7 }  // Sun / Sat
        let longOffset = weekendDays.max() ?? allowed.max()!

        // Choose the other running days. Prefer ones that leave a rest day on both
        // sides of the long run (so the biggest effort has a recovery buffer), but
        // only if dropping those neighbours still leaves enough days to honour
        // daysPerWeek. Then spread the chosen days evenly so rest falls between
        // efforts and any unavoidable adjacency lands on the lighter easy days.
        let others = allowed.filter { $0 != longOffset }
        let isolated = others.filter { abs($0 - longOffset) > 1 }
        func spread(_ need: Int) -> [Int] {
            let pool = isolated.count >= need ? isolated : others
            return (evenlySpaced(pool, count: need) + [longOffset]).sorted()
        }
        let runDays = spread(k - 1)
        guard backToBackCount(runDays) > 0 else { return (runDays, longOffset) }

        // The even spread still put two runs on consecutive days. Look for the set
        // with the fewest back-to-back pairs, then the widest gaps.
        let best = bestSpacing(others: others, longOffset: longOffset, need: k - 1)
        // A partial first week (training starts on a Thursday, say) has no reason to
        // cram runs onto consecutive days: drop runs until each one has a rest day
        // between it and the next. Full weeks keep the running days the athlete asked
        // for, since five or six runs in seven days can't all be spaced out.
        if earliestOffset > 0, backToBackCount(best) > 0 {
            for fewer in stride(from: k - 2, through: 0, by: -1) {
                let candidate = bestSpacing(others: others, longOffset: longOffset, need: fewer)
                if backToBackCount(candidate) == 0 { return (candidate, longOffset) }
            }
        }
        return (best, longOffset)
    }

    /// Number of consecutive-day pairs in a sorted list of day offsets.
    static func backToBackCount(_ days: [Int]) -> Int {
        zip(days, days.dropFirst()).filter { $1 - $0 == 1 }.count
    }

    /// Of every way to pick `need` days from `others` alongside the long run, the one
    /// with the fewest back-to-back pairs, then the largest smallest gap. Ties keep
    /// the earliest set, so the layout is deterministic.
    static func bestSpacing(others: [Int], longOffset: Int, need: Int) -> [Int] {
        func combinations(_ items: ArraySlice<Int>, _ n: Int) -> [[Int]] {
            guard n > 0 else { return [[]] }
            guard let first = items.first else { return [] }
            let rest = items.dropFirst()
            return combinations(rest, n - 1).map { [first] + $0 } + combinations(rest, n)
        }
        func score(_ days: [Int]) -> (Int, Int) {
            let minGap = zip(days, days.dropFirst()).map { $1 - $0 }.min() ?? 7
            return (backToBackCount(days), -minGap)
        }
        var best: [Int] = [longOffset]
        var bestScore = (Int.max, Int.max)
        for pick in combinations(others[...], min(need, others.count)) {
            let days = (pick + [longOffset]).sorted()
            let s = score(days)
            if s < bestScore { best = days; bestScore = s }
        }
        return best
    }

    /// Picks `count` items spread as evenly as possible across a sorted array.
    static func evenlySpaced(_ items: [Int], count: Int) -> [Int] {
        guard count > 0, !items.isEmpty else { return [] }
        if count >= items.count { return items }
        if count == 1 { return [items[items.count / 2]] }
        let n = items.count
        return (0..<count).map { j in
            items[Int((Double(j) * Double(n - 1) / Double(count - 1)).rounded())]
        }
    }

    // MARK: Workout construction

    private func window(_ centerSecPerKm: Double, tolerance: Double = 0.03) -> ClosedRange<Double> {
        (centerSecPerKm * (1 - tolerance))...(centerSecPerKm * (1 + tolerance))
    }

    /// A stable UUID for a workout, derived from its day and type. Regenerating a
    /// plan from the same inputs reproduces identical IDs, so run↔workout links and
    /// adaptation deltas survive recalculation instead of orphaning on each rebuild.
    private func workoutID(date: Date, type: WorkoutType, calendar: Calendar) -> UUID {
        let day = Int(calendar.startOfDay(for: date).timeIntervalSince1970)
        return Self.stableID("\(day)|\(type.rawValue)")
    }

    /// Deterministic UUID from a seed via two salted FNV-1a passes filling 16 bytes.
    static func stableID(_ seed: String) -> UUID {
        func fnv1a(_ string: String) -> UInt64 {
            var hash: UInt64 = 0xcbf2_9ce4_8422_2325
            for byte in string.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x0000_0100_0000_01b3
            }
            return hash
        }
        let hi = fnv1a(seed), lo = fnv1a("\(seed)#salt")
        func b(_ v: UInt64, _ i: Int) -> UInt8 { UInt8((v >> (UInt64(i) * 8)) & 0xff) }
        return UUID(uuid: (
            b(hi, 0), b(hi, 1), b(hi, 2), b(hi, 3), b(hi, 4), b(hi, 5), b(hi, 6), b(hi, 7),
            b(lo, 0), b(lo, 1), b(lo, 2), b(lo, 3), b(lo, 4), b(lo, 5), b(lo, 6), b(lo, 7)
        ))
    }

    private func trainingWeekWorkouts(
        weekStart: Date, phase: TrainingPhase, volume rawVolume: Double,
        daysPerWeek dpw: Int, longRunCap cap: Double, earliestOffset: Int = 0,
        goal: Goal, zones: PaceZones, calendar: Calendar
    ) -> [PlannedWorkout] {
        let layout = Self.weekLayout(
            weekStart: weekStart, daysPerWeek: dpw,
            restWeekdays: goal.restWeekdays, earliestOffset: earliestOffset, calendar: calendar
        )
        let runDays = layout.runDays
        let longOffset = layout.longOffset

        // A partial first week (training begins mid-week) offers fewer running days
        // than a full week. Prorate the week's volume by the fraction of the normal
        // running days that remain, so the individual sessions stay a sensible size
        // instead of cramming a whole week's distance into two or three days.
        let blockedCount = goal.restWeekdays.filter { (1...7).contains($0) }.count
        let normalRunDays = max(1, min(dpw, 7 - blockedCount))
        let volume = earliestOffset > 0
            ? rawVolume * Double(runDays.count) / Double(normalRunDays)
            : rawVolume

        // Non-long running days carry the easy/quality volume; quality slots are
        // assigned by their position among these so a threshold/interval always
        // lands on a real day regardless of where the long run sits.
        let otherDays = runDays.filter { $0 != longOffset }
        let n = otherDays.count

        // The long run must stay the week's single longest run. Its phase fraction
        // (0.28–0.36) can dip below an even per-day share when there are few running
        // days — e.g. 3 days/week leaves only 2 easy days, so an even split would be
        // ~0.33 of volume each and make every easy run longer than the "long" run.
        // Floor the long-run share just above an even split so ordering always holds.
        let evenShareFraction = n > 0 ? 1.15 / Double(n + 1) : 1.0
        let longFraction = max(Self.longRunFraction(for: phase), evenShareFraction)
        let longDistance = min(cap, longFraction * volume)
        let remaining = max(0, volume - longDistance)
        // Spread the rest across the easy/quality days. Clamp to the long run so that
        // if the per-race cap clipped the long run, no easy day can still exceed it.
        let easyEach = n == 0 ? 0 : min(longDistance, remaining / Double(n))

        var workouts: [PlannedWorkout] = []
        for offset in 0..<7 {
            let date = calendar.date(byAdding: .day, value: offset, to: weekStart)!
            if offset == longOffset {
                let isMarathonPeak = (goal.race == .marathon && phase == .peak)
                workouts.append(PlannedWorkout(
                    id: workoutID(date: date, type: .longRun, calendar: calendar),
                    date: date, type: .longRun, distanceMeters: longDistance,
                    targetPaceSecPerKm: window(zones.easySecPerKm),
                    notes: isMarathonPeak ? "Long run, finish last third at marathon pace" : "Long run, easy and conversational"
                ))
            } else if let position = otherDays.firstIndex(of: offset) {
                let (type, _) = qualityAssignment(position: position, count: runDays.count, phase: phase)
                // Quality days (intervals/tempo) carry a structured breakdown; the
                // parts sum to easyEach, so weekly volume is unchanged.
                let structure = Self.structure(for: type, totalMeters: easyEach)
                workouts.append(PlannedWorkout(
                    id: workoutID(date: date, type: type, calendar: calendar),
                    date: date, type: type, distanceMeters: easyEach,
                    targetPaceSecPerKm: window(pace(for: type, zones: zones)),
                    notes: Self.note(for: type, structure: structure),
                    structure: structure
                ))
            } else {
                // A rest day is either a day before the plan starts (blank), one the
                // athlete deliberately keeps free every week (a blocked weekday), or a
                // scheduled recovery/cross-training day. Label them distinctly so the
                // calendar explains *why* there's no run.
                let weekday = calendar.component(.weekday, from: date)
                let note: String
                if offset < earliestOffset {
                    note = ""  // before the plan begins — nothing scheduled yet
                } else if goal.restWeekdays.contains(weekday) {
                    let name = calendar.weekdaySymbols[weekday - 1]  // 1 = Sunday
                    note = "No training, you keep \(name)s free"
                } else {
                    note = "Rest / cross-train"
                }
                workouts.append(PlannedWorkout(
                    id: workoutID(date: date, type: .rest, calendar: calendar),
                    date: date, type: .rest, distanceMeters: 0, notes: note
                ))
            }
        }
        return workouts
    }

    /// Decides whether a mid-week running slot is a quality session. (The note is
    /// regenerated from the structured breakdown in `note(for:structure:)`.)
    private func qualityAssignment(position: Int, count: Int, phase: TrainingPhase) -> (WorkoutType, String) {
        let intervalPosition = count - 2
        if phase == .peak, position == intervalPosition, intervalPosition != 1 {
            return (.interval, "")
        }
        if (phase == .build || phase == .peak || phase == .maintenance), position == 1 {
            return (.threshold, "")
        }
        return (.easy, "Easy run")
    }

    // MARK: Structured quality sessions

    /// Builds the warm-up / work / cool-down breakdown for a quality session so its
    /// parts sum exactly to `total` (weekly volume is preserved). Steady runs (easy,
    /// long, marathon-pace) get no structure.
    static func structure(for type: WorkoutType, totalMeters total: Double) -> WorkoutStructure? {
        switch type {
        case .interval:      return repeatStructure(total: total, work: 1_000, recovery: 400, workType: .interval)
        case .repetitionSpeed: return repeatStructure(total: total, work: 400, recovery: 400, workType: .repetitionSpeed)
        case .threshold:     return tempoStructure(total: total)
        default:             return nil
        }
    }

    /// A warm-up, `reps` × (work + recovery jog), cool-down — sized to fit `total`.
    private static func repeatStructure(total: Double, work: Double, recovery: Double, workType: WorkoutType) -> WorkoutStructure {
        let repDist = work + recovery
        let desiredWarmCool = 3_000.0
        var reps = Int(((total - desiredWarmCool) / repDist).rounded())
        reps = max(3, min(8, reps))
        // Never let the work block overrun the total.
        while Double(reps) * repDist > total && reps > 1 { reps -= 1 }
        let wc = max(0, total - Double(reps) * repDist)
        let warmup = (wc * 0.55).rounded()
        return WorkoutStructure(
            warmupMeters: warmup, reps: reps, workMeters: work, recoveryMeters: recovery,
            cooldownMeters: max(0, wc - warmup), workType: workType
        )
    }

    /// Warm-up, one continuous tempo block, cool-down.
    private static func tempoStructure(total: Double) -> WorkoutStructure {
        let wc = min(total * 0.4, max(2_000, total * 0.35))
        let warmup = (wc * 0.55).rounded()
        return WorkoutStructure(
            warmupMeters: warmup, reps: 1, workMeters: max(0, total - wc), recoveryMeters: 0,
            cooldownMeters: max(0, wc - warmup), workType: .threshold
        )
    }

    /// A human-readable note describing the structured session.
    static func note(for type: WorkoutType, structure: WorkoutStructure?) -> String {
        guard let s = structure else { return type == .easy ? "Easy run" : "" }
        switch type {
        case .interval:
            return "Intervals: \(distLabel(s.workMeters)) × \(s.reps) @ interval pace, \(distLabel(s.recoveryMeters)) jog recoveries"
        case .repetitionSpeed:
            return "Speed: \(distLabel(s.workMeters)) × \(s.reps) @ rep pace, \(distLabel(s.recoveryMeters)) jog"
        case .threshold:
            return "Threshold: \(distLabel(s.workMeters)) continuous @ threshold pace"
        default:
            return ""
        }
    }

    /// "1 km" / "1.5 km" / "400 m" — compact distance label for notes.
    private static func distLabel(_ meters: Double) -> String {
        if meters >= 1_000 {
            let km = meters / 1_000
            return km == km.rounded() ? String(format: "%.0f km", km) : String(format: "%.1f km", km)
        }
        return String(format: "%.0f m", meters)
    }

    private func pace(for type: WorkoutType, zones: PaceZones) -> Double {
        switch type {
        case .easy, .longRun, .rest: return zones.easySecPerKm
        case .marathonPace: return zones.marathonSecPerKm
        case .threshold: return zones.thresholdSecPerKm
        case .interval: return zones.intervalSecPerKm
        case .repetitionSpeed: return zones.repetitionSecPerKm
        case .raceDay: return zones.marathonSecPerKm
        }
    }

    private func raceWeekWorkouts(
        weekStart: Date, raceOffset: Int,
        goal: Goal, vdot: Double, zones: PaceZones, calendar: Calendar
    ) -> [PlannedWorkout] {
        // Race-day pace: use the user's target time if given, else predicted from VDOT.
        let goalKm = goal.race.meters / 1_000
        let raceSeconds = goal.targetTimeSeconds
            ?? calculator.predictedTimeSeconds(distanceMeters: goal.race.meters, vdot: vdot)
        let raceCenter = raceSeconds / goalKm

        // The plan ends at the finish line — no days after the race.
        var workouts: [PlannedWorkout] = []
        for offset in 0...raceOffset {
            let date = calendar.date(byAdding: .day, value: offset, to: weekStart)!
            if offset == raceOffset {
                workouts.append(PlannedWorkout(
                    id: workoutID(date: date, type: .raceDay, calendar: calendar),
                    date: date, type: .raceDay, distanceMeters: goal.race.meters,
                    targetPaceSecPerKm: window(raceCenter, tolerance: 0.015),
                    notes: "🏁 Race day: \(goal.race.displayName)"
                ))
            } else if offset == raceOffset - 2 {
                workouts.append(PlannedWorkout(
                    id: workoutID(date: date, type: .easy, calendar: calendar),
                    date: date, type: .easy, distanceMeters: 4_000,
                    targetPaceSecPerKm: window(zones.easySecPerKm),
                    notes: "Short shakeout with a few strides"
                ))
            } else {
                workouts.append(PlannedWorkout(
                    id: workoutID(date: date, type: .rest, calendar: calendar),
                    date: date, type: .rest, distanceMeters: 0, notes: "Rest, stay fresh"
                ))
            }
        }
        return workouts
    }
}
