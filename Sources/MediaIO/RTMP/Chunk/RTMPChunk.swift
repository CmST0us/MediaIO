import Foundation

/// RTMP Chunk Basic Header format type (fmt)
/// - seealso: RTMP specification 5.3.1.1
public enum RTMPChunkHeaderType: UInt8 {
    /// Type 0: Full header (11 bytes)
    case full = 0x00
    /// Type 1: 7-byte header
    case sevenBytes = 0x01
    /// Type 2: 3-byte header
    case threeBytes = 0x02
    /// Type 3: No message header
    case continuation = 0x03
}

/// Basic header of an RTMP chunk
/// - seealso: RTMP specification 5.3.1.1
public struct RTMPChunkBasicHeader {
    public var type: RTMPChunkHeaderType
    public var chunkStreamID: UInt16

    public init(type: RTMPChunkHeaderType, chunkStreamID: UInt16) {
        self.type = type
        self.chunkStreamID = chunkStreamID
    }

    public func encode() -> Data {
        let fmt = type.rawValue << 6
        if chunkStreamID >= 2 && chunkStreamID <= 63 {
            return Data([fmt | UInt8(chunkStreamID)])
        } else if chunkStreamID >= 64 && chunkStreamID <= 319 {
            return Data([fmt | 0x00, UInt8(chunkStreamID - 64)])
        } else {
            let csid = chunkStreamID - 64
            return Data([fmt | 0x01, UInt8(csid & 0xFF), UInt8(csid >> 8)])
        }
    }

    public static func decode(from data: Data, position: Int) throws -> (header: RTMPChunkBasicHeader, bytesRead: Int) {
        guard position < data.count else { throw ByteArray.Error.eof }
        let byte = data[position]
        let fmt = byte >> 6
        let csid = byte & 0x3F
        guard let headerType = RTMPChunkHeaderType(rawValue: fmt) else {
            throw ByteArray.Error.parse
        }
        switch csid {
        case 0:
            guard position + 1 < data.count else { throw ByteArray.Error.eof }
            return (RTMPChunkBasicHeader(type: headerType, chunkStreamID: UInt16(data[position + 1]) + 64), 2)
        case 1:
            guard position + 2 < data.count else { throw ByteArray.Error.eof }
            let id = (UInt16(data[position + 1]) | (UInt16(data[position + 2]) << 8)) + 64
            return (RTMPChunkBasicHeader(type: headerType, chunkStreamID: id), 3)
        default:
            return (RTMPChunkBasicHeader(type: headerType, chunkStreamID: UInt16(csid)), 1)
        }
    }
}

/// Message header of an RTMP chunk
/// - seealso: RTMP specification 5.3.1.2
public struct RTMPChunkMessageHeader {
    public var timestamp: UInt32 = 0
    public var messageLength: UInt32 = 0
    public var messageTypeID: UInt8 = 0
    public var messageStreamID: UInt32 = 0

    public var hasExtendedTimestamp: Bool {
        timestamp >= 0xFFFFFF
    }

    public init() {}
}

/// An RTMP chunk
/// - seealso: RTMP specification 5.3
public struct RTMPChunk {
    public static let defaultChunkSize: Int = 128
    public static let maxChunkSize: Int = 65536

    public var basicHeader: RTMPChunkBasicHeader
    public var messageHeader: RTMPChunkMessageHeader
    public var data: Data

    /// Encode a message into chunked data
    public static func encode(
        message: RTMPMessage,
        chunkStreamID: UInt16,
        messageStreamID: UInt32,
        chunkSize: Int = RTMPChunk.defaultChunkSize
    ) -> Data {
        var result = Data()
        let payload = message.encode()
        let totalLength = payload.count
        var offset = 0
        var isFirst = true

        while offset < totalLength {
            let size = min(totalLength - offset, chunkSize)

            if isFirst {
                let bh = RTMPChunkBasicHeader(type: .full, chunkStreamID: chunkStreamID)
                result.append(bh.encode())
                let timestamp = message.timestamp
                let tsValue: UInt32 = timestamp >= 0xFFFFFF ? 0xFFFFFF : timestamp
                result.append(contentsOf: [
                    UInt8((tsValue >> 16) & 0xFF),
                    UInt8((tsValue >> 8) & 0xFF),
                    UInt8(tsValue & 0xFF)
                ])
                let msgLen = UInt32(totalLength)
                result.append(contentsOf: [
                    UInt8((msgLen >> 16) & 0xFF),
                    UInt8((msgLen >> 8) & 0xFF),
                    UInt8(msgLen & 0xFF)
                ])
                result.append(message.typeID)
                result.append(contentsOf: [
                    UInt8(messageStreamID & 0xFF),
                    UInt8((messageStreamID >> 8) & 0xFF),
                    UInt8((messageStreamID >> 16) & 0xFF),
                    UInt8((messageStreamID >> 24) & 0xFF)
                ])
                if timestamp >= 0xFFFFFF {
                    result.append(contentsOf: [
                        UInt8((timestamp >> 24) & 0xFF),
                        UInt8((timestamp >> 16) & 0xFF),
                        UInt8((timestamp >> 8) & 0xFF),
                        UInt8(timestamp & 0xFF)
                    ])
                }
                isFirst = false
            } else {
                let bh = RTMPChunkBasicHeader(type: .continuation, chunkStreamID: chunkStreamID)
                result.append(bh.encode())
                if message.timestamp >= 0xFFFFFF {
                    let ts = message.timestamp
                    result.append(contentsOf: [
                        UInt8((ts >> 24) & 0xFF),
                        UInt8((ts >> 16) & 0xFF),
                        UInt8((ts >> 8) & 0xFF),
                        UInt8(ts & 0xFF)
                    ])
                }
            }
            result.append(payload[offset..<offset + size])
            offset += size
        }
        return result
    }
}

