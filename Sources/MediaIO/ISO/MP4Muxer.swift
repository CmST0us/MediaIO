import Foundation

// MARK: - MP4 Sample

/// A single media sample (frame) to be muxed into MP4
public struct MP4Sample {
    /// The raw sample data (e.g., H.264 NALU, AAC frame)
    public var data: Data
    /// Duration of this sample in timescale units
    public var duration: UInt32
    /// Decode timestamp in timescale units
    public var dts: UInt64 = 0
    /// Composition time offset (CTS - DTS) in timescale units, used for B-frames
    public var compositionTimeOffset: Int32 = 0
    /// Whether this sample is a sync sample (keyframe)
    public var isSync: Bool = false

    public init(data: Data, duration: UInt32, isSync: Bool = false, compositionTimeOffset: Int32 = 0) {
        self.data = data
        self.duration = duration
        self.isSync = isSync
        self.compositionTimeOffset = compositionTimeOffset
    }
}

// MARK: - MP4 Track Configuration

/// Video track configuration
public struct MP4VideoTrackConfig {
    public var width: UInt16
    public var height: UInt16
    public var timescale: UInt32
    /// Codec FourCC: "avc1" for H.264, "hev1"/"hvc1" for H.265
    public var codec: String
    /// Decoder configuration record (e.g., AVCDecoderConfigurationRecord)
    public var decoderConfig: Data

    public init(width: UInt16, height: UInt16, timescale: UInt32 = 90000, codec: String = "avc1", decoderConfig: Data = Data()) {
        self.width = width
        self.height = height
        self.timescale = timescale
        self.codec = codec
        self.decoderConfig = decoderConfig
    }
}

/// Audio track configuration
public struct MP4AudioTrackConfig {
    public var sampleRate: UInt32
    public var channelCount: UInt16
    public var timescale: UInt32
    /// Codec FourCC: "mp4a" for AAC
    public var codec: String
    /// Audio specific config (e.g., AudioSpecificConfig for AAC)
    public var decoderConfig: Data

    public init(sampleRate: UInt32 = 44100, channelCount: UInt16 = 2, timescale: UInt32 = 44100, codec: String = "mp4a", decoderConfig: Data = Data()) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.timescale = timescale
        self.codec = codec
        self.decoderConfig = decoderConfig
    }
}

// MARK: - Sample Metadata (lightweight, kept in memory)

/// Lightweight metadata for a sample - no media data, only bookkeeping
struct SampleMetadata {
    var size: UInt32
    var duration: UInt32
    var compositionTimeOffset: Int32
    var isSync: Bool
    /// Offset of this sample's data within the mdat content (relative to mdat body start)
    var mdatOffset: UInt64
}

// MARK: - Track Metadata

/// Track state: holds config + lightweight sample metadata, no media data
final class TrackMetadata {
    let trackID: UInt32
    let timescale: UInt32
    let mediaType: String // "vide" or "soun"
    var videoConfig: MP4VideoTrackConfig?
    var audioConfig: MP4AudioTrackConfig?
    var samples: [SampleMetadata] = []

    init(trackID: UInt32, timescale: UInt32, mediaType: String) {
        self.trackID = trackID
        self.timescale = timescale
        self.mediaType = mediaType
    }

    var totalDuration: UInt64 {
        samples.reduce(0) { $0 + UInt64($1.duration) }
    }
}

// MARK: - MP4 Moov Builder (shared logic)

/// Builds the moov box from track metadata.
/// Used internally by MP4FileWriter.
enum MP4MoovBuilder {

    static func buildMoov(
        tracks: [TrackMetadata],
        nextTrackID: UInt32,
        movieTimescale: UInt32,
        mdatBodyOffset: UInt64
    ) -> Data {
        var movieDuration: UInt32 = 0
        for track in tracks {
            let d = UInt32(Double(track.totalDuration) / Double(track.timescale) * Double(movieTimescale))
            movieDuration = max(movieDuration, d)
        }

        let mvhd = MP4Writer.mvhdBox(timescale: movieTimescale, duration: movieDuration, nextTrackID: nextTrackID)
        var children: [Data] = [mvhd]
        for track in tracks {
            children.append(buildTrak(track: track, movieTimescale: movieTimescale, mdatBodyOffset: mdatBodyOffset))
        }
        return MP4Writer.containerBox(type: "moov", children: children)
    }

