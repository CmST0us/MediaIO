import XCTest
@testable import MediaIO

// MARK: - ByteArray Tests
final class ByteArrayTests: XCTestCase {
    func testWriteReadUInt8() throws {
        let ba = ByteArray()
        ba.writeUInt8(0xFF)
        ba.position = 0
        XCTAssertEqual(try ba.readUInt8(), 0xFF)
    }

    func testWriteReadUInt16() throws {
        let ba = ByteArray()
        ba.writeUInt16(0xABCD)
        ba.position = 0
        XCTAssertEqual(try ba.readUInt16(), 0xABCD)
    }

    func testWriteReadUInt24() throws {
        let ba = ByteArray()
        ba.writeUInt24(0x123456)
        ba.position = 0
        XCTAssertEqual(try ba.readUInt24(), 0x123456)
    }

    func testWriteReadUInt32() throws {
        let ba = ByteArray()
        ba.writeUInt32(0xDEADBEEF)
        ba.position = 0
        XCTAssertEqual(try ba.readUInt32(), 0xDEADBEEF)
    }

    func testWriteReadUInt64() throws {
        let ba = ByteArray()
        ba.writeUInt64(0x0102030405060708)
        ba.position = 0
        XCTAssertEqual(try ba.readUInt64(), 0x0102030405060708)
    }

    func testWriteReadDouble() throws {
        let ba = ByteArray()
        ba.writeDouble(3.14159)
        ba.position = 0
        XCTAssertEqual(try ba.readDouble(), 3.14159, accuracy: 0.00001)
    }

    func testWriteReadFloat() throws {
        let ba = ByteArray()
        ba.writeFloat(2.5)
        ba.position = 0
        XCTAssertEqual(try ba.readFloat(), 2.5, accuracy: 0.001)
    }

    func testWriteReadUTF8() throws {
        let ba = ByteArray()
        try ba.writeUTF8("Hello, World!")
        ba.position = 0
        XCTAssertEqual(try ba.readUTF8(), "Hello, World!")
    }

    func testWriteReadBytes() throws {
        let ba = ByteArray()
        let testData = Data([0x01, 0x02, 0x03, 0x04])
        ba.writeBytes(testData)
        ba.position = 0
        XCTAssertEqual(try ba.readBytes(4), testData)
    }

    func testBytesAvailable() {
        let ba = ByteArray()
        ba.writeUInt32(0)
        ba.writeUInt16(0)
        ba.position = 0
        XCTAssertEqual(ba.bytesAvailable, 6)
        _ = try? ba.readUInt32()
        XCTAssertEqual(ba.bytesAvailable, 2)
    }

    func testClear() {
        let ba = ByteArray()
        ba.writeUInt32(0xFFFFFFFF)
        ba.clear()
        XCTAssertEqual(ba.length, 0)
        XCTAssertEqual(ba.position, 0)
    }

    func testEOFThrows() {
        let ba = ByteArray()
        ba.writeUInt8(0x01)
        ba.position = 0
        XCTAssertThrowsError(try ba.readUInt32())
    }
}

// MARK: - AMF0 Tests
final class AMF0Tests: XCTestCase {
    func testSerializeDeserializeNumber() throws {
        let s = AMF0Serializer()
        s.serialize(42.0 as Double)
        s.position = 0
        let result: Double = try s.deserialize()
        XCTAssertEqual(result, 42.0)
    }

    func testSerializeDeserializeBool() throws {
        let s = AMF0Serializer()
        s.serialize(true)
        s.position = 0
        let result: Bool = try s.deserialize()
        XCTAssertTrue(result)
    }

    func testSerializeDeserializeBoolFalse() throws {
        let s = AMF0Serializer()
        s.serialize(false)
        s.position = 0
        let result: Bool = try s.deserialize()
        XCTAssertFalse(result)
    }

    func testSerializeDeserializeString() throws {
        let s = AMF0Serializer()
        s.serialize("connect")
        s.position = 0
        let result: String = try s.deserialize()
        XCTAssertEqual(result, "connect")
    }

    func testSerializeDeserializeEmptyString() throws {
        let s = AMF0Serializer()
        s.serialize("")
        s.position = 0
        let result: String = try s.deserialize()
        XCTAssertEqual(result, "")
    }

    func testSerializeDeserializeObject() throws {
        let s = AMF0Serializer()
        var obj = ASObject()
        obj["app"] = "live"
        obj["flashVer"] = "FMLE/3.0"
        s.serialize(obj)
        s.position = 0
        let result: ASObject = try s.deserialize()
        XCTAssertEqual(result["app"] as? String, "live")
        XCTAssertEqual(result["flashVer"] as? String, "FMLE/3.0")
    }

    func testSerializeDeserializeNull() throws {
        let s = AMF0Serializer()
        s.serialize(nil as Any?)
        s.position = 0
        let result: Any? = try s.deserialize()
        XCTAssertNil(result)
    }

    func testSerializeDeserializeDate() throws {
        let s = AMF0Serializer()
        let date = Date(timeIntervalSince1970: 1000000)
        s.serialize(date)
        s.position = 0
        let result: Date = try s.deserialize()
        XCTAssertEqual(result.timeIntervalSince1970, 1000000, accuracy: 0.001)
    }

    func testSerializeDeserializeAny() throws {
        let s = AMF0Serializer()
        s.serialize("test" as Any?)
        s.serialize(123.0 as Any?)
        s.serialize(nil as Any?)
        s.position = 0

        let v1: Any? = try s.deserialize()
        XCTAssertEqual(v1 as? String, "test")
        let v2: Any? = try s.deserialize()
        XCTAssertEqual(v2 as? Double, 123.0)
        let v3: Any? = try s.deserialize()
        XCTAssertNil(v3)
    }

    func testSerializeStrictArray() throws {
        let s = AMF0Serializer()
        let arr: [Any?] = [1.0 as Double, "hello", nil]
        s.serialize(arr)
        s.position = 0
        let result: [Any?] = try s.deserialize()
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0] as? Double, 1.0)
        XCTAssertEqual(result[1] as? String, "hello")
        XCTAssertNil(result[2])
    }
}

// MARK: - RTMP Chunk Tests
final class RTMPChunkTests: XCTestCase {
    func testBasicHeaderEncode1Byte() {
        let bh = RTMPChunkBasicHeader(type: .full, chunkStreamID: 3)
        let data = bh.encode()
        XCTAssertEqual(data.count, 1)
        XCTAssertEqual(data[0], 0x03) // fmt=0, csid=3
    }

    func testBasicHeaderEncode2Bytes() {
        let bh = RTMPChunkBasicHeader(type: .full, chunkStreamID: 100)
        let data = bh.encode()
        XCTAssertEqual(data.count, 2)
        XCTAssertEqual(data[0] & 0x3F, 0x00) // 2-byte form
        XCTAssertEqual(data[1], UInt8(100 - 64))
    }

