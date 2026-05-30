import AppKit
import CoreGraphics
import SwiftUI

private final class PermissionDragAssistantPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class PermissionDragAssistantWindowController: ObservableObject {
    static let shared = PermissionDragAssistantWindowController()

    private var panel: NSPanel?
    @Published private(set) var focusedCapability: Capability = .windowControl

    var isVisible: Bool { panel?.isVisible ?? false }

    private init() {}

    func show(focus capability: Capability, openSettings: Bool = true) {
        focusedCapability = capability
        PermissionChecker.shared.passiveRecheck(reason: "show drag helper")

        if openSettings {
            PermissionChecker.shared.openSettings(for: capability)
        }

        let content = PermissionDragAssistantView(
            capability: capability,
            onOpenSettings: { PermissionChecker.shared.openSettings(for: capability) },
            onRevealApp: { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) },
            onClose: { PermissionDragAssistantWindowController.shared.close() }
        )

        let activePanel: NSPanel
        if let panel {
            panel.title = "\(capability.requirementLabel) Helper"
            panel.contentViewController = NSHostingController(rootView: content)
            activePanel = panel
        } else {
            let panel = PermissionDragAssistantPanel(
                contentRect: NSRect(x: 0, y: 0, width: 430, height: 260),
                styleMask: [.titled, .closable, .utilityWindow, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.title = "\(capability.requirementLabel) Helper"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false
            panel.isRestorable = false
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = false
            panel.acceptsMouseMovedEvents = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.backgroundColor = NSColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1.0)
            panel.appearance = NSAppearance(named: .darkAqua)
            panel.contentViewController = NSHostingController(rootView: content)
            panel.setContentSize(NSSize(width: 430, height: 260))
            self.panel = panel
            activePanel = panel
        }

        Task { @MainActor [weak self, weak activePanel] in
            if openSettings {
                _ = await Self.waitForSystemSettingsFrontmost(timeout: 6.0)
            }
            guard let self, let activePanel else { return }
            self.position(activePanel)
            NSApp.activate(ignoringOtherApps: true)
            activePanel.orderFrontRegardless()
            activePanel.makeKey()
            AppDelegate.updateActivationPolicy()
        }
    }

    func close() {
        panel?.orderOut(nil)
        AppDelegate.updateActivationPolicy()
    }

    private static func waitForSystemSettingsFrontmost(timeout: TimeInterval) async -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if let app = NSWorkspace.shared.frontmostApplication,
               isSystemSettings(app) {
                return true
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return false
    }

    private static func isSystemSettings(_ app: NSRunningApplication) -> Bool {
        switch app.bundleIdentifier {
        case "com.apple.systempreferences", "com.apple.SystemSettings":
            return true
        default:
            return app.localizedName == "System Settings"
        }
    }

    private func position(_ panel: NSPanel) {
        let size = CGSize(width: 430, height: 260)
        let anchor = Self.systemSettingsWindowBounds()
            ?? Self.largestCurrentAppWindowBounds(excluding: panel)

        guard let anchor else {
            positionOnMainScreen(panel, size: size)
            return
        }

        let displayBounds = Self.displayBounds(containing: anchor)
            ?? Self.displayBounds(containing: CGPoint(x: anchor.midX, y: anchor.midY))
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)

        let margin: CGFloat = 16
        let gap: CGFloat = 12
        let centeredX = anchor.midX - size.width / 2
        let centeredY = anchor.midY - size.height / 2
        let x: CGFloat
        let y: CGFloat

        if anchor.maxX + gap + size.width <= displayBounds.maxX - margin {
            x = anchor.maxX + gap
            y = clamp(centeredY, min: displayBounds.minY + margin, max: displayBounds.maxY - size.height - margin)
        } else if anchor.minX - gap - size.width >= displayBounds.minX + margin {
            x = anchor.minX - gap - size.width
            y = clamp(centeredY, min: displayBounds.minY + margin, max: displayBounds.maxY - size.height - margin)
        } else if anchor.maxY + gap + size.height <= displayBounds.maxY - margin {
            x = clamp(centeredX, min: displayBounds.minX + margin, max: displayBounds.maxX - size.width - margin)
            y = anchor.maxY + gap
        } else if anchor.minY - gap - size.height >= displayBounds.minY + margin {
            x = clamp(centeredX, min: displayBounds.minX + margin, max: displayBounds.maxX - size.width - margin)
            y = anchor.minY - gap - size.height
        } else {
            x = clamp(centeredX, min: displayBounds.minX + margin, max: displayBounds.maxX - size.width - margin)
            y = displayBounds.maxY - size.height - margin
        }

