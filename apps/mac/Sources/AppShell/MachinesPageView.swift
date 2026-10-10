import AppKit
import HudsonUI
import SwiftUI
import UniformTypeIdentifiers

struct MachinesPageView: View {
    @ObservedObject private var hosts = RemoteHostsModel.shared
    @StateObject private var model = MachinesModel()
    @State private var selection: String?
    @State private var pairing = false

    private var machines: [MachineInventory.Machine] { model.machines(hosts.hosts) }
    private var selected: MachineInventory.Machine? { machines.first { $0.id == selection } ?? machines.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Arrangement").font(Typo.heading(13))
                    Spacer()
                    Button(model.visit.armed ? "Disarm visiting" : "Arm visiting") {
                        VisitController.shared.arm(!model.visit.armed)
                    }.disabled(model.visit.hosts.isEmpty && !model.visit.armed)
                    Button("End visit") { VisitController.shared.end(because: "ended") }
                        .disabled(model.visit.visiting == nil)
                    Button("Pair machine") { pairing = true }
                }
                arrangement
                HudDivider(color: Palette.border)
                machineList
                HudDivider(color: Palette.border)
                displays
                if let selected { detail(selected) }
                if model.pointer.lanMouse && model.pointer.clients.isEmpty {
                    HudDivider(color: Palette.border)
                    HStack {
                        Text("lan-mouse").font(Typo.heading(12))
                        Text(model.pointer.running ? "No clients" : "Stopped").foregroundStyle(Palette.textDim)
                        Spacer()
                        Button("Share · 5 min") { model.share() }.disabled(model.busy)
                    }
                }
                if let error = model.error {
                    Text(error).font(Typo.body(11)).foregroundStyle(Palette.text).textSelection(.enabled)
                }
            }
            .padding(Chrome.inset)
        }
        .font(Typo.body(11))
        .foregroundStyle(Palette.text)
        .tint(Palette.textDim)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .background(PanelBackground())
        .pageActions([PageAction(id: "machines-refresh", title: "Refresh", icon: "arrow.clockwise") {
            model.refresh()
            for host in hosts.hosts {
                if host.status == .online { hosts.refresh(host.name) } else { hosts.reconnect(host.name) }
            }
        }])
        .onAppear { hosts.retain(); model.appear() }
        .onDisappear { model.disappear(); hosts.release() }
        .onReceive(NotificationCenter.default.publisher(for: VisitController.changed)) { _ in model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: PointerShare.changed)) { _ in model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in model.refresh() }
        .sheet(isPresented: $pairing) { MachinePairSheet { model.refresh() } }
    }

    private var arrangement: some View {
        VStack(spacing: 8) {
            side(.top)
            HStack(spacing: 12) {
                side(.left).frame(width: 130)
                displayMap.frame(maxWidth: .infinity).frame(height: 150)
                side(.right).frame(width: 130)
            }
            side(.bottom)
        }
        .frame(maxWidth: .infinity)
    }
    private func side(_ side: VisitTrust.Side) -> some View {
        let host = model.visit.hosts.first { $0.side == side }
        return VStack(spacing: 4) {
            Text(side.rawValue.capitalized).font(Typo.body(10)).foregroundStyle(Palette.textMuted)
            if let host {
                Text(host.name)
                    .font(Typo.heading(12))
                    .foregroundStyle(model.visit.visiting == host.name ? Long.coral : Palette.text)
                    .lineLimit(1)
                    .onDrag { NSItemProvider(object: host.name as NSString) }
                    .accessibilityLabel("\(host.name), \(side.rawValue). Use the Side menu to move.")
            } else {
                Text("—").foregroundStyle(Palette.textMuted)
            }
        }
        .frame(width: 130, height: 48)
        .background(Palette.surface)
        .hudsonHairlineBorder(radius: 6, color: Palette.border)
        .dropDestination(for: String.self) { names, _ in
            guard let name = names.first, model.visit.hosts.contains(where: { $0.name == name }) else { return false }
            model.move(name, to: side)
            return true
        }
        .help("Drop a paired machine here. Occupied sides swap.")
    }
    private var displayMap: some View {
        GeometryReader { geometry in
            let bounds = model.screens.reduce(CGRect.null) { $0.union($1.frame) }
            let scale = min(geometry.size.width / max(bounds.width, 1), geometry.size.height / max(bounds.height, 1)) * 0.9
            ZStack {
                ForEach(model.screens, id: \.number) { screen in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Palette.surface)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.textMuted, lineWidth: 1))
                        .overlay(Text("\(screen.number)\(screen.main ? " · This Mac" : "")").font(Typo.body(10)).lineLimit(1))
                        .frame(width: screen.frame.width * scale, height: screen.frame.height * scale)
                        .opacity(screen.elsewhere ? 0.35 : 1)
                        .position(x: geometry.size.width / 2 + (screen.frame.midX - bounds.midX) * scale,
                                  y: geometry.size.height / 2 + (screen.frame.midY - bounds.midY) * scale)
                        .accessibilityLabel("\(screen.name), \(screen.elsewhere ? "elsewhere" : "here")")
                }
            }
        }
    }
    private var machineList: some View {
        VStack(spacing: 0) {
            if machines.isEmpty {
                Text("No machines").foregroundStyle(Palette.textMuted).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
            }
            ForEach(machines) { machine in
                Button { selection = machine.id } label: {
                    HStack(spacing: 10) {
                        Text(machine.name).font(Typo.heading(12)).frame(width: 120, alignment: .leading)
                        Text(machine.address).font(Typo.mono(10)).frame(maxWidth: .infinity, alignment: .leading)
                        Text(reachability(machine)).frame(width: 82, alignment: .leading)
                        Text(machine.visit == nil ? "Unpaired" : "Paired").frame(width: 58, alignment: .leading)
                        Text(machine.visit?.side.rawValue ?? "—").frame(width: 48, alignment: .leading)
                        Text(model.visit.visiting == machine.visit?.name && machine.visit != nil ? "Visiting" : "—")
                            .foregroundStyle(model.visit.visiting == machine.visit?.name && machine.visit != nil ? Long.coral : Palette.textMuted)
                            .frame(width: 52, alignment: .leading)
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .frame(height: 36)
                    .contentShape(Rectangle())
                    .background(selected?.id == machine.id ? Palette.surface : Color.clear)
                }.buttonStyle(.plain)
            }
        }
    }
    private func reachability(_ machine: MachineInventory.Machine) -> String {
        if let name = machine.remote, let host = hosts.hosts.first(where: { $0.name == name }), host.status == .online { return "Reachable" }
        if let visit = machine.visit {
            return model.reachable[visit.name].map { $0 ? "Reachable" : "Unreachable" } ?? "Checking"
        }
        if let name = machine.remote, let host = hosts.hosts.first(where: { $0.name == name }) {
            return host.status == .connecting ? "Connecting" : "Unreachable"
        }
        return "Unknown"
    }
    private var displays: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Displays").font(Typo.heading(13))
            ForEach(model.screens, id: \.number) { screen in
                HStack {
                    Text("\(screen.number) · \(screen.name)").frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(Int(screen.frame.width)) × \(Int(screen.frame.height))").font(Typo.mono(10)).foregroundStyle(Palette.textDim)
                    Toggle("Elsewhere", isOn: Binding(get: { screen.elsewhere }, set: {
                        if !VisitController.shared.setElsewhere(screen.number, $0) { model.error = "Display changed. Refresh and try again." }
                    })).toggleStyle(.checkbox).frame(width: 100)
                }.frame(height: 28)
            }
        }
    }
    @ViewBuilder private func detail(_ machine: MachineInventory.Machine) -> some View {
        HudDivider(color: Palette.border)
        HStack {
            Text(machine.name).font(Typo.heading(13))
            if let visit = machine.visit {
                Text(visit.bridgeFingerprint).font(Typo.mono(10)).foregroundStyle(Palette.textDim).textSelection(.enabled)
                Spacer()
                Picker("Side", selection: Binding(get: { visit.side }, set: { model.move(visit.name, to: $0) })) {
                    ForEach(VisitTrust.Side.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }.frame(width: 150)
                Button("Forget") { model.forget(visit.name) }
            }
        }
        if model.pointer.lanMouse && !machine.clients.isEmpty {
            HStack {
                Text("lan-mouse").font(Typo.heading(12))
                Text(machine.sharing ? "Sharing" : "Off").foregroundStyle(machine.sharing ? Long.coral : Palette.textDim)
                if let until = model.pointer.until { Text("until \(PointerShare.clock(until))").font(Typo.mono(10)) }
                Spacer()
                Button("Share · 5 min") { model.share() }.disabled(model.busy || model.pointer.sharing)
                    .help("Starts a trial for all configured lan-mouse clients")
                Button("Keep") { PointerShare.shared.keep(); model.refresh() }.disabled(model.busy || model.pointer.until == nil)
                Button("Stop") { model.stopSharing() }.disabled(model.busy || !model.pointer.sharing)
            }
        }
        if let name = machine.remote, let host = hosts.hosts.first(where: { $0.name == name }) {
            MachineHostDetail(host: host, model: hosts)
        }
    }
}

