import DeckKit
import SwiftUI

/// Adding a Mac. Five phases, one screen each, one decision per screen.
///
/// Written directly in `DeckTheme` rather than the older `Lats*` components:
/// this is new surface, so it starts where the type and colour system is going
/// instead of where it has been.
struct AddHostSheet: View {
    @ObservedObject var store: DeckStore
    /// Called once the Mac is trusted, so the caller can seat it in the fleet.
    let onPaired: (BridgeEndpoint) -> Void
    /// Called when the user wants to go straight to the Mac they just added.
    let onOpen: (BridgeEndpoint) -> Void

    @StateObject private var controller = AddHostController()
    @StateObject private var scanner = LocalNetworkScanner()
    @Environment(\.dismiss) private var dismiss
    @State private var isEnteringManually = false

    var body: some View {
        ZStack {
            DeckTheme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                titleBar
                ScrollView {
                    phaseBody
                        .padding(.horizontal, DeckTheme.Space.margin)
                        .padding(.vertical, DeckTheme.Space.x24)
                        .frame(maxWidth: 480)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: controller.phase)
    }

    // MARK: - Chrome

    private var titleBar: some View {
        HStack {
            Text(titleText)
                .font(DeckTheme.title())
                .foregroundStyle(DeckTheme.text)
            Spacer(minLength: 0)
            Button {
                controller.cancelPairing()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DeckTheme.textSecondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, DeckTheme.Space.margin)
        .padding(.vertical, DeckTheme.Space.x12)
    }

    private var titleText: String {
        switch controller.phase {
        case .picking:                    return isEnteringManually ? "Enter an address" : "Add a Host"
        case .confirming(let endpoint):   return "Add \(endpoint.displayName)?"
        case .waiting(let endpoint):      return "Waiting for \(endpoint.displayName)"
        case .added(let endpoint, _):     return "\(endpoint.displayName) added"
        case .failed(let endpoint, _):    return endpoint.displayName
        }
    }

    // MARK: - Phases

    @ViewBuilder
    private var phaseBody: some View {
        switch controller.phase {
        case .picking:
            if isEnteringManually { manualEntry } else { picking }
        case .confirming(let endpoint):
            confirming(endpoint)
        case .waiting(let endpoint):
            waiting(endpoint)
        case .added(let endpoint, let withheld):
            added(endpoint, withheld: withheld)
        case .failed(let endpoint, let failure):
            failed(endpoint, failure)
        }
    }

    // MARK: Picking

    private var candidates: [BridgeEndpoint] {
        AddHostController.candidates(from: store, including: scanner.found)
    }

    private var picking: some View {
        VStack(alignment: .leading, spacing: DeckTheme.Space.x12) {
            if candidates.isEmpty {
                VStack(alignment: .leading, spacing: DeckTheme.Space.x8) {
                    Text("Nothing found yet.")
                        .font(DeckTheme.body())
                        .foregroundStyle(DeckTheme.text)
                    // The thing people actually get stuck on. A host runs
                    // Lattices and still stays invisible until its bridge is
                    // switched on, and nothing on the network can tell us that
                    // is the reason — so the copy has to.
                    Text("On the Mac, open Lattices → Settings → Companion and turn on the local bridge. It stays off until you do.")
                        .font(DeckTheme.secondary())
                        .foregroundStyle(DeckTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Both devices also need to be on the same Wi‑Fi.")
                        .font(DeckTheme.secondary())
                        .foregroundStyle(DeckTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, DeckTheme.Space.x8)
            } else {
                ForEach(candidates) { endpoint in
                    Button { controller.choose(endpoint) } label: {
                        candidateRow(endpoint)
                    }
                    .buttonStyle(.plain)
                }
            }

            scanSection

            Divider().overlay(DeckTheme.hairline).padding(.vertical, DeckTheme.Space.x4)

            HStack(spacing: DeckTheme.Space.x12) {
                Button { isEnteringManually = true } label: {
                    Text("Enter an address manually")
                        .font(DeckTheme.secondary())
                        .foregroundStyle(DeckTheme.textSecondary)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button {
                    scanner.reset()
                    store.refreshDiscovery()
                } label: {
                    Text("Refresh")
                        .font(DeckTheme.secondary())
                        .foregroundStyle(DeckTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(scanner.isScanning)
            }
        }
    }

    // MARK: Sweep
    //
    // Bonjour stays the default and runs on its own. This is the fallback for
    // networks that drop multicast, so it is a deliberate act with a visible
    // cost rather than something the app does quietly in the background.

    @ViewBuilder
    private var scanSection: some View {
        if scanner.isScanning {
            VStack(alignment: .leading, spacing: DeckTheme.Space.x8) {
                Text("Looking for hosts…")
                    .font(DeckTheme.secondary())
                    .foregroundStyle(DeckTheme.textSecondary)
                // The one determinate indicator in this flow, because unlike
                // waiting on a person this work really is finite and countable.
                ProgressView(value: scanner.progress)
                    .tint(DeckTheme.accent)
            }
            .padding(.vertical, DeckTheme.Space.x4)
        } else {
            VStack(alignment: .leading, spacing: DeckTheme.Space.x8) {
                Button {
                    Task { await scanner.scan() }
                } label: {
                    HStack(spacing: DeckTheme.Space.x8) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 13, weight: .medium))
                        Text(scanner.outcome == nil ? "Look for hosts" : "Look again")
                            .font(DeckTheme.secondary(.medium))
                    }
                    .foregroundStyle(DeckTheme.textSecondary)
                    .padding(.horizontal, DeckTheme.Space.x12)
                    .padding(.vertical, DeckTheme.Space.x8)
                    .background(
                        RoundedRectangle(cornerRadius: DeckTheme.radiusCard, style: .continuous)
                            .fill(DeckTheme.control)
                    )
                }
                .buttonStyle(.plain)

                if let note = scanNote {
                    Text(note)
                        .font(DeckTheme.caption())
                        .foregroundStyle(DeckTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var scanNote: String? {
        switch scanner.outcome {
        case .none:
            return nil
        case .swept:
            return scanner.found.isEmpty
                ? "Nothing answered. Check the bridge is on in Lattices on the Mac."
                : nil   // They're in the list above; a count would just repeat it.
        case .networkTooLarge:
            return "This network is too big to check host by host. Enter the address instead."
        case .noNetwork:
            return "Not on a Wi‑Fi network."
        }
    }

    /// Name and address only. The Mac's own fingerprint used to sit here, but
    /// there is nothing on the Mac to check it against, so it was a number that
    /// looked like security without being any.
    private func candidateRow(_ endpoint: BridgeEndpoint) -> some View {
        HStack(spacing: DeckTheme.Space.x12) {
            Image(systemName: endpoint.deviceIcon)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(DeckTheme.textSecondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(endpoint.displayName)
                    .font(DeckTheme.body(.medium))
                    .foregroundStyle(DeckTheme.text)
                    .lineLimit(1)
                Text(endpoint.host)
                    .font(DeckTheme.secondary())
                    .foregroundStyle(DeckTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DeckTheme.textTertiary)
        }
        .padding(.horizontal, DeckTheme.Space.cardPadH)
        .padding(.vertical, DeckTheme.Space.cardPadV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DeckTheme.radiusCard, style: .continuous)
                .fill(DeckTheme.card)
        )
    }

    private var manualEntry: some View {
        VStack(alignment: .leading, spacing: DeckTheme.Space.x12) {
            Text("Use this when the host doesn't appear on its own — usually because the network blocks discovery.")
                .font(DeckTheme.secondary())
                .foregroundStyle(DeckTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            field("Host", text: $controller.manualHost, keyboard: .URL)
            field("Port", text: $controller.manualPort, keyboard: .numberPad)

            primaryButton("Continue", enabled: controller.manualEndpoint != nil) {
                guard let endpoint = controller.manualEndpoint else { return }
                controller.choose(endpoint)
            }

            quietButton("Back") { isEnteringManually = false }
        }
    }

    // MARK: Confirming

    private func confirming(_ endpoint: BridgeEndpoint) -> some View {
        VStack(alignment: .leading, spacing: DeckTheme.Space.x16) {
            Text("\(endpoint.displayName) will ask whether to allow this iPad. Check that it shows this code:")
                .font(DeckTheme.body())
                .foregroundStyle(DeckTheme.text)
                .fixedSize(horizontal: false, vertical: true)

            // The one thing on this screen an impostor cannot fake. Given its
            // own line and a size step above everything else, because the whole
            // instruction above is "compare these".
            Text(controller.deviceCode.replacingOccurrences(of: "-", with: " - "))
                .font(DeckTheme.title())
                .foregroundStyle(DeckTheme.text)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, DeckTheme.Space.x24)
                .accessibilityLabel(controller.deviceCode.map(String.init).joined(separator: " "))

            Text("If the codes don't match, deny it — something else on your network is asking.")
                .font(DeckTheme.secondary())
                .foregroundStyle(DeckTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(endpoint.displayName) · \(endpoint.host):\(endpoint.port)")
                .font(DeckTheme.caption())
                .foregroundStyle(DeckTheme.textTertiary)

            primaryButton("Ask to pair") {
                controller.pair(with: endpoint, onPaired: onPaired)
            }
            quietButton("Cancel") { controller.backToPicking() }
        }
    }

    // MARK: Waiting

    /// Deliberately still. Everything else in this app moves at machine pace;
    /// this is the one state paced by a person walking to a desk. A repeating
    /// animation would promise imminent change, which is exactly the lie that
    /// makes half a minute feel broken — so there is nothing to watch but a
    /// clock, which says only that time is passing and that this is expected.
    private func waiting(_ endpoint: BridgeEndpoint) -> some View {
        VStack(alignment: .leading, spacing: DeckTheme.Space.x16) {
            Text("Approve the prompt on \(endpoint.displayName).")
                .font(DeckTheme.body())
                .foregroundStyle(DeckTheme.text)

            Text(elapsedLabel)
                .font(DeckTheme.caption())
                .foregroundStyle(DeckTheme.textTertiary)
                .monospacedDigit()

            if controller.isWaitingLongerThanExpected {
                Text("Still waiting. Make sure \(endpoint.displayName) is awake.")
                    .font(DeckTheme.secondary())
                    .foregroundStyle(DeckTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            quietButton("Cancel") { controller.backToPicking() }
        }
    }

    private var elapsedLabel: String {
        let seconds = controller.waitedSeconds
        return String(format: "Waiting — %d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: Added

    private func added(_ endpoint: BridgeEndpoint, withheld: [String]) -> some View {
        VStack(alignment: .leading, spacing: DeckTheme.Space.x16) {
            Text("It's in your roster and ready to use.")
                .font(DeckTheme.body())
                .foregroundStyle(DeckTheme.text)

            if !withheld.isEmpty {
                // Said now, once, rather than surfacing as a failed gesture in
                // three days' time when nobody remembers pairing this Mac.
                VStack(alignment: .leading, spacing: DeckTheme.Space.x4) {
                    Text("\(endpoint.displayName) didn't grant \(listed(withheld)).")
                        .font(DeckTheme.secondary())
                        .foregroundStyle(DeckTheme.text)
                    Text("You can change this in Lattices on \(endpoint.displayName).")
                        .font(DeckTheme.secondary())
                        .foregroundStyle(DeckTheme.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(DeckTheme.Space.wellPad)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DeckTheme.radiusCard, style: .continuous)
                        .fill(DeckTheme.card)
                )
            }

            // Adding does not move the Mac you were looking at — but you just
            // spent four screens thinking about this one, so getting to it is
            // one tap rather than a hunt back through Home.
            primaryButton("Open \(endpoint.displayName)") {
                onOpen(endpoint)
                dismiss()
            }
            quietButton("Done") { dismiss() }
        }
    }

    private func listed(_ capabilities: [String]) -> String {
        let names = capabilities.map { AddHostController.capabilityLabel($0) }
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " or " + (names.last ?? "")
    }

    // MARK: Failed

    @ViewBuilder
    private func failed(_ endpoint: BridgeEndpoint, _ failure: AddHostFailure) -> some View {
        VStack(alignment: .leading, spacing: DeckTheme.Space.x16) {
            switch failure {
            case .denied:
                // The Mac answered. Nothing failed, so nothing is coloured:
                // red would claim a fault and amber would claim it still needs
                // something. It is set in the serif because this is the one
                // moment in the flow where the Mac is talking back.
                Text("\(endpoint.displayName) declined the request.")
                    .font(DeckTheme.saidSecondary)
                    .foregroundStyle(DeckTheme.text)
                    .fixedSize(horizontal: false, vertical: true)

            case .unreachable(let reason):
                // This one *is* a failure — the question went unanswered, and
                // the explanation is owed by the system rather than by a person.
                VStack(alignment: .leading, spacing: DeckTheme.Space.x4) {
                    Text("Couldn't reach \(endpoint.displayName).")
                        .font(DeckTheme.body(.medium))
                        .foregroundStyle(DeckTheme.text)
                    Text(reason)
                        .font(DeckTheme.secondary())
                        .foregroundStyle(DeckTheme.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(DeckTheme.Space.wellPad)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DeckTheme.radiusCard, style: .continuous)
                        .fill(DeckTheme.errorFill)
                )

                Text("Check that Lattices is running on \(endpoint.displayName), and that both devices are on the same Wi‑Fi.")
                    .font(DeckTheme.secondary())
                    .foregroundStyle(DeckTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Never automatic: a retry raises a fresh alert on the Mac
            // immediately, and doing that on the user's behalf after they were
            // just told no is how an app becomes something you turn off.
            primaryButton("Try again") {
                controller.pair(with: endpoint, onPaired: onPaired)
            }
            quietButton("Back") { controller.backToPicking() }
        }
    }

    // MARK: - Controls

    private func primaryButton(
        _ title: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(DeckTheme.body(.semibold))
                .foregroundStyle(enabled ? DeckTheme.canvas : DeckTheme.textDisabled)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DeckTheme.Space.x12)
                .background(
                    RoundedRectangle(cornerRadius: DeckTheme.radiusCard, style: .continuous)
                        .fill(enabled ? DeckTheme.accent : DeckTheme.control)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func quietButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(DeckTheme.body())
                .foregroundStyle(DeckTheme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DeckTheme.Space.x8)
        }
        .buttonStyle(.plain)
    }

    private func field(
        _ placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType
    ) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(DeckTheme.body())
            .foregroundStyle(DeckTheme.text)
            .tint(DeckTheme.accent)
            .padding(.horizontal, DeckTheme.Space.x12)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: DeckTheme.radiusCard, style: .continuous)
                    .fill(DeckTheme.control)
            )
    }
}

// MARK: - Endpoint presentation

extension BridgeEndpoint {
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return host }
        return trimmed
    }

    var deviceIcon: String {
        let hint = (displayName + " " + host).lowercased()
        if hint.contains("mini")   { return "macmini" }
        if hint.contains("studio") { return "macstudio" }
        if hint.contains("imac")   { return "desktopcomputer" }
        if hint.contains("air") || hint.contains("book") || hint.contains("pro") {
            return "laptopcomputer"
        }
        return "macwindow"
    }
}
