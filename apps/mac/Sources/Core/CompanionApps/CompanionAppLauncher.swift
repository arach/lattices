import AppKit
import Foundation

enum CompanionAppLaunchResult: Equatable {
    case opened(url: URL)
    case openedProductPage(url: URL)
    case failed(CompanionAppLaunchFailure)
}

enum CompanionAppLaunchFailure: Error, Equatable {
    case notInstalled
    case notDistributedStandalone
    case missingProductPage
    case launchFailed(String)
}

protocol CompanionURLOpening {
    func openApplication(at url: URL, completion: @escaping (Error?) -> Void)
    func openURL(_ url: URL) -> Bool
}

struct WorkspaceCompanionURLOpener: CompanionURLOpening {
    func openApplication(at url: URL, completion: @escaping (Error?) -> Void) {
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { runningApp, error in
            _ = runningApp
            completion(error)
        }
    }

    func openURL(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}

/// Open revalidates the bundle identity before launch. Get opens the official
/// product page. This type does not retain a companion process handle.
struct CompanionAppLauncher {
    var catalog: [CompanionProduct]
    var discovery: CompanionAppDiscovery
    var opener: CompanionURLOpening

    static func system(discovery: CompanionAppDiscovery = .system) -> CompanionAppLauncher {
        CompanionAppLauncher(
            catalog: CompanionAppCatalog.firstParty,
            discovery: discovery,
            opener: WorkspaceCompanionURLOpener()
        )
    }

    func resolveOpenTarget(_ product: CompanionProduct) -> Result<URL, CompanionAppLaunchFailure> {
        guard product.distribution == .standaloneApp else {
            return .failure(.notDistributedStandalone)
        }
        guard let bundleIdentifier = product.bundleIdentifier,
              let url = discovery.validatedURL(bundleIdentifier: bundleIdentifier) else {
            return .failure(.notInstalled)
        }
        return .success(url)
    }

    func resolveGetTarget(_ product: CompanionProduct) -> Result<URL, CompanionAppLaunchFailure> {
        guard product.distribution == .standaloneApp else {
            return .failure(.notDistributedStandalone)
        }
        guard let page = product.productPageURL else {
            return .failure(.missingProductPage)
        }
        return .success(page)
    }

    func open(_ product: CompanionProduct, completion: @escaping (CompanionAppLaunchResult) -> Void) {
        switch resolveOpenTarget(product) {
        case .failure(let failure):
            completion(.failed(failure))
        case .success(let url):
            opener.openApplication(at: url) { error in
                if let error {
                    completion(.failed(.launchFailed(error.localizedDescription)))
                } else {
                    completion(.opened(url: url))
                }
            }
        }
    }

    func get(_ product: CompanionProduct) -> CompanionAppLaunchResult {
        switch resolveGetTarget(product) {
        case .failure(let failure):
            return .failed(failure)
        case .success(let page):
            if opener.openURL(page) {
                return .openedProductPage(url: page)
            }
            return .failed(.launchFailed("The product page could not be opened."))
        }
    }

    func perform(_ action: CompanionAppAction, productID: CompanionProductID, completion: @escaping (CompanionAppLaunchResult) -> Void) {
        guard let product = catalog.first(where: { $0.id == productID }) else {
            completion(.failed(.notInstalled))
            return
        }
        switch action {
        case .open:
            open(product, completion: completion)
        case .get:
            completion(get(product))
        case .none:
            completion(.failed(.notDistributedStandalone))
        }
    }
}
