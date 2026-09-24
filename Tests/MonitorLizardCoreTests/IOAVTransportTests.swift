// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MonitorLizardCore

final class IOAVTransportTests: XCTestCase {
    func testPrivateIOAVSymbolsResolveOnThisMac() {
        // Apple Silicon only; documents the dependency rather than proving the bus.
        XCTAssertTrue(IOAVSymbols.isAvailable)
    }

    func testValidateRejectsZeroByteCount() {
        XCTAssertThrowsError(try IOAVTransport.validate(byteCount: 0)) { error in
            guard case .io(let rc) = error as? DDCError else {
                XCTFail("Expected DDCError.io, got \(error)")
                return
            }
            XCTAssertEqual(rc, kIOReturnBadArgument)
        }
    }

    func testValidateAcceptsPositiveByteCount() {
        do {
            try IOAVTransport.validate(byteCount: 4)
        } catch {
            XCTFail("Expected no throw, but got: \(error)")
        }
    }
}
