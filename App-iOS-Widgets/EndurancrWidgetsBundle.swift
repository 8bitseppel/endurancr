import WidgetKit
import SwiftUI

/// The app's widget extension. Currently hosts only the running Live Activity
/// (Lock Screen + Dynamic Island); regular home-screen widgets could be added here.
@main
struct EndurancrWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RunLiveActivity()
    }
}
