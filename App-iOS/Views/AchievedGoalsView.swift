import SwiftUI
import TrainingCore

/// A permanent record of finished goals: what the athlete set out to do and what
/// they achieved (fitness reached, weeks trained, distance run, adherence). Reads
/// the local `AchievedGoal` store via the coordinator; empty until a goal is
/// marked complete on race day.
struct AchievedGoalsView: View {
    let coordinator: PlanCoordinator

    private var achievements: [GoalAchievement] { coordinator.achievedGoals() }

    var body: some View {
        List {
            if achievements.isEmpty {
                ContentUnavailableView {
                    Label("No achieved goals yet", systemImage: "trophy")
                } description: {
                    Text("When you reach a goal's race day and mark it complete, a summary of what you achieved is saved here.")
                }
            } else {
                ForEach(achievements) { achievement in
                    Section {
                        summary(achievement)
                    } header: {
                        Text(achievement.goalName)
                    }
                }
            }
        }
        .navigationTitle("Achieved goals")
    }

    @ViewBuilder private func summary(_ a: GoalAchievement) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: a.metTargetFitness ? "trophy.fill" : "flag.checkered")
                .font(.title2)
                .foregroundStyle(a.metTargetFitness ? .yellow : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.raceName).font(.headline)
                Text("Race \(a.raceDate.formatted(date: .abbreviated, time: .omitted)) · achieved \(a.achievedDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)

        if let target = a.targetTimeSeconds {
            LabeledContent("Target time", value: Format.duration(target))
        }
        LabeledContent("Final VDOT", value: String(format: "%.1f", a.finalVDOT))
        if let required = a.requiredVDOT {
            LabeledContent("VDOT for target", value: String(format: "%.1f", required))
            LabeledContent("Target fitness") {
                Text(a.metTargetFitness ? "Met ✓" : "Not quite")
                    .foregroundStyle(a.metTargetFitness ? .green : .secondary)
            }
        }
        LabeledContent("Weeks trained", value: "\(a.weeksTrained)")
        LabeledContent("Distance run", value: Format.distance(a.totalDistanceMeters))
        LabeledContent("Workouts done", value: "\(a.workoutsCompleted)/\(a.workoutsPlanned)")
    }
}
