import AppKit
import SwiftUI

// MARK: - Model

@MainActor
final class LongCardModel: ObservableObject {
    @Published var visit = VisitController.shared.status()
    @Published var screens: [VisitController.Screen] = []

    func refresh() {
        visit = VisitController.shared.status()
        screens = VisitController.screens()
    }
}

// MARK: - View

struct LongCardView: View {
    @ObservedObject var model: LongCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            visitSection
            if model.screens.count > 1 {
                Divider().overlay(Palette.border)
                screensSection
            }
            Divider().overlay(Palette.border)
            Button("Bring cursor home") { PointerHome.bringHome(); model.refresh() }
                .buttonStyle(LongCardButton())
        }
        .padding(14)
        .frame(width: 264, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.bg))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.borderLit, lineWidth: 0.5))
    }

    private var visitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { model.visit.armed },
                set: { VisitController.shared.arm($0); model.refresh() }
            )) {
                Text("Visiting cursor").font(Typo.heading(12)).foregroundStyle(Palette.text)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(Long.coral)
            .disabled(model.visit.hosts.isEmpty)

            if model.visit.hosts.isEmpty {
                Text("lats visit pair <host>").font(Typo.mono(10)).foregroundStyle(Palette.textMuted)
            }
            ForEach(model.visit.hosts, id: \.name) { host in
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.visit.visiting == host.name ? Long.coral : Palette.textMuted.opacity(0.5))
                        .frame(width: 6, height: 6)
                    Text(host.name).font(Typo.monoBold(11)).foregroundStyle(Palette.text)
                    Text(host.side.rawValue).font(Typo.mono(10)).foregroundStyle(Palette.textDim)
                    Spacer()
                    Text(host.bridgeFingerprint).font(Typo.mono(9)).foregroundStyle(Palette.textMuted)
                }
            }
            if model.visit.visiting != nil {
                Button("End visit") { VisitController.shared.end(because: "ended"); model.refresh() }
                    .buttonStyle(LongCardButton(accent: true))
            }
        }
    }

    /// A display plugged into another machine is elsewhere: the pointer stays off it.
    private var screensSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(model.screens, id: \.number) { screen in
                HStack(spacing: 6) {
                    Text(screen.name).font(Typo.monoBold(11)).foregroundStyle(screen.elsewhere ? Palette.textDim : Palette.text).lineLimit(1)
                    Text("\(Int(screen.frame.width))×\(Int(screen.frame.height))").font(Typo.mono(10)).foregroundStyle(Palette.textMuted)
                    Spacer()
                    Button(screen.elsewhere ? "Elsewhere" : "Here") {
                        VisitController.shared.setElsewhere(screen.number, !screen.elsewhere)
                        model.refresh()
                    }
                    .buttonStyle(LongCardButton())
                }
            }
        }
    }


}

private struct LongCardButton: ButtonStyle {
    var accent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.body(11))
            .foregroundStyle(accent ? Color.white : Palette.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(accent ? Long.coral : configuration.isPressed ? Palette.surfaceHov : Palette.surface)
            )
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Palette.border, lineWidth: 0.5))
    }
}

// MARK: - Panel

/// Long's card: opens above him, closes on a click anywhere else or on him again.
@MainActor
final class LongCard {
    private let model = LongCardModel()
    private let panel: NSPanel
    private var outside: Any?
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        let host = NSHostingView(rootView: LongCardView(model: model))
        panel = NSPanel(contentRect: CGRect(origin: .zero, size: host.fittingSize),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = host
    }

    func show(above anchor: CGRect) {
        model.refresh()
        guard let host = panel.contentView else { return }
        let size = host.fittingSize
        let visible = NSScreen.screens.first(where: { $0.frame.intersects(anchor) })?.visibleFrame ?? anchor
        var origin = CGPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + 4)
        if origin.y + size.height > visible.maxY { origin.y = anchor.minY - size.height - 4 }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
        if outside == nil {
            outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            }
        }
    }

    func refresh() { model.refresh() }

    func close() {
        if let outside { NSEvent.removeMonitor(outside) }
        outside = nil
        panel.orderOut(nil)
        onClose()
    }
}