    // MARK: - trak

    static func buildTrak(track: TrackMetadata, movieTimescale: UInt32, mdatBodyOffset: UInt64) -> Data {
        let tkhd = buildTkhd(track: track, movieTimescale: movieTimescale)
        let mdia = buildMdia(track: track, mdatBodyOffset: mdatBodyOffset)
        return MP4Writer.containerBox(type: "trak", children: [tkhd, mdia])
    }

    static func buildTkhd(track: TrackMetadata, movieTimescale: UInt32) -> Data {
        let ba = ByteArray()
        ba.writeUInt8(0) // version
        ba.writeUInt24(0x000003) // flags: track_enabled | track_in_movie
        ba.writeUInt32(0) // creation time
        ba.writeUInt32(0) // modification time
        ba.writeUInt32(track.trackID)
        ba.writeUInt32(0) // reserved
        let dur = UInt32(Double(track.totalDuration) / Double(track.timescale) * Double(movieTimescale))
        ba.writeUInt32(dur)
        ba.writeBytes(Data(repeating: 0, count: 8)) // reserved
        ba.writeUInt16(0) // layer
        ba.writeUInt16(0) // alternate group
        ba.writeUInt16(track.mediaType == "soun" ? 0x0100 : 0) // volume
        ba.writeUInt16(0) // reserved
        let matrix: [UInt32] = [0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000]
        for v in matrix { ba.writeUInt32(v) }
        if let vc = track.videoConfig {
            ba.writeUInt32(UInt32(vc.width) << 16)
            ba.writeUInt32(UInt32(vc.height) << 16)
        } else {
            ba.writeUInt32(0); ba.writeUInt32(0)
        }
        return wrapBox(type: "tkhd", payload: ba.data)
    }

    // MARK: - mdia

    static func buildMdia(track: TrackMetadata, mdatBodyOffset: UInt64) -> Data {
        let mdhd = buildMdhd(track: track)
        let hdlr = buildHdlr(track: track)
        let minf = buildMinf(track: track, mdatBodyOffset: mdatBodyOffset)
        return MP4Writer.containerBox(type: "mdia", children: [mdhd, hdlr, minf])
    }

    static func buildMdhd(track: TrackMetadata) -> Data {
        let ba = ByteArray()
        ba.writeUInt32(0) // version + flags
        ba.writeUInt32(0) // creation time
        ba.writeUInt32(0) // modification time
        ba.writeUInt32(track.timescale)
        ba.writeUInt32(UInt32(min(track.totalDuration, UInt64(UInt32.max))))
        ba.writeUInt16(0x55C4) // language
        ba.writeUInt16(0)
        return wrapBox(type: "mdhd", payload: ba.data)
    }

    static func buildHdlr(track: TrackMetadata) -> Data {
        let ba = ByteArray()
        ba.writeUInt32(0)
        ba.writeUInt32(0)
        ba.writeBytes(Data(track.mediaType.utf8.prefix(4)))
        ba.writeBytes(Data(repeating: 0, count: 12))
        let name = track.mediaType == "vide" ? "VideoHandler" : "SoundHandler"
        ba.writeBytes(Data(name.utf8))
        ba.writeUInt8(0)
        return wrapBox(type: "hdlr", payload: ba.data)
    }

    // MARK: - minf

    static func buildMinf(track: TrackMetadata, mdatBodyOffset: UInt64) -> Data {
        var children: [Data] = []
        children.append(track.mediaType == "vide" ? buildVmhd() : buildSmhd())
        children.append(buildDinf())
        children.append(buildStbl(track: track, mdatBodyOffset: mdatBodyOffset))
        return MP4Writer.containerBox(type: "minf", children: children)
    }

