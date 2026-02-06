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

// MARK: - MP4 Muxer

/// Muxes audio/video samples into a complete MP4 file (ISO 14496-12)
///
/// Usage:
/// ```
/// let muxer = MP4Muxer()
/// let videoTrackID = muxer.addVideoTrack(config: videoConfig)
/// let audioTrackID = muxer.addAudioTrack(config: audioConfig)
/// muxer.addSample(trackID: videoTrackID, sample: videoSample)
/// muxer.addSample(trackID: audioTrackID, sample: audioSample)
/// let mp4Data = muxer.finalize()
/// ```
public final class MP4Muxer {
    /// Internal track state
    private final class Track {
        let trackID: UInt32
        let timescale: UInt32
        let mediaType: String // "vide" or "soun"
        var videoConfig: MP4VideoTrackConfig?
        var audioConfig: MP4AudioTrackConfig?
        var samples: [MP4Sample] = []

        init(trackID: UInt32, timescale: UInt32, mediaType: String) {
            self.trackID = trackID
            self.timescale = timescale
            self.mediaType = mediaType
        }

        var totalDuration: UInt64 {
            samples.reduce(0) { $0 + UInt64($1.duration) }
        }

        var totalDataSize: Int {
            samples.reduce(0) { $0 + $1.data.count }
        }
    }

    private var tracks: [Track] = []
    private var nextTrackID: UInt32 = 1
    /// Movie-level timescale (typically 1000 for millisecond precision)
    public var movieTimescale: UInt32 = 1000

    public init() {}

    // MARK: - Add Tracks

    /// Add a video track and return its track ID
    @discardableResult
    public func addVideoTrack(config: MP4VideoTrackConfig) -> UInt32 {
        let track = Track(trackID: nextTrackID, timescale: config.timescale, mediaType: "vide")
        track.videoConfig = config
        tracks.append(track)
        nextTrackID += 1
        return track.trackID
    }

    /// Add an audio track and return its track ID
    @discardableResult
    public func addAudioTrack(config: MP4AudioTrackConfig) -> UInt32 {
        let track = Track(trackID: nextTrackID, timescale: config.timescale, mediaType: "soun")
        track.audioConfig = config
        tracks.append(track)
        nextTrackID += 1
        return track.trackID
    }

    // MARK: - Add Samples

    /// Add a sample (frame) to a track
    public func addSample(trackID: UInt32, sample: MP4Sample) {
        guard let track = tracks.first(where: { $0.trackID == trackID }) else { return }
        track.samples.append(sample)
    }

    // MARK: - Finalize

    /// Finalize and generate the complete MP4 file data
    /// Layout: ftyp + moov + mdat
    public func finalize() -> Data {
        // Calculate mdat offset: ftyp size + moov size
        // We need to build moov first to know its size, but moov needs chunk offsets
        // which depend on mdat position. We solve this in two passes.

        let ftypData = buildFtyp()

        // Build mdat content
        var mdatContent = Data()
        var sampleOffsets: [[UInt32]] = [] // per-track offsets within mdat content

        for track in tracks {
            var trackOffsets: [UInt32] = []
            for sample in track.samples {
                trackOffsets.append(UInt32(mdatContent.count))
                mdatContent.append(sample.data)
            }
            sampleOffsets.append(trackOffsets)
        }

        // mdat header is 8 bytes
        let mdatHeaderSize: UInt32 = 8
        // moov placeholder - build once to get size
        let moovPlaceholder = buildMoov(mdatBaseOffset: 0, sampleOffsets: sampleOffsets)
        let moovSize = UInt32(moovPlaceholder.count)

        // Real mdat base offset = ftyp + moov + mdat header
        let mdatBaseOffset = UInt32(ftypData.count) + moovSize + mdatHeaderSize

        // Rebuild moov with correct offsets
        let moovData = buildMoov(mdatBaseOffset: mdatBaseOffset, sampleOffsets: sampleOffsets)

        // Build mdat
        let mdatData = buildMdat(content: mdatContent)

        return ftypData + moovData + mdatData
    }

    // MARK: - Box Builders

    /// Build ftyp box
    private func buildFtyp() -> Data {
        MP4Writer.ftypBox(
            majorBrand: "isom",
            minorVersion: 512,
            compatibleBrands: ["isom", "iso2", "avc1", "mp41"]
        )
    }

    /// Build mdat box
    private func buildMdat(content: Data) -> Data {
        MP4Writer.mdatBox(data: content)
    }

