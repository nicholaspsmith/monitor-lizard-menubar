import XCTest
@testable import MonitorLizardCore

final class IOAVTransportTests: XCTestCase {
    func testPrivateIOAVSymbolsResolveOnThisMac() {
        // Apple Silicon only; documents the dependency rather than proving the bus.
        XCTAssertTrue(IOAVSymbols.isAvailable)
    }
}
