import SwiftUI
import TrainingCore

/// Symbols and colours shared by Progress and the Plan tab.
extension TrainingPhase {
    /// Fixed colours: the default chart palette puts race week in orange.
    var tint: Color {
        switch self {
        case .base: .teal
        case .build, .maintenance: .blue
        case .peak: .indigo
        case .taper: .green
        case .raceWeek: .purple
        case .recovery: .mint
        }
    }
}

extension TrainingBuddy.Status.Phase {
    var symbol: String {
        switch self {
        case .onTrack: "figure.run"
        case .holding: "equal.circle"
        case .rebuilding: "arrow.up.right.circle"
        case .easingBack: "leaf"
        case .starting: "sparkles"
        }
    }
}

extension GoalOutlook.Verdict {
    var symbol: String {
        switch self {
        case .onTrack: "checkmark.circle.fill"
        case .withinReach: "arrow.up.right.circle.fill"
        case .stretch: "exclamationmark.circle.fill"
        case .unlikely: "arrow.uturn.down.circle.fill"
        }
    }

    /// For the icon only; the title carries the meaning (yellow text would be too
    /// faint on a light background).
    var tint: Color {
        switch self {
        case .onTrack: .green
        case .withinReach: .accentColor
        case .stretch: .yellow
        case .unlikely: .secondary
        }
    }
}

extension GoalOutlook {
    static func rangeText(_ range: ClosedRange<Double>) -> String {
        "\(format(range.lowerBound)) to \(format(range.upperBound))"
    }
}