    static func buildVmhd() -> Data {
        let ba = ByteArray()
        ba.writeUInt8(0); ba.writeUInt24(0x000001)
        ba.writeUInt16(0)
        ba.writeBytes(Data(repeating: 0, count: 6))
        return wrapBox(type: "vmhd", payload: ba.data)
    }

    static func buildSmhd() -> Data {
        let ba = ByteArray()
        ba.writeUInt32(0)
        ba.writeUInt16(0); ba.writeUInt16(0)
        return wrapBox(type: "smhd", payload: ba.data)
    }

    static func buildDinf() -> Data {
        let urlBa = ByteArray()
        urlBa.writeUInt8(0); urlBa.writeUInt24(0x000001)
        let urlBox = wrapBox(type: "url ", payload: urlBa.data)
        let drefBa = ByteArray()
        drefBa.writeUInt32(0); drefBa.writeUInt32(1)
        drefBa.writeBytes(urlBox)
        let dref = wrapBox(type: "dref", payload: drefBa.data)
        return MP4Writer.containerBox(type: "dinf", children: [dref])
    }

    // MARK: - stbl (sample table)

    static func buildStbl(track: TrackMetadata, mdatBodyOffset: UInt64) -> Data {
        var children: [Data] = []
        children.append(buildStsd(track: track))
        children.append(buildStts(samples: track.samples))
        if track.samples.contains(where: { $0.compositionTimeOffset != 0 }) {
            children.append(buildCtts(samples: track.samples))
        }
        children.append(buildStsc())
        children.append(buildStsz(samples: track.samples))
        // Use co64 for large files, stco for small files
        let needsCo64 = track.samples.contains { mdatBodyOffset + $0.mdatOffset > UInt64(UInt32.max) }
        if needsCo64 {
            children.append(buildCo64(samples: track.samples, mdatBodyOffset: mdatBodyOffset))
        } else {
            children.append(buildStco(samples: track.samples, mdatBodyOffset: mdatBodyOffset))
        }
        if track.mediaType == "vide" {
            children.append(buildStss(samples: track.samples))
        }
        return MP4Writer.containerBox(type: "stbl", children: children)
    }

    static func buildStsd(track: TrackMetadata) -> Data {
        let ba = ByteArray()
        ba.writeUInt32(0); ba.writeUInt32(1)
        if track.mediaType == "vide", let vc = track.videoConfig {
            ba.writeBytes(buildVideoSampleEntry(config: vc))
        } else if track.mediaType == "soun", let ac = track.audioConfig {
            ba.writeBytes(buildAudioSampleEntry(config: ac))
        }
        return wrapBox(type: "stsd", payload: ba.data)
    }

    static func buildVideoSampleEntry(config: MP4VideoTrackConfig) -> Data {
        let ba = ByteArray()
        ba.writeBytes(Data(repeating: 0, count: 6))
        ba.writeUInt16(1)
        ba.writeBytes(Data(repeating: 0, count: 16))
        ba.writeUInt16(config.width)
        ba.writeUInt16(config.height)
        ba.writeUInt32(0x00480000)
        ba.writeUInt32(0x00480000)
        ba.writeUInt32(0)
        ba.writeUInt16(1)
        ba.writeBytes(Data(repeating: 0, count: 32))
        ba.writeUInt16(0x0018)
        ba.writeInt16(-1)
        if !config.decoderConfig.isEmpty {
            let t = (config.codec == "hev1" || config.codec == "hvc1") ? "hvcC" : "avcC"
            ba.writeBytes(wrapBox(type: t, payload: config.decoderConfig))
        }
        return wrapBox(type: config.codec, payload: ba.data)
    }

