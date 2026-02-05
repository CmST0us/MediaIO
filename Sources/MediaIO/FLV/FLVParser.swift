import Foundation

/// FLV File Header
/// - seealso: FLV specification E.2
struct FLVHeader {
    static let size: Int = 9
    static let signature: [UInt8] = [0x46, 0x4C, 0x56] // "FLV"

    var version: UInt8 = 1
    var hasAudio: Bool = false
    var hasVideo: Bool = false
    var dataOffset: UInt32 = 9

    func encode() -> Data {
        var flags: UInt8 = 0
        if hasAudio { flags |= 0x04 }
        if hasVideo { flags |= 0x01 }
        let ba = ByteArray()
            .writeBytes(Data(FLVHeader.signature))
            .writeUInt8(version)
            .writeUInt8(flags)
            .writeUInt32(dataOffset)
        return ba.data
    }

    static func decode(from data: Data) throws -> FLVHeader {
        guard data.count >= FLVHeader.size else { throw FLVError.insufficientData }
        let ba = ByteArray(data: data)
        let sig = try ba.readBytes(3)
        guard sig.bytes == FLVHeader.signature else { throw FLVError.invalidSignature }
        var header = FLVHeader()
        header.version = try ba.readUInt8()
        let flags = try ba.readUInt8()
        header.hasAudio = (flags & 0x04) != 0
        header.hasVideo = (flags & 0x01) != 0
        header.dataOffset = try ba.readUInt32()
        return header
    }
}

/// FLV Tag Type
enum FLVTagType: UInt8 {
    case audio = 8
    case video = 9
    case scriptData = 18
}

/// FLV Audio Codec
enum FLVAudioCodec: UInt8 {
    case pcmPlatformEndian = 0
    case adpcm = 1
    case mp3 = 2
    case pcmLittleEndian = 3
    case nellymoser16kHz = 4
    case nellymoser8kHz = 5
    case nellymoser = 6
    case g711ALaw = 7
    case g711MuLaw = 8
    case aac = 10
    case speex = 11
    case mp3_8kHz = 14
    case deviceSpecific = 15
}

/// FLV Audio Sample Rate
enum FLVAudioSampleRate: UInt8 {
    case rate5_5kHz = 0
    case rate11kHz = 1
    case rate22kHz = 2
    case rate44kHz = 3
}

/// FLV Video Codec
enum FLVVideoCodec: UInt8 {
    case sorensonH263 = 2
    case screenVideo = 3
    case on2VP6 = 4
    case on2VP6Alpha = 5
    case screenVideo2 = 6
    case avc = 7  // H.264
    case hevc = 12 // H.265
    case av1 = 13
}

/// FLV Video Frame Type
enum FLVVideoFrameType: UInt8 {
    case keyframe = 1
    case interFrame = 2
    case disposableInterFrame = 3
    case generatedKeyframe = 4
    case videoInfoCommand = 5
}

/// FLV AAC Packet Type
enum FLVAACPacketType: UInt8 {
    case sequenceHeader = 0
    case raw = 1
}

/// FLV AVC Packet Type
enum FLVAVCPacketType: UInt8 {
    case sequenceHeader = 0
    case nalu = 1
    case endOfSequence = 2
}

/// FLV Tag
struct FLVTag {
    static let headerSize: Int = 11

    var tagType: FLVTagType = .video
    var dataSize: UInt32 = 0
    /// Timestamp in milliseconds
    var timestamp: UInt32 = 0
    var streamID: UInt32 = 0
    var data: Data = Data()

    func encode() -> Data {
        let ba = ByteArray()
        ba.writeUInt8(tagType.rawValue)
        ba.writeUInt24(UInt32(data.count))
        // Timestamp: lower 24 bits + upper 8 bits extension
        ba.writeUInt24(timestamp & 0xFFFFFF)
        ba.writeUInt8(UInt8((timestamp >> 24) & 0xFF))
        ba.writeUInt24(streamID)
        ba.writeBytes(data)
        return ba.data
    }