    func testBasicHeaderDecode1Byte() throws {
        let data = Data([0x43]) // fmt=1, csid=3
        let (header, bytesRead) = try RTMPChunkBasicHeader.decode(from: data, position: 0)
        XCTAssertEqual(header.type, .sevenBytes)
        XCTAssertEqual(header.chunkStreamID, 3)
        XCTAssertEqual(bytesRead, 1)
    }

    func testBasicHeaderDecode2Bytes() throws {
        let data = Data([0x00, 0x24]) // fmt=0, 2-byte csid, csid=36+64=100
        let (header, bytesRead) = try RTMPChunkBasicHeader.decode(from: data, position: 0)
        XCTAssertEqual(header.type, .full)
        XCTAssertEqual(header.chunkStreamID, 100)
        XCTAssertEqual(bytesRead, 2)
    }

    func testBasicHeaderRoundTrip() throws {
        for csid: UInt16 in [2, 3, 10, 63, 64, 100, 319] {
            for headerType in [RTMPChunkHeaderType.full, .sevenBytes, .threeBytes, .continuation] {
                let bh = RTMPChunkBasicHeader(type: headerType, chunkStreamID: csid)
                let encoded = bh.encode()
                let (decoded, _) = try RTMPChunkBasicHeader.decode(from: encoded, position: 0)
                XCTAssertEqual(decoded.type, headerType, "Type mismatch for csid=\(csid)")
                XCTAssertEqual(decoded.chunkStreamID, csid, "CSID mismatch for csid=\(csid)")
            }
        }
    }

    func testChunkEncodeSmallPayload() {
        let msg = RTMPAudioMessage()
        msg.timestamp = 100
        msg.payload = Data(repeating: 0xAA, count: 50)
        let chunked = RTMPChunk.encode(message: msg, chunkStreamID: 4, messageStreamID: 1)
        // Should be a single chunk: basic header + 11-byte message header + 50 bytes data
        XCTAssertTrue(chunked.count > 50)
    }

    func testChunkEncodeLargePayload() {
        let msg = RTMPAudioMessage()
        msg.timestamp = 0
        msg.payload = Data(repeating: 0xBB, count: 300) // > default chunk size of 128
        let chunked = RTMPChunk.encode(message: msg, chunkStreamID: 4, messageStreamID: 1, chunkSize: 128)
        // 300 bytes needs 3 chunks: first 128, continuation 128, continuation 44
        // The encoded data should be bigger than 300 bytes due to chunk headers
        XCTAssertTrue(chunked.count > 300)
    }

    func testChunkEncodeDecodeRoundTrip() throws {
        let msg = RTMPAudioMessage()
        msg.timestamp = 500
        msg.payload = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        let chunked = RTMPChunk.encode(message: msg, chunkStreamID: 4, messageStreamID: 1)

        let decoder = RTMPChunkDecoder()
        let (messages, bytesConsumed) = try decoder.decode(from: chunked)
        XCTAssertEqual(bytesConsumed, chunked.count)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].1.messageTypeID, RTMPMessageType.audio.rawValue)
        XCTAssertEqual(messages[0].2, Data([0x01, 0x02, 0x03, 0x04, 0x05]))
        XCTAssertEqual(messages[0].1.timestamp, 500)
    }

    func testChunkEncodeDecodeMultiChunk() throws {
        let msg = RTMPVideoMessage()
        msg.timestamp = 1000
        msg.payload = Data(repeating: 0xCC, count: 300)
        let chunked = RTMPChunk.encode(message: msg, chunkStreamID: 6, messageStreamID: 1, chunkSize: 128)

        let decoder = RTMPChunkDecoder()
        let (messages, _) = try decoder.decode(from: chunked)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].2.count, 300)
        XCTAssertEqual(messages[0].1.messageTypeID, RTMPMessageType.video.rawValue)
    }

    func testChunkDecoderSetChunkSize() throws {
        let msg = RTMPAudioMessage()
        msg.timestamp = 0
        msg.payload = Data(repeating: 0xDD, count: 500)
        let chunked = RTMPChunk.encode(message: msg, chunkStreamID: 4, messageStreamID: 1, chunkSize: 256)

        let decoder = RTMPChunkDecoder()
        decoder.setChunkSize(256)
        let (messages, _) = try decoder.decode(from: chunked)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].2.count, 500)
    }

    func testChunkDecoderReset() throws {
        let decoder = RTMPChunkDecoder()
        decoder.setChunkSize(4096)
        decoder.reset()
        // After reset, should use default chunk size (128)
        let msg = RTMPAudioMessage()
        msg.timestamp = 0
        msg.payload = Data(repeating: 0xEE, count: 50)
        let chunked = RTMPChunk.encode(message: msg, chunkStreamID: 4, messageStreamID: 1)
        let (messages, _) = try decoder.decode(from: chunked)
        XCTAssertEqual(messages.count, 1)
    }

    func testExtendedTimestamp() throws {
        let msg = RTMPAudioMessage()
        msg.timestamp = 0x01000000 // > 0xFFFFFF, needs extended timestamp
        msg.payload = Data([0x01])
        let chunked = RTMPChunk.encode(message: msg, chunkStreamID: 4, messageStreamID: 1)

        let decoder = RTMPChunkDecoder()
        let (messages, _) = try decoder.decode(from: chunked)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].1.timestamp, 0x01000000)
    }
}

// MARK: - RTMP Message Tests
final class RTMPMessageTests: XCTestCase {
    func testSetChunkSizeMessage() {
        let msg = RTMPSetChunkSizeMessage()
        msg.chunkSize = 4096
        let encoded = msg.encode()
        let decoded = RTMPSetChunkSizeMessage.decode(from: encoded)
        XCTAssertEqual(decoded.chunkSize, 4096)
    }

    func testAbortMessage() {
        let msg = RTMPAbortMessage()
        msg.chunkStreamID = 42
        let encoded = msg.encode()
        let decoded = RTMPAbortMessage.decode(from: encoded)
        XCTAssertEqual(decoded.chunkStreamID, 42)
    }

    func testAcknowledgementMessage() {
        let msg = RTMPAcknowledgementMessage()
        msg.sequenceNumber = 1234567
        let encoded = msg.encode()
        let decoded = RTMPAcknowledgementMessage.decode(from: encoded)
        XCTAssertEqual(decoded.sequenceNumber, 1234567)
    }

    func testWindowAcknowledgementSizeMessage() {
        let msg = RTMPWindowAcknowledgementSizeMessage()
        msg.size = 5000000
        let encoded = msg.encode()
        let decoded = RTMPWindowAcknowledgementSizeMessage.decode(from: encoded)
        XCTAssertEqual(decoded.size, 5000000)
    }

    func testSetPeerBandwidthMessage() {
        let msg = RTMPSetPeerBandwidthMessage()
        msg.size = 3000000
        msg.limitType = .soft
        let encoded = msg.encode()
        let decoded = RTMPSetPeerBandwidthMessage.decode(from: encoded)
        XCTAssertEqual(decoded.size, 3000000)
        XCTAssertEqual(decoded.limitType, .soft)
    }