    /// Build complete moov box
    private func buildMoov(mdatBaseOffset: UInt32, sampleOffsets: [[UInt32]]) -> Data {
        // Movie duration in movie timescale
        var movieDuration: UInt32 = 0
        for track in tracks {
            let trackDurationInMovieTimescale = UInt32(
                Double(track.totalDuration) / Double(track.timescale) * Double(movieTimescale)
            )
            movieDuration = max(movieDuration, trackDurationInMovieTimescale)
        }

        let mvhd = buildMvhd(duration: movieDuration)
        var children: [Data] = [mvhd]

        for (index, track) in tracks.enumerated() {
            let offsets = index < sampleOffsets.count ? sampleOffsets[index] : []
            children.append(buildTrak(track: track, mdatBaseOffset: mdatBaseOffset, sampleOffsets: offsets))
        }

        return MP4Writer.containerBox(type: "moov", children: children)
    }

    /// Build mvhd box (movie header)
    private func buildMvhd(duration: UInt32) -> Data {
        MP4Writer.mvhdBox(
            timescale: movieTimescale,
            duration: duration,
            nextTrackID: nextTrackID
        )
    }

    /// Build trak box (track)
    private func buildTrak(track: Track, mdatBaseOffset: UInt32, sampleOffsets: [UInt32]) -> Data {
        let tkhd = buildTkhd(track: track)
        let mdia = buildMdia(track: track, mdatBaseOffset: mdatBaseOffset, sampleOffsets: sampleOffsets)
        return MP4Writer.containerBox(type: "trak", children: [tkhd, mdia])
    }

    /// Build tkhd box (track header)
    private func buildTkhd(track: Track) -> Data {
        let ba = ByteArray()
        // Version(1) + Flags(3): track_enabled | track_in_movie
        ba.writeUInt8(0) // version
        ba.writeUInt24(0x000003) // flags: track_enabled | track_in_movie
        // Creation time
        ba.writeUInt32(0)
        // Modification time
        ba.writeUInt32(0)
        // Track ID
        ba.writeUInt32(track.trackID)
        // Reserved
        ba.writeUInt32(0)
        // Duration in movie timescale
        let durationInMovieTimescale = UInt32(
            Double(track.totalDuration) / Double(track.timescale) * Double(movieTimescale)
        )
        ba.writeUInt32(durationInMovieTimescale)
        // Reserved (8 bytes)
        ba.writeBytes(Data(repeating: 0, count: 8))
        // Layer
        ba.writeUInt16(0)
        // Alternate group
        ba.writeUInt16(0)
        // Volume: 0x0100 for audio, 0 for video
        ba.writeUInt16(track.mediaType == "soun" ? 0x0100 : 0)
        // Reserved
        ba.writeUInt16(0)
        // Matrix (36 bytes) - identity
        let matrix: [UInt32] = [0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000]
        for v in matrix { ba.writeUInt32(v) }
        // Width / Height in 16.16 fixed point
        if let vc = track.videoConfig {
            ba.writeUInt32(UInt32(vc.width) << 16)
            ba.writeUInt32(UInt32(vc.height) << 16)
        } else {
            ba.writeUInt32(0)
            ba.writeUInt32(0)
        }

        return wrapBox(type: "tkhd", payload: ba.data)
    }

    /// Build mdia box (media)
    private func buildMdia(track: Track, mdatBaseOffset: UInt32, sampleOffsets: [UInt32]) -> Data {
        let mdhd = buildMdhd(track: track)
        let hdlr = buildHdlr(track: track)
        let minf = buildMinf(track: track, mdatBaseOffset: mdatBaseOffset, sampleOffsets: sampleOffsets)
        return MP4Writer.containerBox(type: "mdia", children: [mdhd, hdlr, minf])
    }

    /// Build mdhd box (media header)
    private func buildMdhd(track: Track) -> Data {
        let ba = ByteArray()
        // Version(1) + Flags(3)
        ba.writeUInt32(0)
        // Creation time
        ba.writeUInt32(0)
        // Modification time
        ba.writeUInt32(0)
        // Timescale
        ba.writeUInt32(track.timescale)
        // Duration in media timescale
        ba.writeUInt32(UInt32(min(track.totalDuration, UInt64(UInt32.max))))
        // Language (undetermined = 0x55C4)
        ba.writeUInt16(0x55C4)
        // Pre-defined
        ba.writeUInt16(0)

        return wrapBox(type: "mdhd", payload: ba.data)
    }

