import Foundation
import Observation
import TrainingCore

/// The running shoes on this iPhone (`ShoeLog`), kept as a small JSON file next to
/// the app's data and written into the backup file with the plan. Nothing leaves
/// the device: Apple Health has no shoes, so this is the only place they live.
///
/// It reads the runs it needs from Health itself, from the day the oldest pair was
/// added, since shoes are older or younger than any plan.
@MainActor
@Observable
final class ShoeStore {
    static let shared = ShoeStore()

    private(set) var log: ShoeLog
    /// Every run since the oldest pair was added.
    private(set) var runs: [CompletedRun] = []

    private static var fileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("shoes.json")
    }

    init() {
        #if DEBUG
        if DemoMode.isOn {
            log = DemoMode.shoes
            runs = DemoMode.runs
            return
        }
        #endif
        log = (try? Data(contentsOf: Self.fileURL)).flatMap { try? JSONDecoder().decode(ShoeLog.self, from: $0) } ?? ShoeLog()
    }

    var hasShoes: Bool { !log.shoes.isEmpty }

    func meters(of pair: Shoe) -> Double { log.meters(of: pair.id, in: runs) }
    func runs(of pair: Shoe) -> [CompletedRun] { log.runs(of: pair.id, in: runs).sorted { $0.date > $1.date } }

    /// The pair a run in Health was in.
    func shoe(forWorkout id: UUID, date: Date) -> Shoe? {
        log.shoe(log.shoeID(for: CompletedRun(date: date, distanceMeters: 0, durationSeconds: 0, workoutID: id)))
    }

    /// The active pairs past the distance set for them, for the note on Today.
    var dueForReplacing: [Shoe] {
        log.active.filter { meters(of: $0) >= $0.replaceAtMeters }
    }

    /// Reads the runs again, after a run or when the app comes back.
    func refresh(health: HealthKitService) async {
        #if DEBUG
        if DemoMode.isOn { return }
        #endif
        guard let oldest = log.shoes.map(\.addedAt).min() else { runs = []; return }
        runs = await health.fetchRuns(since: Calendar.current.startOfDay(for: oldest), heartRate: false)
    }

    // MARK: Changes

    /// Changes the shoes. The edit works on a copy, so it may read the store while it
    /// runs (a page asking which pair it shows): editing `log` in place while it's
    /// read is an overlapping access, which stops the app.
    func change(_ edit: (inout ShoeLog) -> Void) {
        var changed = log
        edit(&changed)
        log = changed
        save()
    }

    /// Replaces everything, from a backup file.
    func restore(_ restored: ShoeLog) {
        log = restored
        save()
    }

    private func save() {
        #if DEBUG
        if DemoMode.isOn { return }
        #endif
        guard let data = try? JSONEncoder().encode(log) else { return }
        try? data.write(to: Self.fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
