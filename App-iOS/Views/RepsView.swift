import SwiftUI
import TrainingCore

/// The reps of an interval session as they were run: a bar per rep in the colour of
/// its verdict, its pace under it, and what it adds up to in words. Honest on purpose:
/// a slower rep shows as slower, with its pace.
///
/// Strides are shown the same way but never judged: 20 s quick and light is run by
/// feel, so each one gets its time and the pace it covered, in the colour of a speed
/// session, and no on-target mark.
struct RepsView: View {
    let reps: [RepSplit]

    /// "Your strides" when that's all there is, "Your reps" otherwise.
    static func title(for reps: [RepSplit]) -> String {
        RepReport.reps(reps).isEmpty && !RepReport.strides(reps).isEmpty ? "Your strides" : "Your reps"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 4) {
                ForEach(Array(reps.enumerated()), id: \.offset) { _, rep in
                    VStack(spacing: 3) {
                        Capsule()
                            .fill(Self.tint(rep))
                            .frame(height: 8)
                        Text(rep.paceSecPerKm.map { String(Format.pace($0).dropLast(3)) } ?? "--")
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        // A rep: how far off target, in words, not by colour alone.
                        // A stride: how long it lasted, the thing it was run to.
                        Text(rep.kind == .stride ? "\(Int(rep.seconds.rounded())) s" : Self.offset(rep) ?? " ")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: 56)
                }
            }
            .accessibilityHidden(true)
            if let summary = RepReport.summary(reps) {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(RepReport.summary(reps) ?? "")
    }

    /// "+9 s" slower or "−12 s" faster than the target per km, for a rep off target.
    static func offset(_ rep: RepSplit) -> String? {
        guard let pace = rep.paceSecPerKm, let target = rep.targetPaceSecPerKm,
              rep.verdict == .slower || rep.verdict == .faster else { return nil }
        let delta = Int((pace - target).rounded())
        return delta > 0 ? "+\(delta) s" : "\u{2212}\(-delta) s"
    }

    /// A rep in the colour of its verdict. A stride in the colour of a speed session,
    /// softened: there's no verdict to show, and a solid bar where orange means
    /// "slower" would read as a mark against it.
    static func tint(_ rep: RepSplit) -> Color {
        rep.kind == .stride ? WorkoutType.repetitionSpeed.tint.opacity(0.6) : tint(rep.verdict)
    }

    static func tint(_ verdict: RepSplit.Verdict?) -> Color {
        switch verdict {
        case .onPace?: .green
        case .slower?: .orange
        case .faster?: .blue
        case nil: .secondary
        }
    }
}
