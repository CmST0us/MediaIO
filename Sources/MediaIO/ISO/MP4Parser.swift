import Foundation

/// MP4 Box (Atom) - the fundamental unit of an ISO base media file
/// - seealso: ISO 14496-12
public struct MP4Box {
    public var type: String
    public var size: UInt64
    public var data: Data

    /// Offset of this box in the file
    public var offset: UInt64 = 0

    /// Whether this box uses 64-bit extended size
    public var isLargeSize: Bool { size == 1 }

    public static let headerSize: Int = 8
    public static let largeHeaderSize: Int = 16

    public init(type: String, size: UInt64, data: Data) {
        self.type = type
        self.size = size
        self.data = data
    }

    /// Encode box to data
    public func encode() -> Data {
        let ba = ByteArray()
        let boxData = data
        let totalSize = UInt64(headerSize) + UInt64(boxData.count)

        if totalSize > UInt64(UInt32.max) {
            ba.writeUInt32(1) // indicates 64-bit extended size
            ba.writeBytes(Data(type.utf8.prefix(4)))
            ba.writeUInt64(totalSize + 8)
        } else {
            ba.writeUInt32(UInt32(totalSize))
            ba.writeBytes(Data(type.utf8.prefix(4)))
        }
        ba.writeBytes(boxData)
        return ba.data
    }
}

/// MP4 Full Box (version + flags)
public struct MP4FullBox {
    public var type: String
    public var version: UInt8 = 0
    public var flags: UInt32 = 0 // 24-bit flags
    public var data: Data

    public init(type: String, version: UInt8 = 0, flags: UInt32 = 0, data: Data) {
        self.type = type
        self.version = version
        self.flags = flags
        self.data = data
    }

    public func encode() -> Data {
        let ba = ByteArray()
        let innerData = Data([version,
                              UInt8((flags >> 16) & 0xFF),
                              UInt8((flags >> 8) & 0xFF),
                              UInt8(flags & 0xFF)]) + data
        let totalSize = UInt32(8 + innerData.count)
        ba.writeUInt32(totalSize)
        ba.writeBytes(Data(type.utf8.prefix(4)))
        ba.writeBytes(innerData)
        return ba.data
    }
}

/// MP4 file reader - parses box structure
public final class MP4Reader {
    private let data: Data

    public init(data: Data) {
        self.data = data
    }

    /// Parse all top-level boxes
    public func readBoxes() throws -> [MP4Box] {
        try readBoxes(from: data, offset: 0)
    }

    /// Parse boxes from a data range
    public func readBoxes(from data: Data, offset: UInt64) throws -> [MP4Box] {
        var boxes: [MP4Box] = []
        var position: Int = 0

        while position + MP4Box.headerSize <= data.count {
            let ba = ByteArray(data: Data(data[position...]))

            let rawSize = try ba.readUInt32()
            let typeBytes = try ba.readBytes(4)
            guard let type = String(data: typeBytes, encoding: .ascii) else {
                throw MP4Error.invalidBoxType
            }

            var boxSize: UInt64
            var headerSize: Int = MP4Box.headerSize

            if rawSize == 1 {
                // 64-bit extended size
                guard position + MP4Box.largeHeaderSize <= data.count else { break }
                boxSize = try ba.readUInt64()
                headerSize = MP4Box.largeHeaderSize
            } else if rawSize == 0 {
                // Box extends to end of file
                boxSize = UInt64(data.count - position)
            } else {
                boxSize = UInt64(rawSize)
            }

            let dataSize = Int(boxSize) - headerSize
            guard dataSize >= 0, position + Int(boxSize) <= data.count else { break }

            let boxData = data.subdata(in: (position + headerSize)..<(position + Int(boxSize)))

            var box = MP4Box(type: type, size: boxSize, data: boxData)
            box.offset = offset + UInt64(position)
            boxes.append(box)

            position += Int(boxSize)
        }

        return boxes
    }

