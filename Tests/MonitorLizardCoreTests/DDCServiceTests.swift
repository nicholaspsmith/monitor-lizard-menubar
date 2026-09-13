import XCTest
@testable import MonitorLizardCore

/// A transport that plays back scripted replies and records every write.
final class FakeTransport: DDCTransport {
    var writes: [[UInt8]] = []
    var replies: [[UInt8]] = []          // consumed in order by read(count:)
    var writeError: Int32?               // if set, every write throws
    func write(_ bytes: [UInt8]) throws {
        if let e = writeError { throw DDCError.io(e) }
        writes.append(bytes)
    }
    func read(count: Int) throws -> [UInt8] {
        guard !replies.isEmpty else { throw DDCError.io(-1) }
        return replies.removeFirst()
    }
}

final class DDCServiceTests: XCTestCase {
    static let goodBrightness: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x63, 0xA3, 0x00]
    static let badChecksum: [UInt8]    = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x63, 0xA2, 0x00]

    private func makeService(_ t: FakeTransport) -> (DDCService, DispatchQueue) {
        let q = DispatchQueue(label: "test.ddc")
        return (DDCService(transport: t, sleep: { _ in }, queue: q), q)
    }

    func testReadSendsRequestThenParsesReply() {
        let t = FakeTransport(); t.replies = [Self.goodBrightness]
        let (s, q) = makeService(t)
        let done = expectation(description: "read")
        s.read(.brightness) { result in
            XCTAssertEqual(try? result.get(), VCPValue(current: 99, maximum: 100))
            done.fulfill()
        }
        wait(for: [done], timeout: 1)
        q.sync {}
        XCTAssertEqual(t.writes, [[0x82, 0x01, 0x10, 0xAC]])
    }

    func testReadRetriesOnBadChecksumThenSucceeds() {
        let t = FakeTransport(); t.replies = [Self.badChecksum, Self.badChecksum, Self.goodBrightness]
        let (s, _) = makeService(t)
        let done = expectation(description: "read")
        s.read(.brightness) { result in
            XCTAssertEqual(try? result.get(), VCPValue(current: 99, maximum: 100))
            done.fulfill()
        }
        wait(for: [done], timeout: 1)
        XCTAssertEqual(t.writes.count, 3)
    }

    func testReadGivesUpAfterThreeAttempts() {
        let t = FakeTransport(); t.replies = [Self.badChecksum, Self.badChecksum, Self.badChecksum, Self.goodBrightness]
        let (s, _) = makeService(t)
        let done = expectation(description: "read")
        s.read(.brightness) { result in
            if case .failure(.badReply) = result { done.fulfill() } else { XCTFail("expected badReply, got \(result)") }
        }
        wait(for: [done], timeout: 1)
        XCTAssertEqual(t.writes.count, 3)
    }

    func testWriteSendsPacketThenConfirmsByReading() {
        let t = FakeTransport(); t.replies = [Self.goodBrightness]
        let (s, _) = makeService(t)
        let done = expectation(description: "write")
        s.write(.brightness, value: 99) { result in
            XCTAssertEqual(try? result.get(), VCPValue(current: 99, maximum: 100))
            done.fulfill()
        }
        wait(for: [done], timeout: 1)
        XCTAssertEqual(t.writes.first, [0x84, 0x03, 0x10, 0x00, 0x63, 0xCB])
        XCTAssertEqual(t.writes.last, [0x82, 0x01, 0x10, 0xAC])
    }

    func testBurstOfWritesCollapsesToTheLatestValue() {
        // A slider drag posts many values faster than the bus can take them;
        // only the value current when the queue gets to it must be sent.
        let t = FakeTransport()
        t.replies = [[UInt8]](repeating: Self.goodBrightness, count: 30)
        let q = DispatchQueue(label: "test.ddc")
        let gate = DispatchSemaphore(value: 0)
        let s = DDCService(transport: t, sleep: { _ in }, queue: q)
        q.async { gate.wait() }                     // hold the queue so the burst piles up
        var completions = 0
        let all = expectation(description: "all completions")
        for v in 1...20 {
            s.write(.brightness, value: UInt16(v)) { _ in
                completions += 1
                if completions == 20 { all.fulfill() }
            }
        }
        gate.signal()
        wait(for: [all], timeout: 2)
        let sentWrites = t.writes.filter { $0[0] == 0x84 }
        XCTAssertEqual(sentWrites.count, 1, "only the last queued value is written")
        XCTAssertEqual(sentWrites.first?[4], 20)
    }

    func testIOErrorSurfacesAsIO() {
        let t = FakeTransport(); t.writeError = -536870201
        let (s, _) = makeService(t)
        let done = expectation(description: "read")
        s.read(.brightness) { result in
            if case .failure(.io(-536870201)) = result { done.fulfill() } else { XCTFail("\(result)") }
        }
        wait(for: [done], timeout: 1)
    }
}
