// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// Dimming the built-in panel below macOS's lowest brightness. The backlight
/// is already at its minimum there, so this scales the panel's transfer table
/// down instead: lit pixels dim, blacks stay where they are.
///
/// A level runs 0…1; the table's factor is `minFactor^level`, so equal steps
/// look like equal changes. The keys move in eighths.
public enum PanelDim {
    public static let steps = 8
    /// The deepest dim, as a fraction of normal. Much lower and gradients band
    /// through the 256-entry table and text stops being readable.
    public static let minFactor: Float = 0.1
    /// A rise in macOS brightness bigger than this, while dimmed, cancels the
    /// dim. Small enough for one key step or a Control Center drag, larger than
    /// auto-brightness jitter.
    public static let cancelRise: Float = 0.05

    /// macOS brightness at and below which the panel is off (backlight 0).
    public static let offBrightness: Float = 0.001
    /// macOS's lowest lit key step. Every brightness below it, down to
    /// 0.0001, lights the panel the same (1 nit, measured on an M5 Pro).
    public static let lowestLitBrightness: Float = 1.0 / 16

    /// What one brightness key press does once it belongs to the dim:
    /// the new dim level, and a macOS brightness to set, if any.
    public struct KeyStep: Equatable {
        public let level: Float
        public let brightness: Float?
        public init(level: Float, brightness: Float?) {
            self.level = level
            self.brightness = brightness
        }
    }

    /// The ladder is macOS's lowest lit step, the eight dim steps, then off:
    /// down from the deepest dim switches the panel off, and up from off comes
    /// back at the deepest dim rather than at full 1/16.
    public static func keyStep(level: Float, brightness: Float, direction: BrightnessKeys.Direction) -> KeyStep {
        if direction == .up && brightness <= offBrightness {
            return KeyStep(level: 1, brightness: lowestLitBrightness)
        }
        if direction == .down && level >= 1 {
            return KeyStep(level: 0, brightness: 0)
        }
        return KeyStep(level: step(level, direction), brightness: nil)
    }

    public static func factor(level: Float) -> Float {
        pow(minFactor, max(0, min(1, level)))
    }

    /// One key press from `level`, snapped to the eighths.
    public static func step(_ level: Float, _ direction: BrightnessKeys.Direction) -> Float {
        let k = max(0, min(1, level)) * Float(steps)
        let next: Float
        switch direction {
        case .down: next = min(Float(steps), (k + 1e-4).rounded(.down) + 1)
        case .up: next = max(0, (k - 1e-4).rounded(.up) - 1)
        }
        return next / Float(steps)
    }

    /// The slider's readout: "Off", or the percentage of normal left.
    public static func label(level: Float) -> String {
        level <= 0 ? "Off" : "\(Int((factor(level: level) * 100).rounded()))%"
    }

    /// Whether a change in macOS brightness should cancel the dim: someone
    /// (Control Center, auto-brightness in a brighter room) wants more light.
    public static func cancels(previous: Float?, current: Float?) -> Bool {
        guard let previous, let current else { return false }
        return current - previous > cancelRise
    }
}

/// What the built-in panel's transfer table should hold.
public enum PanelTableMode: Equatable {
    case none
    /// Scaled down by this factor.
    case dim(Float)
    /// XDR: lifted into the EDR headroom.
    case boost
}

public enum PanelTablePolicy {
    /// Nothing across sleep or while the display list settles (the XDR
    /// lifecycle); a dim wins over XDR, which it switches off anyway; XDR keeps
    /// its own battery rule.
    public static func mode(xdrEnabled: Bool, dimLevel: Float, asleep: Bool, settling: Bool,
                            onBattery: Bool, offOnBattery: Bool) -> PanelTableMode {
        if asleep || settling { return .none }
        if dimLevel > 0 { return .dim(PanelDim.factor(level: dimLevel)) }
        return XDRPolicy.shouldBoost(enabled: xdrEnabled, asleep: false, settling: false,
                                     onBattery: onBattery, offOnBattery: offOnBattery) ? .boost : .none
    }
}
