import Foundation

final class BridgeDiscovery: NSObject {
    static let serviceType = "_lattices-companion._tcp."

    var onUpdate: (([BridgeEndpoint]) -> Void)?

    private let browser = NetServiceBrowser()
    private var resolvingServices: [String: NetService] = [:]
    private var discoveredEndpoints: [String: BridgeEndpoint] = [:]

    override init() {
        super.init()
        browser.delegate = self
    }

    func start() {
        browser.searchForServices(ofType: Self.serviceType, inDomain: "local.")
    }

    func refresh() {
        browser.stop()
        resolvingServices.removeAll()
        discoveredEndpoints.removeAll()
        onUpdate?([])
        start()
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
        service.delegate = self
        service.resolve(withTimeout: 5)
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

        discoveredEndpoints[key] = BridgeEndpoint(
            name: sender.name,
            host: normalizedHost,
            port: sender.port,
            source: "Bonjour"
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
}
