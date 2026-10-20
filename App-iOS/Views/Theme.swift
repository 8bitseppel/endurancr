import SwiftUI
import TrainingCore

/// endurancr's look, from the pace calculator: a purple and blue background, glass
/// cards, rounded bold numbers and one colour per kind of run, used on every screen
/// so a run looks the same on Today, in the plan and in its detail. Light and dark.

extension WorkoutType {
    /// The run's colour. The paces in the calculator use the same ones.
    var tint: Color {
        switch self {
        case .easy: .teal
        case .longRun: .cyan
        case .marathonPace: .blue
        case .threshold: .indigo
        case .interval: .purple
        case .repetitionSpeed: .pink
        case .timeTrial, .raceDay: .green
        case .rest: .gray
        }
    }

    var symbol: String {
        switch self {
        case .easy: "figure.run"
        case .longRun: "road.lanes"
        case .marathonPace: "metronome"
        case .threshold: "gauge.with.dots.needle.67percent"
        case .interval: "timer"
        case .repetitionSpeed: "hare"
        case .timeTrial: "flag.2.crossed"
        case .raceDay: "flag.checkered"
        case .rest: "moon.zzz"
        }
    }
}

enum Brand {
    /// The deep purple of the background, for buttons with white titles.
    static let purple = Color(red: 0.42, green: 0.26, blue: 0.70)

    /// Rounded bold, for titles and numbers.
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

/// The background of every screen: a mesh of the app's purples and blues, dark at
/// night and soft lilac by day. `animated` lets the middle drift slowly, as in the
/// App Clip; the app's screens keep it still.
struct BrandBackground: View {
    var animated = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !animated || reduceMotion)) { context in
            let t = animated && !reduceMotion ? context.date.timeIntervalSinceReferenceDate / 6 : 0
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], [Float(0.5 + 0.15 * sin(t)), Float(0.45 + 0.12 * cos(t * 0.8))], [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: colorScheme == .dark ? Self.dark : Self.light
            )
        }
        .ignoresSafeArea()
    }

    private static let dark: [Color] = [
        .black, Color(red: 0.16, green: 0.08, blue: 0.32), .black,
        Color(red: 0.10, green: 0.12, blue: 0.36), Color(red: 0.42, green: 0.26, blue: 0.70), Color(red: 0.06, green: 0.22, blue: 0.34),
        .black, Color(red: 0.12, green: 0.06, blue: 0.24), .black,
    ]
    private static let light: [Color] = [
        Color(red: 0.97, green: 0.96, blue: 0.99), Color(red: 0.92, green: 0.89, blue: 0.98), Color(red: 0.96, green: 0.97, blue: 0.99),
        Color(red: 0.89, green: 0.91, blue: 0.99), Color(red: 0.80, green: 0.72, blue: 0.96), Color(red: 0.86, green: 0.94, blue: 0.97),
        Color(red: 0.97, green: 0.96, blue: 0.99), Color(red: 0.93, green: 0.90, blue: 0.98), Color(red: 0.97, green: 0.96, blue: 0.99),
    ]
}

extension View {
    /// A glass card, tinted with a run's colour when it's about one run.
    func brandCard(tint: Color? = nil, cornerRadius: CGFloat = 26, padding: CGFloat = 18) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .glassEffect(tint.map { .regular.tint($0.opacity(0.22)) } ?? .regular, in: .rect(cornerRadius: cornerRadius))
    }

    /// A small heading over a card, in capitals.
    func brandEyebrow() -> some View {
        self
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}
