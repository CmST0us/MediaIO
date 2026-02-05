import Foundation

/// RTMP Connection State
public enum RTMPConnectionState {
    case idle
    case handshaking
    case handshakeDone
    case connecting
    case connected
    case closed
    case error
}

/// RTMP Connection manages the lifecycle of an RTMP session
public final class RTMPConnection {
    public private(set) var state: RTMPConnectionState = .idle
    public private(set) var host: String = ""
    public private(set) var port: Int = 1935
    public private(set) var app: String = ""
    public private(set) var tcUrl: String = ""
    public private(set) var chunkSize: Int = RTMPChunk.defaultChunkSize
    public private(set) var windowAcknowledgementSize: UInt32 = 2500000
    public private(set) var totalBytesReceived: UInt64 = 0
    public private(set) var lastAcknowledgedBytes: UInt64 = 0

    private let handshake = RTMPHandshake()
    private let chunkDecoder = RTMPChunkDecoder()
    private var receiveBuffer = Data()
    private var transactionID: Int = 0
    private var transactions: [Int: String] = [:]

    public init() {}

    /// Parse an RTMP URL: rtmp://host[:port]/app[/instance]
    public func parseURL(_ url: String) -> Bool {
        guard let components = URLComponents(string: url) else { return false }
        guard components.scheme == "rtmp" || components.scheme == "rtmps" else { return false }
        guard let h = components.host, !h.isEmpty else { return false }
        host = h
        port = components.port ?? 1935
        let pathParts = components.path.split(separator: "/", omittingEmptySubsequences: true)
        guard !pathParts.isEmpty else { return false }
        app = String(pathParts[0])
        tcUrl = "\(components.scheme ?? "rtmp")://\(host):\(port)/\(app)"
        return true
    }

    public func startHandshake() -> Data {
        state = .handshaking
        handshake.timestamp = Date().timeIntervalSince1970
        return handshake.c0c1packet
    }

    public func createC2Packet(s0s1Data: Data) -> Data {
        handshake.c2packet(s0s1Data)
    }

    public func createConnectCommand() -> RTMPCommandMessage {
        let msg = RTMPCommandMessage()
        msg.commandName = "connect"
        transactionID += 1
        msg.transactionID = transactionID
        transactions[transactionID] = "connect"
        var obj = ASObject()
        obj["app"] = app
        obj["flashVer"] = "FMLE/3.0 (compatible; MediaIO)"
        obj["tcUrl"] = tcUrl
        obj["fpad"] = false
        obj["capabilities"] = 239.0
        obj["audioCodecs"] = 3575.0
        obj["videoCodecs"] = 252.0
        obj["videoFunction"] = 1.0
        obj["objectEncoding"] = 0.0
        msg.commandObject = obj
        return msg
    }

    public func createCreateStreamCommand() -> RTMPCommandMessage {
        let msg = RTMPCommandMessage()
        msg.commandName = "createStream"
        transactionID += 1
        msg.transactionID = transactionID
        transactions[transactionID] = "createStream"
        return msg
    }

    public func createPublishCommand(streamName: String, type: String = "live") -> RTMPCommandMessage {
        let msg = RTMPCommandMessage()
        msg.commandName = "publish"
        transactionID += 1
        msg.transactionID = transactionID
        transactions[transactionID] = "publish"
        msg.commandObject = nil
        msg.arguments = [streamName, type]
        return msg
    }

    public func createPlayCommand(streamName: String) -> RTMPCommandMessage {
        let msg = RTMPCommandMessage()
        msg.commandName = "play"
        transactionID += 1
        msg.transactionID = transactionID
        transactions[transactionID] = "play"
        msg.commandObject = nil
        msg.arguments = [streamName]
        return msg
    }

    public func processReceivedData(_ data: Data) throws -> [RTMPMessage] {
        receiveBuffer.append(data)
        totalBytesReceived += UInt64(data.count)
        switch state {
        case .handshaking:
            return try processHandshake()
        case .handshakeDone, .connecting, .connected:
            return try processChunks()
        default:
            return []
        }
    }

    private func processHandshake() throws -> [RTMPMessage] {
        let s0s1s2Size = 1 + RTMPHandshake.sigSize + RTMPHandshake.sigSize
        guard receiveBuffer.count >= s0s1s2Size else { return [] }
        guard receiveBuffer[0] == RTMPHandshake.protocolVersion else {
            state = .error
            throw RTMPConnectionError.handshakeFailed
        }
        state = .handshakeDone
        receiveBuffer = Data(receiveBuffer.suffix(from: s0s1s2Size))
        return []
    }

    private func processChunks() throws -> [RTMPMessage] {
        let (rawMessages, bytesConsumed) = try chunkDecoder.decode(from: receiveBuffer)
        if bytesConsumed > 0 {
            receiveBuffer = Data(receiveBuffer.suffix(from: bytesConsumed))
        }
        var messages: [RTMPMessage] = []
        for (_, header, payload) in rawMessages {
            let message = RTMPMessage.create(typeID: header.messageTypeID, payload: payload)
            message.timestamp = header.timestamp
            message.streamID = header.messageStreamID
            handleMessage(message)
            messages.append(message)
        }
        return messages
    }

    private func handleMessage(_ message: RTMPMessage) {
        switch message {
        case let msg as RTMPSetChunkSizeMessage:
            chunkSize = Int(msg.chunkSize)
            chunkDecoder.setChunkSize(chunkSize)
        case let msg as RTMPWindowAcknowledgementSizeMessage:
            windowAcknowledgementSize = msg.size
        case let msg as RTMPCommandMessage:
            handleCommand(msg)
        default:
            break
        }
    }

    private func handleCommand(_ message: RTMPCommandMessage) {
        switch message.commandName {
        case "_result":
            if let txName = transactions[message.transactionID] {
                transactions.removeValue(forKey: message.transactionID)
                if txName == "connect" { state = .connected }
            }
        case "_error":
            transactions.removeValue(forKey: message.transactionID)
            state = .error
        default:
            break
        }
    }

    public func createAcknowledgementMessage() -> RTMPAcknowledgementMessage {
        let msg = RTMPAcknowledgementMessage()
        msg.sequenceNumber = UInt32(totalBytesReceived & 0xFFFFFFFF)
        lastAcknowledgedBytes = totalBytesReceived
        return msg
    }

    public func close() {
        state = .closed
        receiveBuffer.removeAll()
        chunkDecoder.reset()
        handshake.clear()
        transactionID = 0
        transactions.removeAll()
        totalBytesReceived = 0
        lastAcknowledgedBytes = 0
    }
}

public enum RTMPConnectionError: Error {
    case handshakeFailed
    case invalidURL
    case connectionFailed
    case unexpectedState
}
