import SwiftUI

/// The App Clip's pace calculator in the app, as a sheet with a Close button.
struct PaceCalculatorSheet: View {
    let action: PaceCalculatorView.Action
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PaceCalculatorView(action: action)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                    }
                }
        }
        .preferredColorScheme(.dark)
    }
}
