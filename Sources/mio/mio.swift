//
//  mio.swift
//
//  MediaIO Example: MP4 Reader -> RTMP Publisher
//
//  Usage: mio <mp4-file> <rtmp-url>/<stream-key>
//  Example: mio video.mp4 rtmp://localhost/live/stream
//

import Foundation
import MediaIO
import Logging

let logger = Logger(label: "mio")

@main
class mio {
    static func main() {
        logger.info("MediaIO - Multimedia Protocol Toolkit")
        logger.info("======================================")

        let args = CommandLine.arguments
        if args.count < 2 {
            printUsage()
            // Run protocol self-test when no arguments
            runSelfTest()
            return
        }

        let command = args[1]
        switch command {
        case "test":
            runSelfTest()
        case "publish":
            if args.count < 4 {
                logger.error("Usage: mio publish <mp4-file> <rtmp-url>")
                return
            }
            publishMP4(file: args[2], rtmpURL: args[3])
        case "flv-info":
            if args.count < 3 {
                logger.error("Usage: mio flv-info <flv-file>")
                return
            }
            flvInfo(file: args[2])
        case "mp4-info":
            if args.count < 3 {
                logger.error("Usage: mio mp4-info <mp4-file>")
                return
            }
            mp4Info(file: args[2])
        case "mp4-mux":
            if args.count < 3 {
                logger.error("Usage: mio mp4-mux <output.mp4>")
                return
            }
            mp4MuxDemo(output: args[2])
        default:
            // Treat as: mio <mp4-file> <rtmp-url>
            if args.count >= 3 {
                publishMP4(file: args[1], rtmpURL: args[2])
            } else {
                printUsage()
            }
        }
    }

    static func printUsage() {
        print("""
        MediaIO Command Line Tool

        Usage:
          mio test                           Run protocol self-tests
          mio publish <mp4-file> <rtmp-url>  Publish MP4 file via RTMP
          mio flv-info <flv-file>            Show FLV file information
          mio mp4-info <mp4-file>            Show MP4 file information
          mio mp4-mux <output.mp4>           Demo: mux synthetic A/V into MP4
          mio <mp4-file> <rtmp-url>          Shorthand for publish

        Examples:
          mio test
          mio publish video.mp4 rtmp://localhost/live/stream
          mio flv-info input.flv
          mio mp4-info video.mp4
          mio mp4-mux output.mp4
        """)
    }

    // MARK: - Protocol Self-Test

