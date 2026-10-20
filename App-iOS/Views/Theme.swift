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
    /// The same purple for the app's buttons: as it is by day, muted at night.
    static let buttonPurple = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.27, green: 0.21, blue: 0.38, alpha: 1)
            : UIColor(red: 0.42, green: 0.26, blue: 0.70, alpha: 1)
    })

    /// The fill of small cards in long lists (plan days), lighter than glass: frosted
    /// white by day, a faint lift at night.
    static let rowFill = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.06) : UIColor(white: 1, alpha: 0.6)
    })
    static let rowStroke = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.08) : UIColor(white: 1, alpha: 0.8)
    })

    /// Rounded bold, for titles and numbers.
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

/// The background of every screen: a mesh of the app's purples and blues, soft
/// lilac by day and close to black at night. `vivid` is the bright night version of
/// the pace calculator and App Clip, and `animated` lets its middle drift slowly;
/// the app's screens keep it calm and still.
struct BrandBackground: View {
    var animated = false
    var vivid = false
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
                colors: colorScheme == .light ? Self.light : (vivid ? Self.vividDark : Self.dark)
            )
        }
        .ignoresSafeArea()
    }

    /// Close to black with a hint of aubergine, so the runs' colours stay calm.
    private static let dark: [Color] = [
        Color(red: 0.03, green: 0.03, blue: 0.05), Color(red: 0.07, green: 0.05, blue: 0.10), Color(red: 0.03, green: 0.03, blue: 0.05),
        Color(red: 0.05, green: 0.05, blue: 0.09), Color(red: 0.12, green: 0.09, blue: 0.17), Color(red: 0.04, green: 0.06, blue: 0.08),
        Color(red: 0.03, green: 0.03, blue: 0.05), Color(red: 0.06, green: 0.04, blue: 0.08), Color(red: 0.03, green: 0.03, blue: 0.05),
    ]
    private static let vividDark: [Color] = [
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

/// A glass card, tinted with a run's colour when it's about one run: clearly by
/// day, only a hint at night, where bright colours on black glare.
private struct BrandCard: ViewModifier {
    let tint: Color?
    let cornerRadius: CGFloat
    let padding: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let opacity = colorScheme == .dark ? 0.05 : 0.22
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .glassEffect(tint.map { .regular.tint($0.opacity(opacity)) } ?? .regular, in: .rect(cornerRadius: cornerRadius))
    }
}

extension View {
    /// A glass card, tinted with a run's colour when it's about one run.
    func brandCard(tint: Color? = nil, cornerRadius: CGFloat = 26, padding: CGFloat = 18) -> some View {
        modifier(BrandCard(tint: tint, cornerRadius: cornerRadius, padding: padding))
    }

    /// A list or form on the brand background, with the standard rows on top.
    func brandList() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background { BrandBackground() }
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