    /// Build hdlr box (handler reference)
    private func buildHdlr(track: Track) -> Data {
        let ba = ByteArray()
        // Version(1) + Flags(3)
        ba.writeUInt32(0)
        // Pre-defined
        ba.writeUInt32(0)
        // Handler type
        ba.writeBytes(Data(track.mediaType.utf8.prefix(4)))
        // Reserved (12 bytes)
        ba.writeBytes(Data(repeating: 0, count: 12))
        // Name (null-terminated)
        let name = track.mediaType == "vide" ? "VideoHandler" : "SoundHandler"
        ba.writeBytes(Data(name.utf8))
        ba.writeUInt8(0) // null terminator

        return wrapBox(type: "hdlr", payload: ba.data)
    }

    /// Build minf box (media information)
    private func buildMinf(track: Track, mdatBaseOffset: UInt32, sampleOffsets: [UInt32]) -> Data {
        var children: [Data] = []

        // Media header: vmhd for video, smhd for audio
        if track.mediaType == "vide" {
            children.append(buildVmhd())
        } else {
            children.append(buildSmhd())
        }

        // dinf (data information)
        children.append(buildDinf())

        // stbl (sample table)
        children.append(buildStbl(track: track, mdatBaseOffset: mdatBaseOffset, sampleOffsets: sampleOffsets))

        return MP4Writer.containerBox(type: "minf", children: children)
    }

    /// Build vmhd box (video media header)
    private func buildVmhd() -> Data {
        let ba = ByteArray()
        // Version(1) + Flags(3): flag = 1
        ba.writeUInt8(0)
        ba.writeUInt24(0x000001)
        // Graphics mode
        ba.writeUInt16(0)
        // Opcolor (6 bytes)
        ba.writeBytes(Data(repeating: 0, count: 6))

        return wrapBox(type: "vmhd", payload: ba.data)
    }

    /// Build smhd box (sound media header)
    private func buildSmhd() -> Data {
        let ba = ByteArray()
        // Version(1) + Flags(3)
        ba.writeUInt32(0)
        // Balance
        ba.writeUInt16(0)
        // Reserved
        ba.writeUInt16(0)

        return wrapBox(type: "smhd", payload: ba.data)
    }

    /// Build dinf + dref boxes (data information)
    private func buildDinf() -> Data {
        // dref with one "url " entry (self-contained)
        let urlBa = ByteArray()
        // Version(1) + Flags(3): flag = 1 (self-contained)
        urlBa.writeUInt8(0)
        urlBa.writeUInt24(0x000001)
        let urlBox = wrapBox(type: "url ", payload: urlBa.data)

        let drefBa = ByteArray()
        // Version(1) + Flags(3)
        drefBa.writeUInt32(0)
        // Entry count
        drefBa.writeUInt32(1)
        drefBa.writeBytes(urlBox)
        let dref = wrapBox(type: "dref", payload: drefBa.data)

        return MP4Writer.containerBox(type: "dinf", children: [dref])
    }

    /// Build stbl box (sample table)
    private func buildStbl(track: Track, mdatBaseOffset: UInt32, sampleOffsets: [UInt32]) -> Data {
        var children: [Data] = []

        // stsd (sample description)
        children.append(buildStsd(track: track))
        // stts (decoding time to sample)
        children.append(buildStts(track: track))
        // ctts (composition time to sample) - only if needed
        if track.samples.contains(where: { $0.compositionTimeOffset != 0 }) {
            children.append(buildCtts(track: track))
        }
        // stsc (sample to chunk)
        children.append(buildStsc(track: track))
        // stsz (sample sizes)
        children.append(buildStsz(track: track))
        // stco (chunk offsets)
        children.append(buildStco(track: track, mdatBaseOffset: mdatBaseOffset, sampleOffsets: sampleOffsets))
        // stss (sync samples) - only for video tracks
        if track.mediaType == "vide" {
            children.append(buildStss(track: track))
        }

        return MP4Writer.containerBox(type: "stbl", children: children)
    }

    /// Build stsd box (sample description)
    private func buildStsd(track: Track) -> Data {
        let ba = ByteArray()
        // Version(1) + Flags(3)
        ba.writeUInt32(0)
        // Entry count
        ba.writeUInt32(1)

        if track.mediaType == "vide", let vc = track.videoConfig {
            ba.writeBytes(buildVideoSampleEntry(config: vc))
        } else if track.mediaType == "soun", let ac = track.audioConfig {
            ba.writeBytes(buildAudioSampleEntry(config: ac))
        }

        return wrapBox(type: "stsd", payload: ba.data)
    }

