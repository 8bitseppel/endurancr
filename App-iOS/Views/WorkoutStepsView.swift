import SwiftUI
import TrainingCore

/// Renders a structured quality session (intervals / tempo) as labeled steps with
/// the actual paces for the current fitness. Paces come from `zones`, so the
/// breakdown stays correct after adaptation re-paces the plan.
struct WorkoutStepsView: View {
    let structure: WorkoutStructure
    let zones: PaceZones

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(Format.workoutSteps(structure, zones: zones).enumerated()), id: \.offset) { _, step in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(step.label)
                        .font(.caption.weight(.semibold))
                        .frame(minWidth: 54, alignment: .leading)
                    Text(step.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.leading, 2)
    }
}
