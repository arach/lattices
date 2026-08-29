import SwiftUI

/// Lightweight preferences window (menu bar / separate window path).
/// The in-app Settings pane lives in `ActionLauncherRootView`.
struct ActionSettingsRootView: View {
    @Binding var appearanceMode: ActionAppearanceMode
    @ObservedObject private var themeStore = ActionThemeStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ActionSettingsPageHeader(
                title: "Appearance",
                subtitle: "Theme, light and dark"
            )

            ActionSettingsSection(title: "Mode") {
                ActionSettingsControlRow(
                    title: "Light and dark",
                    subtitle: nil,
                    icon: "circle.lefthalf.filled"
                ) {
                    ActionSegmentedControl(
                        options: ActionAppearanceMode.allCases.map { ($0, $0.title) },
                        selection: $appearanceMode
                    )
                    .frame(width: 220)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 480, height: 260, alignment: .topLeading)
        .background(StageHUDTheme.appBackground)
        .id(themeStore.revision)
    }
}
