// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// One I²C endpoint at the monitor's DDC address. The real one wraps an
/// `IOAVService`; tests script replies.
public protocol DDCTransport: AnyObject {
    func write(_ bytes: [UInt8]) throws
    func read(count: Int) throws -> [UInt8]
}

public enum DDCError: Error, Equatable {
    case io(Int32)
    case badReply
    case unavailable
}

/// Serialises every transaction on one display's bus, spaces them out, and
/// retries reads. Writes are latest-wins: a slider drag can post values far
/// faster than the bus accepts them, so a pending write is replaced rather than
/// queued, and each write is confirmed by the read that follows it.
public final class DDCService {
    public static let attempts = 3
    public static let settleMicroseconds: UInt32 = 50_000

    private let transport: DDCTransport
    private let sleep: (UInt32) -> Void
    private let queue: DispatchQueue
    private var pending: [VCPCode: (value: UInt16, completions: [(Result<VCPValue, DDCError>) -> Void])] = [:]
    private let lock = NSLock()

    public init(transport: DDCTransport,
                sleep: @escaping (UInt32) -> Void = { usleep($0) },
                queue: DispatchQueue = DispatchQueue(label: "com.nicholaspsmith.MonitorLizard.ddc")) {
        self.transport = transport
        self.sleep = sleep
        self.queue = queue
    }

    public func read(_ code: VCPCode, completion: @escaping (Result<VCPValue, DDCError>) -> Void) {
        queue.async { completion(self.readNow(code)) }
    }

    public func write(_ code: VCPCode, value: UInt16, completion: @escaping (Result<VCPValue, DDCError>) -> Void) {
        lock.lock()
        if var entry = pending[code] {
            entry.value = value
            entry.completions.append(completion)
            pending[code] = entry
            lock.unlock()
            return                                   // the queued block will pick up the new value
        }
        pending[code] = (value, [completion])
        lock.unlock()
        queue.async {
            self.lock.lock()
            let entry = self.pending.removeValue(forKey: code)
            self.lock.unlock()
            guard let entry else { return }
            let result = self.writeNow(code, value: entry.value)
            entry.completions.forEach { $0(result) }
        }
    }

    // MARK: - On the queue

    private func readNow(_ code: VCPCode) -> Result<VCPValue, DDCError> {
        var last: DDCError = .badReply
        for attempt in 1...Self.attempts {
            do {
                try transport.write(VCP.readRequest(code))
                sleep(Self.settleMicroseconds)
                let reply = try transport.read(count: VCP.replyLength)
                sleep(Self.settleMicroseconds)
                if let value = VCP.parseReply(reply, expecting: code) { return .success(value) }
                last = .badReply
                Log.ddc.debug("bad reply for \(code.rawValue, format: .hex) attempt \(attempt)")
            } catch let e as DDCError {
                last = e
                Log.ddc.debug("i/o error \(String(describing: e), privacy: .public) attempt \(attempt)")
                sleep(Self.settleMicroseconds)
            } catch {
                last = .io(-1)
                sleep(Self.settleMicroseconds)
            }
        }
        return .failure(last)
    }

    private func writeNow(_ code: VCPCode, value: UInt16) -> Result<VCPValue, DDCError> {
        do {
            try transport.write(VCP.writeRequest(code, value: value))
        } catch let e as DDCError {
            sleep(Self.settleMicroseconds)
            return .failure(e)
        } catch {
            sleep(Self.settleMicroseconds)
            return .failure(.io(-1))
        }
        sleep(Self.settleMicroseconds)
        return readNow(code)
    }
}
