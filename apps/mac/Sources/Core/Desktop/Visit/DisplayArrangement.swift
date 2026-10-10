import AppKit

/// The only display mutation entry point. A trial owns its rollback independently
/// of the Machines page, so navigation cannot accidentally keep an arrangement.
@MainActor
final class DisplayArrangement: ObservableObject {
    static let shared = DisplayArrangement()
    @Published private(set) var pending = false
    @Published private(set) var error: String?
    private var original: [CGDirectDisplayID: CGPoint] = [:]
    private var timer: Timer?
    private let readScreens: () -> [VisitController.Screen]
    private let configure: ([CGDirectDisplayID: CGPoint]) throws -> Void
    private let schedule: (TimeInterval, @escaping () -> Void) -> Timer

    init(readScreens: @escaping () -> [VisitController.Screen] = { VisitController.screens() },
         configure: @escaping ([CGDirectDisplayID: CGPoint]) throws -> Void = DisplayArrangement.configureDisplays,
         schedule: @escaping (TimeInterval, @escaping () -> Void) -> Timer = { seconds, action in
             Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in action() }
         }) {
        self.readScreens = readScreens; self.configure = configure; self.schedule = schedule
    }

    func apply(_ frames: [CGDirectDisplayID: CGRect]) throws {
        guard !pending, !frames.isEmpty else { throw VisitTrust.Failure.bad("An arrangement trial is already pending") }
        let screens = readScreens()
        guard Set(frames.keys) == Set(screens.map(\.displayID)), frames.values.allSatisfy({
            MachineGeometry.Placement($0).valid && abs($0.minX) < Double(Int32.max) && abs($0.minY) < Double(Int32.max)
        }) else { throw VisitTrust.Failure.bad("Displays changed. Revert and try again.") }
        original = Dictionary(uniqueKeysWithValues: screens.map { ($0.displayID, $0.frame.origin) })
        do { try configure(frames.mapValues(\.origin)) }
        catch { original = [:]; throw error }
        pending = true
        timer = schedule(15) { [weak self] in self?.revert() }
    }
    func keep() { timer?.invalidate(); timer = nil; original = [:]; pending = false; error = nil }
    func revert() {
        timer?.invalidate(); timer = nil
        do { if !original.isEmpty { try configure(original) }; original = [:]; pending = false; error = nil }
        catch { self.error = "Could not restore displays: \(error)" }
    }
    nonisolated private static func configureDisplays(_ origins: [CGDirectDisplayID: CGPoint]) throws {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else { throw VisitTrust.Failure.bad("Could not begin display configuration") }
        for (id, point) in origins {
            guard CGConfigureDisplayOrigin(config, id, Int32(point.x.rounded()), Int32(point.y.rounded())) == .success else {
                CGCancelDisplayConfiguration(config); throw VisitTrust.Failure.bad("Could not move display \(id)")
            }
        }
        guard CGCompleteDisplayConfiguration(config, .permanently) == .success else {
            throw VisitTrust.Failure.bad("Could not apply display configuration")
        }
    }
}
