import SwiftUI
import AppKit

// MARK: - Onboarding Flow

/// A step-by-step welcome screen shown on first launch.
/// Keeps setup quiet: permissions are introduced as optional capabilities
/// and requested later from the feature that needs them.
struct OnboardingView: View {
    @ObservedObject private var permChecker = PermissionChecker.shared
    @State private var step: Step = .welcome
    var onComplete: () -> Void

    enum Step: Int, CaseIterable {
        case welcome
        case capabilities
        case done
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Circle()
                        .fill(s.rawValue <= step.rawValue ? Color.white : Color.white.opacity(0.20))
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.top, 28)
            .padding(.bottom, 24)


            // Step content
            Group {
                switch step {
                case .welcome:      welcomeStep
                case .capabilities:  capabilitiesStep
                case .done:         doneStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)

            Spacer(minLength: 0)

            // Navigation
            HStack {
                if step != .welcome {
                    Button("Back") { withAnimation(.easeInOut(duration: 0.2)) { goBack() } }
                        .buttonStyle(.plain)
                        .font(Typo.mono(11))
                        .foregroundColor(Palette.textMuted)
                }
                Spacer()
                if step == .done {
                    Button(action: { onComplete() }) {
                        Text("Get started")
                            .angularButton(Palette.running)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { advance() } }) {
                        Text(nextLabel)
                            .angularButton(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 28)
        }
        .frame(width: 480, height: 470)
        .background(Palette.bg)
        .preferredColorScheme(.dark)
        .onAppear {
            PermissionChecker.shared.check(pollIfMissing: true)
        }
        .onChange(of: step) { newStep in
            if newStep == .capabilities {
                PermissionChecker.shared.check(pollIfMissing: true)
            }
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            latticesIcon
            Text("Welcome to Lattices")
                .font(Typo.title(18))
                .foregroundColor(Palette.text)
            Text("A control surface for your Mac workspace.\nArrange windows, search context, and give agents a local view.")
                .font(Typo.body(12))
                .foregroundColor(Palette.textDim)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
    }

    private var capabilitiesStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 28))
                .foregroundColor(.white.opacity(0.7))

            Text("Enable more when you need it")
                .font(Typo.title(16))
                .foregroundColor(Palette.text)

            Text("Lattices keeps setup optional. Click a capability to enable deeper control now, or skip and turn it on from Settings later.")
                .font(Typo.body(12))
                .foregroundColor(Palette.textDim)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Capability.allCases) { cap in
                    capabilityRow(cap)
                }
            }
            .padding(10)
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

    private var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(Palette.running)

            Text("Your workspace is ready")
                .font(Typo.title(18))
                .foregroundColor(Palette.text)

            VStack(alignment: .leading, spacing: 8) {
                statusRow("Window management", granted: permChecker.isGranted(.windowControl),
                          detail: permChecker.isGranted(.windowControl) ? "enabled" : "available later")
                statusRow("Screen context", granted: permChecker.isGranted(.screenSearch),
                          detail: permChecker.isGranted(.screenSearch) ? "enabled" : "available later")
                statusRow("Agent access", granted: true, detail: "local API ready")
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
            )

            Text("Open the app to see your desktop, inspect context, and choose what to enable next.")
                .font(Typo.mono(10))
                .foregroundColor(Palette.textMuted)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Shared helpers

    private func capabilityRow(_ cap: Capability) -> some View {
        let granted = permChecker.isGranted(cap)
        return Button {
            PermissionsAssistantWindowController.shared.show(focus: cap)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: cap.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(granted ? Palette.running : Palette.text.opacity(0.85))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(cap.title)
                        .font(Typo.monoBold(11))
                        .foregroundColor(Palette.text)
                    Text(cap.requirementLabel)
                        .font(Typo.mono(10))
                        .foregroundColor(Palette.textMuted)
                }
                Spacer(minLength: 0)
                Text(granted ? "ON" : "Set up")
                    .font(Typo.monoBold(9))
                    .foregroundColor(granted ? Palette.running : Palette.textDim)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill((granted ? Palette.running : Palette.borderLit).opacity(0.12))
                    )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Palette.border.opacity(0.6), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func statusRow(_ label: String, granted: Bool, detail: String? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11))
                .foregroundColor(granted ? Palette.running : Palette.detach)
            Text(label)
                .font(Typo.mono(11))
                .foregroundColor(Palette.text)
            Spacer()
            if let detail {
                Text(detail)
                    .font(Typo.mono(10))
                    .foregroundColor(granted ? Palette.textDim : Palette.detach)
            } else {
                Text(granted ? "granted" : "not set")
                    .font(Typo.mono(10))
                    .foregroundColor(granted ? Palette.running : Palette.detach)
            }
        }
    }

    private var latticesIcon: some View {
        // 3x3 grid — L-shape pattern
        let cells = [true, false, false, true, false, false, true, true, true]
        let size: CGFloat = 40
        let pad: CGFloat = 4
        let gap: CGFloat = 2.5
        let cell = (size - 2 * pad - 2 * gap) / 3
        return Canvas { context, _ in
            for (i, bright) in cells.enumerated() {
                let row = i / 3
                let col = i % 3
                let rect = CGRect(
                    x: pad + CGFloat(col) * (cell + gap),
                    y: pad + CGFloat(row) * (cell + gap),
                    width: cell, height: cell
                )
                context.fill(
                    RoundedRectangle(cornerRadius: 2).path(in: rect),
                    with: .color(bright ? .white : .white.opacity(0.18))
                )
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - Navigation

    private var nextLabel: String {
        "Continue"
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    private func goBack() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        step = prev
    }

}

// MARK: - Window Controller

final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?
    private static let completedKey = "onboarding.completed"

    var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: Self.completedKey)
    }

    /// Show the onboarding window if not yet completed.
    /// Returns true if onboarding was shown.
    @discardableResult
    func showIfNeeded() -> Bool {
        guard !hasCompleted else { return false }
        show()
        return true
    }

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingView {
            self.complete()
        }

        let w = AppWindowShell.makeWindow(
            config: .init(
                title: "Welcome to Lattices",
                titleVisible: false,
                initialSize: NSSize(width: 480, height: 470),
                minSize: NSSize(width: 480, height: 470),
                maxSize: NSSize(width: 480, height: 470),
                miniaturizable: false
            ),
            rootView: view
        )
        w.styleMask.remove(.resizable)
        AppWindowShell.positionCentered(w)
        AppWindowShell.present(w)
        self.window = w
    }

    private func complete() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        window?.orderOut(nil)
        window = nil
        ScreenMapWindowController.shared.showPage(.home)
        AppDelegate.updateActivationPolicy()
    }

    func reset() {
        UserDefaults.standard.removeObject(forKey: Self.completedKey)
    }
}
