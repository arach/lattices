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
                    Button("Add machine") { pairing = true }
                }
                MachineArrangementCanvas(model: model, machines: machines, onlineNames: Set(hosts.hosts.filter { $0.status == .online }.map(\.name)))
                HudDivider(color: Palette.border)
                machineList
                HudDivider(color: Palette.border)
                displays
                #if LATTICES_BUNDLE
                Toggle("Let other machines visit this Mac", isOn: Binding(
                    get: { MacVisitHost.enabled }, set: { MacVisitHost.setEnabled($0); model.refresh() }
                )).toggleStyle(.checkbox)
                #endif
                if let selected { detail(selected) }
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in model.refresh() }
        .sheet(isPresented: $pairing) { MachinePairSheet { model.refresh() } }
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
                        Text(machine.visit.flatMap { MachineArrangementStore.side(for: $0, displays: model.screens.map(\.frame)) }?.rawValue ?? "Unplaced").frame(width: 58, alignment: .leading)
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
                    Button("Make main") {
                        do { try DisplayArrangement.shared.makeMain(screen.number) } catch { model.error = "\(error)" }
                    }
                    .buttonStyle(.borderless).font(Typo.body(11))
                    .opacity(screen.main ? 0 : 1).disabled(screen.main || DisplayArrangement.shared.pending)
                    .frame(width: 80)
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
                Picker("Side", selection: Binding(get: { MachineArrangementStore.side(for: visit, displays: model.screens.map(\.frame)) ?? visit.side }, set: { model.move(visit.name, to: $0) })) {
                    ForEach(VisitTrust.Side.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }.frame(width: 150)
                Button("Forget") { model.forget(visit.name) }
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
    @State private var kind = "both"
    @State private var waiting = false
    @State private var error: String?
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add machine").font(Typo.heading(15))
            TextField("Name", text: $name).disabled(waiting)
            TextField("Bridge address · host:5287", text: $address).disabled(waiting)
            Picker("Type", selection: $kind) {
                Text("Lattices host").tag("host")
                Text("Visit host").tag("visit")
                Text("Both").tag("both")
            }.disabled(waiting)
            if waiting {
                Text("Approve code on \(name)").font(Typo.body(12))
                Text(VisitTrust.shared.fingerprint).font(Typo.mono(14)).textSelection(.enabled)
                ProgressView().controlSize(.small)
            }
            if let error { Text(error).font(Typo.body(11)).textSelection(.enabled) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.disabled(waiting).keyboardShortcut(.cancelAction)
                Button("Add") { pair() }.keyboardShortcut(.defaultAction)
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
        let side = VisitTrust.Side.right
        let target = address.isEmpty ? name : address
        guard let base = VisitTrust.bridgeURL(target), let hostname = base.host,
              let port = UInt16(exactly: base.port ?? 9399), port > 0 else { error = "Invalid address"; return }
        if kind != "visit" {
            do {
                try MachineArrangementStore.addHost(name: name, address: hostname, port: kind == "host" ? port : 9399)
                RemoteHostsModel.shared.reload()
            } catch { self.error = String(describing: error); return }
        }
        if kind == "host" { done(); dismiss(); return }
        var bridge = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        bridge.port = base.port ?? 5287
        let bridgeAddress = String(bridge.url!.absoluteString.dropFirst("http://".count))
        waiting = true
        error = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = VisitTrust.shared.pair(name: name, address: bridgeAddress, side: side)
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