        let topLeft = CGPoint(x: x, y: y)
        let origin = CGPoint(
            x: topLeft.x,
            y: displayBounds.maxY - (topLeft.y - displayBounds.minY) - size.height
        )

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func positionOnMainScreen(_ panel: NSPanel, size: CGSize) {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = max(screenFrame.minX + 16, screenFrame.maxX - size.width - 32)
        let y = max(screenFrame.minY + 16, screenFrame.maxY - size.height - 72)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    private static func systemSettingsWindowBounds() -> CGRect? {
        visibleWindowBounds {
            ($0[kCGWindowOwnerName as String] as? String) == "System Settings"
        }
    }

    private static func largestCurrentAppWindowBounds(excluding panel: NSPanel) -> CGRect? {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        return visibleWindowBounds {
            guard let ownerPID = ($0[kCGWindowOwnerPID as String] as? NSNumber)?.intValue,
                  ownerPID == currentPID else { return false }
            guard let bounds = windowBounds(from: $0), bounds.width > panel.frame.width + 40 else { return false }
            return true
        }
    }

    private static func visibleWindowBounds(where matches: (NSDictionary) -> Bool) -> CGRect? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [NSDictionary] else {
            return nil
        }

        return windows
            .filter { matches($0) }
            .compactMap(windowBounds(from:))
            .filter { $0.width > 100 && $0.height > 100 }
            .max { $0.width * $0.height < $1.width * $1.height }
    }

    private static func windowBounds(from info: NSDictionary) -> CGRect? {
        guard let dictionary = info[kCGWindowBounds as String] as? NSDictionary else {
            return nil
        }
        return CGRect(dictionaryRepresentation: dictionary)
    }

    private static func displayBounds(containing rect: CGRect) -> CGRect? {
        displayBounds(containing: CGPoint(x: rect.midX, y: rect.midY))
    }

    private static func displayBounds(containing point: CGPoint) -> CGRect? {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)

        return displays
            .map(CGDisplayBounds)
            .first { $0.contains(point) }
    }

    private func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.max(minimum, Swift.min(value, maximum))
    }
}

private struct PermissionDragAssistantView: View {
    @ObservedObject private var permChecker = PermissionChecker.shared
    private static let checkTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    let capability: Capability
    let onOpenSettings: () -> Void
    let onRevealApp: () -> Void
    let onClose: () -> Void

    private var appURL: URL { Bundle.main.bundleURL }
    private var appIcon: NSImage { NSWorkspace.shared.icon(forFile: appURL.path) }