    static func decode(from data: Data, position: Int = 0) throws -> (tag: FLVTag, bytesRead: Int) {
        guard data.count - position >= FLVTag.headerSize else { throw FLVError.insufficientData }
        let ba = ByteArray(data: Data(data[position...]))
        var tag = FLVTag()
        guard let type = FLVTagType(rawValue: try ba.readUInt8()) else {
            throw FLVError.invalidTagType
        }
        tag.tagType = type
        tag.dataSize = try ba.readUInt24()
        let tsLow = try ba.readUInt24()
        let tsHigh = UInt32(try ba.readUInt8())
        tag.timestamp = tsLow | (tsHigh << 24)
        tag.streamID = try ba.readUInt24()
        guard ba.bytesAvailable >= Int(tag.dataSize) else { throw FLVError.insufficientData }
        tag.data = try ba.readBytes(Int(tag.dataSize))
        return (tag, FLVTag.headerSize + Int(tag.dataSize))
    }
}

/// FLV audio tag header parser
struct FLVAudioTagHeader {
    var codec: FLVAudioCodec = .aac
    var sampleRate: FLVAudioSampleRate = .rate44kHz
    var sampleSize: UInt8 = 1 // 0=8-bit, 1=16-bit
    var channels: UInt8 = 1   // 0=mono, 1=stereo
    var aacPacketType: FLVAACPacketType = .raw

    static func decode(from data: Data) throws -> FLVAudioTagHeader {
        guard !data.isEmpty else { throw FLVError.insufficientData }
        var header = FLVAudioTagHeader()
        let byte = data[0]
        header.codec = FLVAudioCodec(rawValue: byte >> 4) ?? .aac
        header.sampleRate = FLVAudioSampleRate(rawValue: (byte >> 2) & 0x03) ?? .rate44kHz
        header.sampleSize = (byte >> 1) & 0x01
        header.channels = byte & 0x01
        if header.codec == .aac && data.count >= 2 {
            header.aacPacketType = FLVAACPacketType(rawValue: data[1]) ?? .raw
        }
        return header
    }
}

/// FLV video tag header parser
struct FLVVideoTagHeader {
    var frameType: FLVVideoFrameType = .keyframe
    var codec: FLVVideoCodec = .avc
    var avcPacketType: FLVAVCPacketType = .nalu
    var compositionTime: Int32 = 0

    static func decode(from data: Data) throws -> FLVVideoTagHeader {
        guard !data.isEmpty else { throw FLVError.insufficientData }
        var header = FLVVideoTagHeader()
        let byte = data[0]
        header.frameType = FLVVideoFrameType(rawValue: byte >> 4) ?? .keyframe
        header.codec = FLVVideoCodec(rawValue: byte & 0x0F) ?? .avc
        if (header.codec == .avc || header.codec == .hevc) && data.count >= 5 {
            header.avcPacketType = FLVAVCPacketType(rawValue: data[1]) ?? .nalu
            let ct = UInt32(data[2]) << 16 | UInt32(data[3]) << 8 | UInt32(data[4])
            // Sign-extend 24-bit to 32-bit
            header.compositionTime = ct & 0x800000 != 0 ? Int32(ct) - 0x1000000 : Int32(ct)
        }
        return header
    }
}

/// FLV file reader
final class FLVReader {
    private let data: Data
    private(set) var header: FLVHeader?
    private var position: Int = 0

    init(data: Data) {
        self.data = data
    }

    func readHeader() throws -> FLVHeader {
        let h = try FLVHeader.decode(from: data)
        header = h
        position = Int(h.dataOffset)
        return h
    }

    /// Read next tag, skipping the previous tag size field
    func readTag() throws -> FLVTag? {
        // Skip previous tag size (4 bytes)
        guard position + 4 <= data.count else { return nil }
        position += 4
        guard position < data.count else { return nil }
        let (tag, bytesRead) = try FLVTag.decode(from: data, position: position)
        position += bytesRead
        return tag
    }
}

/// FLV file writer
final class FLVWriter {
    private(set) var data = Data()

    func writeHeader(hasAudio: Bool, hasVideo: Bool) {
        var header = FLVHeader()
        header.hasAudio = hasAudio
        header.hasVideo = hasVideo
        data.append(header.encode())
        // Previous tag size 0 for first tag
        data.append(ByteArray().writeUInt32(0).data)
    }

    func writeTag(_ tag: FLVTag) {
        let tagData = tag.encode()
        data.append(tagData)
        // Previous tag size
        data.append(ByteArray().writeUInt32(UInt32(tagData.count)).data)
    }
}

enum FLVError: Error {
    case insufficientData
    case invalidSignature
    case invalidTagType
}
