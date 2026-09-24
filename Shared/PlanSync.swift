import Foundation
import SwiftData
import TrainingCore
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Peer-to-peer plan sync between the paired iPhone and Apple Watch over
/// WatchConnectivity. Local-only, no cloud: the phone is the source of truth and
/// publishes the (~1 KB) `PlanInputs` JSON as the session's "application context".
/// WatchConnectivity stores the latest context and delivers it to the watch even
/// when the watch app is not running, so the watch mirrors the plan into its own
/// SwiftData store and its today view works standalone.
///
/// Application context (rather than messages/transfers) is deliberate: it always
/// coalesces to the newest state and survives app relaunches, which is exactly the
/// semantics of "the current plan" — we never need history, only the latest.
@MainActor
final class PlanSync: NSObject {
    static let shared = PlanSync()

    /// The watch app sets this so received contexts can be written into the store
    /// the today view reads from. Unused on iOS.
    var container: ModelContainer?

    /// The last inputs the phone asked to publish, retained so we can (re)send once
    /// the session finishes activating. Unused on watchOS.
    private var pendingContext: [String: Any]?

    private var session: WCSession? {
        WCSession.isSupported() ? WCSession.default : nil
    }

    /// Activates the session. Call once at app launch on both platforms.
    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: Phone -> Watch

    /// Publishes the latest inputs to the watch (or clears them when `nil`).
    /// Coalesces to the newest state, so it is safe to call on every plan change.
    func publish(inputs: PlanInputs?) {
        var context: [String: Any] = [:]
        if let inputs, let data = try? JSONEncoder().encode(inputs) {
            context["inputs"] = data
        }
        pendingContext = context
        flush()
    }

    private func flush() {
        guard let session, session.activationState == .activated,
              let context = pendingContext else { return }
        // Best-effort: if this throws the watch simply keeps its prior state and
        // catches up on the next successful publish.
        try? session.updateApplicationContext(context)
    }

    // MARK: Watch <- Phone

    /// Mirrors the phone's current inputs into the watch's own store, replacing
    /// whatever it held. A `nil` payload means the phone has no plan, so the watch
    /// clears too. Takes `Data?` (Sendable) rather than the raw context dictionary
    /// so it can cross the actor boundary from the WCSession delegate thread.
    private func apply(inputsData: Data?) {
        guard let container else { return }
        let moc = ModelContext(container)
        try? moc.delete(model: StoredPlan.self)
        if let inputsData,
           let inputs = try? JSONDecoder().decode(PlanInputs.self, from: inputsData) {
            moc.insert(StoredPlan(inputs: inputs))
        }
        try? moc.save()
    }
}

extension PlanSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        // Extract the Sendable payload off the delegate thread, then hand off to the
        // main actor for the flush/apply.
        let inputsData = session.receivedApplicationContext["inputs"] as? Data
        Task { @MainActor in
            self.flush()                    // phone: (re)send once activated
            self.apply(inputsData: inputsData) // watch: catch up on last delivered state
        }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        let inputsData = applicationContext["inputs"] as? Data
        Task { @MainActor in self.apply(inputsData: inputsData) }
    }

    #if os(iOS)
    // Required on iOS; re-activate so a switched watch keeps syncing.
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
