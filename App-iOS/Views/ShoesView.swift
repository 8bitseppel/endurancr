import SwiftUI
import TrainingCore

/// Your running shoes, under Progress: the pairs in use with how far each has gone
/// against when to replace it, and the pairs put away, with what they ran. Every
/// run counts for the default pair without asking; it can be changed before a run
/// (on Today) and after it (in its summary and under Recent runs).
struct ShoesView: View {
    let coordinator: PlanCoordinator
    @State private var store = ShoeStore.shared
    @State private var adding = false

    var body: some View {
        List {
            if store.log.shoes.isEmpty {
                ContentUnavailableView {
                    Label("No shoes yet", systemImage: "shoe")
                } description: {
                    Text("Add the pair you run in, and every run counts for it, so you know when they're due for replacing.")
                } actions: {
                    Button("Add shoes") { adding = true }
                        .buttonStyle(.glassProminent)
                        .tint(Brand.buttonPurple)
                }
            }
            if !store.log.active.isEmpty {
                Section {
                    ForEach(store.log.active) { pair in
                        NavigationLink {
                            ShoeDetailView(shoe: pair)
                        } label: {
                            ShoeRow(shoe: pair, meters: store.meters(of: pair),
                                    isDefault: store.log.defaultShoe?.id == pair.id)
                        }
                    }
                } header: {
                    Text("In use")
                } footer: {
                    Text(store.log.active.count > 1
                         ? "Every run counts for the default pair. Change it on Today before a run, or change a run's shoes afterwards in its summary or under Recent runs."
                         : "Every run counts for this pair. Add another and you can choose which one is the default.")
                }
            }
            if !store.log.archived.isEmpty {
                Section("Your earlier shoes") {
                    ForEach(store.log.archived) { pair in
                        NavigationLink {
                            ShoeDetailView(shoe: pair)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pair.name)
                                Text("\(Format.distance(store.meters(of: pair))) · \(Self.span(pair))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .brandList()
        .navigationTitle("Shoes")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add shoes", systemImage: "plus") { adding = true }
            }
        }
        .sheet(isPresented: $adding) { ShoeEditor(shoe: nil) }
        .task { await store.refresh(health: coordinator.health) }
    }

    /// "Mar 2026 to Nov 2026".
    static func span(_ pair: Shoe) -> String {
        let from = pair.addedAt.formatted(.dateTime.month(.abbreviated).year())
        guard let to = pair.archivedAt?.formatted(.dateTime.month(.abbreviated).year()) else { return "since \(from)" }
        return from == to ? from : "\(from) to \(to)"
    }
}

/// A pair with how far it has gone, as a bar toward the distance set for replacing it.
struct ShoeRow: View {
    let shoe: Shoe
    let meters: Double
    var isDefault = false

    private var fraction: Double { min(1, meters / max(1, shoe.replaceAtMeters)) }
    private var isDue: Bool { meters >= shoe.replaceAtMeters }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(shoe.name).font(.headline)
                if isDefault {
                    Text("Default")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Brand.buttonPurple.opacity(0.15), in: .capsule)
                        .foregroundStyle(Brand.buttonPurple)
                }
            }
            ProgressView(value: fraction)
                .tint(isDue ? .red : Brand.buttonPurple)
                .accessibilityHidden(true)
            Text(isDue
                 ? "\(Format.distance(meters)), past the \(Format.distanceCompact(shoe.replaceAtMeters)) set for replacing"
                 : "\(Format.distance(meters)) of \(Format.distanceCompact(shoe.replaceAtMeters))")
                .font(.caption).foregroundStyle(isDue ? .red : .secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// One pair: its distance, its settings, its runs, and putting it away.
struct ShoeDetailView: View {
    let shoe: Shoe
    @State private var store = ShoeStore.shared
    @State private var editing = false
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    /// The pair as it is now, after edits.
    private var current: Shoe { store.log.shoe(shoe.id) ?? shoe }

    var body: some View {
        List {
            Section {
                ShoeRow(shoe: current, meters: store.meters(of: current),
                        isDefault: store.log.defaultShoe?.id == current.id)
                if current.startingMeters > 0 {
                    LabeledContent("Before endurancr", value: Format.distance(current.startingMeters))
                }
                LabeledContent("In use", value: ShoesView.span(current))
            }
            Section {
                if !current.isArchived, store.log.defaultShoe?.id != current.id {
                    Button("Make default", systemImage: "checkmark.circle") {
                        store.change { $0.setDefault(current.id) }
                    }
                }
                Button("Edit", systemImage: "pencil") { editing = true }
                if current.isArchived {
                    Button("Use again", systemImage: "arrow.uturn.backward") {
                        store.change { $0.restore(current.id) }
                    }
                } else {
                    Button("Archive", systemImage: "archivebox") {
                        store.change { $0.archive(current.id) }
                    }
                }
            } footer: {
                Text(current.isArchived
                     ? "Archived pairs keep what they ran. No new run counts for them."
                     : "Archiving keeps the pair and its kilometres under Your earlier shoes. New runs stop counting for it.")
            }
            let runs = store.runs(of: current)
            if !runs.isEmpty {
                Section("Runs in them") {
                    ForEach(runs.prefix(30)) { run in
                        LabeledContent(run.date.formatted(date: .abbreviated, time: .omitted),
                                       value: Format.distance(run.distanceMeters))
                    }
                    if runs.count > 30 {
                        Text("And \(runs.count - 30) more").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("Deleting removes the pair and its history for good. To keep it, archive it.")
            }
        }
        .brandList()
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) { ShoeEditor(shoe: current) }
        .confirmationDialog("Delete \(current.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete for good", role: .destructive) {
                store.change { $0.delete(current.id) }
                dismiss()
            }
            Button("Keep them", role: .cancel) {}
        } message: {
            Text("Their kilometres and which runs were in them go too. Archiving keeps them.")
        }
    }
}

/// Adding a pair, or changing one: its name, what it had run before, and when to
/// replace it. A pair you already own can be added with the kilometres it has, and
/// from the day it was in use, so its runs in Health since then count.
struct ShoeEditor: View {
    let shoe: Shoe?
    @State private var store = ShoeStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var startingKm: Int
    @State private var replaceAtKm: Int
    @State private var since: Date
    @State private var makeDefault: Bool

    /// `prefill`: what the form starts with for a new pair, for the demo screenshots.
    init(shoe: Shoe?, prefill: Shoe? = nil) {
        self.shoe = shoe
        let start = shoe ?? prefill
        _name = State(initialValue: start?.name ?? "")
        _startingKm = State(initialValue: Int(((start?.startingMeters ?? 0) / 1_000).rounded()))
        _replaceAtKm = State(initialValue: Int(((start?.replaceAtMeters ?? Shoe.defaultReplaceAtMeters) / 1_000).rounded()))
        _since = State(initialValue: start?.addedAt ?? Calendar.current.startOfDay(for: .now))
        _makeDefault = State(initialValue: shoe == nil)
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, like Pegasus 41", text: $name)
                        .textInputAutocapitalization(.words)
                }
                Section {
                    DatePicker("In use since", selection: $since, in: ...Date.now, displayedComponents: .date)
                    Stepper(value: $startingKm, in: 0...5_000, step: 10) {
                        LabeledContent("Run before that", value: "\(startingKm) km")
                    }
                } header: {
                    Text("Already run in them?")
                } footer: {
                    Text("Your runs in Apple Health from that day on count for this pair. Add what they had run before, if you know it.")
                }
                Section {
                    Stepper(value: $replaceAtKm, in: 100...2_000, step: 50) {
                        LabeledContent("Replace at", value: "\(replaceAtKm) km")
                    }
                } footer: {
                    Text("Most shoes last 500 to 800 km, racing shoes less. The note on Today comes when they get there; how they feel matters more than the number.")
                }
                if shoe == nil, !store.log.active.isEmpty {
                    Section {
                        Toggle("Make default", isOn: $makeDefault)
                    } footer: {
                        Text("New runs count for the default pair.")
                    }
                }
            }
            .navigationTitle(shoe == nil ? "Add shoes" : "Edit shoes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(shoe == nil ? "Add" : "Save") { save() }
                        .disabled(trimmed.isEmpty)
                }
            }
        }
    }

    private func save() {
        let day = Calendar.current.startOfDay(for: since)
        if var edited = shoe {
            edited.name = trimmed
            edited.startingMeters = Double(startingKm) * 1_000
            edited.replaceAtMeters = Double(replaceAtKm) * 1_000
            edited.addedAt = day
            store.change { $0.update(edited) }
        } else {
            let pair = Shoe(name: trimmed, startingMeters: Double(startingKm) * 1_000, addedAt: day,
                            replaceAtMeters: Double(replaceAtKm) * 1_000)
            store.change { $0.add(pair, makeDefault: makeDefault) }
        }
        dismiss()
    }
}