    func testUserControlMessage() {
        let msg = RTMPUserControlMessage()
        msg.eventType = .streamBegin
        msg.eventData = ByteArray().writeUInt32(1).data
        let encoded = msg.encode()
        let decoded = RTMPUserControlMessage.decode(from: encoded)
        XCTAssertEqual(decoded.eventType, .streamBegin)
    }

    func testCommandMessage() {
        let msg = RTMPCommandMessage()
        msg.commandName = "connect"
        msg.transactionID = 1
        var obj = ASObject()
        obj["app"] = "live"
        msg.commandObject = obj
        let encoded = msg.encode()
        let decoded = RTMPCommandMessage.decode(from: encoded, isAMF3: false)
        XCTAssertEqual(decoded.commandName, "connect")
        XCTAssertEqual(decoded.transactionID, 1)
        XCTAssertEqual(decoded.commandObject?["app"] as? String, "live")
    }

    func testDataMessage() {
        let msg = RTMPDataMessage()
        msg.handlerName = "@setDataFrame"
        msg.arguments = ["onMetaData"]
        let encoded = msg.encode()
        let decoded = RTMPDataMessage.decode(from: encoded, isAMF3: false)
        XCTAssertEqual(decoded.handlerName, "@setDataFrame")
        XCTAssertEqual(decoded.arguments.count, 1)
        XCTAssertEqual(decoded.arguments[0] as? String, "onMetaData")
    }

    func testAudioMessageTypeID() {
        let msg = RTMPAudioMessage()
        XCTAssertEqual(msg.typeID, RTMPMessageType.audio.rawValue)
    }

    func testVideoMessageTypeID() {
        let msg = RTMPVideoMessage()
        XCTAssertEqual(msg.typeID, RTMPMessageType.video.rawValue)
    }

    func testMessageFactory() {
        let payload = ByteArray().writeUInt32(8192).data
        let msg = RTMPMessage.create(typeID: RTMPMessageType.setChunkSize.rawValue, payload: payload)
        XCTAssertTrue(msg is RTMPSetChunkSizeMessage)
        XCTAssertEqual((msg as? RTMPSetChunkSizeMessage)?.chunkSize, 8192)
    }

    func testCommandMessageResult() {
        let msg = RTMPCommandMessage()
        msg.commandName = "_result"
        msg.transactionID = 1
        var obj = ASObject()
        obj["fmsVer"] = "FMS/3,5,7,7009"
        obj["capabilities"] = 31.0
        obj["mode"] = 1.0
        msg.commandObject = obj
        let encoded = msg.encode()
        let decoded = RTMPCommandMessage.decode(from: encoded, isAMF3: false)
        XCTAssertEqual(decoded.commandName, "_result")
        XCTAssertEqual(decoded.commandObject?["fmsVer"] as? String, "FMS/3,5,7,7009")
    }
}

// MARK: - RTMP Connection Tests
final class RTMPConnectionTests: XCTestCase {
    func testParseURL() {
        let conn = RTMPConnection()
        XCTAssertTrue(conn.parseURL("rtmp://example.com/live"))
        XCTAssertEqual(conn.host, "example.com")
        XCTAssertEqual(conn.port, 1935)
        XCTAssertEqual(conn.app, "live")
    }

    func testParseURLWithPort() {
        let conn = RTMPConnection()
        XCTAssertTrue(conn.parseURL("rtmp://example.com:19350/myapp"))
        XCTAssertEqual(conn.host, "example.com")
        XCTAssertEqual(conn.port, 19350)
        XCTAssertEqual(conn.app, "myapp")
    }

    func testParseURLInvalid() {
        let conn = RTMPConnection()
        XCTAssertFalse(conn.parseURL("http://example.com/live"))
        XCTAssertFalse(conn.parseURL("rtmp://"))
    }

    func testStartHandshake() {
        let conn = RTMPConnection()
        _ = conn.parseURL("rtmp://example.com/live")
        let data = conn.startHandshake()
        // C0 (1 byte) + C1 (1536 bytes)
        XCTAssertEqual(data.count, 1 + RTMPHandshake.sigSize)
        XCTAssertEqual(data[0], RTMPHandshake.protocolVersion)
        XCTAssertEqual(conn.state, .handshaking)
    }

    func testCreateConnectCommand() {
        let conn = RTMPConnection()
        _ = conn.parseURL("rtmp://example.com/live")
        let cmd = conn.createConnectCommand()
        XCTAssertEqual(cmd.commandName, "connect")
        XCTAssertEqual(cmd.transactionID, 1)
        XCTAssertEqual(cmd.commandObject?["app"] as? String, "live")
    }

    func testCreateCreateStreamCommand() {
        let conn = RTMPConnection()
        _ = conn.parseURL("rtmp://example.com/live")
        _ = conn.createConnectCommand()
        let cmd = conn.createCreateStreamCommand()
        XCTAssertEqual(cmd.commandName, "createStream")
        XCTAssertEqual(cmd.transactionID, 2)
    }

    func testCreatePublishCommand() {
        let conn = RTMPConnection()
        _ = conn.parseURL("rtmp://example.com/live")
        _ = conn.createConnectCommand()
        let cmd = conn.createPublishCommand(streamName: "stream123")
        XCTAssertEqual(cmd.commandName, "publish")
        XCTAssertEqual(cmd.arguments[0] as? String, "stream123")
        XCTAssertEqual(cmd.arguments[1] as? String, "live")
    }

    func testCreatePlayCommand() {
        let conn = RTMPConnection()
        _ = conn.parseURL("rtmp://example.com/live")
        _ = conn.createConnectCommand()
        let cmd = conn.createPlayCommand(streamName: "stream456")
        XCTAssertEqual(cmd.commandName, "play")
        XCTAssertEqual(cmd.arguments[0] as? String, "stream456")
    }

    func testClose() {
        let conn = RTMPConnection()
        _ = conn.parseURL("rtmp://example.com/live")
        _ = conn.startHandshake()
        conn.close()
        XCTAssertEqual(conn.state, .closed)
    }
}

// MARK: - FLV Tests
final class FLVTests: XCTestCase {
    func testFLVHeaderEncode() {
        var header = FLVHeader()
        header.hasAudio = true
        header.hasVideo = true
        let data = header.encode()
        XCTAssertEqual(data.count, 9)
        XCTAssertEqual(data[0], 0x46) // 'F'
        XCTAssertEqual(data[1], 0x4C) // 'L'
        XCTAssertEqual(data[2], 0x56) // 'V'
        XCTAssertEqual(data[3], 1)    // version
        XCTAssertEqual(data[4], 0x05) // audio + video flags
    }

    func testFLVHeaderDecode() throws {
        var original = FLVHeader()
        original.hasAudio = true
        original.hasVideo = false
        let data = original.encode()
        let decoded = try FLVHeader.decode(from: data)
        XCTAssertEqual(decoded.version, 1)
        XCTAssertTrue(decoded.hasAudio)
        XCTAssertFalse(decoded.hasVideo)
        XCTAssertEqual(decoded.dataOffset, 9)
    }