    static func buildAudioSampleEntry(config: MP4AudioTrackConfig) -> Data {
        let ba = ByteArray()
        ba.writeBytes(Data(repeating: 0, count: 6))
        ba.writeUInt16(1)
        ba.writeBytes(Data(repeating: 0, count: 8))
        ba.writeUInt16(config.channelCount)
        ba.writeUInt16(16)
        ba.writeUInt16(0); ba.writeUInt16(0)
        ba.writeUInt32(config.sampleRate << 16)
        if config.codec == "mp4a" && !config.decoderConfig.isEmpty {
            ba.writeBytes(buildEsds(config: config))
        }
        return wrapBox(type: config.codec, payload: ba.data)
    }

    static func buildEsds(config: MP4AudioTrackConfig) -> Data {
        let ba = ByteArray()
        ba.writeUInt32(0)
        let dcs = config.decoderConfig.count
        ba.writeUInt8(0x03)
        ba.writeUInt8(UInt8(min(23 + dcs, 255)))
        ba.writeUInt16(1); ba.writeUInt8(0)
        ba.writeUInt8(0x04)
        ba.writeUInt8(UInt8(min(15 + dcs, 255)))
        ba.writeUInt8(0x40); ba.writeUInt8(0x15)
        ba.writeUInt24(0); ba.writeUInt32(0); ba.writeUInt32(0)
        ba.writeUInt8(0x05)
        ba.writeUInt8(UInt8(min(dcs, 255)))
        ba.writeBytes(config.decoderConfig)
        ba.writeUInt8(0x06); ba.writeUInt8(1); ba.writeUInt8(0x02)
        return wrapBox(type: "esds", payload: ba.data)
    }

    // MARK: - Sample table boxes

    static func buildStts(samples: [SampleMetadata]) -> Data {
        let ba = ByteArray()
        ba.writeUInt32(0)
        var entries: [(count: UInt32, delta: UInt32)] = []
        for s in samples {
            if let last = entries.last, last.delta == s.duration {
                entries[entries.count - 1].count += 1
            } else {
                entries.append((1, s.duration))
            }
        }
        ba.writeUInt32(UInt32(entries.count))
        for e in entries { ba.writeUInt32(e.count); ba.writeUInt32(e.delta) }
        return wrapBox(type: "stts", payload: ba.data)
    }

    static func buildCtts(samples: [SampleMetadata]) -> Data {
        let ba = ByteArray()
        ba.writeUInt8(1); ba.writeUInt24(0)
        var entries: [(count: UInt32, offset: Int32)] = []
        for s in samples {
            if let last = entries.last, last.offset == s.compositionTimeOffset {
                entries[entries.count - 1].count += 1
            } else {
                entries.append((1, s.compositionTimeOffset))
            }
        }
        ba.writeUInt32(UInt32(entries.count))
        for e in entries { ba.writeUInt32(e.count); ba.writeInt32(e.offset) }
        return wrapBox(type: "ctts", payload: ba.data)
    }

    static func buildStsc() -> Data {
        let ba = ByteArray()
        ba.writeUInt32(0); ba.writeUInt32(1)
        ba.writeUInt32(1); ba.writeUInt32(1); ba.writeUInt32(1)
        return wrapBox(type: "stsc", payload: ba.data)
    }

    static func buildStsz(samples: [SampleMetadata]) -> Data {
        let ba = ByteArray()
        ba.writeUInt32(0)
        let sizes = samples.map { $0.size }
        let allSame = !sizes.isEmpty && sizes.allSatisfy({ $0 == sizes[0] })
        if allSame && !sizes.isEmpty {
            ba.writeUInt32(sizes[0])
            ba.writeUInt32(UInt32(sizes.count))
        } else {
            ba.writeUInt32(0)
            ba.writeUInt32(UInt32(sizes.count))
            for s in sizes { ba.writeUInt32(s) }
        }
        return wrapBox(type: "stsz", payload: ba.data)
    }

    static func buildStco(samples: [SampleMetadata], mdatBodyOffset: UInt64) -> Data {
        let ba = ByteArray()
        ba.writeUInt32(0)
        ba.writeUInt32(UInt32(samples.count))
        for s in samples {
            ba.writeUInt32(UInt32(mdatBodyOffset + s.mdatOffset))
        }
        return wrapBox(type: "stco", payload: ba.data)
    }

