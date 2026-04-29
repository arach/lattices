import SwiftUI

struct HomeDashboardView: View {
    var onNavigate: ((AppPage) -> Void)? = nil

    @ObservedObject private var scanner = ProjectScanner.shared
    @ObservedObject private var piSession = PiChatSession.shared

    var body: some View {
        VStack(spacing: 0) {
            hero

            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.5)

            MainView(scanner: scanner, layout: .embedded)
        }
        .background(Palette.bg)
        .onAppear {
            piSession.refreshBinaryAvailability()
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Home")
                        .font(Typo.heading(18))
                        .foregroundColor(Palette.text)

                    Text("Workspace status, project launch, Screen Map, Desktop Inventory, and Pi in one place.")
                        .font(Typo.mono(11))
                        .foregroundColor(Palette.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                homeActionCard(
                    title: "Screen Map",
                    subtitle: "Arrange windows and layers",
                    icon: "rectangle.3.group",
                    tint: Palette.running
                ) {
                    onNavigate?(.screenMap)
                }

                homeActionCard(
                    title: "Desktop Inventory",
                    subtitle: "Windows, Spaces, and OCR",
                    icon: "macwindow.on.rectangle",
                    tint: Palette.detach
                ) {
                    onNavigate?(.desktopInventory)
                }

                homeActionCard(
                    title: "Pi",
                    subtitle: piSession.hasPiBinary
                        ? (piSession.needsProviderSetup || piSession.isAuthenticating
                            ? piSession.setupStatusSummary
                            : "Standalone assistant workspace")
                        : "Install Pi to enable the assistant",
                    icon: "terminal",
                    tint: piSession.hasPiBinary ? Palette.text : Palette.kill
                ) {
                    onNavigate?(.pi)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                colors: [
                    Palette.running.opacity(0.08),
                    Color.black.opacity(0.18),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func homeActionCard(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(tint)

                    Spacer()

                    Circle()
                        .fill(tint.opacity(0.85))
                        .frame(width: 6, height: 6)
                }

                Text(title)
                    .font(Typo.monoBold(12))
                    .foregroundColor(Palette.text)

                Text(subtitle)
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textMuted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Palette.surface.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(tint.opacity(0.18), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
