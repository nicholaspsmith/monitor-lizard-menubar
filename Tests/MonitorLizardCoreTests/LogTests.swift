import XCTest
@testable import MonitorLizardCore

final class LogTests: XCTestCase {
    func testSubsystemIsTheBundleID() {
        XCTAssertEqual(Log.subsystem, "com.nicholaspsmith.MonitorLizard")
    }
}
