import Foundation
import CoreGraphics

/// What the app knows about one attached display, from CoreDisplay's info
/// dictionary (the same source `system_profiler` reads).
public struct DisplayInfo: Equatable, Identifiable {
    public let id: CGDirectDisplayID
    public let name: String
    public let vendorID: UInt32
    public let productID: UInt32
    public let serial: UInt32
    public let isBuiltIn: Bool
    public let isMain: Bool
    public let isTV: Bool
    public let isHDMI: Bool

    public init(id: CGDirectDisplayID, name: String, vendorID: UInt32, productID: UInt32, serial: UInt32,
                isBuiltIn: Bool, isMain: Bool, isTV: Bool, isHDMI: Bool) {
        self.id = id; self.name = name; self.vendorID = vendorID; self.productID = productID; self.serial = serial
        self.isBuiltIn = isBuiltIn; self.isMain = isMain; self.isTV = isTV; self.isHDMI = isHDMI
    }

    /// `DisplayProductName` is a locale → name dictionary on real hardware, a
    /// plain string on some virtual displays, and absent on the built-in panel.
    public static func from(dictionary d: [String: Any], id: CGDirectDisplayID, isBuiltIn: Bool, isMain: Bool) -> DisplayInfo {
        let name: String
        if let names = d["DisplayProductName"] as? [String: String] {
            name = names["en_US"] ?? names[Locale.current.identifier] ?? names.values.sorted().first
                ?? (isBuiltIn ? "Built-in Display" : "Display \(id)")
        } else if let plain = d["DisplayProductName"] as? String {
            name = plain
        } else {
            name = isBuiltIn ? "Built-in Display" : "Display \(id)"
        }
        func number(_ key: String) -> UInt32 { UInt32(truncatingIfNeeded: (d[key] as? NSNumber)?.int64Value ?? 0) }
        func flag(_ key: String) -> Bool { ((d[key] as? NSNumber)?.boolValue) ?? false }
        return DisplayInfo(id: id, name: name,
                           vendorID: number("DisplayVendorID"), productID: number("DisplayProductID"),
                           serial: number("DisplaySerialNumber"),
                           isBuiltIn: isBuiltIn, isMain: isMain,
                           isTV: flag("DisplayIsTV"), isHDMI: flag("IODisplayIsHDMISink"))
    }
}

/// `CoreDisplay_DisplayCreateInfoDictionary` — private, so resolved at runtime.
public enum CoreDisplayInfo {
    private typealias Create = @convention(c) (UInt32) -> Unmanaged<CFDictionary>?
    private static let create: Create? = {
        guard let h = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_NOW),
              let sym = dlsym(h, "CoreDisplay_DisplayCreateInfoDictionary") else { return nil }
        return unsafeBitCast(sym, to: Create.self)
    }()

    public static var isAvailable: Bool { create != nil }

    public static func dictionary(for id: CGDirectDisplayID) -> [String: Any]? {
        create?(id)?.takeRetainedValue() as? [String: Any]
    }

    public static func info(for id: CGDirectDisplayID) -> DisplayInfo {
        DisplayInfo.from(dictionary: dictionary(for: id) ?? [:], id: id,
                         isBuiltIn: CGDisplayIsBuiltin(id) != 0, isMain: CGDisplayIsMain(id) != 0)
    }
}
