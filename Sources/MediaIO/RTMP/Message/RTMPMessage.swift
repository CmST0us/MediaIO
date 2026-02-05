import Foundation

/// RTMP Message Type IDs
/// - seealso: RTMP specification 7.1
enum RTMPMessageType: UInt8 {
    case setChunkSize = 1
    case abort = 2
    case acknowledgement = 3
    case userControl = 4
    case windowAcknowledgementSize = 5
    case setPeerBandwidth = 6
    case audio = 8
    case video = 9
    case dataAMF3 = 15
    case sharedObjectAMF3 = 16
    case commandAMF3 = 17
    case dataAMF0 = 18
    case sharedObjectAMF0 = 19
    case commandAMF0 = 20
    case aggregate = 22
}

/// User Control Event Types
enum RTMPUserControlEventType: UInt16 {
    case streamBegin = 0
    case streamEOF = 1
    case streamDry = 2
    case setBufferLength = 3
    case streamIsRecorded = 4
    case pingRequest = 6
    case pingResponse = 7
}

/// Peer Bandwidth Limit Type
enum RTMPBandwidthLimitType: UInt8 {
    case hard = 0
    case soft = 1
    case dynamic = 2
}

/// Base RTMP Message
class RTMPMessage {
    var typeID: UInt8 { 0 }
    var timestamp: UInt32 = 0
    var streamID: UInt32 = 0
    var payload: Data = Data()

    func encode() -> Data { payload }

    static func create(typeID: UInt8, payload: Data) -> RTMPMessage {
        guard let type = RTMPMessageType(rawValue: typeID) else {
            let msg = RTMPMessage()
            msg.payload = payload
            return msg
        }
        switch type {
        case .setChunkSize:
            return RTMPSetChunkSizeMessage.decode(from: payload)
        case .abort:
            return RTMPAbortMessage.decode(from: payload)
        case .acknowledgement:
            return RTMPAcknowledgementMessage.decode(from: payload)
        case .windowAcknowledgementSize:
            return RTMPWindowAcknowledgementSizeMessage.decode(from: payload)
        case .setPeerBandwidth:
            return RTMPSetPeerBandwidthMessage.decode(from: payload)
        case .userControl:
            return RTMPUserControlMessage.decode(from: payload)
        case .commandAMF0:
            return RTMPCommandMessage.decode(from: payload, isAMF3: false)
        case .commandAMF3:
            return RTMPCommandMessage.decode(from: payload, isAMF3: true)
        case .dataAMF0:
            return RTMPDataMessage.decode(from: payload, isAMF3: false)
        case .dataAMF3:
            return RTMPDataMessage.decode(from: payload, isAMF3: true)
        case .audio:
            let msg = RTMPAudioMessage()
            msg.payload = payload
            return msg
        case .video:
            let msg = RTMPVideoMessage()
            msg.payload = payload
            return msg
        default:
            let msg = RTMPMessage()
            msg.payload = payload
            return msg
        }
    }
}

// MARK: - Protocol Control Messages

/// Set Chunk Size (Type 1)
final class RTMPSetChunkSizeMessage: RTMPMessage {
    override var typeID: UInt8 { RTMPMessageType.setChunkSize.rawValue }
    var chunkSize: UInt32 = UInt32(RTMPChunk.defaultChunkSize)

    override func encode() -> Data {
        ByteArray().writeUInt32(chunkSize & 0x7FFFFFFF).data
    }

    static func decode(from data: Data) -> RTMPSetChunkSizeMessage {
        let msg = RTMPSetChunkSizeMessage()
        if data.count >= 4 {
            msg.chunkSize = ((try? ByteArray(data: data).readUInt32()) ?? UInt32(RTMPChunk.defaultChunkSize)) & 0x7FFFFFFF
        }
        return msg
    }
}

/// Abort Message (Type 2)
final class RTMPAbortMessage: RTMPMessage {
    override var typeID: UInt8 { RTMPMessageType.abort.rawValue }
    var chunkStreamID: UInt32 = 0

    override func encode() -> Data {
        ByteArray().writeUInt32(chunkStreamID).data
    }

    static func decode(from data: Data) -> RTMPAbortMessage {
        let msg = RTMPAbortMessage()
        if data.count >= 4 { msg.chunkStreamID = (try? ByteArray(data: data).readUInt32()) ?? 0 }
        return msg
    }
}

/// Acknowledgement (Type 3)
final class RTMPAcknowledgementMessage: RTMPMessage {
    override var typeID: UInt8 { RTMPMessageType.acknowledgement.rawValue }
    var sequenceNumber: UInt32 = 0

    override func encode() -> Data {
        ByteArray().writeUInt32(sequenceNumber).data
    }

    static func decode(from data: Data) -> RTMPAcknowledgementMessage {
        let msg = RTMPAcknowledgementMessage()
        if data.count >= 4 { msg.sequenceNumber = (try? ByteArray(data: data).readUInt32()) ?? 0 }
        return msg
    }
}

