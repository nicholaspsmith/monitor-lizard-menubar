import Foundation

/// Whether Night Shift can work on a display, and what the app has done about it.
public enum TVRoleState: Equatable {
    case ok                      // macOS treats it as a monitor
    case blocked                 // flagged as a TV, no override on disk
    case fixedPendingReconnect   // override on disk; takes effect on the next attach
    case skipped                 // blocked, and the admin prompt was cancelled this launch
}

/// The per-model override macOS reads at display attach. Same file, same
/// three keys, as BetterDisplay's "display role: computer monitor" writes, so
/// an existing file counts as already fixed.
public enum OverridePlist {
    public static let root = "/Library/Displays/Contents/Resources/Overrides"

    public static func path(vendorID: UInt32, productID: UInt32) -> String {
        "\(root)/DisplayVendorID-\(String(vendorID, radix: 16))/DisplayProductID-\(String(productID, radix: 16))"
    }

    public static func contents(vendorID: UInt32, productID: UInt32) -> Data {
        let dict: [String: Any] = ["DisplayIsTV": false, "DisplayVendorID": Int(vendorID), "DisplayProductID": Int(productID)]
        // A fresh plist of three scalars cannot fail to serialise.
        return try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }
}

public final class TVRoleTracker {
    private let fileExists: (String) -> Bool
    private var skipped: Set<String> = []

    public init(fileExists: @escaping (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.fileExists = fileExists
    }

    private func key(_ d: DisplayInfo) -> String { "\(d.vendorID):\(d.productID)" }

    public func state(for display: DisplayInfo) -> TVRoleState {
        guard display.isTV else { return .ok }
        if fileExists(OverridePlist.path(vendorID: display.vendorID, productID: display.productID)) { return .fixedPendingReconnect }
        return skipped.contains(key(display)) ? .skipped : .blocked
    }

    public func markSkipped(_ display: DisplayInfo) { skipped.insert(key(display)) }
    public func clearSkipped(_ display: DisplayInfo) { skipped.remove(key(display)) }
    public func needsFix(_ display: DisplayInfo) -> Bool { state(for: display) == .blocked }
}
