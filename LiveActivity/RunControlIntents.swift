import AppIntents
import Foundation

/// Notifications posted by the Live Activity control buttons. `LiveActivityIntent`
/// runs in the *app's* process, so a plain `NotificationCenter` post reaches the
/// active `PhoneWorkoutManager`. Keeping the intents free of app-only types lets
/// this file compile into both the app and the widget extension (the widget needs
/// the intent types to render `Button(intent:)`).
extension Notification.Name {
    static let runPauseRequested = Notification.Name("endurancr.run.pause")
    static let runResumeRequested = Notification.Name("endurancr.run.resume")
    static let runFinishRequested = Notification.Name("endurancr.run.finish")
}

/// Pauses the current run from the Lock Screen / Dynamic Island.
struct PauseRunIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause Run"
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .runPauseRequested, object: nil)
        return .result()
    }
}

/// Resumes a paused run.
struct ResumeRunIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume Run"
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .runResumeRequested, object: nil)
        return .result()
    }
}

/// Finishes the run and saves it to Health.
struct FinishRunIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Finish Run"
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .runFinishRequested, object: nil)
        return .result()
    }
}