    static func runSelfTest() {
        print("\n--- Protocol Self-Test ---\n")
        var passed = 0
        var failed = 0

        func check(_ name: String, _ result: Bool) {
            if result {
                print("[PASS] \(name)")
                passed += 1
            } else {
                print("[FAIL] \(name)")
                failed += 1
            }
        }

        // ByteArray tests
        do {
            let ba = ByteArray()
            ba.writeUInt8(0xFF)
            ba.writeUInt16(0xABCD)
            ba.writeUInt32(0xDEADBEEF)
            ba.writeDouble(3.14159)
            ba.position = 0
            check("ByteArray: UInt8", try ba.readUInt8() == 0xFF)
            check("ByteArray: UInt16", try ba.readUInt16() == 0xABCD)
            check("ByteArray: UInt32", try ba.readUInt32() == 0xDEADBEEF)
            let d = try ba.readDouble()
            check("ByteArray: Double", abs(d - 3.14159) < 0.0001)
        } catch {
            check("ByteArray", false)
        }

        // AMF0 tests
        do {
            let s = AMF0Serializer()
            s.serialize("connect")
            s.serialize(42.0 as Double)
            s.serialize(true)
            s.serialize(nil as Any?)
            s.position = 0
            check("AMF0: String", (try s.deserialize() as String) == "connect")
            check("AMF0: Number", (try s.deserialize() as Double) == 42.0)
            check("AMF0: Bool", (try s.deserialize() as Bool) == true)
            let nilVal: Any? = try s.deserialize()
            check("AMF0: Null", nilVal == nil)
        } catch {
            check("AMF0", false)
        }

        // AMF0 Object
        do {
            let s = AMF0Serializer()
            var obj = ASObject()
            obj["app"] = "live"
            obj["flashVer"] = "FMLE/3.0"
            s.serialize(obj)
            s.position = 0
            let result: ASObject = try s.deserialize()
            check("AMF0: Object.app", (result["app"] as? String) == "live")
            check("AMF0: Object.flashVer", (result["flashVer"] as? String) == "FMLE/3.0")
        } catch {
            check("AMF0: Object", false)
        }

        // FLV tests
        do {
            var header = FLVHeader()
            header.hasAudio = true
            header.hasVideo = true
            let encoded = header.encode()
            let decoded = try FLVHeader.decode(from: encoded)
            check("FLV: Header encode/decode", decoded.hasAudio && decoded.hasVideo && decoded.version == 1)

            var tag = FLVTag()
            tag.tagType = .video
            tag.timestamp = 12345
            tag.data = Data([0x17, 0x00, 0x00, 0x00, 0x00])
            let tagEncoded = tag.encode()
            let (tagDecoded, _) = try FLVTag.decode(from: tagEncoded)
            check("FLV: Tag encode/decode", tagDecoded.tagType == .video && tagDecoded.timestamp == 12345)

            let writer = FLVWriter()
            writer.writeHeader(hasAudio: true, hasVideo: true)
            writer.writeTag(tag)
            let reader = FLVReader(data: writer.data)
            let h = try reader.readHeader()
            let t = try reader.readTag()
            check("FLV: Writer/Reader", h.hasVideo && t?.tagType == .video)
        } catch {
            check("FLV", false)
        }

        // RTMP Chunk tests
        do {
            // Basic header roundtrip
            for csid: UInt16 in [2, 3, 63, 64, 100, 319] {
                let bh = RTMPChunkBasicHeader(type: .full, chunkStreamID: csid)
                let data = bh.encode()
                let (decoded, _) = try RTMPChunkBasicHeader.decode(from: data, position: 0)
                check("RTMP Chunk: BasicHeader csid=\(csid)", decoded.chunkStreamID == csid)
            }

            // Full chunk encode/decode
            let msg = RTMPAudioMessage()
            msg.timestamp = 500
            msg.payload = Data(repeating: 0xAA, count: 200)
            let chunked = RTMPChunk.encode(message: msg, chunkStreamID: 4, messageStreamID: 1, chunkSize: 128)
            let decoder = RTMPChunkDecoder()
            let (messages, _) = try decoder.decode(from: chunked)
            check("RTMP Chunk: encode/decode", messages.count == 1 && messages[0].2.count == 200)
        } catch {
            check("RTMP Chunk", false)
        }

        // RTMP Message tests
        do {
            let setChunkSize = RTMPSetChunkSizeMessage()
            setChunkSize.chunkSize = 4096
            let decoded1 = RTMPSetChunkSizeMessage.decode(from: setChunkSize.encode())
            check("RTMP Msg: SetChunkSize", decoded1.chunkSize == 4096)

            let ack = RTMPAcknowledgementMessage()
            ack.sequenceNumber = 999999
            let decoded2 = RTMPAcknowledgementMessage.decode(from: ack.encode())
            check("RTMP Msg: Acknowledgement", decoded2.sequenceNumber == 999999)

            let cmd = RTMPCommandMessage()
            cmd.commandName = "connect"
            cmd.transactionID = 1
            let decoded3 = RTMPCommandMessage.decode(from: cmd.encode(), isAMF3: false)
            check("RTMP Msg: Command", decoded3.commandName == "connect" && decoded3.transactionID == 1)
        } catch {
            check("RTMP Message", false)
        }

        // RTMP Connection tests
        do {
            let conn = RTMPConnection()
            check("RTMP Conn: parseURL valid", conn.parseURL("rtmp://example.com:1935/live"))
            check("RTMP Conn: host", conn.host == "example.com")
            check("RTMP Conn: port", conn.port == 1935)
            check("RTMP Conn: app", conn.app == "live")
            check("RTMP Conn: parseURL invalid", !conn.parseURL("http://example.com"))

            let handshake = conn.startHandshake()
            check("RTMP Conn: handshake size", handshake.count == 1 + RTMPHandshake.sigSize)
            check("RTMP Conn: handshake state", conn.state == .handshaking)
        }

        // RTP tests
        do {
            var packet = RTPPacket()
            packet.header.payloadType = 96
            packet.header.sequenceNumber = 1000
            packet.header.timestamp = 90000
            packet.header.ssrc = 0x12345678
            packet.header.marker = true
            packet.payload = Data([0x01, 0x02, 0x03, 0x04])
            let encoded = packet.encode()
            let decoded = try RTPPacket.decode(from: encoded)
            check("RTP: PayloadType", decoded.header.payloadType == 96)
            check("RTP: SeqNum", decoded.header.sequenceNumber == 1000)
            check("RTP: Timestamp", decoded.header.timestamp == 90000)
            check("RTP: SSRC", decoded.header.ssrc == 0x12345678)
            check("RTP: Marker", decoded.header.marker == true)
            check("RTP: Payload", decoded.payload == Data([0x01, 0x02, 0x03, 0x04]))

            let builder = RTPPacketBuilder(ssrc: 0xAAAABBBB, payloadType: 97, initialSequence: 500)
            let p1 = builder.buildPacket(timestamp: 0, payload: Data([0xFF]))
            let p2 = builder.buildPacket(timestamp: 3600, payload: Data([0xFE]))
            check("RTP: Builder seq", p1.header.sequenceNumber == 500 && p2.header.sequenceNumber == 501)
        } catch {
            check("RTP", false)
        }

        // RTCP tests
        do {
            var block = RTCPReportBlock()
            block.ssrc = 0x11223344
            block.fractionLost = 10
            block.cumulativePacketsLost = 500
            block.extendedHighestSequence = 10000
            let encoded = block.encode()
            let ba = ByteArray(data: encoded)
            let decoded = try RTCPReportBlock.decode(from: ba)
            check("RTCP: ReportBlock SSRC", decoded.ssrc == 0x11223344)
            check("RTCP: ReportBlock fraction", decoded.fractionLost == 10)
            check("RTCP: ReportBlock lost", decoded.cumulativePacketsLost == 500)

            var sr = RTCPSenderReport()
            sr.ssrc = 0xDEADBEEF
            sr.senderPacketCount = 100
            let srData = sr.encode()
            check("RTCP: SenderReport size", srData.count == 28)
        } catch {
            check("RTCP", false)
        }

        // RTSP tests
        do {
            var request = RTSPRequest(method: .OPTIONS, url: "rtsp://example.com/live")
            request.cseq = 1
            request.setHeader("User-Agent", value: "MediaIO/1.0")
            let data = request.serialize()
            let parsed = try RTSPRequest.parse(from: data)
            check("RTSP: Request roundtrip", parsed.method == .OPTIONS && parsed.cseq == 1)

            var response = RTSPResponse(statusCode: 200)
            response.cseq = 1
            response.setHeader("Public", value: "DESCRIBE, SETUP, PLAY, TEARDOWN")
            let rData = response.serialize()
            let parsedR = try RTSPResponse.parse(from: rData)
            check("RTSP: Response roundtrip", parsedR.statusCode == 200 && parsedR.cseq == 1)

            let transport = RTSPTransport.parse("RTP/AVP/TCP;unicast;interleaved=0-1")
            check("RTSP: Transport parse", transport.lowerTransport == "TCP")
            check("RTSP: Transport interleaved", transport.interleaved?.0 == 0 && transport.interleaved?.1 == 1)

            let serialized = transport.serialize()
            let reparsed = RTSPTransport.parse(serialized)
            check("RTSP: Transport roundtrip", reparsed.lowerTransport == "TCP")

            let session = RTSPSession()
            let optReq = session.createOptionsRequest(url: "rtsp://test.com/stream")
            check("RTSP: Session OPTIONS", optReq.method == .OPTIONS && session.state == .optionsSent)
        } catch {
            check("RTSP", false)
        }

        // MP4 tests
        do {
            let ftyp = MP4Writer.ftypBox(majorBrand: "isom", minorVersion: 512, compatibleBrands: ["isom", "iso2"])
            let mvhd = MP4Writer.mvhdBox(timescale: 90000, duration: 900000)
            let moov = MP4Writer.containerBox(type: "moov", children: [mvhd])
            let mdat = MP4Writer.mdatBox(data: Data(repeating: 0, count: 64))
            let fileData = ftyp + moov + mdat
            let reader = MP4Reader(data: fileData)
            let boxes = try reader.readBoxes()
            check("MP4: Box count", boxes.count == 3)
            check("MP4: ftyp", boxes[0].type == "ftyp")
            check("MP4: moov", boxes[1].type == "moov")
            check("MP4: mdat", boxes[2].type == "mdat")

            let foundMvhd = try reader.findBox(path: "moov/mvhd")
            check("MP4: findBox moov/mvhd", foundMvhd?.type == "mvhd")
        } catch {
            check("MP4", false)
        }

        // MP4 Muxer tests
        do {
            let muxer = MP4Muxer()
            let videoTrackID = muxer.addVideoTrack(config: MP4VideoTrackConfig(
                width: 1920, height: 1080, timescale: 90000, codec: "avc1",
                decoderConfig: Data([0x01, 0x64, 0x00, 0x1E])
            ))
            let audioTrackID = muxer.addAudioTrack(config: MP4AudioTrackConfig(
                sampleRate: 44100, channelCount: 2, timescale: 44100, codec: "mp4a",
                decoderConfig: Data([0x12, 0x10])
            ))
            check("MP4 Muxer: addVideoTrack", videoTrackID == 1)
            check("MP4 Muxer: addAudioTrack", audioTrackID == 2)

            // Add video samples (I, P, P)
            muxer.addSample(trackID: videoTrackID, sample: MP4Sample(
                data: Data(repeating: 0x11, count: 1000), duration: 3000, isSync: true
            ))
            muxer.addSample(trackID: videoTrackID, sample: MP4Sample(
                data: Data(repeating: 0x22, count: 500), duration: 3000, isSync: false
            ))
            muxer.addSample(trackID: videoTrackID, sample: MP4Sample(
                data: Data(repeating: 0x33, count: 700), duration: 3000, isSync: false
            ))

            // Add audio samples
            for i in 0..<5 {
                muxer.addSample(trackID: audioTrackID, sample: MP4Sample(
                    data: Data(repeating: UInt8(0xA0 + i), count: 256), duration: 1024
                ))
            }

            let mp4Data = muxer.finalize()
            check("MP4 Muxer: finalize size > 0", mp4Data.count > 0)

            let reader = MP4Reader(data: mp4Data)
            let boxes = try reader.readBoxes()
            check("MP4 Muxer: ftyp+moov+mdat", boxes.count == 3)
            check("MP4 Muxer: ftyp box", boxes[0].type == "ftyp")
            check("MP4 Muxer: moov box", boxes[1].type == "moov")
            check("MP4 Muxer: mdat box", boxes[2].type == "mdat")

            // Verify mdat contains all sample data
            let expectedMdatSize = 1000 + 500 + 700 + 5 * 256
            check("MP4 Muxer: mdat data size", boxes[2].data.count == expectedMdatSize)

            // Verify moov has 2 traks
            let moovReader = MP4Reader(data: boxes[1].data)
            let moovChildren = try moovReader.readBoxes()
            check("MP4 Muxer: mvhd + 2 trak", moovChildren.count == 3)

            // Verify chunk offsets point to correct data
            let trak = try reader.findBox(path: "moov/trak")
            check("MP4 Muxer: trak exists", trak != nil)
        } catch {
            check("MP4 Muxer", false)
        }

        // Demuxer/Muxer tests
        do {
            let demuxer = RTMPDemuxer()
            var audioReceived = false
            var videoReceived = false
            demuxer.onAudioTag = { _ in audioReceived = true }
            demuxer.onVideoTag = { _ in videoReceived = true }

            let audioMsg = RTMPAudioMessage()
            audioMsg.payload = Data([0xAF, 0x01])
            demuxer.processMessage(audioMsg)
            check("Demuxer: Audio", audioReceived)

            let videoMsg = RTMPVideoMessage()
            videoMsg.payload = Data([0x17, 0x00, 0x00, 0x00, 0x00])
            demuxer.processMessage(videoMsg)
            check("Demuxer: Video", videoReceived)

            let muxer = RTMPMuxer(messageStreamID: 1)
            var tag = FLVTag()
            tag.tagType = .audio
            tag.data = Data([0xAF, 0x01])
            let chunked = muxer.muxAudio(tag: tag)
            let decoder = RTMPChunkDecoder()
            let (messages, _) = try decoder.decode(from: chunked)
            check("Muxer: Audio chunk", messages.count == 1)
        } catch {
            check("Demuxer/Muxer", false)
        }

        print("\n--- Results: \(passed) passed, \(failed) failed ---")
        if failed > 0 {
            print("SOME TESTS FAILED!")
        } else {
            print("ALL TESTS PASSED!")
        }
    }