private struct MachinePairSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var side = VisitTrust.Side.right
    @State private var waiting = false
    @State private var error: String?
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pair machine").font(Typo.heading(15))
            TextField("Name", text: $name).disabled(waiting)
            TextField("Bridge address · host:5287", text: $address).disabled(waiting)
            Picker("Side", selection: $side) {
                ForEach(VisitTrust.Side.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            .disabled(waiting)
            if waiting {
                Text("Approve code on \(name)").font(Typo.body(12))
                Text(VisitTrust.shared.fingerprint).font(Typo.mono(14)).textSelection(.enabled)
                ProgressView().controlSize(.small)
            }
            if let error { Text(error).font(Typo.body(11)).textSelection(.enabled) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.disabled(waiting).keyboardShortcut(.cancelAction)
                Button("Pair") { pair() }.keyboardShortcut(.defaultAction)
                    .disabled(waiting || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .interactiveDismissDisabled(waiting)
        .textFieldStyle(.roundedBorder)
        .padding(20).frame(width: 360)
        .foregroundStyle(Palette.text).tint(Palette.textDim)
    }
    private func pair() {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let side = side
        guard VisitTrust.shared.host(on: side).map({ $0.name.caseInsensitiveCompare(name) == .orderedSame }) ?? true else {
            error = "The \(side.rawValue) side is occupied. Move its machine first."
            return
        }
        waiting = true
        error = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = VisitTrust.shared.pair(name: name, address: address.isEmpty ? "\(name):5287" : address, side: side)
            DispatchQueue.main.async {
                waiting = false
                switch result {
                case .success: done(); dismiss()
                case .failure(let failure): error = failure.description
                }
            }
        }
    }
}
