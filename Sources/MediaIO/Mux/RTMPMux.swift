import Foundation

/// Muxes FLV tags into RTMP messages for publishing
final class RTMPMuxer {
    static let audioChunkStreamID: UInt16 = 4
    static let videoChunkStreamID: UInt16 = 6
    static let dataChunkStreamID: UInt16 = 3

    private var chunkSize: Int = RTMPChunk.defaultChunkSize
    private(set) var messageStreamID: UInt32 = 1

    init(messageStreamID: UInt32 = 1, chunkSize: Int = RTMPChunk.defaultChunkSize) {
        self.messageStreamID = messageStreamID
        self.chunkSize = chunkSize
    }

    func setChunkSize(_ size: Int) {
        chunkSize = size
    }

    func muxAudio(tag: FLVTag) -> Data {
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

    func muxVideo(tag: FLVTag) -> Data {
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

    func muxData(handlerName: String, arguments: [Any?] = []) -> Data {
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
