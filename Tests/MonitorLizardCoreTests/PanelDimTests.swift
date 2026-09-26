// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MonitorLizardCore

final class PanelDimTests: XCTestCase {
    func testFactorRunsFromNormalToThirtyFivePercent() {
        XCTAssertEqual(PanelDim.factor(level: 0), 1)
        XCTAssertEqual(PanelDim.factor(level: 1), 0.35, accuracy: 1e-6)
        XCTAssertEqual(PanelDim.factor(level: 0.5), 0.5916, accuracy: 1e-4)
        XCTAssertEqual(PanelDim.factor(level: 2), 0.35, accuracy: 1e-6, "clamped")
        XCTAssertEqual(PanelDim.factor(level: -1), 1, "clamped")
    }

    func testKeysWalkFiveDistinctSteps() {
        var level: Float = 0
        var factors: [Int] = []
        for _ in 0..<7 { level = PanelDim.step(level, .down); factors.append(Int((PanelDim.factor(level: level) * 100).rounded())) }
        XCTAssertEqual(factors, [81, 66, 53, 43, 35, 35, 35])
        // Every step lets through at most ~81% of the one above: visibly darker.
        for (a, b) in zip([100] + factors.prefix(5), factors.prefix(5)) { XCTAssertLessThanOrEqual(Double(b) / Double(a), 0.82) }
        for _ in 0..<5 { level = PanelDim.step(level, .up) }
        XCTAssertEqual(level, 0)
        XCTAssertEqual(PanelDim.step(0, .up), 0)
    }

    func testStepsSnapFromASliderValue() {
        XCTAssertEqual(PanelDim.step(0.3, .down), 2 / 5)
        XCTAssertEqual(PanelDim.step(0.3, .up), 1 / 5)
        XCTAssertEqual(PanelDim.step(Float(2) / 5, .down), 3 / 5, "on a step: the next one")
    }

    func testLabel() {
        XCTAssertEqual(PanelDim.label(level: 0), "Off")
        XCTAssertEqual(PanelDim.label(level: 1), "35%")
        XCTAssertEqual(PanelDim.label(level: 0.2), "81%")
    }

    func testRaisingBrightnessCancels() {
        XCTAssertTrue(PanelDim.cancels(previous: 0, current: 0.0625))
        XCTAssertFalse(PanelDim.cancels(previous: 0, current: 0.03), "auto-brightness jitter")
        XCTAssertFalse(PanelDim.cancels(previous: 0.5, current: 0.3))
        XCTAssertFalse(PanelDim.cancels(previous: nil, current: 0.5))
    }

    // One key press: the ladder is 1/16 → eight dim steps → off, and back.
    func testKeyStepWalksTheLadder() {
        XCTAssertEqual(PanelDim.keyStep(level: 0, brightness: 0.0625, direction: .down), PanelDim.KeyStep(level: 0.2, brightness: nil))
        XCTAssertEqual(PanelDim.keyStep(level: 0.6, brightness: 0.0625, direction: .up), PanelDim.KeyStep(level: 0.4, brightness: nil))
        XCTAssertEqual(PanelDim.keyStep(level: 1, brightness: 0.0625, direction: .down), PanelDim.KeyStep(level: 0, brightness: 0), "deepest, then off")
        XCTAssertEqual(PanelDim.keyStep(level: 0, brightness: 0, direction: .up), PanelDim.KeyStep(level: 1, brightness: 0.0625), "off, then deepest")
        XCTAssertEqual(PanelDim.keyStep(level: 0.2, brightness: 0.0625, direction: .up), PanelDim.KeyStep(level: 0, brightness: nil), "out of the dim; macOS takes the next press")
    }
}
