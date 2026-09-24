import Foundation

/// A versioned, self-describing backup of everything needed to reconstruct a
/// training plan on another device: the regenerable `PlanInputs` (goal, training
/// rules, vacations, fitness, start date).
///
/// **No personal data and no recorded runs.** Runs live in HealthKit and migrate
/// with the OS (encrypted iCloud / device-to-device); this file holds only the
/// training inputs the user set. It is plain JSON — now that we persist inputs
/// (~1 KB) rather than the expanded calendar (~89 KB), compression would add an
/// Apple-only dependency to this otherwise platform-agnostic package for no
/// meaningful saving, and would cost the file its human-readability.
public struct PlanBackup: Sendable, Equatable, Codable {
    /// Bumped only on a breaking change to the stored shape. `decode` refuses a
    /// version newer than it understands and migrates older ones.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// The app version that wrote the file — for diagnostics only.
    public var appVersion: String
    public var exportedAt: Date
    public var inputs: PlanInputs

    public init(
        inputs: PlanInputs,
        appVersion: String,
        exportedAt: Date = .now,
        schemaVersion: Int = PlanBackup.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.exportedAt = exportedAt
        self.inputs = inputs
    }
}

/// Errors surfaced when a backup file can't be produced or restored.
public enum PlanBackupError: Error, Equatable {
    /// There is no active plan to export.
    case nothingToExport
    /// The file was written by a newer app than this one understands.
    case unsupportedVersion(found: Int, supported: Int)
    /// The file isn't a valid backup (corrupt, truncated, or unrelated data).
    case corruptData
}

/// Encodes and decodes `PlanBackup` for offline export & import. Lives in
/// TrainingCore so it stays pure and unit-testable without Apple hardware.
public enum PlanBackupCodec {
    public static func encode(_ backup: PlanBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    /// Decodes and validates a backup. Throws `PlanBackupError.corruptData` for
    /// unreadable input and `.unsupportedVersion` for a newer schema.
    public static func decode(_ data: Data) throws -> PlanBackup {
        let backup: PlanBackup
        do {
            backup = try JSONDecoder().decode(PlanBackup.self, from: data)
        } catch {
            throw PlanBackupError.corruptData
        }
        guard backup.schemaVersion <= PlanBackup.currentSchemaVersion else {
            throw PlanBackupError.unsupportedVersion(
                found: backup.schemaVersion, supported: PlanBackup.currentSchemaVersion
            )
        }
        // No migrations needed at v1; older-but-supported versions decode as-is
        // (additive fields are tolerated by the models' own decoders).
        return backup
    }
}
