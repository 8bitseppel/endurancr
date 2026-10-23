import SwiftUI
import TrainingCore

/// The reps of an interval session as they were run: a bar per rep in the colour of
/// its verdict, its pace under it, and what it adds up to in words. Honest on purpose:
/// a slower rep shows as slower, with its pace.
struct RepsView: View {
    let reps: [RepSplit]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 4) {
                ForEach(Array(reps.enumerated()), id: \.offset) { _, rep in
                    VStack(spacing: 3) {
                        Capsule()
                            .fill(Self.tint(rep.verdict))
                            .frame(height: 8)
                        Text(rep.paceSecPerKm.map { String(Format.pace($0).dropLast(3)) } ?? "--")
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
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
