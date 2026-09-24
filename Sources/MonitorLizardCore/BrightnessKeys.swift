// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import CoreGraphics

/// What a brightness key does: which display it steps and by how much. Pure,
/// so the tap wiring in the app has nothing to decide.
public enum BrightnessKeys {
    public enum Direction { case up, down }

    /// Sixteen steps across the range, like Apple's keys on the built-in panel.
    public static let stepsAcrossRange: UInt16 = 16

    public static func step(_ value: VCPValue, _ direction: Direction) -> UInt16 {
        let size = max(1, value.maximum / stepsAcrossRange)
        switch direction {
        case .up: return min(value.maximum, value.current &+ size)
        case .down: return value.current > size ? value.current - size : 0
        }
    }

    public struct Display: Equatable {
        public let id: CGDirectDisplayID
        public let isMain: Bool
        public let isBuiltIn: Bool
        public let hasDDC: Bool
        public init(id: CGDirectDisplayID, isMain: Bool, isBuiltIn: Bool, hasDDC: Bool) {
            self.id = id
            self.isMain = isMain
            self.isBuiltIn = isBuiltIn
            self.hasDDC = hasDDC
        }
    }

    /// The display a brightness key steps: the main display, if it is an
    /// external monitor we can drive over DDC. `nil` means leave the key to
    /// macOS — the main display is the built-in panel (which macOS dims
    /// itself) or a monitor with no DDC (nothing to do).
    public static func target(among displays: [Display]) -> CGDirectDisplayID? {
        guard let main = displays.first(where: \.isMain) ?? displays.first else { return nil }
        guard !main.isBuiltIn, main.hasDDC else { return nil }
        return main.id
    }
}
