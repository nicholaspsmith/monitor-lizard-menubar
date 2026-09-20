// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MonitorLizardCore

final class VCPTests: XCTestCase {
    // Vectors computed from the DDC/CI spec and confirmed against the Dell U3818DW on 2026-09-12.
    func testReadRequestBytes() {
        XCTAssertEqual(VCP.readRequest(.brightness), [0x82, 0x01, 0x10, 0xAC])
        XCTAssertEqual(VCP.readRequest(.contrast), [0x82, 0x01, 0x12, 0xAE])
    }

    func testWriteRequestBytes() {
        XCTAssertEqual(VCP.writeRequest(.brightness, value: 99), [0x84, 0x03, 0x10, 0x00, 0x63, 0xCB])
        XCTAssertEqual(VCP.writeRequest(.contrast, value: 75), [0x84, 0x03, 0x12, 0x00, 0x4B, 0xE1])
    }

    func testWriteRequestSplitsHighByte() {
        XCTAssertEqual(Array(VCP.writeRequest(.brightness, value: 0x0102)[3...4]), [0x01, 0x02])
    }

    func testParsesAGoodReply() {
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x63, 0xA3, 0x00]
        XCTAssertEqual(VCP.parseReply(reply, expecting: .brightness), VCPValue(current: 99, maximum: 100))
        let contrast: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x12, 0x00, 0x00, 0x64, 0x00, 0x4B, 0x89, 0x00]
        XCTAssertEqual(VCP.parseReply(contrast, expecting: .contrast), VCPValue(current: 75, maximum: 100))
    }

    func testRejectsWrongVCP() {
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x12, 0x00, 0x00, 0x64, 0x00, 0x4B, 0x89, 0x00]
        XCTAssertNil(VCP.parseReply(reply, expecting: .brightness))
    }

    func testRejectsBadChecksum() {
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x63, 0xA2, 0x00]
        XCTAssertNil(VCP.parseReply(reply, expecting: .brightness))
    }

    func testRejectsWrongLengthMarkerAndShortBuffers() {
        var reply: [UInt8] = [0x6E, 0x86, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x63, 0xA3, 0x00]
        XCTAssertNil(VCP.parseReply(reply, expecting: .brightness))
        reply = [0x6E, 0x88, 0x02]
        XCTAssertNil(VCP.parseReply(reply, expecting: .brightness))
        XCTAssertNil(VCP.parseReply([UInt8](repeating: 0, count: 12), expecting: .brightness))
    }
}