    func testFLVHeaderRoundTrip() throws {
        var header = FLVHeader()
        header.hasAudio = true
        header.hasVideo = true
        let encoded = header.encode()
        let decoded = try FLVHeader.decode(from: encoded)
        XCTAssertEqual(decoded.hasAudio, true)
        XCTAssertEqual(decoded.hasVideo, true)
        XCTAssertEqual(decoded.version, 1)
    }

    func testFLVHeaderInvalidSignature() {
        let data = Data([0x00, 0x00, 0x00, 0x01, 0x05, 0x00, 0x00, 0x00, 0x09])
        XCTAssertThrowsError(try FLVHeader.decode(from: data))
    }

    func testFLVTagEncode() {
        var tag = FLVTag()
        tag.tagType = .audio
        tag.timestamp = 1000
        tag.data = Data([0xAF, 0x01, 0x02, 0x03])
        let encoded = tag.encode()
        // 11 bytes header + 4 bytes data
        XCTAssertEqual(encoded.count, 15)
    }

    func testFLVTagDecode() throws {
        var tag = FLVTag()
        tag.tagType = .video
        tag.timestamp = 2000
        tag.streamID = 0
        tag.data = Data([0x17, 0x00, 0x00, 0x00, 0x00])
        let encoded = tag.encode()
        let (decoded, bytesRead) = try FLVTag.decode(from: encoded)
        XCTAssertEqual(decoded.tagType, .video)
        XCTAssertEqual(decoded.timestamp, 2000)
        XCTAssertEqual(decoded.data, Data([0x17, 0x00, 0x00, 0x00, 0x00]))
        XCTAssertEqual(bytesRead, encoded.count)
    }

    func testFLVTagTimestampExtended() throws {
        var tag = FLVTag()
        tag.tagType = .audio
        tag.timestamp = 0x01000001 // Uses timestamp extension byte
        tag.data = Data([0xAF, 0x01])
        let encoded = tag.encode()
        let (decoded, _) = try FLVTag.decode(from: encoded)
        XCTAssertEqual(decoded.timestamp, 0x01000001)
    }

    func testFLVAudioTagHeader() throws {
        // AAC, 44kHz, 16-bit, stereo, sequence header
        let data = Data([0xAF, 0x00])
        let header = try FLVAudioTagHeader.decode(from: data)
        XCTAssertEqual(header.codec, .aac)
        XCTAssertEqual(header.sampleRate, .rate44kHz)
        XCTAssertEqual(header.sampleSize, 1) // 16-bit
        XCTAssertEqual(header.channels, 1) // stereo
        XCTAssertEqual(header.aacPacketType, .sequenceHeader)
    }

    func testFLVVideoTagHeader() throws {
        // AVC keyframe, sequence header, composition time 0
        let data = Data([0x17, 0x00, 0x00, 0x00, 0x00])
        let header = try FLVVideoTagHeader.decode(from: data)
        XCTAssertEqual(header.frameType, .keyframe)
        XCTAssertEqual(header.codec, .avc)
        XCTAssertEqual(header.avcPacketType, .sequenceHeader)
        XCTAssertEqual(header.compositionTime, 0)
    }

    func testFLVVideoTagHeaderInterFrame() throws {
        // AVC inter frame, NALU
        let data = Data([0x27, 0x01, 0x00, 0x00, 0x50])
        let header = try FLVVideoTagHeader.decode(from: data)
        XCTAssertEqual(header.frameType, .interFrame)
        XCTAssertEqual(header.codec, .avc)
        XCTAssertEqual(header.avcPacketType, .nalu)
        XCTAssertEqual(header.compositionTime, 80)
    }

    func testFLVWriterReader() throws {
        let writer = FLVWriter()
        writer.writeHeader(hasAudio: true, hasVideo: true)

        var audioTag = FLVTag()
        audioTag.tagType = .audio
        audioTag.timestamp = 0
        audioTag.data = Data([0xAF, 0x00, 0x12, 0x10])
        writer.writeTag(audioTag)

        var videoTag = FLVTag()
        videoTag.tagType = .video
        videoTag.timestamp = 33
        videoTag.data = Data([0x17, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFE])
        writer.writeTag(videoTag)

        // Read back
        let reader = FLVReader(data: writer.data)
        let header = try reader.readHeader()
        XCTAssertTrue(header.hasAudio)
        XCTAssertTrue(header.hasVideo)

        let tag1 = try reader.readTag()
        XCTAssertNotNil(tag1)
        XCTAssertEqual(tag1?.tagType, .audio)
        XCTAssertEqual(tag1?.timestamp, 0)
        XCTAssertEqual(tag1?.data, Data([0xAF, 0x00, 0x12, 0x10]))

        let tag2 = try reader.readTag()
        XCTAssertNotNil(tag2)
        XCTAssertEqual(tag2?.tagType, .video)
        XCTAssertEqual(tag2?.timestamp, 33)
    }
}

// MARK: - MP4 Tests
final class MP4Tests: XCTestCase {
    func testMP4BoxEncode() {
        let box = MP4Box(type: "test", size: 0, data: Data([0x01, 0x02, 0x03, 0x04]))
        let encoded = box.encode()
        // 8-byte header + 4-byte data
        XCTAssertEqual(encoded.count, 12)
        // Size should be 12
        let ba = ByteArray(data: encoded)
        let size = try! ba.readUInt32()
        XCTAssertEqual(size, 12)
        let type = try! ba.readBytes(4)
        XCTAssertEqual(String(data: type, encoding: .ascii), "test")
    }

    func testMP4ReaderParseBoxes() throws {
        // Build a simple MP4 with ftyp box
        let ftypData = MP4Writer.ftypBox(
            majorBrand: "isom",
            minorVersion: 512,
            compatibleBrands: ["isom", "iso2", "avc1", "mp41"]
        )
        let mdatData = MP4Writer.mdatBox(data: Data(repeating: 0xFF, count: 16))
        let fileData = ftypData + mdatData

        let reader = MP4Reader(data: fileData)
        let boxes = try reader.readBoxes()
        XCTAssertEqual(boxes.count, 2)
        XCTAssertEqual(boxes[0].type, "ftyp")
        XCTAssertEqual(boxes[1].type, "mdat")
    }

    func testMP4WriterFtypBox() {
        let data = MP4Writer.ftypBox(majorBrand: "isom", minorVersion: 0, compatibleBrands: ["isom"])
        XCTAssertTrue(data.count > 8)
        let ba = ByteArray(data: data)
        let size = try! ba.readUInt32()
        XCTAssertEqual(Int(size), data.count)
        let type = try! ba.readBytes(4)
        XCTAssertEqual(String(data: type, encoding: .ascii), "ftyp")
    }

    func testMP4WriterMvhdBox() {
        let data = MP4Writer.mvhdBox(timescale: 90000, duration: 900000)
        XCTAssertTrue(data.count > 8)
        let ba = ByteArray(data: data)
        let size = try! ba.readUInt32()
        XCTAssertEqual(Int(size), data.count)
        let type = try! ba.readBytes(4)
        XCTAssertEqual(String(data: type, encoding: .ascii), "mvhd")
    }

