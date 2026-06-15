import AppKit
import SwiftUI

// MARK: - NewLayerPanel
//
// The "create a new layer" authoring flow for Hyperspace. Tapping the ＋ pile opens this:
// name the layer and choose which apps define it (rule-backed membership — the same model as
// the rest of Studio). It must be its own key panel because the survey's screen-panels can't
// become key, so a TextField hosted there wouldn't take input. Floats above the survey (level
// +2) with a scrim that dims it; Esc / click-away / Cancel close it.

final class NewLayerPanel: NSPanel {
    struct Candidate: Identifiable {
        let id = UUID()
        let app: String
        let image: NSImage?
        let count: Int          // windows of this app on the active display
    }

    private let onCreate: (String, [String]) -> Void
    private let onCancel: () -> Void

    init(candidates: [Candidate], preselected: Set<String>, defaultName: String,
         onCreate: @escaping (String, [String]) -> Void, onCancel: @escaping () -> Void) {
        self.onCreate = onCreate
        self.onCancel = onCancel
        super.init(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 2)   // above the survey panels
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        let form = NewLayerForm(
            candidates: candidates, preselected: preselected, defaultName: defaultName,
            onCreate: { [weak self] name, apps in self?.onCreate(name, apps); self?.close() },
            onCancel: { [weak self] in self?.onCancel(); self?.close() })
        let host = NSHostingView(rootView: form)
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        contentView = host
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var canBecomeKey: Bool { true }

    func present(on screen: NSScreen) {
        setFrame(screen.frame, display: true)
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}

// MARK: - NewLayerForm

private struct NewLayerForm: View {
    let candidates: [NewLayerPanel.Candidate]
    @State private var selected: Set<String>
    @State private var name: String
    @FocusState private var nameFocused: Bool
    let onCreate: (String, [String]) -> Void
    let onCancel: () -> Void

    init(candidates: [NewLayerPanel.Candidate], preselected: Set<String>, defaultName: String,
         onCreate: @escaping (String, [String]) -> Void, onCancel: @escaping () -> Void) {
        self.candidates = candidates
        _selected = State(initialValue: preselected)
        _name = State(initialValue: defaultName)
        self.onCreate = onCreate
        self.onCancel = onCancel
    }

    // Selected apps in the candidate order, the live match count, and the create gate.
    private var selectedApps: [String] { candidates.map(\.app).filter { selected.contains($0) } }
    private var matchCount: Int { candidates.filter { selected.contains($0.app) }.reduce(0) { $0 + $1.count } }
    private var canCreate: Bool {
        !selected.isEmpty && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func create() { if canCreate { onCreate(name, selectedApps) } }

    var body: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onCancel() }            // click-away cancels
            vessel
        }
    }

    private var vessel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(Palette.running)
                Text("New Layer").font(Typo.monoBold(14)).foregroundColor(.white)
                Spacer()
                Text("esc").font(Typo.mono(9)).foregroundColor(.white.opacity(0.4))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("NAME").font(Typo.mono(8.5)).tracking(0.6).foregroundColor(.white.opacity(0.4))
                TextField("Layer name", text: $name)
                    .textFieldStyle(.plain).font(Typo.heading(15)).foregroundColor(.white)
                    .focused($nameFocused)
                    .onSubmit(create)
                    .onExitCommand(perform: onCancel)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Palette.running.opacity(0.45), lineWidth: 1)))
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("DEFINED BY  ·  tap to toggle")
                    .font(Typo.mono(8.5)).tracking(0.6).foregroundColor(.white.opacity(0.4))
                if candidates.isEmpty {
                    Text("No windows on this display to define a rule.")
                        .font(Typo.mono(10)).foregroundColor(.white.opacity(0.4))
                } else {
                    FlowLayout(spacing: 7, lineSpacing: 7, alignment: .leading) {
                        ForEach(candidates) { appChip($0) }
                    }
                }
            }
            HStack(spacing: 12) {
                Text(selected.isEmpty ? "pick at least one app"
                                      : "matches \(matchCount) window\(matchCount == 1 ? "" : "s") now")
                    .font(Typo.mono(9)).foregroundColor(.white.opacity(0.45))
                Spacer(minLength: 0)
                Button(action: onCancel) {
                    Text("Cancel").font(Typo.monoBold(11)).foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                }.buttonStyle(.plain)
                Button(action: create) {
                    Text("Create Layer")
                        .font(Typo.monoBold(11)).foregroundColor(canCreate ? Palette.bg : .white.opacity(0.4))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(canCreate ? Palette.running : Color.white.opacity(0.08)))
                }.buttonStyle(.plain).disabled(!canCreate)
            }
        }
        .padding(22)
        .frame(width: 460)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.06, green: 0.07, blue: 0.09))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 44, y: 20)
        )
        .onAppear { nameFocused = true }
    }

    private func appChip(_ c: NewLayerPanel.Candidate) -> some View {
        let on = selected.contains(c.app)
        return Button {
            if on { selected.remove(c.app) } else { selected.insert(c.app) }
        } label: {
            HStack(spacing: 6) {
                if let img = c.image {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 20, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
                Text(c.app).font(Typo.mono(11)).foregroundColor(on ? Palette.bg : .white.opacity(0.85)).lineLimit(1)
                if c.count > 1 {
                    Text("\(c.count)").font(Typo.monoBold(8))
                        .foregroundColor(on ? Palette.bg.opacity(0.7) : .white.opacity(0.4))
                }
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10)).foregroundColor(on ? Palette.bg : .white.opacity(0.35))
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(Capsule().fill(on ? Palette.running : Color.white.opacity(0.06))
                .overlay(Capsule().strokeBorder(on ? Palette.running : Palette.border, lineWidth: 1)))
        }
        .buttonStyle(.plain)
    }
}
