// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation
import IOKit
import CoreGraphics

/// Reads the two kinds of IORegistry node the matcher needs, looked up fresh
/// on every re-enumeration.
///
/// `externalAVServices()` filters to `Location == "External"` proxies only —
/// `DisplayMatcher.match` requires that the `services` it is given are
/// exclusively external, and this is what guarantees that invariant.
public enum IORegistryScanner {
    /// Reads `name`/`DisplayAttributes` from each framebuffer node and releases
    /// it immediately — nothing here is kept: there is no `IOObjectRetain` and
    /// no kernel object outlives this call.
    public static func framebuffers() -> [FramebufferEntry] {
        var out: [FramebufferEntry] = []
        for cls in ["IOMobileFramebufferShim", "AppleCLCD2"] {
            forEachService(matching: cls) { entry in
                let attrs = property(entry, "DisplayAttributes") as? [String: Any]
                let product = attrs?["ProductAttributes"] as? [String: Any]
                out.append(FramebufferEntry(
                    name: nodeName(entry),
                    productID: (product?["ProductID"] as? NSNumber).map { UInt32(truncating: $0) },
                    serial: (product?["SerialNumber"] as? NSNumber).map { UInt32(truncating: $0) }))
                IOObjectRelease(entry)
            }
        }
        return out
    }

    /// Non-external `DCPAVServiceProxy` nodes are released immediately and
    /// dropped. Each returned `AVServiceEntry` carries a **retained**
    /// `io_service_t` in `.entry` — the caller owns it and must
    /// `IOObjectRelease` it once done (`makeDDCServices(for:)` does this for
    /// every entry it fetches).
    public static func externalAVServices() -> [AVServiceEntry] {
        var out: [AVServiceEntry] = []
        forEachService(matching: "DCPAVServiceProxy") { entry in
            guard property(entry, "Location") as? String == "External" else { IOObjectRelease(entry); return }
            out.append(AVServiceEntry(path: path(entry), entry: entry))
        }
        return out
    }

    public static func makeDDCServices(for displays: [DisplayInfo]) -> [CGDirectDisplayID: DDCService] {
        let services = externalAVServices()
        defer { for service in services { IOObjectRelease(service.entry) } }
        let matched = DisplayMatcher.match(displays: displays, framebuffers: framebuffers(), services: services)
        var out: [CGDirectDisplayID: DDCService] = [:]
        for (id, service) in matched {
            if let transport = IOAVTransport(service: service.entry) {
                out[id] = DDCService(transport: transport)
            } else {
                Log.ddc.error("IOAVServiceCreateWithService failed for display \(id)")
            }
        }
        return out
    }

    // MARK: - IOKit helpers

    /// The parent node's name is the framebuffer's name (`dispext0@B0000000` → `dispext0`);
    /// `IOMobileFramebufferShim` itself is a child of that node.
    private static func nodeName(_ entry: io_registry_entry_t) -> String {
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent) == KERN_SUCCESS else {
            Log.ddc.debug("IORegistryEntryGetParentEntry failed for framebuffer entry \(entry)")
            return ""
        }
        defer { IOObjectRelease(parent) }
        var name = [CChar](repeating: 0, count: 128)
        IORegistryEntryGetName(parent, &name)
        return String(cString: name).components(separatedBy: "@").first ?? ""
    }

    private static func path(_ entry: io_registry_entry_t) -> String {
        var buf = [CChar](repeating: 0, count: 1024)
        IORegistryEntryGetPath(entry, kIOServicePlane, &buf)
        return String(cString: buf)
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    /// Hands each matching service to `body` retained; `body` owns the release.
    private static func forEachService(matching cls: String, _ body: (io_service_t) -> Void) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(cls), &iterator) == KERN_SUCCESS else {
            Log.ddc.debug("IOServiceGetMatchingServices found no \(cls, privacy: .public) services")
            return
        }
        defer { IOObjectRelease(iterator) }
        while case let s = IOIteratorNext(iterator), s != 0 { body(s) }
    }
}