    func testMP4WriterMdatBox() {
        let payload = Data([0x00, 0x01, 0x02, 0x03])
        let data = MP4Writer.mdatBox(data: payload)
        XCTAssertEqual(data.count, 12) // 8 header + 4 payload
        let ba = ByteArray(data: data)
        let size = try! ba.readUInt32()
        XCTAssertEqual(size, 12)
    }

    func testMP4WriterContainerBox() {
        let child1 = MP4Writer.mdatBox(data: Data([0x01]))
        let child2 = MP4Writer.mdatBox(data: Data([0x02]))
        let container = MP4Writer.containerBox(type: "moov", children: [child1, child2])
        let ba = ByteArray(data: container)
        let size = try! ba.readUInt32()
        let type = try! ba.readBytes(4)
        XCTAssertEqual(String(data: type, encoding: .ascii), "moov")
        XCTAssertEqual(Int(size), container.count)
    }

    func testMP4ReaderFindBox() throws {
        // Build moov > mvhd structure
        let mvhdData = MP4Writer.mvhdBox(timescale: 90000, duration: 0)
        let moovData = MP4Writer.containerBox(type: "moov", children: [mvhdData])
        let ftypData = MP4Writer.ftypBox(majorBrand: "isom", minorVersion: 0, compatibleBrands: ["isom"])
        let fileData = ftypData + moovData

        let reader = MP4Reader(data: fileData)
        let ftyp = try reader.findBox(path: "ftyp")
        XCTAssertNotNil(ftyp)
        XCTAssertEqual(ftyp?.type, "ftyp")

        let moov = try reader.findBox(path: "moov")
        XCTAssertNotNil(moov)
        XCTAssertEqual(moov?.type, "moov")

        let mvhd = try reader.findBox(path: "moov/mvhd")
        XCTAssertNotNil(mvhd)
        XCTAssertEqual(mvhd?.type, "mvhd")
    }

    func testMP4FullBoxEncode() {
        let box = MP4FullBox(type: "stsd", version: 0, flags: 0, data: Data([0x00, 0x00, 0x00, 0x01]))
        let encoded = box.encode()
        // 8 (header) + 4 (version+flags) + 4 (data) = 16
        XCTAssertEqual(encoded.count, 16)
    }
}

// MARK: - RTP Tests
final class RTPTests: XCTestCase {
    func testRTPHeaderEncode() {
        var header = RTPHeader()
        header.payloadType = 96
        header.sequenceNumber = 1234
        header.timestamp = 90000
        header.ssrc = 0x12345678
        header.marker = true
        let data = header.encode()
        XCTAssertEqual(data.count, RTPHeader.fixedSize)
    }

    func testRTPHeaderDecode() throws {
        var header = RTPHeader()
        header.payloadType = 97
        header.sequenceNumber = 5000
        header.timestamp = 180000
        header.ssrc = 0xAABBCCDD
        header.marker = false
        let data = header.encode()
        let (decoded, bytesRead) = try RTPHeader.decode(from: data)
        XCTAssertEqual(bytesRead, RTPHeader.fixedSize)
        XCTAssertEqual(decoded.version, kRTPVersion)
        XCTAssertEqual(decoded.payloadType, 97)
        XCTAssertEqual(decoded.sequenceNumber, 5000)
        XCTAssertEqual(decoded.timestamp, 180000)
        XCTAssertEqual(decoded.ssrc, 0xAABBCCDD)
        XCTAssertFalse(decoded.marker)
    }

    func testRTPHeaderRoundTrip() throws {
        var header = RTPHeader()
        header.payloadType = 96
        header.sequenceNumber = 65535
        header.timestamp = 0xFFFFFFFF
        header.ssrc = 0x01020304
        header.marker = true
        header.padding = false
        let encoded = header.encode()
        let (decoded, _) = try RTPHeader.decode(from: encoded)
        XCTAssertEqual(decoded.payloadType, 96)
        XCTAssertEqual(decoded.sequenceNumber, 65535)
        XCTAssertEqual(decoded.timestamp, 0xFFFFFFFF)
        XCTAssertEqual(decoded.ssrc, 0x01020304)
        XCTAssertTrue(decoded.marker)
    }

    func testRTPPacketEncodeDecode() throws {
        var packet = RTPPacket()
        packet.header.payloadType = 96
        packet.header.sequenceNumber = 100
        packet.header.timestamp = 3600
        packet.header.ssrc = 0xDEADBEEF
        packet.payload = Data([0x00, 0x01, 0x02, 0x03, 0x04])
        let encoded = packet.encode()
        let decoded = try RTPPacket.decode(from: encoded)
        XCTAssertEqual(decoded.header.payloadType, 96)
        XCTAssertEqual(decoded.header.sequenceNumber, 100)
        XCTAssertEqual(decoded.header.timestamp, 3600)
        XCTAssertEqual(decoded.header.ssrc, 0xDEADBEEF)
        XCTAssertEqual(decoded.payload, Data([0x00, 0x01, 0x02, 0x03, 0x04]))
    }

    func testRTPPacketWithExtension() throws {
        var packet = RTPPacket()
        packet.header.payloadType = 96
        packet.header.sequenceNumber = 200
        packet.header.timestamp = 7200
        packet.header.ssrc = 0x11223344
        packet.header.hasExtension = true
        packet.headerExtension = RTPHeaderExtension(profile: 0xBEDE, data: Data([0x01, 0x02, 0x03, 0x04]))
        packet.payload = Data([0xAA, 0xBB])
        let encoded = packet.encode()
        let decoded = try RTPPacket.decode(from: encoded)
        XCTAssertEqual(decoded.header.hasExtension, true)
        XCTAssertNotNil(decoded.headerExtension)
        XCTAssertEqual(decoded.headerExtension?.profile, 0xBEDE)
        XCTAssertEqual(decoded.payload, Data([0xAA, 0xBB]))
    }

    func testRTPPacketBuilder() {
        let builder = RTPPacketBuilder(ssrc: 0x12345678, payloadType: 96, initialSequence: 100)
        let p1 = builder.buildPacket(timestamp: 0, payload: Data([0x01]))
        XCTAssertEqual(p1.header.sequenceNumber, 100)
        XCTAssertEqual(p1.header.ssrc, 0x12345678)
        let p2 = builder.buildPacket(timestamp: 3600, payload: Data([0x02]))
        XCTAssertEqual(p2.header.sequenceNumber, 101)
        let p3 = builder.buildPacket(timestamp: 7200, payload: Data([0x03]), marker: true)
        XCTAssertEqual(p3.header.sequenceNumber, 102)
        XCTAssertTrue(p3.header.marker)
    }

    func testRTPHeaderExtensionRoundTrip() throws {
        let ext = RTPHeaderExtension(profile: 0x1234, data: Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]))
        let encoded = ext.encode()
        let (decoded, bytesRead) = try RTPHeaderExtension.decode(from: encoded)
        XCTAssertEqual(decoded.profile, 0x1234)
        XCTAssertEqual(decoded.data, Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]))
        XCTAssertEqual(bytesRead, encoded.count)
    }

    func testInvalidRTPVersion() {
        // Version 0 packet
        var data = Data(repeating: 0, count: 12)
        data[0] = 0x00 // version 0
        XCTAssertThrowsError(try RTPHeader.decode(from: data))
    }
}

