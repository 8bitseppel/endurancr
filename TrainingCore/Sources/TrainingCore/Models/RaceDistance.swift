import Foundation

/// A race target the user is training for. Distances are stored in meters so the
/// engine stays unit-agnostic; UI decides km/mi formatting.
public enum RaceDistance: Sendable, Hashable, Codable {
    case fiveK
    case tenK
    case halfMarathon
    case marathon
    case custom(meters: Double)

    public var meters: Double {
        switch self {
        case .fiveK: return 5_000
        case .tenK: return 10_000
        case .halfMarathon: return 21_097.5
        case .marathon: return 42_195
        case .custom(let m): return m
        }
    }

    public var displayName: String {
        switch self {
        case .fiveK: return "5K"
        case .tenK: return "10K"
        case .halfMarathon: return "Half Marathon"
        case .marathon: return "Marathon"
        case .custom(let m): return String(format: "%.1f km", m / 1_000)
        }
    }
}
