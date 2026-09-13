import Foundation
import CoreGraphics

/// A framebuffer (`IOMobileFramebufferShim` / `AppleCLCD2`) as found in the
/// IORegistry: its node name (`dispext0`) and the identity it publishes under
/// `DisplayAttributes.ProductAttributes`, when it publishes one.
public struct FramebufferEntry: Equatable {
    public let name: String
    public let productID: UInt32?
    public let serial: UInt32?
    public init(name: String, productID: UInt32?, serial: UInt32?) {
        self.name = name; self.productID = productID; self.serial = serial
    }
}

/// A `DCPAVServiceProxy` with `Location = External`.
public struct AVServiceEntry: Equatable {
    public let path: String
    public let entry: UInt32
    public init(path: String, entry: UInt32) { self.path = path; self.entry = entry }
}

/// Which AV service belongs to which display. The service's registry path
/// names its framebuffer (`…/dispext0:dcpav-service-epic:0/…`); the framebuffer
/// carries the product ID and serial that CoreDisplay reports for the display.
public enum DisplayMatcher {
    public static func framebufferName(inAVServicePath path: String) -> String? {
        guard let range = path.range(of: #"(disp(?:ext)?\d+):dcpav-service-epic"#, options: .regularExpression) else { return nil }
        return String(path[range]).components(separatedBy: ":").first
    }

    public static func match(displays: [DisplayInfo], framebuffers: [FramebufferEntry], services: [AVServiceEntry]) -> [CGDirectDisplayID: AVServiceEntry] {
        var result: [CGDirectDisplayID: AVServiceEntry] = [:]
        let externals = displays.filter { !$0.isBuiltIn }
        for service in services {
            guard let fbName = framebufferName(inAVServicePath: service.path),
                  let fb = framebuffers.first(where: { $0.name == fbName }) else { continue }
            if let pid = fb.productID, let serial = fb.serial,
               let display = externals.first(where: { $0.productID == pid && $0.serial == serial }) {
                result[display.id] = service
            }
        }
        // One external display and one external service: the pairing is forced
        // even when the framebuffer publishes no attributes.
        if result.isEmpty, externals.count == 1, services.count == 1 {
            result[externals[0].id] = services[0]
        }
        return result
    }
}
