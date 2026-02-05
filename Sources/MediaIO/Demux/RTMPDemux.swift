import Foundation

/// Demuxes RTMP audio/video messages into FLV tags
final class RTMPDemuxer {
    var onAudioTag: ((FLVTag) -> Void)?
    var onVideoTag: ((FLVTag) -> Void)?
    var onScriptData: ((FLVTag) -> Void)?

    func processMessage(_ message: RTMPMessage) {
        switch message {
        case let msg as RTMPAudioMessage:
            var tag = FLVTag()
            tag.tagType = .audio
            tag.timestamp = msg.timestamp
            tag.data = msg.payload
            onAudioTag?(tag)

        case let msg as RTMPVideoMessage:
            var tag = FLVTag()
            tag.tagType = .video
            tag.timestamp = msg.timestamp
            tag.data = msg.payload
            onVideoTag?(tag)

        case let msg as RTMPDataMessage:
            var tag = FLVTag()
            tag.tagType = .scriptData
            tag.timestamp = msg.timestamp
            tag.data = msg.encode()
            onScriptData?(tag)

        default:
            break
        }
    }
}