// MARK: - RTCP Tests
final class RTCPTests: XCTestCase {
    func testRTCPHeaderEncode() {
        var header = RTCPHeader()
        header.packetType = .senderReport
        header.count = 0
        let data = header.encode()
        XCTAssertEqual(data.count, 4)
    }

    func testRTCPHeaderDecode() throws {
        var header = RTCPHeader()
        header.packetType = .receiverReport
        header.count = 1
        header.length = 7
        let encoded = header.encode()
        let decoded = try RTCPHeader.decode(from: encoded)
        XCTAssertEqual(decoded.packetType, .receiverReport)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.length, 7)
        XCTAssertEqual(decoded.version, kRTPVersion)
    }

    func testRTCPSenderReportEncode() {
        var sr = RTCPSenderReport()
        sr.ssrc = 0x12345678
        sr.ntpTimestamp = 0x0102030405060708
        sr.rtpTimestamp = 90000
        sr.senderPacketCount = 100
        sr.senderOctetCount = 15000
        let data = sr.encode()
        // 4 (header) + 4 (ssrc) + 8 (ntp) + 4 (rtp ts) + 4 (pkt cnt) + 4 (octet cnt) = 28
        XCTAssertEqual(data.count, 28)
    }

    func testRTCPReceiverReportEncode() {
        var rr = RTCPReceiverReport()
        rr.ssrc = 0xAABBCCDD
        let data = rr.encode()
        // 4 (header) + 4 (ssrc) = 8
        XCTAssertEqual(data.count, 8)
    }

    func testRTCPReportBlockRoundTrip() throws {
        var block = RTCPReportBlock()
        block.ssrc = 0x11223344
        block.fractionLost = 25
        block.cumulativePacketsLost = 1000
        block.extendedHighestSequence = 50000
        block.interarrivalJitter = 150
        block.lastSR = 0xABCD1234
        block.delaySinceLastSR = 65535
        let encoded = block.encode()
        XCTAssertEqual(encoded.count, 24) // Report block is 24 bytes
        let ba = ByteArray(data: encoded)
        let decoded = try RTCPReportBlock.decode(from: ba)
        XCTAssertEqual(decoded.ssrc, 0x11223344)
        XCTAssertEqual(decoded.fractionLost, 25)
        XCTAssertEqual(decoded.cumulativePacketsLost, 1000)
        XCTAssertEqual(decoded.extendedHighestSequence, 50000)
        XCTAssertEqual(decoded.interarrivalJitter, 150)
        XCTAssertEqual(decoded.lastSR, 0xABCD1234)
        XCTAssertEqual(decoded.delaySinceLastSR, 65535)
    }

    func testRTCPSenderReportWithReportBlocks() {
        var sr = RTCPSenderReport()
        sr.ssrc = 0x12345678
        sr.ntpTimestamp = 0
        sr.rtpTimestamp = 0
        sr.senderPacketCount = 0
        sr.senderOctetCount = 0
        var block = RTCPReportBlock()
        block.ssrc = 0xAABBCCDD
        sr.reportBlocks = [block]
        let data = sr.encode()
        // 4 (header) + 4 (ssrc) + 8 (ntp) + 4 (rtp ts) + 4 (pkt cnt) + 4 (octet cnt) + 24 (report block) = 52
        XCTAssertEqual(data.count, 52)
    }
}

// MARK: - RTSP Tests
final class RTSPTests: XCTestCase {
    func testRTSPRequestSerialize() {
        var request = RTSPRequest(method: .OPTIONS, url: "rtsp://example.com/stream")
        request.cseq = 1
        request.setHeader("User-Agent", value: "TestAgent/1.0")
        let data = request.serialize()
        let text = String(data: data, encoding: .utf8)!
        XCTAssertTrue(text.hasPrefix("OPTIONS rtsp://example.com/stream RTSP/1.0\r\n"))
        XCTAssertTrue(text.contains("CSeq: 1\r\n"))
        XCTAssertTrue(text.contains("User-Agent: TestAgent/1.0\r\n"))
    }

    func testRTSPRequestParse() throws {
        let text = "OPTIONS rtsp://example.com/stream RTSP/1.0\r\nCSeq: 1\r\nUser-Agent: Test\r\n\r\n"
        let data = Data(text.utf8)
        let request = try RTSPRequest.parse(from: data)
        XCTAssertEqual(request.method, .OPTIONS)
        XCTAssertEqual(request.url, "rtsp://example.com/stream")
        XCTAssertEqual(request.cseq, 1)
    }

    func testRTSPRequestRoundTrip() throws {
        var original = RTSPRequest(method: .DESCRIBE, url: "rtsp://example.com/live")
        original.cseq = 5
        original.setHeader("Accept", value: "application/sdp")
        let data = original.serialize()
        let parsed = try RTSPRequest.parse(from: data)
        XCTAssertEqual(parsed.method, .DESCRIBE)
        XCTAssertEqual(parsed.url, "rtsp://example.com/live")
        XCTAssertEqual(parsed.cseq, 5)
        XCTAssertEqual(parsed.getHeader("Accept"), "application/sdp")
    }

    func testRTSPResponseSerialize() {
        var response = RTSPResponse(statusCode: 200)
        response.cseq = 1
        response.setHeader("Public", value: "DESCRIBE, SETUP, TEARDOWN, PLAY, PAUSE")
        let data = response.serialize()
        let text = String(data: data, encoding: .utf8)!
        XCTAssertTrue(text.hasPrefix("RTSP/1.0 200 OK\r\n"))
        XCTAssertTrue(text.contains("CSeq: 1\r\n"))
    }

