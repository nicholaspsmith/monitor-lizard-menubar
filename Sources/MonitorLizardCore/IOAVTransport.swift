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
        guard let write = IOAVSymbols.write else { throw DDCError.unavailable }
        let rc = bytes.withUnsafeBytes { write(service, VCP.chipAddress, VCP.sourceAddress, $0.baseAddress!, UInt32(bytes.count)) }
        if rc != KERN_SUCCESS { throw DDCError.io(rc) }
    }

    public func read(count: Int) throws -> [UInt8] {
        guard let read = IOAVSymbols.read else { throw DDCError.unavailable }
        var buffer = [UInt8](repeating: 0, count: count)
        let rc = buffer.withUnsafeMutableBytes { read(service, VCP.chipAddress, VCP.sourceAddress, $0.baseAddress!, UInt32(count)) }
        if rc != KERN_SUCCESS { throw DDCError.io(rc) }
        return buffer
    }
}
