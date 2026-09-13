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
}
