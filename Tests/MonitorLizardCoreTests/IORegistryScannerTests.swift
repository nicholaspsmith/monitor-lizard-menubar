// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
import IOKit
import CoreGraphics
@testable import MonitorLizardCore

final class IORegistryScannerTests: XCTestCase {
    func testFindsFramebuffersAndTheExternalService() throws {
        let fbs = IORegistryScanner.framebuffers()
        XCTAssertTrue(fbs.contains { $0.name.hasPrefix("disp") }, "no framebuffers found: \(fbs)")
        let services = IORegistryScanner.externalAVServices()
        for s in services { XCTAssertNotNil(DisplayMatcher.framebufferName(inAVServicePath: s.path), s.path) }
        for s in services { IOObjectRelease(s.entry) }
    }

    func testMakeDDCServicesFindsTheOneExternalDisplayOnThisMac() throws {
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &displayCount)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetOnlineDisplayList(displayCount, &ids, &displayCount)
        let displays = ids.map { CoreDisplayInfo.info(for: $0) }
        guard displays.contains(where: { !$0.isBuiltIn }) else {
            throw XCTSkip("no external display online")
        }
        XCTAssertEqual(IORegistryScanner.makeDDCServices(for: displays).count, 1)
    }
}