    /// Build video sample entry (e.g., avc1)
    private func buildVideoSampleEntry(config: MP4VideoTrackConfig) -> Data {
        let ba = ByteArray()
        // Reserved (6 bytes)
        ba.writeBytes(Data(repeating: 0, count: 6))
        // Data reference index
        ba.writeUInt16(1)
        // Pre-defined + Reserved (16 bytes)
        ba.writeBytes(Data(repeating: 0, count: 16))
        // Width
        ba.writeUInt16(config.width)
        // Height
        ba.writeUInt16(config.height)
        // Horizontal resolution (72 dpi = 0x00480000)
        ba.writeUInt32(0x00480000)
        // Vertical resolution (72 dpi = 0x00480000)
        ba.writeUInt32(0x00480000)
        // Reserved
        ba.writeUInt32(0)
        // Frame count
        ba.writeUInt16(1)
        // Compressor name (32 bytes, padded)
        ba.writeBytes(Data(repeating: 0, count: 32))
        // Depth
        ba.writeUInt16(0x0018) // 24-bit color
        // Pre-defined
        ba.writeInt16(-1)

        // avcC or hvcC box (decoder configuration)
        if !config.decoderConfig.isEmpty {
            let configBoxType = config.codec == "hev1" || config.codec == "hvc1" ? "hvcC" : "avcC"
            ba.writeBytes(wrapBox(type: configBoxType, payload: config.decoderConfig))
        }

        return wrapBox(type: config.codec, payload: ba.data)
    }

    /// Build audio sample entry (e.g., mp4a)
    private func buildAudioSampleEntry(config: MP4AudioTrackConfig) -> Data {
        let ba = ByteArray()
        // Reserved (6 bytes)
        ba.writeBytes(Data(repeating: 0, count: 6))
        // Data reference index
        ba.writeUInt16(1)
        // Reserved (8 bytes)
        ba.writeBytes(Data(repeating: 0, count: 8))
        // Channel count
        ba.writeUInt16(config.channelCount)
        // Sample size (bits)
        ba.writeUInt16(16)
        // Pre-defined
        ba.writeUInt16(0)
        // Reserved
        ba.writeUInt16(0)
        // Sample rate in 16.16 fixed point
        ba.writeUInt32(config.sampleRate << 16)

        // esds box for AAC
        if config.codec == "mp4a" && !config.decoderConfig.isEmpty {
            ba.writeBytes(buildEsds(config: config))
        }

        return wrapBox(type: config.codec, payload: ba.data)
    }

    /// Build esds box for AAC audio
    private func buildEsds(config: MP4AudioTrackConfig) -> Data {
        let ba = ByteArray()
        // Version(1) + Flags(3)
        ba.writeUInt32(0)

        // ES_Descriptor
        ba.writeUInt8(0x03) // tag
        let decoderConfigSize = config.decoderConfig.count
        let esDescLen = 23 + decoderConfigSize
        ba.writeUInt8(UInt8(min(esDescLen, 255)))
        ba.writeUInt16(1) // ES_ID
        ba.writeUInt8(0)  // stream priority

        // DecoderConfigDescriptor
        ba.writeUInt8(0x04) // tag
        ba.writeUInt8(UInt8(min(15 + decoderConfigSize, 255)))
        ba.writeUInt8(0x40) // objectTypeIndication: Audio ISO/IEC 14496-3 (AAC)
        ba.writeUInt8(0x15) // streamType: audio stream
        ba.writeUInt24(0)   // bufferSizeDB
        ba.writeUInt32(0)   // maxBitrate
        ba.writeUInt32(0)   // avgBitrate

        // DecoderSpecificInfo
        ba.writeUInt8(0x05) // tag
        ba.writeUInt8(UInt8(min(decoderConfigSize, 255)))
        ba.writeBytes(config.decoderConfig)

        // SLConfigDescriptor
        ba.writeUInt8(0x06) // tag
        ba.writeUInt8(1)
        ba.writeUInt8(0x02) // predefined: MP4

        return wrapBox(type: "esds", payload: ba.data)
    }