/// Window Acknowledgement Size (Type 5)
final class RTMPWindowAcknowledgementSizeMessage: RTMPMessage {
    override var typeID: UInt8 { RTMPMessageType.windowAcknowledgementSize.rawValue }
    var size: UInt32 = 2500000

    override func encode() -> Data {
        ByteArray().writeUInt32(size).data
    }

    static func decode(from data: Data) -> RTMPWindowAcknowledgementSizeMessage {
        let msg = RTMPWindowAcknowledgementSizeMessage()
        if data.count >= 4 { msg.size = (try? ByteArray(data: data).readUInt32()) ?? 2500000 }
        return msg
    }
}

/// Set Peer Bandwidth (Type 6)
final class RTMPSetPeerBandwidthMessage: RTMPMessage {
    override var typeID: UInt8 { RTMPMessageType.setPeerBandwidth.rawValue }
    var size: UInt32 = 2500000
    var limitType: RTMPBandwidthLimitType = .dynamic

    override func encode() -> Data {
        ByteArray().writeUInt32(size).writeUInt8(limitType.rawValue).data
    }

    static func decode(from data: Data) -> RTMPSetPeerBandwidthMessage {
        let msg = RTMPSetPeerBandwidthMessage()
        if data.count >= 5 {
            let ba = ByteArray(data: data)
            msg.size = (try? ba.readUInt32()) ?? 2500000
            if let lt = try? ba.readUInt8() { msg.limitType = RTMPBandwidthLimitType(rawValue: lt) ?? .dynamic }
        }
        return msg
    }
}

/// User Control Message (Type 4)
final class RTMPUserControlMessage: RTMPMessage {
    override var typeID: UInt8 { RTMPMessageType.userControl.rawValue }
    var eventType: RTMPUserControlEventType = .streamBegin
    var eventData: Data = Data()

    override func encode() -> Data {
        ByteArray().writeUInt16(eventType.rawValue).writeBytes(eventData).data
    }

    static func decode(from data: Data) -> RTMPUserControlMessage {
        let msg = RTMPUserControlMessage()
        if data.count >= 2 {
            let ba = ByteArray(data: data)
            if let et = try? ba.readUInt16() { msg.eventType = RTMPUserControlEventType(rawValue: et) ?? .streamBegin }
            if ba.bytesAvailable > 0 { msg.eventData = (try? ba.readBytes(ba.bytesAvailable)) ?? Data() }
        }
        return msg
    }
}

// MARK: - Command Messages

/// RTMP Command Message (Type 20 AMF0 / Type 17 AMF3)
final class RTMPCommandMessage: RTMPMessage {
    var isAMF3: Bool = false
    override var typeID: UInt8 {
        isAMF3 ? RTMPMessageType.commandAMF3.rawValue : RTMPMessageType.commandAMF0.rawValue
    }
    var commandName: String = ""
    var transactionID: Int = 0
    var commandObject: ASObject? = nil
    var arguments: [Any?] = []

    override func encode() -> Data {
        let s = AMF0Serializer()
        s.serialize(commandName)
        s.serialize(Double(transactionID))
        s.serialize(commandObject as Any?)
        for arg in arguments { s.serialize(arg) }
        return s.data
    }

    static func decode(from data: Data, isAMF3: Bool) -> RTMPCommandMessage {
        let msg = RTMPCommandMessage()
        msg.isAMF3 = isAMF3
        let s = AMF0Serializer(data: data)
        do {
            msg.commandName = try s.deserialize() as String
            msg.transactionID = Int(try s.deserialize() as Double)
            msg.commandObject = try s.deserialize() as? ASObject
            while s.bytesAvailable > 0 { msg.arguments.append(try s.deserialize()) }
        } catch {}
        return msg
    }
}

// MARK: - Data Messages

/// RTMP Data Message (Type 18 AMF0 / Type 15 AMF3)
final class RTMPDataMessage: RTMPMessage {
    var isAMF3: Bool = false
    override var typeID: UInt8 {
        isAMF3 ? RTMPMessageType.dataAMF3.rawValue : RTMPMessageType.dataAMF0.rawValue
    }
    var handlerName: String = ""
    var arguments: [Any?] = []

    override func encode() -> Data {
        let s = AMF0Serializer()
        s.serialize(handlerName)
        for arg in arguments { s.serialize(arg) }
        return s.data
    }

    static func decode(from data: Data, isAMF3: Bool) -> RTMPDataMessage {
        let msg = RTMPDataMessage()
        msg.isAMF3 = isAMF3
        let s = AMF0Serializer(data: data)
        do {
            msg.handlerName = try s.deserialize() as String
            while s.bytesAvailable > 0 { msg.arguments.append(try s.deserialize()) }
        } catch {}
        return msg
    }
}

// MARK: - Media Messages

/// RTMP Audio Message (Type 8)
final class RTMPAudioMessage: RTMPMessage {
    override var typeID: UInt8 { RTMPMessageType.audio.rawValue }
}

/// RTMP Video Message (Type 9)
final class RTMPVideoMessage: RTMPMessage {
    override var typeID: UInt8 { RTMPMessageType.video.rawValue }
}
