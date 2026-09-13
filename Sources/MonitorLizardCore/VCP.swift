import Foundation

/// The two VCP codes the app uses. Nothing else is ever sent to a monitor.
public enum VCPCode: UInt8 {
    case brightness = 0x10
    case contrast = 0x12
}

public struct VCPValue: Equatable {
    public let current: UInt16
    public let maximum: UInt16
    public init(current: UInt16, maximum: UInt16) {
        self.current = current
        self.maximum = maximum
    }
}

/// DDC/CI over I²C as the monitor sees it. Pure byte-level codec; the
/// transport lives elsewhere.
///
/// Requests are sent to chip 0x37 with source address 0x51 and are
/// checksummed as `0x6E ^ 0x51 ^ payload`. A reply is 11 bytes
/// `6E 88 02 rc vcp type maxH maxL curH curL chk` (read as 12) and is
/// checksummed as `0x50 ^ bytes[0…9]`. Both forms were confirmed byte for
/// byte against a Dell U3818DW.
public enum VCP {
    public static let chipAddress: UInt32 = 0x37
    public static let sourceAddress: UInt32 = 0x51
    public static let replyLength = 12

    public static func readRequest(_ code: VCPCode) -> [UInt8] {
        checksummed([0x82, 0x01, code.rawValue])
    }

    public static func writeRequest(_ code: VCPCode, value: UInt16) -> [UInt8] {
        checksummed([0x84, 0x03, code.rawValue, UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    public static func parseReply(_ bytes: [UInt8], expecting code: VCPCode) -> VCPValue? {
        guard bytes.count >= 11, bytes[1] == 0x88, bytes[4] == code.rawValue else { return nil }
        var checksum: UInt8 = 0x50
        for byte in bytes[0..<10] { checksum ^= byte }
        guard checksum == bytes[10] else { return nil }
        let maximum = UInt16(bytes[6]) << 8 | UInt16(bytes[7])
        let current = UInt16(bytes[8]) << 8 | UInt16(bytes[9])
        return VCPValue(current: current, maximum: maximum)
    }

    private static func checksummed(_ payload: [UInt8]) -> [UInt8] {
        var checksum: UInt8 = 0x6E ^ 0x51
        for byte in payload { checksum ^= byte }
        return payload + [checksum]
    }
}
