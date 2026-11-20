import Foundation

/// A pair of running shoes and how far they've gone, to know when to replace them.
/// Kept by endurancr alone: Apple Health has no idea of shoes, and a run in Health
/// can't be changed once it's saved, so which shoe a run was in lives here (`ShoeLog`).
public struct Shoe: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    /// What they had already run before they were added, for a pair you already own.
    public var startingMeters: Double
    /// When they were added: runs from then on count for them.
    public var addedAt: Date
    /// When to think about replacing them, set per pair.
    public var replaceAtMeters: Double
    /// When they were put away; `nil` while in use. Archived shoes stay in the
    /// history with what they ran, and no new run counts for them.
    public var archivedAt: Date?

    public init(id: UUID = UUID(), name: String, startingMeters: Double = 0, addedAt: Date = .now,
                replaceAtMeters: Double = Shoe.defaultReplaceAtMeters, archivedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.startingMeters = startingMeters
        self.addedAt = addedAt
        self.replaceAtMeters = replaceAtMeters
        self.archivedAt = archivedAt
    }

    public var isArchived: Bool { archivedAt != nil }

    /// 700 km: inside the 500 to 800 km the shoe makers and most running books give,
    /// a little past its middle, since most runners replace on feel well before the
    /// foam is gone. Changeable per pair.
    public static let defaultReplaceAtMeters: Double = 700_000
}

/// The shoes, which one is worn by default, and the runs moved to another pair.
///
/// A run belongs to the shoe that was the default on its day, so nothing has to be
/// picked for each run: with one pair, every run is in it. Changing the default
/// counts from then on, so the runs before stay with the pair they were run in.
/// A run changed afterwards (`assignments`) belongs to the pair it was changed to,
/// or to none.
///
/// Everything is in the backup file, with the plan.
public struct ShoeLog: Sendable, Equatable, Codable {
    public var shoes: [Shoe]
    /// Which pair was the default from when, oldest first. `shoeID` `nil` means no
    /// default from then (the default was archived and no other pair was in use).
    public var defaults: [DefaultChange]
    /// Runs moved to another pair after the run, by the run's ID in Apple Health.
    /// A `nil` shoe means the run was in none of them.
    public var assignments: [String: UUID?]

    public struct DefaultChange: Sendable, Equatable, Codable {
        public var from: Date
        public var shoeID: UUID?
        public init(from: Date, shoeID: UUID?) {
            self.from = from
            self.shoeID = shoeID
        }
    }

    public init(shoes: [Shoe] = [], defaults: [DefaultChange] = [], assignments: [String: UUID?] = [:]) {
        self.shoes = shoes
        self.defaults = defaults
        self.assignments = assignments
    }

    public var active: [Shoe] { shoes.filter { !$0.isArchived } }
    /// Put away, most recently archived first.
    public var archived: [Shoe] {
        shoes.filter(\.isArchived).sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
    }

    public func shoe(_ id: UUID?) -> Shoe? { id.flatMap { id in shoes.first { $0.id == id } } }

    /// The pair new runs count for now.
    public var defaultShoe: Shoe? { defaultID(at: .distantFuture).flatMap(shoe) }

    /// The default on `date`.
    public func defaultID(at date: Date) -> UUID? {
        defaults.last { $0.from <= date }?.shoeID
    }

    /// The pair a run was in: the one it was changed to, or the default on its day,
    /// if that pair had been added by then.
    public func shoeID(for run: CompletedRun) -> UUID? {
        if let key = run.workoutID?.uuidString, let assigned = assignments[key] { return assigned }
        guard let id = defaultID(at: run.date), let pair = shoe(id), pair.addedAt <= run.date,
              pair.archivedAt.map({ run.date < $0 }) ?? true else { return nil }
        return id
    }

    /// The runs each pair was in.
    public func runs(of id: UUID, in runs: [CompletedRun]) -> [CompletedRun] {
        runs.filter { shoeID(for: $0) == id }
    }

    /// How far a pair has gone: what it had run before, plus every run in it.
    public func meters(of id: UUID, in runs: [CompletedRun]) -> Double {
        guard let pair = shoe(id) else { return 0 }
        return pair.startingMeters + self.runs(of: id, in: runs).reduce(0) { $0 + $1.distanceMeters }
    }

    // MARK: Changes

    /// Adds a pair. The first one, or one asked to be, becomes the default from the
    /// day it was in use, so its runs in Health since then count for it; unless
    /// another pair was the default after that day, which keeps its runs.
    public mutating func add(_ pair: Shoe, makeDefault: Bool) {
        shoes.append(pair)
        guard makeDefault || active.count == 1 else { return }
        let lastChange = defaults.last?.from ?? .distantPast
        setDefault(pair.id, from: lastChange < pair.addedAt ? pair.addedAt : max(lastChange, .now))
    }

    /// The pair runs count for from `date` on.
    public mutating func setDefault(_ id: UUID?, from date: Date = .now) {
        // Two changes on the same moment: the later one is what was meant.
        if let last = defaults.last, last.from >= date { defaults.removeLast() }
        defaults.append(DefaultChange(from: date, shoeID: id))
    }

    /// Moves one run to another pair, or to none.
    public mutating func assign(_ run: CompletedRun, to id: UUID?) {
        guard let key = run.workoutID?.uuidString else { return }
        assignments[key] = .some(id)
    }

    /// Puts a pair away. Its runs stay with it; if it was the default, the only other
    /// pair in use takes over, or no pair does.
    public mutating func archive(_ id: UUID, at date: Date = .now) {
        guard let i = shoes.firstIndex(where: { $0.id == id }) else { return }
        shoes[i].archivedAt = date
        if defaultID(at: .distantFuture) == id {
            let others = active
            setDefault(others.count == 1 ? others[0].id : nil, from: date)
        }
    }

    /// Takes an archived pair out again.
    public mutating func restore(_ id: UUID) {
        guard let i = shoes.firstIndex(where: { $0.id == id }) else { return }
        shoes[i].archivedAt = nil
    }

    /// Changes a pair. The first pair ever, moved to an earlier day in use, counts
    /// its runs from then; later pairs keep the day they became the default, which
    /// another pair's runs reach up to.
    public mutating func update(_ pair: Shoe) {
        guard let i = shoes.firstIndex(where: { $0.id == pair.id }) else { return }
        shoes[i] = pair
        if let first = defaults.first, first.shoeID == pair.id, first.from != pair.addedAt,
           defaults.count == 1 || defaults[1].from > pair.addedAt {
            defaults[0].from = pair.addedAt
        }
    }

    /// Removes a pair for good, with the runs moved to it.
    public mutating func delete(_ id: UUID) {
        shoes.removeAll { $0.id == id }
        assignments = assignments.filter { $0.value != .some(id) }
        if defaultID(at: .distantFuture) == id {
            let others = active
            setDefault(others.count == 1 ? others[0].id : nil)
        }
        defaults = defaults.map { $0.shoeID == id ? DefaultChange(from: $0.from, shoeID: nil) : $0 }
    }
}
