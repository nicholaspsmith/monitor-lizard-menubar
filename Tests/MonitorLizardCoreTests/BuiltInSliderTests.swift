// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MonitorLizardCore

final class BuiltInSliderTests: XCTestCase {
    typealias L = BuiltInLevel
    private let floor = PanelDim.lowestLitBrightness

    func testSegmentsWithoutXDR() {
        XCTAssertEqual(BuiltInSlider.level(at: 0, xdr: false), L(dim: 1, brightness: floor, boost: 0))
        XCTAssertEqual(BuiltInSlider.level(at: 0.2, xdr: false), L(dim: 0, brightness: floor, boost: 0))
        XCTAssertEqual(BuiltInSlider.level(at: 1, xdr: false), L(dim: 0, brightness: 1, boost: 0))
        let mid = BuiltInSlider.level(at: 0.1, xdr: false)
        XCTAssertEqual(mid.dim, 0.5, accuracy: 1e-6)
    }

    func testXDRAddsTheTopFifth() {
        XCTAssertEqual(BuiltInSlider.level(at: 0.8, xdr: true), L(dim: 0, brightness: 1, boost: 0))
        XCTAssertEqual(BuiltInSlider.level(at: 1, xdr: true), L(dim: 0, brightness: 1, boost: 1))
        XCTAssertEqual(BuiltInSlider.level(at: 0.9, xdr: true).boost, 0.5, accuracy: 1e-6)
        XCTAssertEqual(BuiltInSlider.level(at: 0.5, xdr: true).brightness, floor + 0.5 * (1 - floor), accuracy: 1e-6)
    }

    func testPositionRoundTrips() {
        for xdr in [false, true] {
            for p in stride(from: 0.0, through: 1.0, by: 0.05) {
                let l = BuiltInSlider.level(at: p, xdr: xdr)
                XCTAssertEqual(BuiltInSlider.position(l, xdr: xdr), p, accuracy: 1e-5, "p=\(p) xdr=\(xdr)")
            }
        }
    }

    func testPositionOfStatesTheSliderCanNotMake() {
        // Below 1/16 lights the same as 1/16.
        XCTAssertEqual(BuiltInSlider.position(L(dim: 0, brightness: 0.03, boost: 0), xdr: false), 0.2, accuracy: 1e-6)
        // A boost only counts at full brightness, and only with XDR on.
        XCTAssertEqual(BuiltInSlider.position(L(dim: 0, brightness: 1, boost: 0.5), xdr: false), 1, accuracy: 1e-6)
        XCTAssertEqual(BuiltInSlider.position(L(dim: 0, brightness: 0.5, boost: 0.5), xdr: true),
                       BuiltInSlider.position(L(dim: 0, brightness: 0.5, boost: 0), xdr: true), accuracy: 1e-6)
    }

    func testLabels() {
        XCTAssertEqual(BuiltInSlider.label(L(dim: 1, brightness: floor, boost: 0)), "Dim 35%")
        XCTAssertEqual(BuiltInSlider.label(L(dim: 0, brightness: 0.5, boost: 0)), "50%")
        XCTAssertEqual(BuiltInSlider.label(L(dim: 0, brightness: 1, boost: 0.5)), "XDR +50%")
        XCTAssertEqual(BuiltInSlider.label(L(dim: 0, brightness: 1, boost: 0)), "100%")
    }

    func testBoostKeySteps() {
        XCTAssertEqual(BuiltInSlider.boostStep(0, .up), 0.25)
        XCTAssertEqual(BuiltInSlider.boostStep(1, .up), 1)
        XCTAssertEqual(BuiltInSlider.boostStep(0.25, .down), 0)
        XCTAssertEqual(BuiltInSlider.boostStep(0.6, .down), 0.5, "snaps to quarters")
    }
}
