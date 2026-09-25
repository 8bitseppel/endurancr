import Foundation
import TrainingCore

/// Display helpers shared by both apps. Uses the user's locale/units where possible.
enum Format {
    /// Distance in km with one decimal, e.g. "12.4 km".
    static func distance(_ meters: Double) -> String {
        String(format: "%.1f km", meters / 1_000)
    }

    /// Pace as m:ss/km, e.g. "5:07/km".
    static func pace(_ secPerKm: Double) -> String {
        guard secPerKm.isFinite, secPerKm > 0 else { return "--" }
        let total = Int(secPerKm.rounded())
        return String(format: "%d:%02d/km", total / 60, total % 60)
    }

    /// A pace window, e.g. "4:58-5:16/km".
    static func paceRange(_ range: ClosedRange<Double>?) -> String {
        guard let range else { return "--" }
        return "\(paceNoUnit(range.lowerBound))-\(pace(range.upperBound))"
    }

    private static func paceNoUnit(_ secPerKm: Double) -> String {
        let total = Int(secPerKm.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Duration as h:mm:ss or m:ss.
    static func duration(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// A rough session time from distance and a target pace window (uses the
    /// window midpoint). `nil` when either input is missing or non-finite.
    static func estimatedDuration(distanceMeters: Double, pace: ClosedRange<Double>?) -> String? {
        guard let pace, distanceMeters > 0 else { return nil }
        let mid = (pace.lowerBound + pace.upperBound) / 2
        let seconds = distanceMeters / 1_000 * mid
        guard seconds.isFinite, seconds > 0 else { return nil }
        return duration(seconds)
    }

    /// Compact distance for step labels: "1 km", "1.5 km", "400 m".
    static func distanceCompact(_ meters: Double) -> String {
        if meters >= 1_000 {
            let km = meters / 1_000
            return km == km.rounded() ? String(format: "%.0f km", km) : String(format: "%.1f km", km)
        }
        return String(format: "%.0f m", meters)
    }

    /// Turns a structured session into labeled steps with the paces for the current
    /// fitness. Paces are read from `zones` (never stored on the structure), so this
    /// stays correct after re-pacing. Warm-up/cool-down run at the recovery zone.
    static func workoutSteps(_ s: WorkoutStructure, zones: PaceZones) -> [(label: String, detail: String)] {
        let easyPace = pace(zones.pace(for: s.recoveryType))
        let workPace = pace(zones.pace(for: s.workType))
        var steps: [(String, String)] = []
        if s.warmupMeters > 0 {
            steps.append(("Warm-up", "\(distanceCompact(s.warmupMeters)) @ \(easyPace)"))
        }
        if s.reps > 1 {
            var detail = "\(distanceCompact(s.workMeters)) @ \(workPace)"
            if s.recoveryMeters > 0 {
                detail += "  ·  \(distanceCompact(s.recoveryMeters)) jog @ \(easyPace)"
            }
            steps.append(("\(s.reps) ×", detail))
        } else if s.workMeters > 0 {
            steps.append(("Tempo", "\(distanceCompact(s.workMeters)) @ \(workPace)"))
        }
        if s.cooldownMeters > 0 {
            steps.append(("Cool-down", "\(distanceCompact(s.cooldownMeters)) @ \(easyPace)"))
        }
        return steps
    }

    static func workoutTitle(_ type: WorkoutType) -> String {
        switch type {
        case .rest: return "Rest"
        case .easy: return "Easy Run"
        case .longRun: return "Long Run"
        case .marathonPace: return "Marathon Pace"
        case .threshold: return "Threshold"
        case .interval: return "Intervals"
        case .repetitionSpeed: return "Speed"
        case .raceDay: return "Race Day"
        }
    }

    /// Icon for a rest day, chosen from its note so the calendar reads at a glance:
    /// scheduled recovery vs. a weekday the athlete keeps free vs. one-off time off
    /// (vacation) vs. a fixed holiday. Unknown notes fall back to the time-off icon,
    /// which is the safe default for a custom vacation reason.
    static func restSymbol(note: String) -> String {
        switch note {
        case "", "Rest / cross-train", "Rest, the week's distance is already done": return "moon.zzz"
        case "Christmas", "New Year": return "gift"
        case let n where n.hasPrefix("No training"): return "calendar.badge.minus"
        default: return "airplane"
        }
    }
}

extension TrainingPhase {
    /// The phase as a label: "Base", "Race week".
    var displayName: String {
        switch self {
        case .base: "Base"
        case .build: "Build"
        case .peak: "Peak"
        case .taper: "Taper"
        case .raceWeek: "Race week"
        case .maintenance: "Maintenance"
        }
    }
}
