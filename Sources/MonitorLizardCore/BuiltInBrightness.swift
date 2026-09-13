import Foundation
import CoreGraphics

public protocol BrightnessBackend: AnyObject {
    var isAvailable: Bool { get }
    func canChange(_ id: CGDirectDisplayID) -> Bool
    func brightness(_ id: CGDirectDisplayID) -> Float?
    func setBrightness(_ id: CGDirectDisplayID, _ value: Float) -> Bool
}

/// DisplayServices.framework (private) — what Control Center uses for the
/// built-in panel. `BrightnessChanged` is posted after a set so Control
/// Center's own slider follows.
public final class DisplayServicesBrightness: BrightnessBackend {
    private typealias CanChangeFn = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias ChangedFn = @convention(c) (CGDirectDisplayID, Double) -> Void

    private let canChangeFn: CanChangeFn?
    private let getFn: GetFn?
    private let setFn: SetFn?
    private let changedFn: ChangedFn?

    public init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
        func sym<T>(_ name: String) -> T? {
            guard let handle, let s = dlsym(handle, name) else { return nil }
            return unsafeBitCast(s, to: T.self)
        }
        canChangeFn = sym("DisplayServicesCanChangeBrightness")
        getFn = sym("DisplayServicesGetBrightness")
        setFn = sym("DisplayServicesSetBrightness")
        changedFn = sym("DisplayServicesBrightnessChanged")
    }

    public var isAvailable: Bool { getFn != nil && setFn != nil }

    /// Clamp a raw value into the valid 0...1 brightness/strength range. A
    /// pure, tiny seam so the clamping logic — shared with
    /// `CoreBrightnessNightShift` — is unit-testable even though the private
    /// functions it guards are not.
    public static func clamp(_ value: Float) -> Float { max(0, min(1, value)) }

    public func canChange(_ id: CGDirectDisplayID) -> Bool { canChangeFn?(id) ?? false }

    public func brightness(_ id: CGDirectDisplayID) -> Float? {
        guard let getFn else { return nil }
        var value: Float = 0
        return getFn(id, &value) == 0 ? value : nil
    }

    public func setBrightness(_ id: CGDirectDisplayID, _ value: Float) -> Bool {
        let clamped = Self.clamp(value)
        guard let setFn, setFn(id, clamped) == 0 else { return false }
        changedFn?(id, Double(clamped))
        return true
    }
}