/// Which pair a run counts for, as a menu: the pairs in use, and none. Before a run
/// it sets the default; after one, the pair that run was in.
struct ShoeMenu: View {
    let title: String
    let selected: Shoe?
    let onPick: (UUID?) -> Void
    @State private var store = ShoeStore.shared

    var body: some View {
        Menu {
            Picker(title, selection: Binding(get: { selected?.id }, set: { onPick($0) })) {
                ForEach(store.log.active) { pair in
                    Text(pair.name).tag(Optional(pair.id))
                }
                Text("None").tag(UUID?.none)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "shoe").accessibilityHidden(true)
                Text(selected.map { "\(title): \($0.name)" } ?? "\(title): none")
                Image(systemName: "chevron.up.chevron.down").font(.caption2).accessibilityHidden(true)
            }
            .font(.subheadline)
        }
        .accessibilityLabel("\(title), \(selected?.name ?? "none")")
    }
}

/// On Today, when a pair in use has run the distance set for replacing it. Said
/// once and plainly: the number is a rule of thumb, so it offers to archive them or
/// to wait another 100 km, and never asks again before then.
struct ShoeDueNote: View {
    @State private var store = ShoeStore.shared

    var body: some View {
        if let pair = store.dueForReplacing.first {
            let meters = store.meters(of: pair)
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text("Your \(pair.name) have run \(Format.distanceCompact((meters / 1_000).rounded() * 1_000)), past the \(Format.distanceCompact(pair.replaceAtMeters)) you set for replacing them. If the midsole feels flat or new aches turn up, it's time for a new pair.")
                        .font(.subheadline)
                } icon: {
                    Image(systemName: "shoe").foregroundStyle(.tint)
                }
                HStack(spacing: 10) {
                    Button("Archive them") { store.change { $0.archive(pair.id) } }
                        .buttonStyle(.glass)
                        .frame(maxWidth: .infinity)
                    Button("Another 100 km") {
                        var later = pair
                        later.replaceAtMeters = (meters / 1_000).rounded(.up) * 1_000 + 100_000
                        store.change { $0.update(later) }
                    }
                    .buttonStyle(.glass)
                    .frame(maxWidth: .infinity)
                }
                .font(.subheadline.weight(.semibold))
            }
            .brandCard()
        }
    }
}