    static func buildCo64(samples: [SampleMetadata], mdatBodyOffset: UInt64) -> Data {
        let ba = ByteArray()
        ba.writeUInt32(0)
        ba.writeUInt32(UInt32(samples.count))
        for s in samples {
            ba.writeUInt64(mdatBodyOffset + s.mdatOffset)
        }
        return wrapBox(type: "co64", payload: ba.data)
    }

    static func buildStss(samples: [SampleMetadata]) -> Data {
        let ba = ByteArray()
        ba.writeUInt32(0)
        let syncIndices = samples.enumerated().filter { $0.element.isSync }.map { UInt32($0.offset + 1) }
        ba.writeUInt32(UInt32(syncIndices.count))
        for i in syncIndices { ba.writeUInt32(i) }
        return wrapBox(type: "stss", payload: ba.data)
    }

    // MARK: - Helper

    static func wrapBox(type: String, payload: Data) -> Data {
        let ba = ByteArray()
        ba.writeUInt32(UInt32(8 + payload.count))
        ba.writeBytes(Data(type.utf8.prefix(4)))
        ba.writeBytes(payload)
        return ba.data
    }
}

// MARK: - MP4 File Writer (streaming, disk-based)

/// Streaming MP4 writer that writes sample data directly to disk.
///
/// Only lightweight sample metadata (offset, size, duration, flags) is kept in memory.
/// Media data (the actual bytes of each frame) is written to the file immediately,
/// keeping memory usage constant regardless of file size.
///
/// File layout: `ftyp | mdat (streaming) | moov`
/// After finalization, optionally call ``relocateMoov()`` to move moov before mdat
/// for progressive playback (equivalent to `ffmpeg -movflags +faststart`).
///
/// Usage:
/// ```
/// let writer = try MP4FileWriter(path: "/tmp/output.mp4")
/// let videoTrackID = writer.addVideoTrack(config: videoConfig)
/// try writer.writeSample(trackID: videoTrackID, sample: videoSample)
/// try writer.finalize()
/// // Optional: move moov to front for progressive playback
/// try MP4FileWriter.relocateMoov(path: "/tmp/output.mp4")
/// ```
public final class MP4FileWriter {
    private let fileHandle: FileHandle
    private let filePath: String
    private var tracks: [TrackMetadata] = []
    private var nextTrackID: UInt32 = 1
    public var movieTimescale: UInt32 = 1000

    /// Offset in the file where mdat body (sample data) begins.
    /// ftyp is written first, then mdat header, then sample data streams in.
    private var mdatBodyFileOffset: UInt64 = 0
    /// Current write position within mdat body (relative offset, = total bytes written so far)
    private var mdatContentSize: UInt64 = 0
    /// File offset where the mdat box header is written (needed to patch the size)
    private var mdatBoxFileOffset: UInt64 = 0
    private var headerWritten = false
    private var finalized = false

    /// Create a new MP4FileWriter writing to the given path.
    /// The file is created/truncated immediately.
    public init(path: String) throws {
        self.filePath = path
        FileManager.default.createFile(atPath: path, contents: nil)
        guard let fh = FileHandle(forWritingAtPath: path) else {
            throw MP4Error.invalidFormat
        }
        self.fileHandle = fh
    }

    deinit {
        fileHandle.closeFile()
    }

    // MARK: - Add Tracks

    @discardableResult
    public func addVideoTrack(config: MP4VideoTrackConfig) -> UInt32 {
        let track = TrackMetadata(trackID: nextTrackID, timescale: config.timescale, mediaType: "vide")
        track.videoConfig = config
        tracks.append(track)
        nextTrackID += 1
        return track.trackID
    }

    @discardableResult
    public func addAudioTrack(config: MP4AudioTrackConfig) -> UInt32 {
        let track = TrackMetadata(trackID: nextTrackID, timescale: config.timescale, mediaType: "soun")
        track.audioConfig = config
        tracks.append(track)
        nextTrackID += 1
        return track.trackID
    }

