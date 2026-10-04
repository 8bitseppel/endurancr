import SwiftUI
import TrainingCore

/// Manage stretches of time the athlete can't train (vacation, travel, illness).
/// Adding a period blanks the affected future workouts to rest across the plan.
struct UnavailabilityView: View {
    let coordinator: PlanCoordinator

    @State private var showingAdd = false

    var body: some View {
        List {
            Section {
                Text("Block out days you can't train. Runs in these ranges become rest days, and your other sessions and paces are untouched.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            let periods = coordinator.unavailablePeriods
            if periods.isEmpty {
                ContentUnavailableView("No time off scheduled", systemImage: "airplane",
                    description: Text("Tap + to add a vacation or break."))
            } else {
                Section("Scheduled") {
                    ForEach(periods) { period in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(period.reason).font(.body)
                            Text("\(period.start.formatted(date: .abbreviated, time: .omitted)) to \(period.end.formatted(date: .abbreviated, time: .omitted)) · \(period.dayCount()) days")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        offsets.map { periods[$0].id }.forEach(coordinator.removeUnavailablePeriod)
                    }
                }
            }
        }
        .navigationTitle("Time Off")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddUnavailabilityView(coordinator: coordinator)
        }
    }
}

private struct AddUnavailabilityView: View {
    let coordinator: PlanCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var reason = "Vacation"
    @State private var start: Date
    @State private var end: Date

    /// Starts the day after the latest period already scheduled, so trips in a row
    /// are quick to enter. Today when there's none, or the latest is in the past.
    init(coordinator: PlanCoordinator) {
        self.coordinator = coordinator
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let dayAfter = coordinator.unavailablePeriods.map(\.end).max()
            .flatMap { cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: $0)) }
        let first = max(today, dayAfter ?? today)
        _start = State(initialValue: first)
        _end = State(initialValue: cal.date(byAdding: .day, value: 6, to: first) ?? first)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Reason") {
                    TextField("Reason", text: $reason)
                }
                Section("Dates") {
                    DatePicker("From", selection: $start, displayedComponents: .date)
                    DatePicker("To", selection: $end, in: start..., displayedComponents: .date)
                }
            }
            .navigationTitle("Add Time Off")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let label = reason.trimmingCharacters(in: .whitespaces)
                        coordinator.addUnavailablePeriod(start: start, end: end, reason: label.isEmpty ? "Unavailable" : label)
                        dismiss()
                    }
                }
            }
        }
    }
}
