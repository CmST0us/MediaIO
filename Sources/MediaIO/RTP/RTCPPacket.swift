import Foundation

/// RTCP Packet Types
/// - seealso: RFC 3550 Section 6
enum RTCPPacketType: UInt8 {
    case senderReport = 200      // SR
    case receiverReport = 201    // RR
    case sourceDescription = 202 // SDES
    case goodbye = 203           // BYE
    case applicationDefined = 204 // APP
}

/// RTCP common header
struct RTCPHeader {
    var version: UInt8 = kRTPVersion
    var padding: Bool = false
    var count: UInt8 = 0 // Reception report count or subtype
    var packetType: RTCPPacketType = .senderReport
    var length: UInt16 = 0 // In 32-bit words minus one

    func encode() -> Data {
        let ba = ByteArray()
        var byte0: UInt8 = (version & 0x03) << 6
        if padding { byte0 |= 0x20 }
        byte0 |= (count & 0x1F)
        ba.writeUInt8(byte0)
        ba.writeUInt8(packetType.rawValue)
        ba.writeUInt16(length)
        return ba.data
    }

    static func decode(from data: Data) throws -> RTCPHeader {
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
struct RTCPSenderReport {
    var ssrc: UInt32 = 0
    var ntpTimestamp: UInt64 = 0
    var rtpTimestamp: UInt32 = 0
    var senderPacketCount: UInt32 = 0
    var senderOctetCount: UInt32 = 0
    var reportBlocks: [RTCPReportBlock] = []

    func encode() -> Data {
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
struct RTCPReceiverReport {
    var ssrc: UInt32 = 0
    var reportBlocks: [RTCPReportBlock] = []

    func encode() -> Data {
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
struct RTCPReportBlock {
    var ssrc: UInt32 = 0
    var fractionLost: UInt8 = 0
    var cumulativePacketsLost: UInt32 = 0 // 24-bit
    var extendedHighestSequence: UInt32 = 0
    var interarrivalJitter: UInt32 = 0
    var lastSR: UInt32 = 0
    var delaySinceLastSR: UInt32 = 0

    func encode() -> Data {
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

    static func decode(from ba: ByteArray) throws -> RTCPReportBlock {
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
