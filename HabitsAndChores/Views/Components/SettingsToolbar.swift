import SwiftUI

/// Adds a Settings gear button to the top-right of a screen's navigation bar, opening
/// `SettingsView` as a sheet. Applied to each top-level tab (Today / Tasks / Stats /
/// Awards / Households) so Settings is reachable everywhere instead of being its own
/// tab. Must be used inside a `NavigationStack` (it contributes a toolbar item).
private struct SettingsToolbar: ViewModifier {
    @State private var showSettings = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
    }
}

extension View {
    /// Adds the global Settings gear (top-right) that presents `SettingsView` as a sheet.
    func settingsToolbar() -> some View { modifier(SettingsToolbar()) }
}
