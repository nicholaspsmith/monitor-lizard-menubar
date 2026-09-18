import XCTest
@testable import MonitorLizardCore

final class BrightnessSourceTests: XCTestCase {
    func testBuiltInAlwaysUsesSystem() {
        XCTAssertEqual(BrightnessSource.pick(isBuiltIn: true, hasDDC: false, ddcUnavailable: false, systemCanChange: true), .system)
        XCTAssertEqual(BrightnessSource.pick(isBuiltIn: true, hasDDC: false, ddcUnavailable: false, systemCanChange: false), .system)
    }

    func testExternalPrefersDDCWhileItAnswers() {
        XCTAssertEqual(BrightnessSource.pick(isBuiltIn: false, hasDDC: true, ddcUnavailable: false, systemCanChange: false), .ddc)
        XCTAssertEqual(BrightnessSource.pick(isBuiltIn: false, hasDDC: true, ddcUnavailable: false, systemCanChange: true), .ddc)
    }

    func testExternalFallsBackToSystemWhenDDCFails() {
        // A TV over HDMI that ignores DDC/CI but that macOS dims itself — the
        // keyboard brightness keys already work on it.
        XCTAssertEqual(BrightnessSource.pick(isBuiltIn: false, hasDDC: true, ddcUnavailable: true, systemCanChange: true), .system)
        XCTAssertEqual(BrightnessSource.pick(isBuiltIn: false, hasDDC: false, ddcUnavailable: false, systemCanChange: true), .system)
    }

    func testExternalWithNeitherHasNoControl() {
        XCTAssertEqual(BrightnessSource.pick(isBuiltIn: false, hasDDC: true, ddcUnavailable: true, systemCanChange: false), .none)
        XCTAssertEqual(BrightnessSource.pick(isBuiltIn: false, hasDDC: false, ddcUnavailable: false, systemCanChange: false), .none)
    }
}
