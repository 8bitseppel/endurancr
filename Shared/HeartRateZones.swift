import HealthKit
import SwiftUI

/// Time spent in one heart rate zone during a run, from Apple Health's own zones
/// (iOS 27 and watchOS 27): the ones set in the Health settings, or Apple's
/// defaults from your age and resting heart rate. endurancr doesn't work zones out
/// itself, so the numbers match the Fitness app's.
struct ZoneTime: Equatable, Identifiable, Sendable {
    /// 1 to 5.
    var number: Int
    var lowerBPM: Double?
    var upperBPM: Double?
    var seconds: Double
    var id: Int { number }

    /// "120 to 139 bpm", "under 120 bpm", "160 bpm and up".
    var range: String {
        switch (lowerBPM, upperBPM) {
        case let (low?, high?): "\(Int(low.rounded())) to \(Int(high.rounded()) - 1) bpm"
        case let (nil, high?): "under \(Int(high.rounded())) bpm"
        case let (low?, nil): "\(Int(low.rounded())) bpm and up"
        default: ""
        }
    }
}

enum HeartRateZones {
    /// The heart rate zones of a saved run, or `[]` before iOS 27 and watchOS 27, or
    /// when the run has no heart rate (an iPhone-only run).
    static func times(in workout: HKWorkout) -> [ZoneTime] {
        guard #available(iOS 27.0, watchOS 27.0, *),
              let group = workout.zoneGroup(for: HKQuantityType(.heartRate)) else { return [] }
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let times = group.zoneDurations.map { d in
            ZoneTime(number: d.zone.index + 1,
                     lowerBPM: d.zone.minimum?.doubleValue(for: bpm),
                     upperBPM: d.zone.maximum?.doubleValue(for: bpm),
                     seconds: d.duration)
        }
        return times.contains { $0.seconds >= 1 } ? times.sorted { $0.number < $1.number } : []
    }

    #if DEBUG
    /// A steady easy run, mostly in zone 2, for screenshots (`-demoZones YES`).
    static let demo: [ZoneTime] = [
        ZoneTime(number: 1, lowerBPM: nil, upperBPM: 126, seconds: 190),
        ZoneTime(number: 2, lowerBPM: 126, upperBPM: 140, seconds: 1_610),
        ZoneTime(number: 3, lowerBPM: 140, upperBPM: 154, seconds: 560),
        ZoneTime(number: 4, lowerBPM: 154, upperBPM: 168, seconds: 140),
        ZoneTime(number: 5, lowerBPM: 168, upperBPM: nil, seconds: 0),
    ]
    #endif
}

/// One bar per zone, as long as the time spent in it, with the time beside it.
struct ZoneBars: View {
    let zones: [ZoneTime]
    /// The bpm range under each zone; off on the watch, where it doesn't fit.
    var showsRange = true

    private var longest: Double { max(1, zones.map(\.seconds).max() ?? 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(zones) { zone in
                HStack(spacing: 8) {
                    Text("Z\(zone.number)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Self.tint(zone.number))
                        .frame(width: 24, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        GeometryReader { geo in
                            Capsule()
                                .fill(Self.tint(zone.number).gradient)
                                .frame(width: max(4, geo.size.width * zone.seconds / longest))
                        }
                        .frame(height: 8)
                        if showsRange, !zone.range.isEmpty {
                            Text(zone.range).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Text(Format.duration(zone.seconds))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .frame(minWidth: 44, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Zone \(zone.number)\(zone.range.isEmpty ? "" : ", \(zone.range)")")
                .accessibilityValue(Format.duration(zone.seconds))
            }
        }
    }

    /// Blue for the easy zones up to red for the hardest, as the Fitness app colours
    /// them by effort.
    static func tint(_ number: Int) -> Color {
        switch number {
        case 1: .blue
        case 2: .teal
        case 3: .green
        case 4: .yellow
        default: .red
        }
    }
}
