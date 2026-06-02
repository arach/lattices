import AppKit
import SwiftUI

/// Small helper for macOS privacy panes that accept app bundles by drag.
/// Useful when TCC has a stale bundle reference and the user needs to add the
/// current signed app again.
struct PermissionAppDragCard: View {
    let title: String
    let permissionName: String
    let detail: String
    let onOpenSettings: () -> Void

    private var appURL: URL {
        Bundle.main.bundleURL
    }

    private var appIcon: NSImage {
        NSWorkspace.shared.icon(forFile: appURL.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "hand.draw.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("DRAG THE CURRENT LATTICES APP")
                    .font(Typo.monoBold(9.5))

                Spacer(minLength: 0)

                Text(permissionName.uppercased())
                    .font(Typo.monoBold(8.5))
                    .foregroundColor(Palette.detach)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Palette.detach.opacity(0.12))
                            .overlay(
                                Capsule()
                                    .strokeBorder(Palette.detach.opacity(0.24), lineWidth: 0.5)
                            )
                    )
            }
            .foregroundColor(Palette.detach)

            HStack(alignment: .center, spacing: 12) {
                dragTile

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(Typo.monoBold(11))
                        .foregroundColor(Palette.text)

                    Text(detail)
                        .font(Typo.caption(10))
                        .foregroundColor(Palette.textDim)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 5) {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Palette.textMuted)
                        Text(appURL.path)
                            .font(Typo.mono(8.5))
                            .foregroundColor(Palette.textMuted.opacity(0.78))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 6) {
                    Button {
                        onOpenSettings()
                    } label: {
                        Label(permissionName, systemImage: "gearshape")
                            .font(Typo.monoBold(9.5))
                            .foregroundColor(Palette.text)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Palette.surfaceHov)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .strokeBorder(Palette.borderLit, lineWidth: 0.5)
                                    )
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([appURL])
                    } label: {
                        Label("Reveal App", systemImage: "folder")
                            .font(Typo.mono(9))
                            .foregroundColor(Palette.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Palette.detach.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Palette.detach.opacity(0.30), lineWidth: 0.75)
                )
        )
    }

    private var dragTile: some View {
        NativePermissionAppDragTile(
            appURL: appURL,
            appIcon: appIcon,
            permissionName: permissionName,
            onDragStarted: {
                PermissionChecker.shared.passiveRecheck(reason: "drag card started")
            },
            onDragCompleted: {
                PermissionChecker.shared.recheckNow(reason: "drag card completed")
            }
        )
        .frame(width: 88, height: 88)
    }
}
