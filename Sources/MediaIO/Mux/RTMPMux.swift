import Foundation

/// Muxes FLV tags into RTMP messages for publishing
public final class RTMPMuxer {
    public static let audioChunkStreamID: UInt16 = 4
    public static let videoChunkStreamID: UInt16 = 6
    public static let dataChunkStreamID: UInt16 = 3

    private var chunkSize: Int = RTMPChunk.defaultChunkSize
    public private(set) var messageStreamID: UInt32 = 1

    public init(messageStreamID: UInt32 = 1, chunkSize: Int = RTMPChunk.defaultChunkSize) {
        self.messageStreamID = messageStreamID
        self.chunkSize = chunkSize
    }

    public func setChunkSize(_ size: Int) {
        chunkSize = size
    }

    public func muxAudio(tag: FLVTag) -> Data {
        let msg = RTMPAudioMessage()
        msg.timestamp = tag.timestamp
        msg.payload = tag.data
        return RTMPChunk.encode(
            message: msg,
            chunkStreamID: RTMPMuxer.audioChunkStreamID,
            messageStreamID: messageStreamID,
            chunkSize: chunkSize
        )
    }

    public func muxVideo(tag: FLVTag) -> Data {
        let msg = RTMPVideoMessage()
        msg.timestamp = tag.timestamp
        msg.payload = tag.data
        return RTMPChunk.encode(
            message: msg,
            chunkStreamID: RTMPMuxer.videoChunkStreamID,
            messageStreamID: messageStreamID,
            chunkSize: chunkSize
        )
    }

    public func muxData(handlerName: String, arguments: [Any?] = []) -> Data {
        let msg = RTMPDataMessage()
        msg.handlerName = handlerName
        msg.arguments = arguments
        return RTMPChunk.encode(
            message: msg,
            chunkStreamID: RTMPMuxer.dataChunkStreamID,
            messageStreamID: messageStreamID,
            chunkSize: chunkSize
        )
    }
}
