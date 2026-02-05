import Foundation

/// RTP Protocol Version
let kRTPVersion: UInt8 = 2

/// Common RTP Payload Types
/// - seealso: RFC 3551
enum RTPPayloadType: UInt8 {
    case pcmu = 0
    case pcma = 8
    case g722 = 9
    case l16Stereo = 10
    case l16Mono = 11
    case mpa = 14  // MPEG Audio (MP3)
    case mpv = 32  // MPEG Video
    case mp2t = 33 // MPEG-2 TS
    case h261 = 31
    case h263 = 34
    // Dynamic payload types: 96-127
    case dynamic96 = 96
    case dynamic97 = 97
    case dynamic98 = 98
}

/// RTP Fixed Header (12 bytes minimum)
/// - seealso: RFC 3550 Section 5.1
///
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |V=2|P|X|  CC   |M|     PT      |       sequence number         |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                           timestamp                           |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |           synchronization source (SSRC) identifier            |
/// +=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
/// |            contributing source (CSRC) identifiers             |
/// |                             ....                              |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
struct RTPHeader {
    var version: UInt8 = kRTPVersion
    var padding: Bool = false
    var hasExtension: Bool = false
    var csrcCount: UInt8 = 0
    var marker: Bool = false
    var payloadType: UInt8 = 0
    var sequenceNumber: UInt16 = 0
    var timestamp: UInt32 = 0
    var ssrc: UInt32 = 0
    var csrc: [UInt32] = []

    static let fixedSize: Int = 12

    func encode() -> Data {
        let ba = ByteArray()
        var byte0: UInt8 = (version & 0x03) << 6
        if padding { byte0 |= 0x20 }
        if hasExtension { byte0 |= 0x10 }
        byte0 |= (csrcCount & 0x0F)
        ba.writeUInt8(byte0)

        var byte1: UInt8 = payloadType & 0x7F
        if marker { byte1 |= 0x80 }
        ba.writeUInt8(byte1)

        ba.writeUInt16(sequenceNumber)
        ba.writeUInt32(timestamp)
        ba.writeUInt32(ssrc)

        for id in csrc.prefix(Int(csrcCount)) {
            ba.writeUInt32(id)
        }
        return ba.data
    }

    static func decode(from data: Data) throws -> (header: RTPHeader, bytesRead: Int) {
        guard data.count >= RTPHeader.fixedSize else { throw RTPError.insufficientData }
        let ba = ByteArray(data: data)

        let byte0 = try ba.readUInt8()
        let byte1 = try ba.readUInt8()

        var header = RTPHeader()
        header.version = (byte0 >> 6) & 0x03
        guard header.version == kRTPVersion else { throw RTPError.invalidVersion }
        header.padding = (byte0 & 0x20) != 0
        header.hasExtension = (byte0 & 0x10) != 0
        header.csrcCount = byte0 & 0x0F
        header.marker = (byte1 & 0x80) != 0
        header.payloadType = byte1 & 0x7F
        header.sequenceNumber = try ba.readUInt16()
        header.timestamp = try ba.readUInt32()
        header.ssrc = try ba.readUInt32()

        var bytesRead = RTPHeader.fixedSize
        let csrcBytes = Int(header.csrcCount) * 4
        guard data.count >= bytesRead + csrcBytes else { throw RTPError.insufficientData }
        for _ in 0..<header.csrcCount {
            header.csrc.append(try ba.readUInt32())
        }
        bytesRead += csrcBytes

        return (header, bytesRead)
    }
}

/// RTP Header Extension
/// - seealso: RFC 3550 Section 5.3.1
struct RTPHeaderExtension {
    var profile: UInt16 = 0
    var data: Data = Data()

    func encode() -> Data {
        let ba = ByteArray()
        ba.writeUInt16(profile)
        let lengthInWords = UInt16((data.count + 3) / 4)
        ba.writeUInt16(lengthInWords)
        ba.writeBytes(data)
        // Pad to 4-byte boundary
        let padding = (4 - (data.count % 4)) % 4
        if padding > 0 {
            ba.writeBytes(Data(repeating: 0, count: padding))
        }
        return ba.data
    }

    static func decode(from data: Data) throws -> (ext: RTPHeaderExtension, bytesRead: Int) {
        guard data.count >= 4 else { throw RTPError.insufficientData }
        let ba = ByteArray(data: data)
        var ext = RTPHeaderExtension()
        ext.profile = try ba.readUInt16()
        let lengthInWords = try ba.readUInt16()
        let length = Int(lengthInWords) * 4
        guard ba.bytesAvailable >= length else { throw RTPError.insufficientData }
        ext.data = try ba.readBytes(length)
        return (ext, 4 + length)
    }
}

/// A complete RTP packet
struct RTPPacket {
    var header: RTPHeader = RTPHeader()
    var headerExtension: RTPHeaderExtension? = nil
    var payload: Data = Data()

    func encode() -> Data {
        var result = header.encode()
        if let ext = headerExtension {
            result.append(ext.encode())
        }
        result.append(payload)
        return result
    }

    static func decode(from data: Data) throws -> RTPPacket {
        let (header, headerBytes) = try RTPHeader.decode(from: data)
        var offset = headerBytes
        var packet = RTPPacket()
        packet.header = header

        if header.hasExtension {
            let remaining = Data(data[offset...])
            let (ext, extBytes) = try RTPHeaderExtension.decode(from: remaining)
            packet.headerExtension = ext
            offset += extBytes
        }

        var payloadEnd = data.count
        if header.padding && data.count > offset {
            let paddingLength = Int(data[data.count - 1])
            payloadEnd -= paddingLength
        }

        guard offset <= payloadEnd else { throw RTPError.insufficientData }
        packet.payload = Data(data[offset..<payloadEnd])
        return packet
    }
}

/// RTP packet builder for sending
final class RTPPacketBuilder {
    private var sequenceNumber: UInt16
    let ssrc: UInt32
    let payloadType: UInt8

    init(ssrc: UInt32, payloadType: UInt8, initialSequence: UInt16 = 0) {
        self.ssrc = ssrc
        self.payloadType = payloadType
        self.sequenceNumber = initialSequence
    }

    func buildPacket(timestamp: UInt32, payload: Data, marker: Bool = false) -> RTPPacket {
        var packet = RTPPacket()
        packet.header.ssrc = ssrc
        packet.header.payloadType = payloadType
        packet.header.sequenceNumber = sequenceNumber
        packet.header.timestamp = timestamp
        packet.header.marker = marker
        packet.payload = payload
        sequenceNumber &+= 1
        return packet
    }
}

enum RTPError: Error {
    case insufficientData
    case invalidVersion
    case invalidPacket
}
