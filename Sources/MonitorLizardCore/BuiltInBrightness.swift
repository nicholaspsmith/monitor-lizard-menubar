// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation
import CoreGraphics

public protocol BrightnessBackend: AnyObject {
    var isAvailable: Bool { get }
    func canChange(_ id: CGDirectDisplayID) -> Bool
    func brightness(_ id: CGDirectDisplayID) -> Float?
    func setBrightness(_ id: CGDirectDisplayID, _ value: Float) -> Bool
    /// Calls `handler` on the main thread whenever the display's brightness
    /// changes by any route (keyboard keys, Control Center, this app). Register
    /// once per display; repeat calls for the same display are ignored.
    func observeChanges(_ id: CGDirectDisplayID, _ handler: @escaping () -> Void)
}

/// DisplayServices.framework (private) — what Control Center uses for the
/// built-in panel. `BrightnessChanged` is posted after a set so Control
/// Center's own slider follows.
public final class DisplayServicesBrightness: BrightnessBackend {
    private typealias CanChangeFn = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias ChangedFn = @convention(c) (CGDirectDisplayID, Double) -> Void
    private typealias Callback = @convention(c) (CFNotificationCenter?, UnsafeMutableRawPointer?, CFNotificationName?, UnsafeRawPointer?, CFDictionary?) -> Void
    private typealias RegisterFn = @convention(c) (CGDirectDisplayID, CGDirectDisplayID, Callback) -> Int32

    private let canChangeFn: CanChangeFn?
    private let getFn: GetFn?
    private let setFn: SetFn?
    private let changedFn: ChangedFn?
    private let registerFn: RegisterFn?

    /// The registration takes a C function pointer and no context, so the
    /// handlers live in a process-wide table keyed by display; a notification
    /// for any display fans out to every handler (each just re-reads its own
    /// display, which is cheap). Main-thread only.
    private static var handlers: [CGDirectDisplayID: () -> Void] = [:]

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
        registerFn = sym("DisplayServicesRegisterForBrightnessChangeNotifications")
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

    public func observeChanges(_ id: CGDirectDisplayID, _ handler: @escaping () -> Void) {
        guard Self.handlers[id] == nil else { return }
        Self.handlers[id] = handler
        guard let registerFn else { return }
        // Fires on the main run loop (CFNotificationCenter), with the new value
        // in userInfo["value"]; we ignore the payload and let handlers re-read.
        let rc = registerFn(id, id) { _, _, _, _, _ in
            DispatchQueue.main.async { DisplayServicesBrightness.handlers.values.forEach { $0() } }
        }
        if rc != 0 { Log.menu.error("brightness change registration for display \(id) failed rc=\(rc)") }
    }
}