/// Reassembles RTMP chunks into complete messages
public final class RTMPChunkDecoder {
    private var chunkSize: Int = RTMPChunk.defaultChunkSize
    private var lastHeaders: [UInt16: RTMPChunkMessageHeader] = [:]
    private var chunkBuffers: [UInt16: Data] = [:]

    public init() {}

    public func setChunkSize(_ size: Int) {
        chunkSize = min(size, RTMPChunk.maxChunkSize)
    }

    public func decode(from data: Data) throws -> (messages: [(chunkStreamID: UInt16, header: RTMPChunkMessageHeader, payload: Data)], bytesConsumed: Int) {
        var messages: [(UInt16, RTMPChunkMessageHeader, Data)] = []
        var position = 0

        while position < data.count {
            let startPosition = position
            guard let (basicHeader, basicHeaderSize) = try? RTMPChunkBasicHeader.decode(from: data, position: position) else { break }
            guard position + basicHeaderSize <= data.count else { break }

            let csid = basicHeader.chunkStreamID
            var offset = position + basicHeaderSize
            var header = lastHeaders[csid] ?? RTMPChunkMessageHeader()

            switch basicHeader.type {
            case .full:
                guard offset + 11 <= data.count else { return (messages, startPosition) }
                header.timestamp = UInt32(data[offset]) << 16 | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2])
                header.messageLength = UInt32(data[offset + 3]) << 16 | UInt32(data[offset + 4]) << 8 | UInt32(data[offset + 5])
                header.messageTypeID = data[offset + 6]
                header.messageStreamID = UInt32(data[offset + 7])
                    | UInt32(data[offset + 8]) << 8
                    | UInt32(data[offset + 9]) << 16
                    | UInt32(data[offset + 10]) << 24
                offset += 11
                chunkBuffers[csid] = nil
            case .sevenBytes:
                guard offset + 7 <= data.count else { return (messages, startPosition) }
                header.timestamp = UInt32(data[offset]) << 16 | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2])
                header.messageLength = UInt32(data[offset + 3]) << 16 | UInt32(data[offset + 4]) << 8 | UInt32(data[offset + 5])
                header.messageTypeID = data[offset + 6]
                offset += 7
                chunkBuffers[csid] = nil
            case .threeBytes:
                guard offset + 3 <= data.count else { return (messages, startPosition) }
                header.timestamp = UInt32(data[offset]) << 16 | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2])
                offset += 3
            case .continuation:
                break
            }

            if header.timestamp == 0xFFFFFF {
                guard offset + 4 <= data.count else { return (messages, startPosition) }
                header.timestamp = UInt32(data[offset]) << 24
                    | UInt32(data[offset + 1]) << 16
                    | UInt32(data[offset + 2]) << 8
                    | UInt32(data[offset + 3])
                offset += 4
            }

            lastHeaders[csid] = header

            let buffer = chunkBuffers[csid] ?? Data()
            let remaining = Int(header.messageLength) - buffer.count
            let toRead = min(remaining, chunkSize)
            guard offset + toRead <= data.count else { return (messages, startPosition) }

            let chunkData = data[offset..<offset + toRead]
            offset += toRead

            let accumulated = buffer + chunkData
            if accumulated.count >= Int(header.messageLength) {
                messages.append((csid, header, accumulated))
                chunkBuffers[csid] = nil
            } else {
                chunkBuffers[csid] = accumulated
            }
            position = offset
        }
        return (messages, position)
    }

    public func reset() {
        lastHeaders.removeAll()
        chunkBuffers.removeAll()
        chunkSize = RTMPChunk.defaultChunkSize
    }
}