    private var granted: Bool { permChecker.isGranted(capability) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: capability.iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(granted ? Palette.running : Palette.detach)
                    .frame(width: 30, height: 30)
                    .background((granted ? Palette.running : Palette.detach).opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 3) {
                    Text(granted ? "\(capability.requirementLabel) is enabled" : "Drag Lattices into \(capability.requirementLabel)")
                        .font(Typo.heading(13))
                        .foregroundColor(Palette.text)
                    Text(granted ? capability.whenGrantedDetail : "Remove older Lattices rows first if they exist. Then drag this current app into the list and toggle it on.")
                        .font(Typo.caption(10))
                        .foregroundColor(Palette.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                statusBadge
            }

            HStack(alignment: .center, spacing: 14) {
                NativePermissionAppDragTile(
                    appURL: appURL,
                    appIcon: appIcon,
                    permissionName: capability.requirementLabel,
                    isDragEnabled: !granted,
                    onDragStarted: {
                        PermissionChecker.shared.passiveRecheck(reason: "drag started")
                    },
                    onDragCompleted: {
                        PermissionChecker.shared.recheckNow(reason: "drag completed")
                    }
                )
                .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Lattices.app")
                        .font(Typo.monoBold(11))
                        .foregroundColor(Palette.text)
                    Text(Bundle.main.bundleIdentifier ?? LatticesRuntime.releaseBundleIdentifier)
                        .font(Typo.mono(9.5))
                        .foregroundColor(Palette.textDim)
                        .textSelection(.enabled)
                    Text(appURL.path)
                        .font(Typo.mono(8.5))
                        .foregroundColor(Palette.textMuted)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Text(checkHint)
                        .font(Typo.mono(8.5))
                        .foregroundColor(granted ? Palette.running : (permChecker.refreshInFlight ? Palette.detach : Palette.textMuted))
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button {
                    onOpenSettings()
                } label: {
                    Label("Open Settings", systemImage: "gearshape")
                }

                Button {
                    onRevealApp()
                } label: {
                    Label("Reveal App", systemImage: "folder")
                }

                if !granted {
                    Button {
                        PermissionChecker.shared.resetSavedApproval(for: capability)
                    } label: {
                        Label("Clear Row", systemImage: "trash")
                    }
                    .help("Clears Lattices' saved macOS permission row, then reopens this privacy pane.")
                }

                Button {
                    PermissionChecker.shared.recheckNow(reason: "drag helper")
                } label: {
                    Label(permChecker.refreshInFlight ? "Checking" : "Recheck", systemImage: "checkmark.shield")
                }

                Spacer()

                if capability == .screenSearch && !granted {
                    Button {
                        PermissionChecker.shared.quitAndRelaunch()
                    } label: {
                        Label("Relaunch", systemImage: "arrow.clockwise.circle")
                    }
                    .help("Screen Recording often becomes usable only after Lattices restarts.")
                }

                Button(granted ? "Done" : "Close") {
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
            .buttonStyle(.bordered)
            .font(Typo.caption(10))
        }
        .padding(16)
        .frame(width: 430)
        .background(PanelBackground())
        .preferredColorScheme(.dark)
        .task(id: capability.rawValue) {
            while !Task.isCancelled {
                PermissionChecker.shared.check()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private var statusBadge: some View {
        Label(statusText, systemImage: statusIcon)
            .font(Typo.monoBold(9))
            .foregroundColor(granted ? Palette.running : (permChecker.refreshInFlight ? Palette.detach : Palette.textMuted))
    }

    private var statusText: String {
        if granted { return "Granted" }
        if permChecker.refreshInFlight { return "Checking" }
        if permChecker.lastCheckedAt != nil { return "Still missing" }
        return "Waiting"
    }

    private var statusIcon: String {
        if granted { return "checkmark.circle.fill" }
        if permChecker.refreshInFlight { return "arrow.clockwise" }
        if permChecker.lastCheckedAt != nil { return "exclamationmark.circle.fill" }
        return "arrow.down.app"
    }

    private var checkHint: String {
        if granted { return "Current signed app is enabled." }
        if permChecker.refreshInFlight { return "Checking macOS permission state..." }
        if let lastCheckedAt = permChecker.lastCheckedAt {
            return "Last checked \(Self.checkTimeFormatter.string(from: lastCheckedAt)); macOS still reports disabled."
        }
        return "Waiting for the first macOS permission check."
    }
}

struct NativePermissionAppDragTile: NSViewRepresentable {
    let appURL: URL
    let appIcon: NSImage
    let permissionName: String
    var isDragEnabled: Bool = true
    var onDragStarted: () -> Void = {}
    var onDragCompleted: () -> Void = {}

    func makeNSView(context: Context) -> NativePermissionAppDragTileView {
        NativePermissionAppDragTileView(
            appURL: appURL,
            appIcon: appIcon,
            permissionName: permissionName,
            isDragEnabled: isDragEnabled,
            onDragStarted: onDragStarted,
            onDragCompleted: onDragCompleted
        )
    }

    func updateNSView(_ nsView: NativePermissionAppDragTileView, context: Context) {
        nsView.appURL = appURL
        nsView.appIcon = appIcon
        nsView.permissionName = permissionName
        nsView.isDragEnabled = isDragEnabled
        nsView.onDragStarted = onDragStarted
        nsView.onDragCompleted = onDragCompleted
    }
}

final class NativePermissionAppDragTileView: NSView, NSDraggingSource {
    var appURL: URL { didSet { updateToolTip(); needsDisplay = true } }
    var appIcon: NSImage { didSet { needsDisplay = true } }
    var permissionName: String { didSet { updateToolTip() } }
    var isDragEnabled: Bool { didSet { updateToolTip(); discardCursorRects(); needsDisplay = true } }
    var onDragStarted: () -> Void
    var onDragCompleted: () -> Void

    private var dragStartLocation: NSPoint?
    private var isDragging = false
    private let dragThreshold: CGFloat = 4

    init(
        appURL: URL,
        appIcon: NSImage,
        permissionName: String,
        isDragEnabled: Bool,
        onDragStarted: @escaping () -> Void,
        onDragCompleted: @escaping () -> Void
    ) {
        self.appURL = appURL
        self.appIcon = appIcon
        self.permissionName = permissionName
        self.isDragEnabled = isDragEnabled
        self.onDragStarted = onDragStarted
        self.onDragCompleted = onDragCompleted
        super.init(frame: .zero)
        updateToolTip()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let amber = NSColor(calibratedRed: 0.96, green: 0.65, blue: 0.14, alpha: isDragEnabled ? 1.0 : 0.42)
        let fill = NSColor(calibratedWhite: 0.08, alpha: 0.96)
        let cardRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: 7, yRadius: 7)

        fill.setFill()
        cardPath.fill()

        let iconSize = min(bounds.width, bounds.height) * 0.50
        let iconRect = NSRect(
            x: (bounds.width - iconSize) / 2,
            y: 15,
            width: iconSize,
            height: iconSize
        )
        appIcon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: isDragEnabled ? 1.0 : 0.45)

        if let symbol = NSImage(
            systemSymbolName: isDragEnabled ? "hand.draw" : "checkmark.circle.fill",
            accessibilityDescription: isDragEnabled ? "Drag" : "Granted"
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)) {
            let symbolSize = NSSize(width: 17, height: 17)
            let symbolRect = NSRect(
                x: (bounds.width - symbolSize.width) / 2,
                y: iconRect.maxY + 5,
                width: symbolSize.width,
                height: symbolSize.height
            )
            symbol.isTemplate = true
            amber.set()
            symbol.draw(in: symbolRect)
        }

        let label = (isDragEnabled ? "DRAG ME" : "GRANTED") as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 8.5, weight: .semibold),
            .foregroundColor: amber
        ]
        let labelSize = label.size(withAttributes: attributes)
        label.draw(
            at: NSPoint(x: (bounds.width - labelSize.width) / 2, y: bounds.height - labelSize.height - 9),
            withAttributes: attributes
        )

        var dash: [CGFloat] = [5, 4]
        cardPath.setLineDash(&dash, count: dash.count, phase: 0)
        cardPath.lineWidth = isDragEnabled ? 1.2 : 1.0
        amber.withAlphaComponent(isDragEnabled ? 0.72 : 0.35).setStroke()
        cardPath.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard isDragEnabled else { return }
        window?.makeKey()
        _ = window?.makeFirstResponder(self)
        dragStartLocation = convert(event.locationInWindow, from: nil)
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragEnabled, !isDragging, let startLocation = dragStartLocation else { return }

        let currentLocation = convert(event.locationInWindow, from: nil)
        let dx = currentLocation.x - startLocation.x
        let dy = currentLocation.y - startLocation.y
        guard sqrt(dx * dx + dy * dy) >= dragThreshold else { return }

        startDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        dragStartLocation = nil
        isDragging = false
    }

    override func resetCursorRects() {
        if isDragEnabled {
            addCursorRect(bounds, cursor: .openHand)
        }
    }

    private func startDrag(with event: NSEvent) {
        isDragging = true
        dragStartLocation = nil
        onDragStarted()

        let draggingItem = NSDraggingItem(pasteboardWriter: appURL as NSURL)
        let imageSize = NSSize(width: 64, height: 64)
        let imageFrame = NSRect(
            x: bounds.midX - imageSize.width / 2,
            y: bounds.midY - imageSize.height / 2,
            width: imageSize.width,
            height: imageSize.height
        )
        draggingItem.setDraggingFrame(imageFrame, contents: appIcon)

        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        isDragging = false
        dragStartLocation = nil
        onDragCompleted()
    }

    private func updateToolTip() {
        toolTip = isDragEnabled
            ? "Drag \(appURL.lastPathComponent) into \(permissionName)"
            : "\(permissionName) is enabled"
    }
}
