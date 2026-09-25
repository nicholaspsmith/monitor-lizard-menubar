// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import os

/// One logger per subsystem area so `log show --predicate 'subsystem == "com.nicholaspsmith.MonitorLizard"'`
/// tells the story the way Barn's does.
public enum Log {
    public static let subsystem = "com.nicholaspsmith.MonitorLizard"
    public static let ddc = Logger(subsystem: subsystem, category: "ddc")
    public static let modes = Logger(subsystem: subsystem, category: "modes")
    public static let nightshift = Logger(subsystem: subsystem, category: "nightshift")
    public static let tvrole = Logger(subsystem: subsystem, category: "tvrole")
    public static let menu = Logger(subsystem: subsystem, category: "menu")
    public static let xdr = Logger(subsystem: subsystem, category: "xdr")
}
