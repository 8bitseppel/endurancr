import Foundation

/// Fixed year-end holidays where no training is scheduled, applied when the
/// athlete opts in via `Goal.skipHolidays`. These are expanded per calendar year
/// so a plan crossing a December automatically picks up that season's Christmas
/// and New Year — the athlete never has to add them as time off by hand.
///
/// Ranges match the German public holidays (the app's home context): Christmas
/// Eve through Boxing Day (Dec 24–26) and New Year's Eve through New Year's Day
/// (Dec 31 – Jan 1).
public enum Holidays {
    /// Inclusive holiday periods overlapping the `[from, to]` window, ready to be
    /// blanked like any other `UnavailablePeriod`. Empty when `from > to`.
    public static func periods(from: Date, to: Date, calendar: Calendar = .current) -> [UnavailablePeriod] {
        guard from <= to else { return [] }
        let fromDay = calendar.startOfDay(for: from)
        let toDay = calendar.startOfDay(for: to)
        let startYear = calendar.component(.year, from: from)
        let endYear = calendar.component(.year, from: to)

        var all: [UnavailablePeriod] = []
        // Start one year early so a New Year period that opened on Dec 31 of the
        // prior year (and runs into Jan 1 of the window) is still generated.
        for year in (startYear - 1)...endYear {
            if let christmas = period(
                reason: "Christmas",
                start: DateComponents(year: year, month: 12, day: 24),
                end: DateComponents(year: year, month: 12, day: 26),
                calendar: calendar
            ) {
                all.append(christmas)
            }
            if let newYear = period(
                reason: "New Year",
                start: DateComponents(year: year, month: 12, day: 31),
                end: DateComponents(year: year + 1, month: 1, day: 1),
                calendar: calendar
            ) {
                all.append(newYear)
            }
        }
        // Keep only the periods that actually touch the plan window.
        return all.filter {
            calendar.startOfDay(for: $0.end) >= fromDay && calendar.startOfDay(for: $0.start) <= toDay
        }
    }

    private static func period(
        reason: String, start: DateComponents, end: DateComponents, calendar: Calendar
    ) -> UnavailablePeriod? {
        guard let s = calendar.date(from: start), let e = calendar.date(from: end) else { return nil }
        // Deterministic id (from the reason + start year) so regenerating the plan
        // reproduces the identical period instead of churning a fresh UUID.
        let id = stableID("holiday-\(reason)-\(start.year ?? 0)")
        return UnavailablePeriod(id: id, start: s, end: e, reason: reason)
    }

    /// A stable UUID derived from a seed via FNV-1a, so the same seed always maps
    /// to the same id (mirrors `VDOTPlanGenerator.stableID` for workouts).
    private static func stableID(_ seed: String) -> UUID {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in seed.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        let lo = hash
        let hi = hash &* 0x100000001b3
        var bytes = [UInt8]()
        for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8((hi >> shift) & 0xff)) }
        for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8((lo >> shift) & 0xff)) }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
