import XCTest
@testable import MonitorLizardCore

final class IORegistryScannerTests: XCTestCase {
    func testFindsFramebuffersAndTheExternalService() throws {
        let fbs = IORegistryScanner.framebuffers()
        XCTAssertTrue(fbs.contains { $0.name.hasPrefix("disp") }, "no framebuffers found: \(fbs)")
        let services = IORegistryScanner.externalAVServices()
        for s in services { XCTAssertNotNil(DisplayMatcher.framebufferName(inAVServicePath: s.path), s.path) }
    }
}
