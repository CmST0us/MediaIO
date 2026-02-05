import Foundation

/// RTMP Message Type IDs
/// - seealso: RTMP specification 7.1
public enum RTMPMessageType: UInt8 {
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
public enum RTMPUserControlEventType: UInt16 {
    case streamBegin = 0
    case streamEOF = 1
    case streamDry = 2
    case setBufferLength = 3
    case streamIsRecorded = 4
    case pingRequest = 6
    case pingResponse = 7
}

/// Peer Bandwidth Limit Type
public enum RTMPBandwidthLimitType: UInt8 {
    case hard = 0
    case soft = 1
    case dynamic = 2
}

/// Base RTMP Message
public class RTMPMessage {
    public var typeID: UInt8 { 0 }
    public var timestamp: UInt32 = 0
    public var streamID: UInt32 = 0
    public var payload: Data = Data()

    public init() {}

    public func encode() -> Data { payload }

    public static func create(typeID: UInt8, payload: Data) -> RTMPMessage {
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
public final class RTMPSetChunkSizeMessage: RTMPMessage {
    public override var typeID: UInt8 { RTMPMessageType.setChunkSize.rawValue }
    public var chunkSize: UInt32 = UInt32(RTMPChunk.defaultChunkSize)

    public override func encode() -> Data {
        ByteArray().writeUInt32(chunkSize & 0x7FFFFFFF).data
    }

    public static func decode(from data: Data) -> RTMPSetChunkSizeMessage {
        let msg = RTMPSetChunkSizeMessage()
        if data.count >= 4 {
            msg.chunkSize = ((try? ByteArray(data: data).readUInt32()) ?? UInt32(RTMPChunk.defaultChunkSize)) & 0x7FFFFFFF
        }
        return msg
    }
}

/// Abort Message (Type 2)
public final class RTMPAbortMessage: RTMPMessage {
    public override var typeID: UInt8 { RTMPMessageType.abort.rawValue }
    public var chunkStreamID: UInt32 = 0

    public override func encode() -> Data {
        ByteArray().writeUInt32(chunkStreamID).data
    }

    public static func decode(from data: Data) -> RTMPAbortMessage {
        let msg = RTMPAbortMessage()
        if data.count >= 4 { msg.chunkStreamID = (try? ByteArray(data: data).readUInt32()) ?? 0 }
        return msg
    }
}

/// Acknowledgement (Type 3)
public final class RTMPAcknowledgementMessage: RTMPMessage {
    public override var typeID: UInt8 { RTMPMessageType.acknowledgement.rawValue }
    public var sequenceNumber: UInt32 = 0

    public override func encode() -> Data {
        ByteArray().writeUInt32(sequenceNumber).data
    }

    public static func decode(from data: Data) -> RTMPAcknowledgementMessage {
        let msg = RTMPAcknowledgementMessage()
        if data.count >= 4 { msg.sequenceNumber = (try? ByteArray(data: data).readUInt32()) ?? 0 }
        return msg
    }
}

/// Window Acknowledgement Size (Type 5)
public final class RTMPWindowAcknowledgementSizeMessage: RTMPMessage {
    public override var typeID: UInt8 { RTMPMessageType.windowAcknowledgementSize.rawValue }
    public var size: UInt32 = 2500000

    public override func encode() -> Data {
        ByteArray().writeUInt32(size).data
    }

    public static func decode(from data: Data) -> RTMPWindowAcknowledgementSizeMessage {
        let msg = RTMPWindowAcknowledgementSizeMessage()
        if data.count >= 4 { msg.size = (try? ByteArray(data: data).readUInt32()) ?? 2500000 }
        return msg
    }
}

/// Set Peer Bandwidth (Type 6)
public final class RTMPSetPeerBandwidthMessage: RTMPMessage {
    public override var typeID: UInt8 { RTMPMessageType.setPeerBandwidth.rawValue }
    public var size: UInt32 = 2500000
    public var limitType: RTMPBandwidthLimitType = .dynamic

    public override func encode() -> Data {
        ByteArray().writeUInt32(size).writeUInt8(limitType.rawValue).data
    }

    public static func decode(from data: Data) -> RTMPSetPeerBandwidthMessage {
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
public final class RTMPUserControlMessage: RTMPMessage {
    public override var typeID: UInt8 { RTMPMessageType.userControl.rawValue }
    public var eventType: RTMPUserControlEventType = .streamBegin
    public var eventData: Data = Data()

    public override func encode() -> Data {
        ByteArray().writeUInt16(eventType.rawValue).writeBytes(eventData).data
    }

    public static func decode(from data: Data) -> RTMPUserControlMessage {
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
public final class RTMPCommandMessage: RTMPMessage {
    public var isAMF3: Bool = false
    public override var typeID: UInt8 {
        isAMF3 ? RTMPMessageType.commandAMF3.rawValue : RTMPMessageType.commandAMF0.rawValue
    }
    public var commandName: String = ""
    public var transactionID: Int = 0
    public var commandObject: ASObject? = nil
    public var arguments: [Any?] = []

    public override func encode() -> Data {
        let s = AMF0Serializer()
        s.serialize(commandName)
        s.serialize(Double(transactionID))
        s.serialize(commandObject as Any?)
        for arg in arguments { s.serialize(arg) }
        return s.data
    }

    public static func decode(from data: Data, isAMF3: Bool) -> RTMPCommandMessage {
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
public final class RTMPDataMessage: RTMPMessage {
    public var isAMF3: Bool = false
    public override var typeID: UInt8 {
        isAMF3 ? RTMPMessageType.dataAMF3.rawValue : RTMPMessageType.dataAMF0.rawValue
    }
    public var handlerName: String = ""
    public var arguments: [Any?] = []

    public override func encode() -> Data {
        let s = AMF0Serializer()
        s.serialize(handlerName)
        for arg in arguments { s.serialize(arg) }
        return s.data
    }

    public static func decode(from data: Data, isAMF3: Bool) -> RTMPDataMessage {
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
public final class RTMPAudioMessage: RTMPMessage {
    public override var typeID: UInt8 { RTMPMessageType.audio.rawValue }
}

/// RTMP Video Message (Type 9)
public final class RTMPVideoMessage: RTMPMessage {
    public override var typeID: UInt8 { RTMPMessageType.video.rawValue }
}
