import AppKit
import SwiftUI

/// Calm, opt-in setup surface for capabilities that require an OS permission.
/// Never opens automatically — only from explicit entry points
/// (banner button, onboarding row, Settings, feature gate).
struct PermissionsAssistantView: View {
    @ObservedObject private var permChecker = PermissionChecker.shared
    @ObservedObject private var prefs = Preferences.shared
    @Binding var selected: Capability
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 240, alignment: .top)

            Rectangle()
                .fill(Palette.border)
                .frame(width: 0.5)
                .frame(maxHeight: .infinity)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(PanelBackground())
        .preferredColorScheme(.dark)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("CAPABILITIES")
                    .font(Typo.pixel(14))
                    .foregroundColor(Palette.textDim)
                    .tracking(1)
                Text("Lattices works with whichever of these you turn on. Nothing here runs unless you press the button.")
                    .font(Typo.caption(11))
                    .foregroundColor(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 6) {
                ForEach(Capability.allCases) { cap in
                    sidebarRow(cap)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private func sidebarRow(_ cap: Capability) -> some View {
        let active = selected == cap
        let granted = cap.isGranted

        return Button {
            selected = cap
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: cap.iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(active ? Palette.text : Palette.textMuted)
                    .frame(width: 16, alignment: .center)

                VStack(alignment: .leading, spacing: 3) {
                    Text(cap.title)
                        .font(Typo.mono(11))
                        .foregroundColor(active ? Palette.text : Palette.textMuted)

                    Text(cap.requirementLabel)
                        .font(Typo.caption(9.5))
                        .foregroundColor(Palette.textMuted.opacity(active ? 0.9 : 0.7))
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                statusDot(granted: granted)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(active ? Palette.surfaceHov : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func statusDot(granted: Bool) -> some View {
        Circle()
            .fill(granted ? Palette.running : Palette.detach)
            .frame(width: 6, height: 6)
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero(selected)
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 16)

            Rectangle().fill(Palette.border).frame(height: 0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    valueCard(selected)
                    statusCard(selected)
                    actionsCard(selected)

                    if prefs.isCapabilityDismissed(selected.rawValue) {
                        Text("You snoozed this earlier. We will not nag — opening this from a feature will surface it again.")
                            .font(Typo.caption(10))
                            .foregroundColor(Palette.textMuted)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
        }
    }

    private func hero(_ cap: Capability) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Palette.surface)
                    .frame(width: 40, height: 40)
                Image(systemName: cap.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(cap.title)
                    .font(Typo.heading(14))
                    .foregroundColor(Palette.text)
                Text(cap.requirementLabel)
                    .font(Typo.mono(10))
                    .foregroundColor(Palette.textMuted)
            }

            Spacer()

            buildChannelBadge
            statusBadge(cap)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Palette.textMuted)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
        }
    }

    private func statusBadge(_ cap: Capability) -> some View {
        let granted = cap.isGranted
        let label = granted ? "ON" : (prefs.isCapabilityDismissed(cap.rawValue) ? "SNOOZED" : "OFF")
        let color: Color = granted ? Palette.running : Palette.detach

        return Text(label)
            .font(Typo.monoBold(9))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(color.opacity(0.12))
            )
    }

    private var buildChannelBadge: some View {
        let tint = LatticesRuntime.isDevBuild ? Palette.detach : Palette.running

        return Text(LatticesRuntime.buildChannelLabel)
            .font(Typo.monoBold(9))
            .foregroundColor(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(tint.opacity(0.12))
                    .overlay(
                        Capsule()
                            .strokeBorder(tint.opacity(0.28), lineWidth: 0.5)
                    )
            )
    }

    private func valueCard(_ cap: Capability) -> some View {
        sectionCard(title: "WHAT YOU GET") {
            VStack(alignment: .leading, spacing: 6) {
                Text(cap.pitch)
                    .font(Typo.body(12))
                    .foregroundColor(Palette.text)
                    .lineSpacing(3)
                Text(cap.why)
                    .font(Typo.caption(10))
                    .foregroundColor(Palette.textMuted)
                    .lineSpacing(2)
            }
        }
    }

    private func statusCard(_ cap: Capability) -> some View {
        sectionCard(title: "STATUS") {
            HStack(spacing: 8) {
                Image(systemName: cap.isGranted ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.system(size: 12))
                    .foregroundColor(cap.isGranted ? Palette.running : Palette.detach)
                Text(cap.isGranted ? cap.whenGrantedDetail : "Not enabled. Lattices works without it; the rest of the app stays usable.")
                    .font(Typo.mono(11))
                    .foregroundColor(Palette.text)
                Spacer(minLength: 0)
            }
        }
    }

    private func actionsCard(_ cap: Capability) -> some View {
        sectionCard(title: "ACTIONS") {
            VStack(alignment: .leading, spacing: 10) {
                primaryAction(cap)

                HStack(spacing: 10) {
                    if !cap.isGranted {
                        Button {
                            prefs.dismissCapability(cap.rawValue)
                        } label: {
                            Text(prefs.isCapabilityDismissed(cap.rawValue) ? "Snoozed" : "Maybe later")
                                .font(Typo.monoBold(10))
                                .foregroundColor(Palette.textMuted)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Palette.surface)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .strokeBorder(Palette.border, lineWidth: 0.5)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(prefs.isCapabilityDismissed(cap.rawValue))
                    }

                    Button {
                        openSystemSettings(cap)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 9))
                            Text("Open System Settings")
                                .font(Typo.monoBold(10))
                        }
                        .foregroundColor(Palette.textMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Palette.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(Palette.border, lineWidth: 0.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }

                Text(actionFootnote(cap))
                    .font(Typo.caption(9.5))
                    .foregroundColor(Palette.textMuted)
            }
        }
    }

    @ViewBuilder
    private func primaryAction(_ cap: Capability) -> some View {
        if cap.isGranted {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Palette.running)
                Text("Enabled")
                    .font(Typo.monoBold(11))
                    .foregroundColor(Palette.running)
            }
            .padding(.vertical, 4)
        } else {
            Button {
                triggerPrimary(cap)
            } label: {
                Text(primaryLabel(cap))
                    .angularButton(.white, filled: false)
            }
            .buttonStyle(.plain)
        }
    }

    private func primaryLabel(_ cap: Capability) -> String {
        switch cap {
        case .windowControl: return "Request Accessibility"
        case .screenSearch:  return "Enable OCR"
        }
    }

    private func actionFootnote(_ cap: Capability) -> String {
        switch cap {
        case .windowControl:
            return "macOS will add Lattices to its Accessibility list. You finish the toggle in System Settings."
        case .screenSearch:
            return "Enabling this turns on OCR and asks macOS for Screen Recording on this Mac."
        }
    }

    private func triggerPrimary(_ cap: Capability) {
        // The primary action is the explicit user gesture — clear any prior snooze.
        prefs.clearDismissal(cap.rawValue)

        switch cap {
        case .windowControl:
            permChecker.requestAccessibility()
        case .screenSearch:
            // Turning on OCR is the moment we ask for Screen Recording.
            OcrModel.shared.setEnabled(true)
        }
    }

    private func openSystemSettings(_ cap: Capability) {
        switch cap {
        case .windowControl: permChecker.openAccessibilitySettings()
        case .screenSearch:  permChecker.openScreenRecordingSettings()
        }
    }

    // MARK: - Section card

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Typo.pixel(11))
                .foregroundColor(Palette.textDim)
                .tracking(1)
            content()
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Palette.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Palette.border, lineWidth: 0.5)
                        )
                )
        }
    }
}
