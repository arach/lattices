import AppKit
import SwiftUI
import HudsonUI

struct WorkspaceAssistantView: View {
    @StateObject private var session = WorkspaceAssistantSession.shared
    @StateObject private var runtimes = AssistantRuntimeCatalog.shared
    @FocusState private var composerFocused: Bool
    @State private var pickingRuntime = false
    @AppStorage(AssistantAppearance.defaultsKey) private var appearance = AssistantAppearance.dark.rawValue

    var body: some View {
        VStack(spacing: 0) {
            header
            WorkspaceAssistantTranscript(session: session, style: .workspace)
            WorkspaceAssistantComposer(
                session: session,
                style: .workspace,
                focus: $composerFocused,
                runtimePicking: $pickingRuntime
            )
        }
        .hudRuntimePicker(
            isPresented: $pickingRuntime,
            harnesses: runtimes.harnesses,
            efforts: runtimes.efforts,
            selection: Binding(
                get: { session.runtimeSelection },
                set: { session.runtimeSelection = $0 }
            )
        )
        .environment(\.hudTheme, .latticesAssistant)
        .onAppear { runtimes.refresh() }
        .onChange(of: pickingRuntime) { _, open in
            if !open { composerFocused = true }
        }
        .background(WorkspaceAssistantSurface())
        // Inks are read from defaults, so a theme flip rebuilds the page.
        .id(appearance)
        .background(WorkspaceFocusActivator())
        .onReceive(NotificationCenter.default.publisher(for: .workspaceComposerFocus)) { _ in
            // Fired exactly when the hosting window becomes key, so setting the
            // caret here actually renders it — no timed guessing.
            composerFocused = true
        }
        .onAppear {
            session.prepareForDisplay()
        }
    }

    /// On the transcript's column, so the status line, every turn and the
    /// composer share one left edge. A one-pixel rule is the hard edge the
    /// transcript scrolls under.
    private var header: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 2) {
                WorkspaceAssistantStatusLine(session: session)

                Spacer(minLength: 12)

                if session.hasConversationHistory {
                    HudSquareIconButton(symbol: "doc.on.doc", help: "Copy chat") {
                        session.copyConversationToClipboard()
                    }
                    HudSquareIconButton(symbol: "square.and.pencil", help: "New chat") {
                        session.clearConversation()
                    }
                }
                HudSquareIconButton(
                    symbol: appearance == AssistantAppearance.light.rawValue ? "moon" : "sun.max",
                    help: appearance == AssistantAppearance.light.rawValue ? "Dark page" : "Light page"
                ) {
                    appearance = appearance == AssistantAppearance.light.rawValue
                        ? AssistantAppearance.dark.rawValue
                        : AssistantAppearance.light.rawValue
                }
                HudSquareIconButton(symbol: "slider.horizontal.3", help: "Assistant settings") {
                    SettingsWindowController.shared.showAssistant()
                }
                .padding(.trailing, -7)
            }
            .frame(maxWidth: WorkspaceAssistantStyle.workspace.maxContentWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, WorkspaceAssistantStyle.workspace.horizontalPadding)
            .frame(height: 40)

            HudRule(color: HudTheme.latticesAssistant.hairline.subtle)
        }
    }
}

/// The page surface: one flat, opaque colour, the same ground every text
/// view paints under its glyphs. No backdrop blur and no tint layers.
struct WorkspaceAssistantSurface: View {
    var body: some View {
        Color(nsColor: AssistantInk.page)
            .ignoresSafeArea()
    }
}

extension Notification.Name {
    /// Posted when the assistant's hosting window becomes key, so the composer
    /// can take the caret at the exact moment it can actually render one.
    static let workspaceComposerFocus = Notification.Name("dev.lattices.workspaceComposerFocus")
}

/// Zero-size bridge that activates the app + makes the hosting window key on
/// attach, and re-signals focus every time the window becomes key.
private struct WorkspaceFocusActivator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { FocusTrackerView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class FocusTrackerView: NSView {
        private var observer: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            if observer == nil {
                observer = NotificationCenter.default.addObserver(
                    forName: NSWindow.didBecomeKeyNotification,
                    object: window,
                    queue: .main
                ) { _ in
                    NotificationCenter.default.post(name: .workspaceComposerFocus, object: nil)
                }
            }
            // If it's already key (tab switch within a focused window), signal now.
            if window.isKeyWindow {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .workspaceComposerFocus, object: nil)
                }
            }
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