    func testRTSPResponseParse() throws {
        let text = "RTSP/1.0 200 OK\r\nCSeq: 1\r\nPublic: DESCRIBE, SETUP, PLAY, TEARDOWN\r\n\r\n"
        let data = Data(text.utf8)
        let response = try RTSPResponse.parse(from: data)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.reasonPhrase, "OK")
        XCTAssertEqual(response.cseq, 1)
        XCTAssertEqual(response.getHeader("Public"), "DESCRIBE, SETUP, PLAY, TEARDOWN")
    }

    func testRTSPResponseRoundTrip() throws {
        var original = RTSPResponse(statusCode: 200)
        original.cseq = 3
        original.setHeader("Session", value: "12345678")
        let data = original.serialize()
        let parsed = try RTSPResponse.parse(from: data)
        XCTAssertEqual(parsed.statusCode, 200)
        XCTAssertEqual(parsed.cseq, 3)
        XCTAssertEqual(parsed.getHeader("Session"), "12345678")
    }

    func testRTSPTransportParse() {
        let value = "RTP/AVP;unicast;client_port=8000-8001;server_port=9000-9001;ssrc=AABBCCDD"
        let transport = RTSPTransport.parse(value)
        XCTAssertEqual(transport.transportProtocol, "RTP")
        XCTAssertEqual(transport.profile, "AVP")
        XCTAssertTrue(transport.unicast)
        XCTAssertEqual(transport.clientPortRange?.0, 8000)
        XCTAssertEqual(transport.clientPortRange?.1, 8001)
        XCTAssertEqual(transport.serverPortRange?.0, 9000)
        XCTAssertEqual(transport.serverPortRange?.1, 9001)
        XCTAssertEqual(transport.ssrc, "AABBCCDD")
    }

    func testRTSPTransportParseTCP() {
        let value = "RTP/AVP/TCP;unicast;interleaved=0-1"
        let transport = RTSPTransport.parse(value)
        XCTAssertEqual(transport.transportProtocol, "RTP")
        XCTAssertEqual(transport.profile, "AVP")
        XCTAssertEqual(transport.lowerTransport, "TCP")
        XCTAssertTrue(transport.unicast)
        XCTAssertEqual(transport.interleaved?.0, 0)
        XCTAssertEqual(transport.interleaved?.1, 1)
    }

    func testRTSPTransportSerialize() {
        var transport = RTSPTransport()
        transport.transportProtocol = "RTP"
        transport.profile = "AVP"
        transport.unicast = true
        transport.clientPortRange = (8000, 8001)
        let serialized = transport.serialize()
        XCTAssertTrue(serialized.contains("RTP/AVP"))
        XCTAssertTrue(serialized.contains("unicast"))
        XCTAssertTrue(serialized.contains("client_port=8000-8001"))
    }

    func testRTSPTransportRoundTrip() {
        var original = RTSPTransport()
        original.transportProtocol = "RTP"
        original.profile = "AVP"
        original.lowerTransport = "TCP"
        original.unicast = true
        original.interleaved = (0, 1)
        let serialized = original.serialize()
        let parsed = RTSPTransport.parse(serialized)
        XCTAssertEqual(parsed.transportProtocol, "RTP")
        XCTAssertEqual(parsed.profile, "AVP")
        XCTAssertEqual(parsed.lowerTransport, "TCP")
        XCTAssertTrue(parsed.unicast)
        XCTAssertEqual(parsed.interleaved?.0, 0)
        XCTAssertEqual(parsed.interleaved?.1, 1)
    }

    func testRTSPStatusCodes() {
        XCTAssertEqual(RTSPStatusCode.ok.reasonPhrase, "OK")
        XCTAssertEqual(RTSPStatusCode.notFound.reasonPhrase, "Not Found")
        XCTAssertEqual(RTSPStatusCode.unauthorized.reasonPhrase, "Unauthorized")
        XCTAssertEqual(RTSPStatusCode.internalServerError.reasonPhrase, "Internal Server Error")
    }
}

// MARK: - RTSP Session Tests
final class RTSPSessionTests: XCTestCase {
    func testCreateOptionsRequest() {
        let session = RTSPSession()
        let request = session.createOptionsRequest(url: "rtsp://example.com/live")
        XCTAssertEqual(request.method, .OPTIONS)
        XCTAssertEqual(request.url, "rtsp://example.com/live")
        XCTAssertEqual(request.cseq, 1)
        XCTAssertEqual(session.state, .optionsSent)
    }

    func testCreateDescribeRequest() {
        let session = RTSPSession()
        _ = session.createOptionsRequest(url: "rtsp://example.com/live")
        let request = session.createDescribeRequest()
        XCTAssertEqual(request.method, .DESCRIBE)
        XCTAssertEqual(request.cseq, 2)
        XCTAssertEqual(request.getHeader("Accept"), "application/sdp")
    }

    func testCreateSetupRequest() {
        let session = RTSPSession()
        _ = session.createOptionsRequest(url: "rtsp://example.com/live")
        var transport = RTSPTransport()
        transport.unicast = true
        transport.clientPortRange = (8000, 8001)
        let request = session.createSetupRequest(trackURL: "rtsp://example.com/live/trackID=1", transport: transport)
        XCTAssertEqual(request.method, .SETUP)
        XCTAssertNotNil(request.getHeader("Transport"))
    }

    func testCreatePlayRequest() {
        let session = RTSPSession()
        _ = session.createOptionsRequest(url: "rtsp://example.com/live")
        let request = session.createPlayRequest()
        XCTAssertEqual(request.method, .PLAY)
        XCTAssertEqual(request.getHeader("Range"), "npt=0.000-")
    }

    func testProcessOptionsResponse() {
        let session = RTSPSession()
        _ = session.createOptionsRequest(url: "rtsp://example.com/live")
        var response = RTSPResponse(statusCode: 200)
        response.setHeader("Public", value: "DESCRIBE, SETUP, PLAY, TEARDOWN")
        session.processResponse(response, for: .OPTIONS)
        XCTAssertTrue(session.supportedMethods.contains(.DESCRIBE))
        XCTAssertTrue(session.supportedMethods.contains(.SETUP))
        XCTAssertTrue(session.supportedMethods.contains(.PLAY))
        XCTAssertTrue(session.supportedMethods.contains(.TEARDOWN))
    }

    func testProcessSetupResponse() {
        let session = RTSPSession()
        _ = session.createOptionsRequest(url: "rtsp://example.com/live")
        var response = RTSPResponse(statusCode: 200)
        response.setHeader("Session", value: "12345678;timeout=60")
        response.setHeader("Transport", value: "RTP/AVP;unicast;client_port=8000-8001;server_port=9000-9001")
        session.processResponse(response, for: .SETUP)
        XCTAssertEqual(session.sessionID, "12345678")
        XCTAssertNotNil(session.transport)
        XCTAssertEqual(session.state, .setup)
    }

    func testProcessPlayResponse() {
        let session = RTSPSession()
        _ = session.createOptionsRequest(url: "rtsp://example.com/live")
        let response = RTSPResponse(statusCode: 200)
        session.processResponse(response, for: .PLAY)
        XCTAssertEqual(session.state, .playing)
    }

    func testReset() {
        let session = RTSPSession()
        _ = session.createOptionsRequest(url: "rtsp://example.com/live")
        session.reset()
        XCTAssertNil(session.sessionID)
        XCTAssertEqual(session.state, .idle)
        XCTAssertTrue(session.supportedMethods.isEmpty)
    }
}

// MARK: - RTMP Demuxer/Muxer Tests
final class RTMPDemuxMuxTests: XCTestCase {
    func testRTMPDemuxerAudio() {
        let demuxer = RTMPDemuxer()
        var receivedTag: FLVTag?
        demuxer.onAudioTag = { tag in
            receivedTag = tag
        }
        let msg = RTMPAudioMessage()
        msg.timestamp = 100
        msg.payload = Data([0xAF, 0x01, 0x02])
        demuxer.processMessage(msg)
        XCTAssertNotNil(receivedTag)
        XCTAssertEqual(receivedTag?.tagType, .audio)
        XCTAssertEqual(receivedTag?.timestamp, 100)
        XCTAssertEqual(receivedTag?.data, Data([0xAF, 0x01, 0x02]))
    }

