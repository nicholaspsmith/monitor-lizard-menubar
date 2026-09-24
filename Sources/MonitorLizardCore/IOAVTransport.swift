// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation
import IOKit

/// The three private IOKit entry points DDC needs on Apple Silicon. Resolved
/// with dlsym so a future macOS that drops one degrades to "No DDC control"
/// instead of a launch-time link failure.
public enum IOAVSymbols {
    typealias CreateWithService = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    typealias ReadI2C = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
    typealias WriteI2C = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeRawPointer, UInt32) -> IOReturn

    static let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
    static let create: CreateWithService? = symbol("IOAVServiceCreateWithService")
    static let read: ReadI2C? = symbol("IOAVServiceReadI2C")
    static let write: WriteI2C? = symbol("IOAVServiceWriteI2C")

    public static var isAvailable: Bool { create != nil && read != nil && write != nil }

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }
}

/// A `DDCTransport` bound to one `DCPAVServiceProxy` (one external display).
public final class IOAVTransport: DDCTransport {
    private let service: CFTypeRef

    public init?(service ioService: io_service_t) {
        guard let create = IOAVSymbols.create,
              let ref = create(kCFAllocatorDefault, ioService)?.takeRetainedValue() else { return nil }
        service = ref
    }

    public func write(_ bytes: [UInt8]) throws {
        try Self.validate(byteCount: bytes.count)
        guard let writeFn = IOAVSymbols.write else { throw DDCError.unavailable }
        let rc = bytes.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return kIOReturnBadArgument }
            return writeFn(service, VCP.chipAddress, VCP.sourceAddress, base, UInt32(bytes.count))
        }
        if rc != kIOReturnSuccess { throw DDCError.io(rc) }
    }

    public func read(count: Int) throws -> [UInt8] {
        try Self.validate(byteCount: count)
        guard let readFn = IOAVSymbols.read else { throw DDCError.unavailable }
        var buffer = [UInt8](repeating: 0, count: count)
        let rc = buffer.withUnsafeMutableBytes { mutableBuffer in
            guard let base = mutableBuffer.baseAddress else { return kIOReturnBadArgument }
            return readFn(service, VCP.chipAddress, VCP.sourceAddress, base, UInt32(count))
        }
        if rc != kIOReturnSuccess { throw DDCError.io(rc) }
        return buffer
    }

    static func validate(byteCount: Int) throws {
        guard byteCount > 0 else { throw DDCError.io(kIOReturnBadArgument) }
    }
}
