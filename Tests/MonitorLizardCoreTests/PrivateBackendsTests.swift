import XCTest
@testable import MonitorLizardCore

final class PrivateBackendsTests: XCTestCase {
    func testDisplayServicesResolves() {
        XCTAssertTrue(DisplayServicesBrightness().isAvailable)
    }

    func testNightShiftStatusReadsSanely() throws {
        let ns = try XCTUnwrap(CoreBrightnessNightShift())
        let s = ns.status()
        XCTAssertTrue(s.available, "this Mac supports Night Shift")
        XCTAssertTrue((0...1).contains(s.strength))
    }
}
