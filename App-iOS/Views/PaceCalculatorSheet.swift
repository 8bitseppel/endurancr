import SwiftUI

/// The App Clip's pace calculator in the app, as a sheet. A floating Close button
/// instead of a navigation bar, so it lays out exactly as in the clip.
struct PaceCalculatorSheet: View {
    let action: PaceCalculatorView.Action
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PaceCalculatorView(action: action)
            .overlay(alignment: .topTrailing) {
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .padding(.trailing, 16)
                    .padding(.top, 8)
            }
            .preferredColorScheme(.dark)
    }
}