    func testRTMPDemuxerVideo() {
        let demuxer = RTMPDemuxer()
        var receivedTag: FLVTag?
        demuxer.onVideoTag = { tag in
            receivedTag = tag
        }
        let msg = RTMPVideoMessage()
        msg.timestamp = 200
        msg.payload = Data([0x17, 0x00, 0x00, 0x00, 0x00])
        demuxer.processMessage(msg)
        XCTAssertNotNil(receivedTag)
        XCTAssertEqual(receivedTag?.tagType, .video)
        XCTAssertEqual(receivedTag?.timestamp, 200)
    }

    func testRTMPMuxerAudio() throws {
        let muxer = RTMPMuxer(messageStreamID: 1)
        var tag = FLVTag()
        tag.tagType = .audio
        tag.timestamp = 100
        tag.data = Data([0xAF, 0x01])
        let chunkedData = muxer.muxAudio(tag: tag)
        XCTAssertTrue(chunkedData.count > 0)

        // Decode the chunked data
        let decoder = RTMPChunkDecoder()
        let (messages, _) = try decoder.decode(from: chunkedData)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].1.messageTypeID, RTMPMessageType.audio.rawValue)
        XCTAssertEqual(messages[0].2, Data([0xAF, 0x01]))
    }

    func testRTMPMuxerVideo() throws {
        let muxer = RTMPMuxer(messageStreamID: 1)
        var tag = FLVTag()
        tag.tagType = .video
        tag.timestamp = 33
        tag.data = Data([0x17, 0x00, 0x00, 0x00, 0x00])
        let chunkedData = muxer.muxVideo(tag: tag)
        let decoder = RTMPChunkDecoder()
        let (messages, _) = try decoder.decode(from: chunkedData)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].1.messageTypeID, RTMPMessageType.video.rawValue)
    }

    func testRTMPMuxerData() throws {
        let muxer = RTMPMuxer(messageStreamID: 1)
        let chunkedData = muxer.muxData(handlerName: "@setDataFrame", arguments: ["onMetaData"])
        let decoder = RTMPChunkDecoder()
        let (messages, _) = try decoder.decode(from: chunkedData)
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].1.messageTypeID, RTMPMessageType.dataAMF0.rawValue)
    }
}

// MARK: - Integration Tests
final class IntegrationTests: XCTestCase {
    /// Test full RTMP chunk encode -> decode -> message factory roundtrip
    func testRTMPFullRoundTrip() throws {
        // Create a command message
        let cmdMsg = RTMPCommandMessage()
        cmdMsg.commandName = "connect"
        cmdMsg.transactionID = 1
        var obj = ASObject()
        obj["app"] = "live"
        cmdMsg.commandObject = obj

        // Encode into chunks
        let chunked = RTMPChunk.encode(
            message: cmdMsg,
            chunkStreamID: 3,
            messageStreamID: 0,
            chunkSize: 128
        )

        // Decode chunks
        let decoder = RTMPChunkDecoder()
        let (rawMessages, _) = try decoder.decode(from: chunked)
        XCTAssertEqual(rawMessages.count, 1)

        // Reconstruct message via factory
        let message = RTMPMessage.create(typeID: rawMessages[0].1.messageTypeID, payload: rawMessages[0].2)
        XCTAssertTrue(message is RTMPCommandMessage)
        let cmd = message as! RTMPCommandMessage
        XCTAssertEqual(cmd.commandName, "connect")
        XCTAssertEqual(cmd.transactionID, 1)
        XCTAssertEqual(cmd.commandObject?["app"] as? String, "live")
    }

    /// Test FLV write -> read roundtrip
    func testFLVFullRoundTrip() throws {
        let writer = FLVWriter()
        writer.writeHeader(hasAudio: true, hasVideo: true)

        // Write script data tag
        var scriptTag = FLVTag()
        scriptTag.tagType = .scriptData
        scriptTag.timestamp = 0
        scriptTag.data = Data([0x02, 0x00, 0x0A]) // AMF0 string marker
        writer.writeTag(scriptTag)

        // Write video tag (AVC sequence header)
        var videoTag = FLVTag()
        videoTag.tagType = .video
        videoTag.timestamp = 0
        videoTag.data = Data([0x17, 0x00, 0x00, 0x00, 0x00, 0x01, 0x64, 0x00, 0x1E])
        writer.writeTag(videoTag)

        // Write audio tag (AAC sequence header)
        var audioTag = FLVTag()
        audioTag.tagType = .audio
        audioTag.timestamp = 0
        audioTag.data = Data([0xAF, 0x00, 0x12, 0x10])
        writer.writeTag(audioTag)

        // Write video data
        var videoDataTag = FLVTag()
        videoDataTag.tagType = .video
        videoDataTag.timestamp = 33
        videoDataTag.data = Data([0x27, 0x01, 0x00, 0x00, 0x00] + Data(repeating: 0xAA, count: 100))
        writer.writeTag(videoDataTag)

        // Read back
        let reader = FLVReader(data: writer.data)
        let header = try reader.readHeader()
        XCTAssertTrue(header.hasAudio)
        XCTAssertTrue(header.hasVideo)

        let t1 = try reader.readTag()
        XCTAssertEqual(t1?.tagType, .scriptData)

        let t2 = try reader.readTag()
        XCTAssertEqual(t2?.tagType, .video)
        XCTAssertEqual(t2?.timestamp, 0)

        let t3 = try reader.readTag()
        XCTAssertEqual(t3?.tagType, .audio)
        XCTAssertEqual(t3?.timestamp, 0)

        let t4 = try reader.readTag()
        XCTAssertEqual(t4?.tagType, .video)
        XCTAssertEqual(t4?.timestamp, 33)
        XCTAssertEqual(t4?.data.count, 105) // 5 header + 100 payload
    }

    /// Test MP4 box hierarchy build and parse
    func testMP4BoxHierarchy() throws {
        let ftyp = MP4Writer.ftypBox(majorBrand: "isom", minorVersion: 512, compatibleBrands: ["isom", "iso2"])
        let mvhd = MP4Writer.mvhdBox(timescale: 90000, duration: 900000, nextTrackID: 3)
        let moov = MP4Writer.containerBox(type: "moov", children: [mvhd])
        let mdat = MP4Writer.mdatBox(data: Data(repeating: 0, count: 1024))
        let fileData = ftyp + moov + mdat

        let reader = MP4Reader(data: fileData)
        let boxes = try reader.readBoxes()
        XCTAssertEqual(boxes.count, 3)
        XCTAssertEqual(boxes[0].type, "ftyp")
        XCTAssertEqual(boxes[1].type, "moov")
        XCTAssertEqual(boxes[2].type, "mdat")

        // Parse nested box
        let foundMvhd = try reader.findBox(path: "moov/mvhd")
        XCTAssertNotNil(foundMvhd)
        XCTAssertEqual(foundMvhd?.type, "mvhd")
    }
}
