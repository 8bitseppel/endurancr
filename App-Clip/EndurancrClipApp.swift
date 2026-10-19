import SwiftUI

/// The endurancr App Clip: a pace calculator that opens without installing, from a
/// link, QR code or the banner on endurancr.app. It reads no Health data and stores
/// nothing; the full app does the training.
@main
struct EndurancrClipApp: App {
    var body: some Scene {
        WindowGroup {
            PaceCalculatorView()
        }
    }
}
