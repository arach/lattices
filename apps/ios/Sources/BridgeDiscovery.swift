import Foundation

final class BridgeDiscovery: NSObject {
    static let serviceType = "_lattices-companion._tcp."

    var onUpdate: (([BridgeEndpoint]) -> Void)?

    private let browser = NetServiceBrowser()
    private var resolvingServices: [String: NetService] = [:]
    private var discoveredEndpoints: [String: BridgeEndpoint] = [:]

    /// Bumped per rescan, so a late prune from an older rescan can't fire.
    private var scanGeneration = 0
    /// Services the current rescan has *seen*, which is a different and much
    /// earlier signal than having resolved them — see `refresh()`.
    private var seenThisScan: Set<String> = []
    /// Comfortably longer than `resolveTimeout`, so a slow resolve is never
    /// mistaken for a host that went away.
    private let rescanGracePeriod: TimeInterval = 12
    private let resolveTimeout: TimeInterval = 5

    override init() {
        super.init()
        browser.delegate = self
    }

    func start() {
        browser.searchForServices(ofType: Self.serviceType, inDomain: "local.")
    }

    /// Re-browse the network without ever publishing an empty roster.
    ///
    /// Clearing the list first looked harmless and was not: subscribers treat a
    /// Mac's absence as a reason to tear down its live session, so a rescan
    /// disconnected every secondary Mac and rebuilt it as a *new* session with
    /// a new identity — which the Fleet Deck keys its channels on. Rescanning is
    /// exactly what someone does while adding a Mac, so it has to be harmless.
    ///
    /// Instead the current roster stands, and only what the new browse never
    /// even *sees* is pruned.
    ///
    /// That distinction matters: pruning on "hasn't resolved yet" raced the
    /// resolve timeout, so tapping refresh could delete a host that was simply
    /// slow to answer — the host then stayed gone until something else provoked
    /// the browser. Being *found* means the service is there; resolving is just
    /// how long it takes to learn its address.
    func refresh() {
        browser.stop()
        resolvingServices.removeAll()

        scanGeneration += 1
        let generation = scanGeneration
        seenThisScan.removeAll()
        start()

        DispatchQueue.main.asyncAfter(deadline: .now() + rescanGracePeriod) { [weak self] in
            guard let self, self.scanGeneration == generation else { return }
            let vanished = self.discoveredEndpoints.keys.filter { !self.seenThisScan.contains($0) }
            guard !vanished.isEmpty else { return }
            vanished.forEach { self.discoveredEndpoints.removeValue(forKey: $0) }
            self.publish()
        }
    }

    func stop() {
        browser.stop()
        resolvingServices.removeAll()
        discoveredEndpoints.removeAll()
        onUpdate?([])
    }
}

extension BridgeDiscovery: NetServiceBrowserDelegate, NetServiceDelegate {
    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        let key = service.name + service.type + service.domain
        resolvingServices[key] = service
        // Seen is enough to keep it: the service is on the network whether or
        // not we have its address yet.
        seenThisScan.insert(key)
        service.delegate = self
        service.resolve(withTimeout: resolveTimeout)
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didRemove service: NetService,
        moreComing: Bool
    ) {
        let key = service.name + service.type + service.domain
        resolvingServices.removeValue(forKey: key)
        discoveredEndpoints.removeValue(forKey: key)
        if !moreComing {
            publish()
        }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let key = sender.name + sender.type + sender.domain
        guard let hostName = sender.hostName else { return }
        let normalizedHost = normalize(hostName: hostName)
        guard !normalizedHost.isEmpty, sender.port > 0 else { return }
        let txt = txtDictionary(from: sender.txtRecordData())

        seenThisScan.insert(key)
        discoveredEndpoints[key] = BridgeEndpoint(
            name: sender.name,
            host: normalizedHost,
            port: sender.port,
            source: "Bonjour",
            bridgeFingerprint: txt["fp"],
            securityMode: txt["sec"],
            capabilities: txt["cap"]?.split(separator: ",").map(String.init) ?? []
        )
        publish()
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        let key = sender.name + sender.type + sender.domain
        resolvingServices.removeValue(forKey: key)
    }

    private func publish() {
        let sorted = discoveredEndpoints.values.sorted {
            if $0.name == $1.name {
                return $0.host < $1.host
            }
            return $0.name < $1.name
        }
        onUpdate?(sorted)
    }

    private func normalize(hostName: String) -> String {
        guard hostName.hasSuffix(".") else { return hostName }
        return String(hostName.dropLast())
    }

    private func txtDictionary(from data: Data?) -> [String: String] {
        guard let data else { return [:] }
        return NetService.dictionary(fromTXTRecord: data).reduce(into: [:]) { result, entry in
            guard let value = String(data: entry.value, encoding: .utf8) else { return }
            result[entry.key] = value
        }
    }
}
