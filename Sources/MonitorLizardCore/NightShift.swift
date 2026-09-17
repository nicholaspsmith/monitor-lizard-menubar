import Foundation

public struct NightShiftStatus: Equatable {
    public let available: Bool
    /// Whether Night Shift is engaged right now — what Control Center shows.
    /// Key all UI off this field, never off `active`: empirically on this
    /// Mac, `active == true` while Night Shift is OFF
    /// (`corebrightnessdiag` shows `BlueLightReductionFactor = 0`,
    /// `mode = 0`), so `enabled` is the real engagement flag (as Shifty and
    /// the `nightlight` CLI use it).
    public let enabled: Bool
    public let active: Bool
    public let strength: Float
    public init(available: Bool, enabled: Bool, active: Bool, strength: Float) {
        self.available = available; self.enabled = enabled; self.active = active; self.strength = strength
    }
}

public protocol NightShiftBackend: AnyObject {
    var isAvailable: Bool { get }
    func status() -> NightShiftStatus
    func setEnabled(_ enabled: Bool) -> Bool
    func setStrength(_ strength: Float) -> Bool
    func onChange(_ handler: @escaping () -> Void)
}

/// `CBBlueLightClient`'s status struct, as laid out in CoreBrightness (the
/// layout the `nightlight` CLI uses; sanity-checked at runtime by `status()`).
private struct BlueLightTime { var hour: Int32; var minute: Int32 }
private struct BlueLightSchedule { var from: BlueLightTime; var to: BlueLightTime }
private struct BlueLightStatusData {
    var active: Bool
    var enabled: Bool
    var sunSchedulePermitted: Bool
    var mode: Int32
    var schedule: BlueLightSchedule
    var disableFlags: UInt64
    var available: Bool
}

/// The private class's selectors, expressed as an @objc protocol so the
/// existential is a plain object pointer and `unsafeBitCast` is legal.
@objc private protocol BlueLightClient {
    func setEnabled(_ enabled: Bool) -> Bool
    func setStrength(_ strength: Float, commit: Bool) -> Bool
    func getStrength(_ strength: UnsafeMutablePointer<Float>) -> Bool
    func getBlueLightStatus(_ status: UnsafeMutableRawPointer) -> Bool
    func setStatusNotificationBlock(_ block: @escaping @convention(block) () -> Void)
}

public final class CoreBrightnessNightShift: NightShiftBackend {
    private let client: BlueLightClient
    private var handlers: [() -> Void] = []

    public init?() {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW) != nil,
              let cls = NSClassFromString("CBBlueLightClient") as? NSObject.Type else { return nil }
        let object = cls.init()
        let requiredSelectors: [(name: String, selector: Selector)] = [
            ("setEnabled:", #selector(BlueLightClient.setEnabled(_:))),
            ("setStrength:commit:", #selector(BlueLightClient.setStrength(_:commit:))),
            ("getStrength:", #selector(BlueLightClient.getStrength(_:))),
            ("getBlueLightStatus:", #selector(BlueLightClient.getBlueLightStatus(_:))),
            ("setStatusNotificationBlock:", #selector(BlueLightClient.setStatusNotificationBlock(_:))),
        ]
        for (name, selector) in requiredSelectors {
            guard object.responds(to: selector) else {
                Log.nightshift.error("CBBlueLightClient does not respond to \(name, privacy: .public); Night Shift disabled")
                return nil
            }
        }
        client = unsafeBitCast(object, to: BlueLightClient.self)
        client.setStatusNotificationBlock { [weak self] in
            DispatchQueue.main.async { self?.handlers.forEach { $0() } }
        }
    }

    public var isAvailable: Bool { status().available }

    public func status() -> NightShiftStatus {
        var data = BlueLightStatusData(active: false, enabled: false, sunSchedulePermitted: false, mode: 0,
                                       schedule: .init(from: .init(hour: 0, minute: 0), to: .init(hour: 0, minute: 0)),
                                       disableFlags: 0, available: false)
        let ok = withUnsafeMutablePointer(to: &data) { client.getBlueLightStatus(UnsafeMutableRawPointer($0)) }
        guard ok, (0...4).contains(data.mode) else {
            Log.nightshift.error("CBBlueLightClient status looked wrong (ok=\(ok) mode=\(data.mode)); treating Night Shift as unavailable")
            return NightShiftStatus(available: false, enabled: false, active: false, strength: 0)
        }
        var strength: Float = 0
        _ = client.getStrength(&strength)
        return NightShiftStatus(available: data.available, enabled: data.enabled, active: data.active, strength: DisplayServicesBrightness.clamp(strength))
    }

    public func setEnabled(_ enabled: Bool) -> Bool { client.setEnabled(enabled) }

    public func setStrength(_ strength: Float) -> Bool { client.setStrength(DisplayServicesBrightness.clamp(strength), commit: true) }

    public func onChange(_ handler: @escaping () -> Void) { handlers.append(handler) }
}