    // MARK: - Write Header

    /// Write the ftyp box and begin the mdat box.
    /// Called automatically on the first ``writeSample`` if not called explicitly.
    public func writeHeader() throws {
        guard !headerWritten else { return }
        headerWritten = true

        let ftyp = MP4Writer.ftypBox(majorBrand: "isom", minorVersion: 512, compatibleBrands: ["isom", "iso2", "avc1", "mp41"])
        fileHandle.write(ftyp)

        // Write mdat header with placeholder size (0 = extends to EOF).
        // We'll patch this in finalize().
        mdatBoxFileOffset = UInt64(ftyp.count)
        let mdatHeader = ByteArray()
        mdatHeader.writeUInt32(0) // placeholder size, patched later
        mdatHeader.writeBytes(Data("mdat".utf8))
        fileHandle.write(mdatHeader.data)

        mdatBodyFileOffset = mdatBoxFileOffset + 8
        mdatContentSize = 0
    }

    // MARK: - Write Sample (streaming)

    /// Write a sample's media data directly to disk.
    /// Only the lightweight metadata is kept in memory.
    public func writeSample(trackID: UInt32, sample: MP4Sample) throws {
        guard !finalized else { throw MP4Error.invalidFormat }
        if !headerWritten { try writeHeader() }

        guard let track = tracks.first(where: { $0.trackID == trackID }) else { return }

        let meta = SampleMetadata(
            size: UInt32(sample.data.count),
            duration: sample.duration,
            compositionTimeOffset: sample.compositionTimeOffset,
            isSync: sample.isSync,
            mdatOffset: mdatContentSize
        )
        track.samples.append(meta)

        // Write media data to file immediately - no in-memory accumulation
        fileHandle.write(sample.data)
        mdatContentSize += UInt64(sample.data.count)
    }

    /// Current number of samples written to a track
    public func sampleCount(trackID: UInt32) -> Int {
        tracks.first(where: { $0.trackID == trackID })?.samples.count ?? 0
    }

    /// Total bytes of media data written so far
    public var bytesWritten: UInt64 { mdatContentSize }

    // MARK: - Finalize

    /// Finalize the MP4 file: patch mdat size and append moov box.
    /// After this call, no more samples can be written.
    public func finalize() throws {
        guard !finalized else { return }
        guard headerWritten else {
            // Nothing was written
            try writeHeader()
        }
        finalized = true

        // Patch mdat box size
        let mdatTotalSize = 8 + mdatContentSize
        if mdatTotalSize <= UInt64(UInt32.max) {
            // Standard 32-bit size
            let sizeData = ByteArray()
            sizeData.writeUInt32(UInt32(mdatTotalSize))
            fileHandle.seek(toFileOffset: mdatBoxFileOffset)
            fileHandle.write(sizeData.data)
        } else {
            // For files > 4GB we'd need to rewrite with extended size header.
            // For now, leave size=0 (meaning "to end of file") which most players support.
            // The moov will still be appended after mdat.
        }

        // Seek to end of mdat
        fileHandle.seekToEndOfFile()

        // Build and write moov
        let moovData = MP4MoovBuilder.buildMoov(
            tracks: tracks,
            nextTrackID: nextTrackID,
            movieTimescale: movieTimescale,
            mdatBodyOffset: mdatBodyFileOffset
        )
        fileHandle.write(moovData)
        fileHandle.synchronizeFile()
    }

    // MARK: - Faststart (moov relocation)

