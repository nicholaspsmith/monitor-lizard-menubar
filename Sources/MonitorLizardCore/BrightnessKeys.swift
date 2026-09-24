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

    /// The same step over DisplayServices' 0…1 range.
    public static func step(_ fraction: Float, _ direction: Direction) -> Float {
        let size = 1 / Float(stepsAcrossRange)
        switch direction {
        case .up: return min(1, fraction + size)
        case .down: return max(0, fraction - size)
        }
    }

    public struct Display: Equatable {
        public let id: CGDirectDisplayID
        public let isMain: Bool
        public let isBuiltIn: Bool
        /// What the display's Brightness row uses — the keys take the same route.
        public let source: BrightnessSource
        public init(id: CGDirectDisplayID, isMain: Bool, isBuiltIn: Bool, source: BrightnessSource) {
            self.id = id
            self.isMain = isMain
            self.isBuiltIn = isBuiltIn
            self.source = source
        }
    }

    /// The display a brightness key steps: the main display, if it is an
    /// external monitor we can drive — over DDC, or through DisplayServices
    /// once DDC has refused and macOS can dim it itself. `nil` means leave
    /// the key to macOS — the main display is the built-in panel (which macOS
    /// dims itself) or a monitor nothing can drive.
    public static func target(among displays: [Display]) -> CGDirectDisplayID? {
        guard let main = displays.first(where: \.isMain) ?? displays.first else { return nil }
        guard !main.isBuiltIn, main.source != .none else { return nil }
        return main.id
    }
}
