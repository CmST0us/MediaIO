# CLAUDE.md

## Project Overview

MediaIO is a pure Swift multimedia I/O framework focused on streaming protocols. It provides RTMP protocol support, AMF serialization, and binary data utilities for live streaming scenarios.

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
  - `RTMP/` - Real-Time Messaging Protocol implementation
    - `AMF/` - AMF0/AMF3 serialization
    - `Chunk/` - RTMP chunk protocol
    - `Connection/` - RTMP connection handling
    - `Handshake/` - RTMP handshake (protocol version 3)
    - `Message/` - RTMP message protocol
  - `FLV/` - Flash Video format parser
  - `ISO/` - MP4/ISO base media file format parser
  - `Net/` - Socket/network layer
  - `Demux/` - RTMP demultiplexing
  - `Mux/` - RTMP multiplexing
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
