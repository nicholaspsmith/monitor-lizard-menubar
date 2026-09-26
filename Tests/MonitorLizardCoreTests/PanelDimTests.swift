// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MonitorLizardCore

final class PanelDimTests: XCTestCase {
    func testFactorRunsFromNormalToTenPercent() {
        XCTAssertEqual(PanelDim.factor(level: 0), 1)
        XCTAssertEqual(PanelDim.factor(level: 1), 0.1, accuracy: 1e-6)
        XCTAssertEqual(PanelDim.factor(level: 0.5), 0.3162, accuracy: 1e-4)
        XCTAssertEqual(PanelDim.factor(level: 2), 0.1, accuracy: 1e-6, "clamped")
        XCTAssertEqual(PanelDim.factor(level: -1), 1, "clamped")
    }

    func testKeysWalkEightSteps() {
        var level: Float = 0
        var factors: [Int] = []
        for _ in 0..<10 { level = PanelDim.step(level, .down); factors.append(Int((PanelDim.factor(level: level) * 100).rounded())) }
        XCTAssertEqual(factors, [75, 56, 42, 32, 24, 18, 13, 10, 10, 10])
        for _ in 0..<8 { level = PanelDim.step(level, .up) }
        XCTAssertEqual(level, 0)
        XCTAssertEqual(PanelDim.step(0, .up), 0)
    }

    func testStepsSnapFromASliderValue() {
        XCTAssertEqual(PanelDim.step(0.3, .down), 3 / 8)
        XCTAssertEqual(PanelDim.step(0.3, .up), 2 / 8)
        XCTAssertEqual(PanelDim.step(Float(3) / 8, .down), 4 / 8, "on a step: the next one")
    }

    func testLabel() {
        XCTAssertEqual(PanelDim.label(level: 0), "Off")
        XCTAssertEqual(PanelDim.label(level: 1), "10%")
        XCTAssertEqual(PanelDim.label(level: 0.125), "75%")
    }

    func testRaisingBrightnessCancels() {
        XCTAssertTrue(PanelDim.cancels(previous: 0, current: 0.0625))
        XCTAssertFalse(PanelDim.cancels(previous: 0, current: 0.03), "auto-brightness jitter")
        XCTAssertFalse(PanelDim.cancels(previous: 0.5, current: 0.3))
        XCTAssertFalse(PanelDim.cancels(previous: nil, current: 0.5))
    }

    func testTablePolicy() {
        func mode(xdr: Bool = false, dim: Float = 0, asleep: Bool = false, settling: Bool = false, battery: Bool = false) -> PanelTableMode {
            PanelTablePolicy.mode(xdrEnabled: xdr, dimLevel: dim, asleep: asleep, settling: settling, onBattery: battery, offOnBattery: true)
        }
        XCTAssertEqual(mode(), .none)
        XCTAssertEqual(mode(xdr: true), .boost)
        XCTAssertEqual(mode(dim: 1), .dim(PanelDim.factor(level: 1)))
        XCTAssertEqual(mode(xdr: true, dim: 0.5), .dim(PanelDim.factor(level: 0.5)), "dim wins")
        XCTAssertEqual(mode(dim: 1, asleep: true), .none)
        XCTAssertEqual(mode(dim: 1, settling: true), .none)
        XCTAssertEqual(mode(dim: 1, battery: true), .dim(PanelDim.factor(level: 1)), "the battery rule is XDR's")
        XCTAssertEqual(mode(xdr: true, battery: true), .none)
    }
}