    /// Build stts box (decoding time to sample)
    /// Groups consecutive samples with the same duration into entries
    private func buildStts(track: Track) -> Data {
        let ba = ByteArray()
        // Version(1) + Flags(3)
        ba.writeUInt32(0)

        // Build run-length encoded entries
        var entries: [(count: UInt32, delta: UInt32)] = []
        for sample in track.samples {
            if let last = entries.last, last.delta == sample.duration {
                entries[entries.count - 1].count += 1
            } else {
                entries.append((count: 1, delta: sample.duration))
            }
        }

        ba.writeUInt32(UInt32(entries.count))
        for entry in entries {
            ba.writeUInt32(entry.count)
            ba.writeUInt32(entry.delta)
        }

        return wrapBox(type: "stts", payload: ba.data)
    }

    /// Build ctts box (composition time to sample)
    private func buildCtts(track: Track) -> Data {
        let ba = ByteArray()
        // Version 1 allows negative offsets
        ba.writeUInt8(1) // version
        ba.writeUInt24(0) // flags

        var entries: [(count: UInt32, offset: Int32)] = []
        for sample in track.samples {
            if let last = entries.last, last.offset == sample.compositionTimeOffset {
                entries[entries.count - 1].count += 1
            } else {
                entries.append((count: 1, offset: sample.compositionTimeOffset))
            }
        }

        ba.writeUInt32(UInt32(entries.count))
        for entry in entries {
            ba.writeUInt32(entry.count)
            ba.writeInt32(entry.offset)
        }

        return wrapBox(type: "ctts", payload: ba.data)
    }

    /// Build stsc box (sample to chunk)
    /// Simple strategy: one sample per chunk
    private func buildStsc(track: Track) -> Data {
        let ba = ByteArray()
        // Version(1) + Flags(3)
        ba.writeUInt32(0)
        // Entry count: 1 entry covering all chunks (each chunk has 1 sample)
        ba.writeUInt32(1)
        // First chunk
        ba.writeUInt32(1)
        // Samples per chunk
        ba.writeUInt32(1)
        // Sample description index
        ba.writeUInt32(1)

        return wrapBox(type: "stsc", payload: ba.data)
    }

    /// Build stsz box (sample sizes)
    private func buildStsz(track: Track) -> Data {
        let ba = ByteArray()
        // Version(1) + Flags(3)
        ba.writeUInt32(0)

        // Check if all samples are the same size
        let sizes = track.samples.map { UInt32($0.data.count) }
        let allSameSize = sizes.count > 0 && sizes.allSatisfy({ $0 == sizes[0] })

        if allSameSize && !sizes.isEmpty {
            // Default sample size
            ba.writeUInt32(sizes[0])
            // Sample count
            ba.writeUInt32(UInt32(sizes.count))
        } else {
            // Default sample size = 0 (variable)
            ba.writeUInt32(0)
            // Sample count
            ba.writeUInt32(UInt32(sizes.count))
            for size in sizes {
                ba.writeUInt32(size)
            }
        }

        return wrapBox(type: "stsz", payload: ba.data)
    }

    /// Build stco box (chunk offsets)
    private func buildStco(track: Track, mdatBaseOffset: UInt32, sampleOffsets: [UInt32]) -> Data {
        let ba = ByteArray()
        // Version(1) + Flags(3)
        ba.writeUInt32(0)
        // Entry count
        ba.writeUInt32(UInt32(sampleOffsets.count))
        // Each chunk offset (one sample per chunk)
        for offset in sampleOffsets {
            ba.writeUInt32(mdatBaseOffset + offset)
        }

        return wrapBox(type: "stco", payload: ba.data)
    }

    /// Build stss box (sync sample table) - lists keyframe indices
    private func buildStss(track: Track) -> Data {
        let ba = ByteArray()
        // Version(1) + Flags(3)
        ba.writeUInt32(0)

        let syncIndices = track.samples.enumerated()
            .filter { $0.element.isSync }
            .map { UInt32($0.offset + 1) } // 1-based

        ba.writeUInt32(UInt32(syncIndices.count))
        for index in syncIndices {
            ba.writeUInt32(index)
        }

        return wrapBox(type: "stss", payload: ba.data)
    }

    // MARK: - Helpers

    /// Wrap payload data into a box with type header
    private func wrapBox(type: String, payload: Data) -> Data {
        let ba = ByteArray()
        let totalSize = UInt32(8 + payload.count)
        ba.writeUInt32(totalSize)
        ba.writeBytes(Data(type.utf8.prefix(4)))
        ba.writeBytes(payload)
        return ba.data
    }
}
