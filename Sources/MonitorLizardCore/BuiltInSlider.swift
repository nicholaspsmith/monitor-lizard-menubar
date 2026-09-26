// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// Everything that sets how bright the built-in panel looks: the Dim
/// overlay, macOS's brightness, and the XDR boost.
public struct BuiltInLevel: Equatable {
    /// `PanelDim` level, 0 … 1.
    public var dim: Float
    /// macOS (DisplayServices) brightness, 0 … 1.
    public var brightness: Float
    /// XDR boost, 0 … 1 across 1× … 2×.
    public var boost: Float
    public init(dim: Float, brightness: Float, boost: Float) {
        self.dim = dim
        self.brightness = brightness
        self.boost = boost
    }
}

/// The built-in panel's one Brightness slider, which runs through all three:
/// Dim along the bottom fifth, macOS's range from its lowest lit step (1/16)
/// to full across the middle, and, with XDR Brightness on, the boost along the
/// top fifth. Off (brightness 0) is left to the keys.
public enum BuiltInSlider {
    public static let dimShare = 0.2
    public static let boostShare = 0.2
    public static let boostSteps = 4

    private static var floor: Double { Double(PanelDim.lowestLitBrightness) }
    private static func systemShare(xdr: Bool) -> Double { 1 - dimShare - (xdr ? boostShare : 0) }

    public static func level(at position: Double, xdr: Bool) -> BuiltInLevel {
        let p = max(0, min(1, position))
        let system = systemShare(xdr: xdr)
        if p < dimShare {
            return BuiltInLevel(dim: Float(1 - p / dimShare), brightness: Float(floor), boost: 0)
        }
        let top = dimShare + system
        if p <= top {
            let b = floor + min(1, (p - dimShare) / system) * (1 - floor)
            return BuiltInLevel(dim: 0, brightness: Float(min(1, b)), boost: 0)
        }
        return BuiltInLevel(dim: 0, brightness: 1, boost: Float(min(1, (p - top) / boostShare)))
    }

    public static func position(_ level: BuiltInLevel, xdr: Bool) -> Double {
        if level.dim > 0 { return (1 - Double(min(1, level.dim))) * dimShare }
        let system = systemShare(xdr: xdr)
        if xdr && level.brightness >= 0.999 && level.boost > 0 {
            return dimShare + system + Double(min(1, level.boost)) * boostShare
        }
        // Everything below 1/16 lights the panel the same as 1/16.
        let b = max(floor, min(1, Double(level.brightness)))
        return dimShare + (b - floor) / (1 - floor) * system
    }

    /// The row's readout.
    public static func label(_ level: BuiltInLevel) -> String {
        if level.dim > 0 { return "Dim \(PanelDim.label(level: level.dim))" }
        if level.boost > 0 && level.brightness >= 0.999 { return "XDR +\(Int((level.boost * 100).rounded()))%" }
        return "\(Int((level.brightness * 100).rounded()))%"
    }

    /// One brightness key press through the boost, in quarters (+25% each).
    public static func boostStep(_ boost: Float, _ direction: BrightnessKeys.Direction) -> Float {
        let k = max(0, min(1, boost)) * Float(boostSteps)
        let next: Float
        switch direction {
        case .up: next = min(Float(boostSteps), (k + 1e-4).rounded(.down) + 1)
        case .down: next = max(0, (k - 1e-4).rounded(.up) - 1)
        }
        return next / Float(boostSteps)
    }
}
