# CLAUDE.md

## Project Overview

MediaIO is a pure Swift multimedia protocol implementation framework. It aims to implement common multimedia protocols and container formats including RTMP, RTSP, RTP, FLV, MP4 and more, providing protocol-level parsing, serialization, muxing and demuxing capabilities.

## Build & Test

```bash
# Build the project
swift build

# Run tests
swift test

# Run the CLI tool
swift run mio
```

## Project Structure

- `Sources/MediaIO/` - Main library target
  - `RTMP/` - Real-Time Messaging Protocol
    - `AMF/` - AMF0/AMF3 serialization (ActionScript Message Format)
    - `Chunk/` - Chunk encoder/decoder (4 header types, extended timestamp)
    - `Connection/` - Connection state machine (handshake, connect, publish, play)
    - `Handshake/` - RTMP handshake (protocol version 3)
    - `Message/` - All message types (protocol control, command, data, audio, video)
  - `RTP/` - Real-time Transport Protocol (RFC 3550)
    - `RTPPacket.swift` - RTP header, extension, packet encode/decode, packet builder
    - `RTCPPacket.swift` - RTCP Sender/Receiver Reports, Report Blocks
  - `RTSP/` - Real Time Streaming Protocol (RFC 2326)
    - `RTSPMessage.swift` - Request/response parsing, Transport header, status codes
    - `RTSPSession.swift` - Session state machine (OPTIONS/DESCRIBE/SETUP/PLAY/TEARDOWN)
  - `FLV/` - Flash Video format (header, tags, audio/video tag headers, reader/writer)
  - `ISO/` - MP4/ISO base media file format
    - `MP4Parser.swift` - Box parser (MP4Reader), box writer (MP4Writer), MP4Box, MP4FullBox, MP4TrackInfo
    - `MP4Muxer.swift` - MP4FileWriter: streaming disk-based MP4 writer with moov-at-end and faststart (moov relocation) support
  - `Net/` - TCP socket abstraction (POSIX/Glibc)
  - `Demux/` - RTMP message demuxer (RTMP -> FLV tags)
  - `Mux/` - RTMP message muxer (FLV tags -> RTMP chunks)
  - `Util/` - Core utilities (ByteArray, DataBuffer, DataConvertible)
  - `Extension/` - Swift type extensions
- `Sources/mio/` - Command-line executable
- `Tests/MediaIOTests/` - Unit tests

## Dependencies

- **swift-log** (v1.5.3) - Apple's logging framework

## Code Conventions

- Swift 5.9+, Swift Package Manager
- Protocol-oriented design (`ByteArrayConvertible`, `DataConvertible`, `AMFSerializer`)
- Fluent API with `@discardableResult` for method chaining (e.g., `ByteArray` write methods)
- Big-endian byte order for network protocol data
- Structs for value types (ASArray, ASObject), classes for reference types (ByteArray, DataBuffer)
- Custom error enums with `throws`-based error propagation
- Apache License 2.0
