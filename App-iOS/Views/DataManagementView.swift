import SwiftUI
import UniformTypeIdentifiers
import TrainingCore

/// Offline backup & restore for the training plan. Export writes the regenerable
/// inputs (goal, rules, vacations, fitness) to a JSON file via the share sheet /
/// Files; import reads one back and replaces the current plan. Everything stays
/// on-device — no cloud, no account. Recorded runs live in Apple Health and are
/// never part of the file.
struct DataManagementView: View {
    let coordinator: PlanCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var exportDocument: PlanBackupDocument?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var pendingImport: Data?
    @State private var showImportConfirm = false
    @State private var showResetConfirm = false
    @State private var alertMessage: String?
    @State private var usage = PlanCoordinator.StorageUsage(planBytes: 0, storeBytes: 0)

    var body: some View {
        List {
            Section {
                LabeledContent("Plan data", value: byteText(usage.planBytes))
                LabeledContent("On-device store", value: byteText(usage.storeBytes))
            } header: {
                Text("Storage")
            } footer: {
                Text("endurancr stores only your goal and training rules. Your calendar is regenerated on the fly, so past weeks take up no space and there's nothing to prune. Recorded runs live in Apple Health and aren't counted here.")
            }

            Section {
                Button {
                    startExport()
                } label: {
                    Label("Export plan…", systemImage: "square.and.arrow.up")
                }
                .disabled(coordinator.inputs == nil)
            } header: {
                Text("Back up")
            } footer: {
                Text("Saves your goal, training rules, and vacations to a file you can keep or AirDrop to a new iPhone. No personal data or recorded runs; those stay in Apple Health.")
            }

            Section {
                Button {
                    showImporter = true
                } label: {
                    Label("Import plan…", systemImage: "square.and.arrow.down")
                }
            } footer: {
                Text("Restores a plan from a backup file. This replaces your current plan; recorded runs in Health are kept.")
            }

            Section {
                Button("Reset all data", role: .destructive) { showResetConfirm = true }
                    .disabled(coordinator.inputs == nil)
            } footer: {
                Text("Deletes your goal and plan from this iPhone. Recorded runs in Apple Health are kept, so set a new goal or import a backup afterward.")
            }
        }
        .navigationTitle("Storage & Data")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task { usage = coordinator.storageUsage() }
        .confirmationDialog(
            "Reset all data?",
            isPresented: $showResetConfirm, titleVisibility: .visible
        ) {
            Button("Delete plan", role: .destructive) {
                coordinator.deletePlan()
                usage = coordinator.storageUsage()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes your goal and training plan from this iPhone. Recorded runs in Apple Health are kept.")
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result { alertMessage = error.localizedDescription }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handlePicked(result)
        }
        .confirmationDialog(
            "Replace your current plan?",
            isPresented: $showImportConfirm, titleVisibility: .visible
        ) {
            Button("Replace plan", role: .destructive) { performImport() }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: {
            Text("Importing replaces your current goal and training rules. Recorded runs in Health are kept.")
        }
        .alert("Backup & restore", isPresented: alertBinding) {
            Button("OK", role: .cancel) { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    // MARK: Export

    private func startExport() {
        do {
            exportDocument = PlanBackupDocument(data: try coordinator.exportData())
            showExporter = true
        } catch PlanBackupError.nothingToExport {
            alertMessage = "There's no plan to export yet. Set your goal first."
        } catch {
            alertMessage = "Couldn't create the backup: \(error.localizedDescription)"
        }
    }

    private var exportFilename: String {
        let base = coordinator.inputs?.goal.displayName ?? "endurancr plan"
        let safe = base.replacingOccurrences(of: "/", with: "-")
        return "\(safe) backup"
    }

    // MARK: Import

    private func handlePicked(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let needsStop = url.startAccessingSecurityScopedResource()
            defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
            do {
                pendingImport = try Data(contentsOf: url)
                showImportConfirm = true
            } catch {
                alertMessage = "Couldn't read the file: \(error.localizedDescription)"
            }
        case .failure(let error):
            alertMessage = error.localizedDescription
        }
    }

    private func performImport() {
        guard let data = pendingImport else { return }
        pendingImport = nil
        do {
            try coordinator.importData(data)
            Task {
                await coordinator.refreshAdaptation()
                dismiss()
            }
        } catch PlanBackupError.unsupportedVersion(let found, let supported) {
            alertMessage = "This backup was made by a newer version of endurancr (format \(found); this app supports \(supported)). Update the app and try again."
        } catch is PlanBackupError {
            alertMessage = "That file isn't a valid endurancr backup."
        } catch {
            alertMessage = "Couldn't import the plan: \(error.localizedDescription)"
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
    }

    /// Human-readable size, e.g. "342 bytes" / "1 KB". `.file` style keeps small
    /// figures honest rather than rounding everything up to "1 KB".
    private func byteText(_ bytes: Int) -> String {
        Int64(bytes).formatted(.byteCount(style: .file))
    }
}

/// A minimal `FileDocument` that carries already-encoded backup bytes to
/// `.fileExporter`. The JSON is produced by `PlanBackupCodec` in TrainingCore;
/// this only moves the bytes into the share/Files flow.
struct PlanBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data
    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
