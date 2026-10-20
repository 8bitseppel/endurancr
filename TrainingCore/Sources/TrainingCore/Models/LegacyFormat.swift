import Foundation

/// What the iPhone sends watches still on an older endurancr (1.1.0 and before),
/// which fail on a run type or phase they don't know and then drop the whole plan.
/// The new values are put in terms they know, as close as they get:
/// - a tune-up race (`timeTrial`) becomes a threshold run, its race part a
///   threshold block;
/// - a recovery week after the race becomes a maintenance week;
/// - the goal says `skipHolidays: false`, the year-end holidays switch they still
///   read (it's gone, so they'd skip Christmas otherwise).
/// Newer watches read the plan as it is, from its own key.
public enum LegacyFormat {
    public static func forOlderWatch(_ data: Data) -> Data {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return data }
        let converted = convert(object)
        return (try? JSONSerialization.data(withJSONObject: converted)) ?? data
    }

    private static func convert(_ value: Any) -> Any {
        if let array = value as? [Any] { return array.map(convert) }
        guard var dict = value as? [String: Any] else { return value }
        for (key, inner) in dict {
            switch (key, inner as? String) {
            case ("type", "timeTrial"?), ("workType", "timeTrial"?), ("recoveryType", "timeTrial"?):
                dict[key] = "threshold"
            case ("phase", "recovery"?):
                dict[key] = "maintenance"
            default:
                dict[key] = convert(inner)
            }
        }
        // A goal: it has a race and a race date.
        if dict["race"] != nil, dict["raceDate"] != nil, dict["skipHolidays"] == nil {
            dict["skipHolidays"] = false
        }
        return dict
    }
}
