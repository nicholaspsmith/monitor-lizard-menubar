// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

/// Decides when Armonitor runs his lap of the whole screen: only on yes/no
/// changes, never on a slider. A display he has not seen before appearing, or
/// Night Shift turning on or off (from the menu, Control Center or its
/// schedule). The first look only learns what is there; launch has its own lap.
public struct LapTrigger {
    private var displays: Set<UInt32>?
    private var nightShift: Bool?

    public init() {}

    /// Feed it the current state on every change; true means run the lap.
    public mutating func update(displays now: Set<UInt32>, nightShift ns: Bool?) -> Bool {
        defer { displays = (displays ?? []).union(now); if ns != nil { nightShift = ns } }
        guard let seen = displays else { return false }
        let newDisplay = !now.isSubset(of: seen)
        let flipped = ns != nil && nightShift != nil && ns != nightShift
        return newDisplay || flipped
    }
}