    /// Recursively find a box by type path (e.g., "moov/trak/mdia")
    public func findBox(path: String) throws -> MP4Box? {
        let components = path.split(separator: "/").map(String.init)
        var currentData = data
        var currentOffset: UInt64 = 0

        for (index, component) in components.enumerated() {
            let boxes = try readBoxes(from: currentData, offset: currentOffset)
            guard let box = boxes.first(where: { $0.type == component }) else {
                return nil
            }
            if index == components.count - 1 {
                return box
            }
            currentData = box.data
            currentOffset = box.offset + UInt64(box.size - UInt64(box.data.count))
        }
        return nil
    }
}

/// MP4 file writer - builds box structure
public final class MP4Writer {
    public init() {}

    /// Create a container box that wraps child box data
    public static func containerBox(type: String, children: [Data]) -> Data {
        let innerData = children.reduce(Data()) { $0 + $1 }
        let ba = ByteArray()
        let totalSize = UInt32(8 + innerData.count)
        ba.writeUInt32(totalSize)
        ba.writeBytes(Data(type.utf8.prefix(4)))
        ba.writeBytes(innerData)
        return ba.data
    }

    /// Create an ftyp box
    public static func ftypBox(majorBrand: String, minorVersion: UInt32, compatibleBrands: [String]) -> Data {
        let ba = ByteArray()
        let inner = ByteArray()
        inner.writeBytes(Data(majorBrand.utf8.prefix(4)))
        inner.writeUInt32(minorVersion)
        for brand in compatibleBrands {
            inner.writeBytes(Data(brand.utf8.prefix(4)))
        }
        let totalSize = UInt32(8 + inner.length)
        ba.writeUInt32(totalSize)
        ba.writeBytes(Data("ftyp".utf8))
        ba.writeBytes(inner.data)
        return ba.data
    }

    /// Create an mvhd (movie header) box
    public static func mvhdBox(
        timescale: UInt32,
        duration: UInt32,
        rate: UInt32 = 0x00010000,
        volume: UInt16 = 0x0100,
        nextTrackID: UInt32 = 2
    ) -> Data {
        let ba = ByteArray()
        // Version(1) + Flags(3)
        ba.writeUInt32(0)
        // Creation time
        ba.writeUInt32(0)
        // Modification time
        ba.writeUInt32(0)
        // Timescale
        ba.writeUInt32(timescale)
        // Duration
        ba.writeUInt32(duration)
        // Rate (1.0 = 0x00010000)
        ba.writeUInt32(rate)
        // Volume (1.0 = 0x0100)
        ba.writeUInt16(volume)
        // Reserved (10 bytes)
        ba.writeBytes(Data(repeating: 0, count: 10))
        // Matrix (36 bytes) - identity
        let matrix: [UInt32] = [0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000]
        for v in matrix { ba.writeUInt32(v) }
        // Pre-defined (24 bytes)
        ba.writeBytes(Data(repeating: 0, count: 24))
        // Next track ID
        ba.writeUInt32(nextTrackID)

        let totalSize = UInt32(8 + ba.length)
        let result = ByteArray()
        result.writeUInt32(totalSize)
        result.writeBytes(Data("mvhd".utf8))
        result.writeBytes(ba.data)
        return result.data
    }

    /// Create an mdat box
    public static func mdatBox(data: Data) -> Data {
        let ba = ByteArray()
        let totalSize = UInt32(8 + data.count)
        ba.writeUInt32(totalSize)
        ba.writeBytes(Data("mdat".utf8))
        ba.writeBytes(data)
        return ba.data
    }
}

/// Track information extracted from an MP4 file
public struct MP4TrackInfo {
    public var trackID: UInt32 = 0
    public var timescale: UInt32 = 0
    public var duration: UInt64 = 0
    public var mediaType: String = "" // "vide", "soun", "hint"
    public var codecType: String = "" // "avc1", "hev1", "mp4a"
    public var width: UInt16 = 0
    public var height: UInt16 = 0
    public var sampleRate: UInt32 = 0
    public var channelCount: UInt16 = 0

    public init() {}
}

public enum MP4Error: Error {
    case invalidBoxType
    case insufficientData
    case invalidFormat
}
