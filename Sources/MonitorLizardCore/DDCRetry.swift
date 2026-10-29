// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// What a failed DDC read means. A monitor that has just been plugged in or
/// woken refuses DDC for a few seconds, so the first read after a
/// reconfiguration often fails; without a retry the display stayed marked
/// unavailable, and its brightness keys passed through to macOS, until the
/// menu happened to be opened.
public enum DDCRetry {
    /// Seconds before each re-read after a failure: about a minute in all,
    /// then the display is left to DisplayServices (a TV over HDMI never
    /// answers). DDC is still never polled on a timer.
    public static let delays: [TimeInterval] = [2, 4, 8, 16, 30]

    /// - Returns: the wait before re-read number `attempt` (0-based), or nil
    ///   once the retries are spent.
    public static func delay(afterFailure attempt: Int) -> TimeInterval? {
        delays.indices.contains(attempt) ? delays[attempt] : nil
    }

    /// Whether a failed read of `code` makes the display's DDC unavailable.
    /// The keys and the Brightness row depend on brightness alone.
    public static func marksUnavailable(_ code: VCPCode) -> Bool {
        code == .brightness
    }
}