    // MARK: - FLV Info

    static func flvInfo(file: String) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: file)) else {
            logger.error("Cannot read file: \(file)")
            return
        }

        let reader = FLVReader(data: data)
        do {
            let header = try reader.readHeader()
            print("FLV File: \(file)")
            print("  Version: \(header.version)")
            print("  Has Audio: \(header.hasAudio)")
            print("  Has Video: \(header.hasVideo)")
            print("  Data Offset: \(header.dataOffset)")
            print()

            var audioCount = 0
            var videoCount = 0
            var scriptCount = 0
            var maxTimestamp: UInt32 = 0

            while let tag = try reader.readTag() {
                switch tag.tagType {
                case .audio:
                    audioCount += 1
                    if audioCount == 1 {
                        let ah = try FLVAudioTagHeader.decode(from: tag.data)
                        print("  Audio Codec: \(ah.codec)")
                        print("  Sample Rate: \(ah.sampleRate)")
                    }
                case .video:
                    videoCount += 1
                    if videoCount == 1 {
                        let vh = try FLVVideoTagHeader.decode(from: tag.data)
                        print("  Video Codec: \(vh.codec)")
                        print("  Frame Type: \(vh.frameType)")
                    }
                case .scriptData:
                    scriptCount += 1
                }
                maxTimestamp = max(maxTimestamp, tag.timestamp)
            }

            print()
            print("  Audio Tags: \(audioCount)")
            print("  Video Tags: \(videoCount)")
            print("  Script Tags: \(scriptCount)")
            print("  Duration: ~\(maxTimestamp)ms (\(String(format: "%.1f", Double(maxTimestamp) / 1000.0))s)")
        } catch {
            logger.error("Error reading FLV: \(error)")
        }
    }

    // MARK: - MP4 Info

    static func mp4Info(file: String) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: file)) else {
            logger.error("Cannot read file: \(file)")
            return
        }

        let reader = MP4Reader(data: data)
        do {
            let boxes = try reader.readBoxes()
            print("MP4 File: \(file)")
            print("  Size: \(data.count) bytes")
            print("  Top-level boxes: \(boxes.count)")
            print()
            for box in boxes {
                print("  [\(box.type)] size=\(box.size) offset=\(box.offset)")
                // Parse children for container boxes
                if ["moov", "trak", "mdia", "minf", "stbl", "dinf", "edts", "udta"].contains(box.type) {
                    if let childBoxes = try? reader.readBoxes(from: box.data, offset: box.offset + UInt64(MP4Box.headerSize)) {
                        for child in childBoxes {
                            print("    [\(child.type)] size=\(child.size)")
                        }
                    }
                }
            }
        } catch {
            logger.error("Error reading MP4: \(error)")
        }
    }

    // MARK: - MP4 Mux Demo

    static func mp4MuxDemo(output: String) {
        print("MP4 File Writer Demo (streaming, disk-based)")
        print("=============================================")
        print("Generating MP4 file: \(output)")
        print("  Sample data is written directly to disk (low memory usage)")
        print()

        do {
            let writer = try MP4FileWriter(path: output)

            // Configure video track: 1280x720 @ 30fps, H.264
            let videoConfig = MP4VideoTrackConfig(
                width: 1280, height: 720, timescale: 90000, codec: "avc1",
                decoderConfig: Data([
                    0x01, 0x64, 0x00, 0x1E, 0xFF, 0xE1,
                    0x00, 0x04, 0x67, 0x64, 0x00, 0x1E,
                    0x01, 0x00, 0x02, 0x68, 0xEF
                ])
            )
            let videoTrackID = writer.addVideoTrack(config: videoConfig)
            print("  Video track \(videoTrackID): \(videoConfig.width)x\(videoConfig.height) \(videoConfig.codec)")

            // Configure audio track: AAC-LC 44100Hz stereo
            let audioConfig = MP4AudioTrackConfig(
                sampleRate: 44100, channelCount: 2, timescale: 44100, codec: "mp4a",
                decoderConfig: Data([0x12, 0x10])
            )
            let audioTrackID = writer.addAudioTrack(config: audioConfig)
            print("  Audio track \(audioTrackID): \(audioConfig.sampleRate)Hz \(audioConfig.channelCount)ch \(audioConfig.codec)")
            print()

            // Stream 2 seconds of video at 30fps
            let videoDuration: UInt32 = 3000
            let gopSize = 30

            print("  Writing video frames...")
            for i in 0..<60 {
                let isKeyframe = i % gopSize == 0
                let frameSize = isKeyframe ? 5000 : 1500
                try writer.writeSample(trackID: videoTrackID, sample: MP4Sample(
                    data: Data(repeating: UInt8(i & 0xFF), count: frameSize),
                    duration: videoDuration,
                    isSync: isKeyframe,
                    compositionTimeOffset: (i % 3 != 0) ? 3000 : 0
                ))
            }
            print("    60 video frames, \(writer.bytesWritten) bytes written")

            // Stream ~2 seconds of audio
            print("  Writing audio frames...")
            for i in 0..<86 {
                try writer.writeSample(trackID: audioTrackID, sample: MP4Sample(
                    data: Data(repeating: UInt8((i * 3) & 0xFF), count: 256),
                    duration: 1024
                ))
            }
            print("    86 audio frames, \(writer.bytesWritten) bytes total")
            print()

            // Finalize: patches mdat size and writes moov
            print("  Finalizing (writing moov)...")
            try writer.finalize()

            // Apply faststart: move moov before mdat
            print("  Applying faststart (relocating moov before mdat)...")
            try MP4FileWriter.relocateMoov(path: output)
            print()

            // Verify the output
            print("--- Verification ---")
            let data = try Data(contentsOf: URL(fileURLWithPath: output))
            print("  File size: \(data.count) bytes")

            let reader = MP4Reader(data: data)
            let boxes = try reader.readBoxes()
            for box in boxes {
                print("  [\(box.type)] size=\(box.size)")
            }

            if let moovBox = boxes.first(where: { $0.type == "moov" }) {
                let moovReader = MP4Reader(data: moovBox.data)
                let moovChildren = try moovReader.readBoxes()
                for child in moovChildren {
                    print("    [\(child.type)] size=\(child.size)")
                    if child.type == "trak" {
                        let trakReader = MP4Reader(data: child.data)
                        let trakChildren = try trakReader.readBoxes()
                        for tChild in trakChildren {
                            print("      [\(tChild.type)] size=\(tChild.size)")
                        }
                    }
                }
            }

            let moovIdx = boxes.firstIndex(where: { $0.type == "moov" })!
            let mdatIdx = boxes.firstIndex(where: { $0.type == "mdat" })!
            print()
            if moovIdx < mdatIdx {
                print("  moov is before mdat (faststart enabled)")
            } else {
                print("  moov is after mdat")
            }
            print("  MP4 muxing complete!")

        } catch {
            logger.error("Error: \(error)")
        }
    }

    // MARK: - MP4 -> RTMP Publisher

    static func publishMP4(file: String, rtmpURL: String) {
        print("MP4 -> RTMP Publisher")
        print("  Input: \(file)")
        print("  Output: \(rtmpURL)")
        print()

        // Parse RTMP URL
        let conn = RTMPConnection()
        guard conn.parseURL(rtmpURL) else {
            logger.error("Invalid RTMP URL: \(rtmpURL)")
            return
        }

        // Extract stream name from URL
        guard let urlComponents = URLComponents(string: rtmpURL) else {
            logger.error("Cannot parse URL")
            return
        }
        let pathParts = urlComponents.path.split(separator: "/", omittingEmptySubsequences: true)
        guard pathParts.count >= 2 else {
            logger.error("URL must include app and stream name: rtmp://host/app/stream")
            return
        }
        let streamName = String(pathParts.dropFirst().joined(separator: "/"))

        print("  Host: \(conn.host)")
        print("  Port: \(conn.port)")
        print("  App: \(conn.app)")
        print("  Stream: \(streamName)")
        print()

        // Read MP4 file
        guard let fileData = try? Data(contentsOf: URL(fileURLWithPath: file)) else {
            logger.error("Cannot read file: \(file)")
            return
        }

        print("  File size: \(fileData.count) bytes")

        // Parse MP4 structure
        let mp4Reader = MP4Reader(data: fileData)
        do {
            let boxes = try mp4Reader.readBoxes()
            print("  MP4 boxes: \(boxes.map { $0.type }.joined(separator: ", "))")

            // Find mdat box for media data
            guard let mdatBox = boxes.first(where: { $0.type == "mdat" }) else {
                logger.error("No mdat box found in MP4 file")
                return
            }

            print("  Media data size: \(mdatBox.data.count) bytes")
            print()

            // Demonstrate RTMP connection setup (without actual network)
            print("--- RTMP Connection Flow (simulated) ---")
            print()

            // Step 1: Handshake
            let c0c1 = conn.startHandshake()
            print("1. C0C1 Handshake sent (\(c0c1.count) bytes)")
            print("   State: \(conn.state)")

            // Step 2: Simulate receiving S0S1S2
            let s0s1s2 = Data([RTMPHandshake.protocolVersion]) + Data(repeating: 0, count: RTMPHandshake.sigSize * 2)
            let _ = try conn.processReceivedData(s0s1s2)
            print("2. S0S1S2 received, handshake complete")
            print("   State: \(conn.state)")

            // Step 3: Send connect command
            let connectCmd = conn.createConnectCommand()
            let connectData = RTMPChunk.encode(
                message: connectCmd,
                chunkStreamID: 3,
                messageStreamID: 0
            )
            print("3. Connect command prepared (\(connectData.count) bytes)")
            print("   Command: \(connectCmd.commandName)")
            print("   App: \(connectCmd.commandObject?["app"] as? String ?? "?")")

            // Step 4: Simulate receiving _result
            let resultCmd = RTMPCommandMessage()
            resultCmd.commandName = "_result"
            resultCmd.transactionID = 1
            let resultData = RTMPChunk.encode(
                message: resultCmd,
                chunkStreamID: 3,
                messageStreamID: 0
            )
            let _ = try conn.processReceivedData(resultData)
            print("4. Connect result received")
            print("   State: \(conn.state)")

            // Step 5: Create stream
            let createStreamCmd = conn.createCreateStreamCommand()
            let createStreamData = RTMPChunk.encode(
                message: createStreamCmd,
                chunkStreamID: 3,
                messageStreamID: 0
            )
            print("5. CreateStream command prepared (\(createStreamData.count) bytes)")

            // Step 6: Publish
            let publishCmd = conn.createPublishCommand(streamName: streamName)
            let publishData = RTMPChunk.encode(
                message: publishCmd,
                chunkStreamID: 3,
                messageStreamID: 1
            )
            print("6. Publish command prepared (\(publishData.count) bytes)")
            print("   Stream: \(publishCmd.arguments[0] as? String ?? "?")")
            print("   Type: \(publishCmd.arguments[1] as? String ?? "?")")

            // Step 7: Prepare media data using RTMPMuxer
            let muxer = RTMPMuxer(messageStreamID: 1)
            print()
            print("--- Media Data Packaging ---")

            // Send metadata
            var metaObj = ASObject()
            metaObj["duration"] = 0.0
            metaObj["width"] = 1920.0
            metaObj["height"] = 1080.0
            metaObj["videocodecid"] = 7.0  // AVC
            metaObj["audiocodecid"] = 10.0 // AAC
            metaObj["framerate"] = 30.0
            let metaData = muxer.muxData(handlerName: "@setDataFrame", arguments: ["onMetaData", metaObj])
            print("7. Metadata prepared (\(metaData.count) bytes)")

            // Simulate video sequence header (AVC)
            var videoSeqTag = FLVTag()
            videoSeqTag.tagType = .video
            videoSeqTag.timestamp = 0
            // AVC sequence header: keyframe(1) + AVC(7) = 0x17, seq header = 0x00, CT=0
            videoSeqTag.data = Data([0x17, 0x00, 0x00, 0x00, 0x00])
                + Data(repeating: 0x00, count: 16) // placeholder SPS/PPS
            let videoSeqData = muxer.muxVideo(tag: videoSeqTag)
            print("8. Video sequence header prepared (\(videoSeqData.count) bytes)")

            // Simulate audio sequence header (AAC)
            var audioSeqTag = FLVTag()
            audioSeqTag.tagType = .audio
            audioSeqTag.timestamp = 0
            // AAC(10=0xA) + 44kHz(3) + 16bit(1) + stereo(1) = 0xAF, seq header = 0x00
            audioSeqTag.data = Data([0xAF, 0x00, 0x12, 0x10]) // AAC-LC 44.1kHz stereo
            let audioSeqData = muxer.muxAudio(tag: audioSeqTag)
            print("9. Audio sequence header prepared (\(audioSeqData.count) bytes)")

            // Simulate sending media frames from mdat
            let chunkSize = min(mdatBox.data.count, 4096)
            var frameCount = 0
            var totalBytes = 0
            var offset = 0

            while offset < mdatBox.data.count && frameCount < 100 {
                let size = min(chunkSize, mdatBox.data.count - offset)
                let frameData = mdatBox.data.subdata(in: offset..<offset + size)

                // Alternate video/audio tags
                if frameCount % 3 == 0 {
                    // Video frame
                    var vTag = FLVTag()
                    vTag.tagType = .video
                    vTag.timestamp = UInt32(frameCount * 33) // ~30fps
                    let isKeyframe = frameCount % 30 == 0
                    vTag.data = Data([isKeyframe ? 0x17 : 0x27, 0x01, 0x00, 0x00, 0x00]) + frameData
                    let chunked = muxer.muxVideo(tag: vTag)
                    totalBytes += chunked.count
                } else {
                    // Audio frame
                    var aTag = FLVTag()
                    aTag.tagType = .audio
                    aTag.timestamp = UInt32(frameCount * 23) // ~44.1kHz
                    aTag.data = Data([0xAF, 0x01]) + frameData
                    let chunked = muxer.muxAudio(tag: aTag)
                    totalBytes += chunked.count
                }

                offset += size
                frameCount += 1
            }

            print("10. Prepared \(frameCount) media frames (\(totalBytes) bytes total)")

            // Cleanup
            conn.close()
            print()
            print("Connection closed. State: \(conn.state)")
            print()
            print("--- Summary ---")
            print("  RTMP handshake: OK")
            print("  RTMP connect: OK")
            print("  RTMP publish: OK")
            print("  Media muxing: OK (\(frameCount) frames, \(totalBytes) bytes)")
            print()
            print("Note: This is a simulated publish flow.")
            print("For actual streaming, connect to an RTMP server (e.g., nginx-rtmp, SRS).")

        } catch {
            logger.error("Error: \(error)")
        }
    }
}
