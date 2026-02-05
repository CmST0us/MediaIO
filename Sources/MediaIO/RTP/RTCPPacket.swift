import Foundation

/// RTCP Packet Types
/// - seealso: RFC 3550 Section 6
public enum RTCPPacketType: UInt8 {
    case senderReport = 200      // SR
    case receiverReport = 201    // RR
    case sourceDescription = 202 // SDES
    case goodbye = 203           // BYE
    case applicationDefined = 204 // APP
}

/// RTCP common header
public struct RTCPHeader {
    public var version: UInt8 = kRTPVersion
    public var padding: Bool = false
    public var count: UInt8 = 0 // Reception report count or subtype
    public var packetType: RTCPPacketType = .senderReport
    public var length: UInt16 = 0 // In 32-bit words minus one

    public init() {}

    public func encode() -> Data {
        let ba = ByteArray()
        var byte0: UInt8 = (version & 0x03) << 6
        if padding { byte0 |= 0x20 }
        byte0 |= (count & 0x1F)
        ba.writeUInt8(byte0)
        ba.writeUInt8(packetType.rawValue)
        ba.writeUInt16(length)
        return ba.data
    }

    public static func decode(from data: Data) throws -> RTCPHeader {
        guard data.count >= 4 else { throw RTPError.insufficientData }
        let ba = ByteArray(data: data)
        let byte0 = try ba.readUInt8()
        var header = RTCPHeader()
        header.version = (byte0 >> 6) & 0x03
        header.padding = (byte0 & 0x20) != 0
        header.count = byte0 & 0x1F
        guard let pt = RTCPPacketType(rawValue: try ba.readUInt8()) else {
            throw RTPError.invalidPacket
        }
        header.packetType = pt
        header.length = try ba.readUInt16()
        return header
    }
}

/// RTCP Sender Report
/// - seealso: RFC 3550 Section 6.4.1
public struct RTCPSenderReport {
    public var ssrc: UInt32 = 0
    public var ntpTimestamp: UInt64 = 0
    public var rtpTimestamp: UInt32 = 0
    public var senderPacketCount: UInt32 = 0
    public var senderOctetCount: UInt32 = 0
    public var reportBlocks: [RTCPReportBlock] = []

    public init() {}

    public func encode() -> Data {
        let ba = ByteArray()
        // Header
        var header = RTCPHeader()
        header.packetType = .senderReport
        header.count = UInt8(reportBlocks.count)

        let bodyBa = ByteArray()
        bodyBa.writeUInt32(ssrc)
        bodyBa.writeUInt64(ntpTimestamp)
        bodyBa.writeUInt32(rtpTimestamp)
        bodyBa.writeUInt32(senderPacketCount)
        bodyBa.writeUInt32(senderOctetCount)
        for block in reportBlocks {
            bodyBa.writeBytes(block.encode())
        }

        header.length = UInt16(bodyBa.length / 4)
        ba.writeBytes(header.encode())
        ba.writeBytes(bodyBa.data)
        return ba.data
    }
}

/// RTCP Receiver Report
/// - seealso: RFC 3550 Section 6.4.2
public struct RTCPReceiverReport {
    public var ssrc: UInt32 = 0
    public var reportBlocks: [RTCPReportBlock] = []

    public init() {}

    public func encode() -> Data {
        let ba = ByteArray()
        var header = RTCPHeader()
        header.packetType = .receiverReport
        header.count = UInt8(reportBlocks.count)

        let bodyBa = ByteArray()
        bodyBa.writeUInt32(ssrc)
        for block in reportBlocks {
            bodyBa.writeBytes(block.encode())
        }

        header.length = UInt16(bodyBa.length / 4)
        ba.writeBytes(header.encode())
        ba.writeBytes(bodyBa.data)
        return ba.data
    }
}

/// RTCP Report Block (24 bytes)
public struct RTCPReportBlock {
    public var ssrc: UInt32 = 0
    public var fractionLost: UInt8 = 0
    public var cumulativePacketsLost: UInt32 = 0 // 24-bit
    public var extendedHighestSequence: UInt32 = 0
    public var interarrivalJitter: UInt32 = 0
    public var lastSR: UInt32 = 0
    public var delaySinceLastSR: UInt32 = 0

    public init() {}

    public func encode() -> Data {
        let ba = ByteArray()
        ba.writeUInt32(ssrc)
        ba.writeUInt8(fractionLost)
        ba.writeUInt24(cumulativePacketsLost & 0xFFFFFF)
        ba.writeUInt32(extendedHighestSequence)
        ba.writeUInt32(interarrivalJitter)
        ba.writeUInt32(lastSR)
        ba.writeUInt32(delaySinceLastSR)
        return ba.data
    }

    public static func decode(from ba: ByteArray) throws -> RTCPReportBlock {
        var block = RTCPReportBlock()
        block.ssrc = try ba.readUInt32()
        block.fractionLost = try ba.readUInt8()
        block.cumulativePacketsLost = try ba.readUInt24()
        block.extendedHighestSequence = try ba.readUInt32()
        block.interarrivalJitter = try ba.readUInt32()
        block.lastSR = try ba.readUInt32()
        block.delaySinceLastSR = try ba.readUInt32()
        return block
    }
}
