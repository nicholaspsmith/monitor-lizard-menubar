// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import CoreGraphics

/// The gamma-table half of XDR brightness: once an EDR overlay has put the
/// built-in panel into HDR mode, a transfer table that maps SDR white above
/// 1.0 pushes everything into the EDR headroom. Pure, so the table and the
/// "is it gone?" check are unit-testable without a display.
public enum XDRGamma {
    public static let tableSize = 256

    /// The value the overlay pixel draws. Anything above SDR white makes the
    /// window server switch the panel into HDR mode; BrightIntosh uses 1.6.
    public static let overlayValue: Double = 1.6

    /// `NSScreen.maximumExtendedDynamicRangeColorComponentValue` sits at 1.0
    /// until HDR mode is engaged; a table written before that only clips.
    public static let hdrReadyThreshold: Float = 1.05

    public static func isHDREngaged(currentHeadroom: Float) -> Bool {
        currentHeadroom > hdrReadyThreshold
    }

    /// Never map SDR white higher than this, whatever headroom the panel
    /// reports: the potential headroom on an XDR panel is reference-mode HDR
    /// (16×), which would blow every highlight out. 2× is ~1000 nits from a
    /// 500-nit SDR ceiling — what the panel sustains full-screen.
    public static let maxFactor: Float = 2

    /// How far to lift SDR white: `boost` 0…1 across 1…min(headroom, maxFactor).
    public static func factor(boost: Float, headroom: Float) -> Float {
        let top = min(max(1, headroom), maxFactor)
        return 1 + max(0, min(1, boost)) * (top - 1)
    }

    /// A linear ramp scaled by `factor`: entry i is i/(n-1) × factor.
    public static func table(factor: Float, size: Int = tableSize) -> [CGGammaValue] {
        guard size > 1 else { return [factor] }
        return (0..<size).map { Float($0) / Float(size - 1) * factor }
    }

    /// The panel's own table lifted by `factor`, so a calibration curve keeps
    /// its shape and only its scale changes.
    public static func scaled(_ base: [CGGammaValue], by factor: Float) -> [CGGammaValue] {
        base.map { $0 * factor }
    }

    /// Whether a transfer table still lifts anything past SDR white — the
    /// regression check that switching the feature off really removed it.
    public static func carriesBoost(_ table: [CGGammaValue], tolerance: Float = 0.01) -> Bool {
        table.contains { $0 > 1 + tolerance }
    }

    /// The colour guard's ramp check: a sane table rises monotonically from
    /// ~0 and ends at or under 1. A scrambled or still-boosted one fails.
    public static func isPlainRamp(_ table: [CGGammaValue], tolerance: Float = 0.01) -> Bool {
        guard let first = table.first, let last = table.last else { return false }
        guard first <= tolerance, last >= 1 - 0.25, !carriesBoost(table, tolerance: tolerance) else { return false }
        return zip(table, table.dropFirst()).allSatisfy { $1 >= $0 - tolerance }
    }
}

/// When the boost may be on the panel. Everything that can go wrong with a
/// gamma table happens across sleep and reconfiguration, so the table is only
/// present while the machine is awake and the display list has settled.
public enum XDRPolicy {
    public static func shouldBoost(enabled: Bool, asleep: Bool, settling: Bool,
                                   onBattery: Bool, offOnBattery: Bool) -> Bool {
        enabled && !asleep && !settling && !(onBattery && offOnBattery)
    }

    /// Unplugging switches the feature off rather than pausing it, so going
    /// back on power never brightens the panel by surprise.
    public static func shouldSwitchOff(enabled: Bool, onBattery: Bool, offOnBattery: Bool) -> Bool {
        enabled && onBattery && offOnBattery
    }
}