    /// Relocate moov box to before mdat for progressive playback.
    /// This is equivalent to `ffmpeg -movflags +faststart`.
    ///
    /// Reads the existing file, finds moov at the end, and rewrites the file
    /// with moov placed before mdat, adjusting all chunk offsets.
    ///
    /// Call this after ``finalize()``.
    public static func relocateMoov(path: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let reader = MP4Reader(data: data)
        let boxes = try reader.readBoxes()

        // Find ftyp, mdat, moov
        guard let ftypBox = boxes.first(where: { $0.type == "ftyp" }),
              let mdatBox = boxes.first(where: { $0.type == "mdat" }),
              let moovBox = boxes.first(where: { $0.type == "moov" }) else {
            throw MP4Error.invalidFormat
        }

        // If moov is already before mdat, nothing to do
        if moovBox.offset < mdatBox.offset { return }

        // Encode moov box for measuring
        let moovEncoded = moovBox.encode()
        let moovSize = moovEncoded.count

        // Adjust chunk offsets in moov: all offsets shift by +moovSize
        // (because moov is being inserted between ftyp and mdat)
        let adjustedMoov = try adjustChunkOffsets(moovData: moovBox.data, delta: Int64(moovSize))
        let adjustedMoovBox = ByteArray()
        adjustedMoovBox.writeUInt32(UInt32(8 + adjustedMoov.count))
        adjustedMoovBox.writeBytes(Data("moov".utf8))
        adjustedMoovBox.writeBytes(adjustedMoov)

        // Rewrite: ftyp + moov (adjusted) + mdat
        let ftypEncoded = ftypBox.encode()
        let mdatEncoded = mdatBox.encode()

        var output = Data()
        output.reserveCapacity(ftypEncoded.count + adjustedMoovBox.data.count + mdatEncoded.count)
        output.append(ftypEncoded)
        output.append(adjustedMoovBox.data)
        output.append(mdatEncoded)

        try output.write(to: URL(fileURLWithPath: path))
    }

    /// Adjust stco/co64 chunk offsets within moov data by a delta.
    private static func adjustChunkOffsets(moovData: Data, delta: Int64) throws -> Data {
        var result = moovData
        // We need to find and patch stco and co64 boxes within the moov hierarchy.
        // Walk the box tree recursively.
        try patchChunkOffsets(in: &result, offset: 0, delta: delta)
        return result
    }

    /// Recursively walk boxes in data, patching stco/co64 entries.
    private static func patchChunkOffsets(in data: inout Data, offset: Int, delta: Int64) throws {
        var pos = offset
        while pos + 8 <= data.count {
            let rawSize = UInt32(data: Data(data[pos..<pos+4])).bigEndian
            guard rawSize >= 8 else { break }
            let size = Int(rawSize)
            guard pos + size <= data.count else { break }

            let typeData = Data(data[pos+4..<pos+8])
            let type = String(data: typeData, encoding: .ascii) ?? ""

            if type == "stco" {
                // stco: version(4) + count(4) + offsets(4 each)
                let headerStart = pos + 8
                guard headerStart + 8 <= data.count else { break }
                let count = Int(UInt32(data: Data(data[headerStart+4..<headerStart+8])).bigEndian)
                for i in 0..<count {
                    let entryPos = headerStart + 8 + i * 4
                    guard entryPos + 4 <= data.count else { break }
                    let oldOffset = UInt32(data: Data(data[entryPos..<entryPos+4])).bigEndian
                    let newOffset = UInt32(Int64(oldOffset) + delta)
                    let bytes = newOffset.bigEndian.data
                    data.replaceSubrange(entryPos..<entryPos+4, with: bytes)
                }
            } else if type == "co64" {
                let headerStart = pos + 8
                guard headerStart + 8 <= data.count else { break }
                let count = Int(UInt32(data: Data(data[headerStart+4..<headerStart+8])).bigEndian)
                for i in 0..<count {
                    let entryPos = headerStart + 8 + i * 8
                    guard entryPos + 8 <= data.count else { break }
                    let oldOffset = UInt64(data: Data(data[entryPos..<entryPos+8])).bigEndian
                    let newOffset = UInt64(Int64(oldOffset) + delta)
                    let bytes = newOffset.bigEndian.data
                    data.replaceSubrange(entryPos..<entryPos+8, with: bytes)
                }
            } else if ["moov", "trak", "mdia", "minf", "stbl"].contains(type) {
                // Container box: recurse into children
                try patchChunkOffsets(in: &data, offset: pos + 8, delta: delta)
            }

            pos += size
        }
    }
}
