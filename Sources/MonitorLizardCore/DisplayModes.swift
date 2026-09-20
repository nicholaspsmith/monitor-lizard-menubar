// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation
import CoreGraphics

/// One CGDisplayMode, reduced to what the planner needs. `index` points back
/// into the array the mode came from so `apply` can find the real object.
public struct ModeSpec: Equatable, Hashable {
    public let index: Int
    public let width: Int
    public let height: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let refresh: Double
    public let usable: Bool

    public init(index: Int, width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, refresh: Double, usable: Bool) {
        self.index = index; self.width = width; self.height = height
        self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight; self.refresh = refresh; self.usable = usable
    }

    public var isHiDPI: Bool { pixelWidth == 2 * width }
    public var aspect: Double { Double(width) / Double(height) }
    public var label: String { "\(width)×\(height)" }
}

public struct ModePlan: Equatable {
    public let native: ModeSpec?
    public let hiDPI: [ModeSpec]
    public let lowRes: [ModeSpec]
    public let current: ModeSpec?

    /// Position of `mode`'s size among the HiDPI stops (refresh ignored).
    public func stopIndex(of mode: ModeSpec) -> Int? {
        hiDPI.firstIndex { $0.width == mode.width && $0.height == mode.height }
    }
}

/// Turns the raw mode list into the slider's stops and the picker's rows.
/// Letterboxed aspect ratios are dropped everywhere; nobody wants 1280×720 on
/// a 21:9 panel from a slider.
public enum DisplayModes {
    public static let aspectTolerance = 0.01

    public static func plan(all: [ModeSpec], current: ModeSpec?) -> ModePlan {
        let usable = all.filter(\.usable)
        let native = usable.filter { !$0.isHiDPI }.max { a, b in
            (a.pixelWidth * a.pixelHeight, a.refresh) < (b.pixelWidth * b.pixelHeight, b.refresh)
        }
        guard let native else { return ModePlan(native: nil, hiDPI: [], lowRes: [], current: current) }
        let sameAspect = usable.filter { abs($0.aspect - native.aspect) / native.aspect <= aspectTolerance }
        return ModePlan(native: native,
                        hiDPI: dedup(sameAspect.filter(\.isHiDPI), preferring: current?.refresh),
                        lowRes: dedup(sameAspect.filter { !$0.isHiDPI }, preferring: current?.refresh),
                        current: current)
    }

    /// One mode per (width, height): the one at the preferred refresh rate if
    /// it exists, else the fastest. Ordered by width, then height.
    private static func dedup(_ modes: [ModeSpec], preferring refresh: Double?) -> [ModeSpec] {
        let groups = Dictionary(grouping: modes) { "\($0.width)x\($0.height)" }
        return groups.values.compactMap { group -> ModeSpec? in
            if let refresh, let exact = group.first(where: { $0.refresh == refresh }) { return exact }
            return group.max { $0.refresh < $1.refresh }
        }
        .sorted { ($0.width, $0.height) < ($1.width, $1.height) }
    }

    // MARK: - CoreGraphics

    public static func specs(for id: CGDirectDisplayID) -> (all: [ModeSpec], current: ModeSpec?, modes: [CGDisplayMode]) {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: kCFBooleanTrue] as CFDictionary
        let modes = (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode]) ?? []
        let all = modes.enumerated().map { i, m in
            ModeSpec(index: i, width: m.width, height: m.height, pixelWidth: m.pixelWidth, pixelHeight: m.pixelHeight,
                     refresh: m.refreshRate, usable: m.isUsableForDesktopGUI())
        }
        let current = CGDisplayCopyDisplayMode(id).flatMap { cur in
            all.first { $0.width == cur.width && $0.height == cur.height && $0.pixelWidth == cur.pixelWidth && $0.refresh == cur.refreshRate }
        }
        return (all, current, modes)
    }

    /// Checks that `spec.index` still points at the mode it was derived from,
    /// rather than trusting a caller who may be replaying a spec against a
    /// mode list refreshed since. `.rangeCheck` for an out-of-bounds index,
    /// `.illegalArgument` when the index is in range but names a different mode.
    public static func validate(_ spec: ModeSpec, against all: [ModeSpec]) -> CGError {
        guard all.indices.contains(spec.index) else { return .rangeCheck }
        let mode = all[spec.index]
        guard mode.width == spec.width, mode.height == spec.height,
              mode.pixelWidth == spec.pixelWidth, mode.refresh == spec.refresh else {
            return .illegalArgument
        }
        return .success
    }

    public static func apply(_ spec: ModeSpec, all: [ModeSpec], modes: [CGDisplayMode], to id: CGDirectDisplayID) -> CGError {
        let validation = validate(spec, against: all)
        guard validation == .success else {
            Log.modes.error("display \(id) → \(spec.label) @\(spec.refresh) failed validation rc=\(validation.rawValue)")
            return validation
        }
        guard modes.indices.contains(spec.index) else {
            Log.modes.error("display \(id) → \(spec.label) @\(spec.refresh) index \(spec.index) out of range for modes rc=\(CGError.rangeCheck.rawValue)")
            return .rangeCheck
        }
        var config: CGDisplayConfigRef?
        var err = CGBeginDisplayConfiguration(&config)
        guard err == .success, let config else {
            Log.modes.error("display \(id) → \(spec.label) @\(spec.refresh) CGBeginDisplayConfiguration failed rc=\(err.rawValue)")
            return err
        }
        err = CGConfigureDisplayWithDisplayMode(config, id, modes[spec.index], nil)
        guard err == .success else {
            CGCancelDisplayConfiguration(config)
            Log.modes.error("display \(id) → \(spec.label) @\(spec.refresh) CGConfigureDisplayWithDisplayMode failed rc=\(err.rawValue)")
            return err
        }
        err = CGCompleteDisplayConfiguration(config, .forSession)
        Log.modes.info("display \(id) → \(spec.label) @\(spec.refresh) HiDPI=\(spec.isHiDPI) rc=\(err.rawValue)")
        return err
    }
}
