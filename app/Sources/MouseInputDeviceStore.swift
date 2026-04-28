import Foundation
import IOKit.hid

struct MouseInputDeviceInfo: Identifiable, Equatable {
    var id: String
    var vendorId: Int?
    var productId: Int?
    var locationId: Int?
    var product: String?
    var manufacturer: String?
    var transport: String?

    var summary: String {
        var parts: [String] = []
        if let product, !product.isEmpty {
            parts.append(product)
        }
        if let manufacturer, !manufacturer.isEmpty, parts.isEmpty {
            parts.append(manufacturer)
        }
        if let vendorId { parts.append("vid:\(vendorId)") }
        if let productId { parts.append("pid:\(productId)") }
        if let locationId { parts.append("loc:\(locationId)") }
        if let transport, !transport.isEmpty { parts.append(transport) }
        return parts.isEmpty ? "Unknown pointer device" : parts.joined(separator: " | ")
    }
}

final class MouseInputDeviceStore: ObservableObject {
    static let shared = MouseInputDeviceStore()

    @Published private(set) var devices: [MouseInputDeviceInfo] = []

    private init() {
        refresh()
    }

    func refresh() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches: [[String: Any]] = [
            [
                kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Mouse,
            ],
            [
                kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Pointer,
            ],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        let resolved: [MouseInputDeviceInfo]
        if let rawDevices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            resolved = rawDevices.compactMap(Self.deviceInfo(for:))
                .sorted { $0.summary.localizedCaseInsensitiveCompare($1.summary) == .orderedAscending }
        } else {
            resolved = []
        }

        DispatchQueue.main.async {
            self.devices = resolved
        }
    }

    private static func deviceInfo(for device: IOHIDDevice) -> MouseInputDeviceInfo? {
        let vendorId = integerProperty(kIOHIDVendorIDKey as CFString, from: device)
        let productId = integerProperty(kIOHIDProductIDKey as CFString, from: device)
        let locationId = integerProperty(kIOHIDLocationIDKey as CFString, from: device)
        let product = stringProperty(kIOHIDProductKey as CFString, from: device)
        let manufacturer = stringProperty(kIOHIDManufacturerKey as CFString, from: device)
        let transport = stringProperty(kIOHIDTransportKey as CFString, from: device)

        let vendorToken = vendorId.map(String.init) ?? "vid"
        let productToken = productId.map(String.init) ?? "pid"
        let locationToken = locationId.map(String.init) ?? "loc"
        let id = [product ?? "mouse", vendorToken, productToken, locationToken].joined(separator: ":")

        return MouseInputDeviceInfo(
            id: id,
            vendorId: vendorId,
            productId: productId,
            locationId: locationId,
            product: product,
            manufacturer: manufacturer,
            transport: transport
        )
    }

    private static func integerProperty(_ key: CFString, from device: IOHIDDevice) -> Int? {
        guard let value = IOHIDDeviceGetProperty(device, key) else { return nil }
        return (value as? NSNumber)?.intValue
    }

    private static func stringProperty(_ key: CFString, from device: IOHIDDevice) -> String? {
        IOHIDDeviceGetProperty(device, key) as? String
    }
}
