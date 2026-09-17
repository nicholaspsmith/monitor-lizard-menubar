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
