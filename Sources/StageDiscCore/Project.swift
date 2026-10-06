import Foundation

public enum DiscFormat: String, Codable, CaseIterable, Identifiable {
    case bluray, uhd
    public var id: String { rawValue }
    public var label: String { self == .bluray ? "Blu-ray · 1080p SDR" : "UHD · 2160p (experimental)" }
}
public enum Capacity: Int64, Codable, CaseIterable, Identifiable {
    case bd25 = 25_000_000_000, bd50 = 50_000_000_000, bd100 = 100_000_000_000
    public var id: Int64 { rawValue }
    public var label: String { "\(rawValue / 1_000_000_000) GB" }
}
public enum VideoMode: String, Codable, CaseIterable, Identifiable {
    case encode, prepared
    public var id: String { rawValue }
    public var label: String { self == .encode ? "Encode from source" : "Use prepared disc video" }
}
public enum AudioMode: String, Codable, CaseIterable, Identifiable {
    case pcm, pcm16, pcm96, pcm192, ac3, preserve
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .pcm: return "LPCM · 24-bit / 48 kHz"
        case .pcm16: return "LPCM · 16-bit / 48 kHz"
        case .pcm96: return "LPCM · 24-bit / 96 kHz"
        case .pcm192: return "LPCM · 24-bit / 192 kHz"
        case .ac3: return "Dolby Digital · 640 kb/s"
        case .preserve: return "Copy prepared DTS / Dolby bitstream"
        }
    }
    public var isPCM: Bool { ![.ac3, .preserve].contains(self) }
    public var sampleRate: Int { self == .pcm96 ? 96_000 : self == .pcm192 ? 192_000 : 48_000 }
    public var bitDepth: Int { self == .pcm16 ? 16 : 24 }
}
public enum ContentMode: String, Codable, CaseIterable, Identifiable {
    case film, album
    public var id: String { rawValue }
    public var label: String { self == .film ? "Concert film & extras" : "Audio album & bonus content" }
}
public struct AudioTrack: Codable, Identifiable {
    public var id = UUID()
    public var name: String
    public var path: String
    public var streamIndex: Int
    public var media: MediaInfo
    public var mode: AudioMode
    public var language = "und"
    public var delayMS = 0
    public init(name: String, path: String, streamIndex: Int, media: MediaInfo, mode: AudioMode) {
        self.name = name; self.path = path; self.streamIndex = streamIndex; self.media = media; self.mode = mode
        self.language = media.audio.first { $0.index == streamIndex }?.language ?? "und"
    }
    public var stream: MediaStream? { media.audio.first { $0.index == streamIndex } }
    public var bitRate: Double {
        guard let stream else { return 0 }
        if mode.isPCM { let channels = stream.channels ?? 2; return Double((channels + channels % 2) * mode.sampleRate * mode.bitDepth) }
        if mode == .ac3 { return 640_000 }
        // Use the format maximum for unknown VBR peaks when budgeting the disc transport.
        switch stream.codec { case "truehd": return 19_280_000; case "dts": return (stream.profile ?? "").contains("HD") ? 24_500_000 : 1_524_000; case "eac3": return 4_736_000; default: return 640_000 }
    }
}
public struct Chapter: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var name: String
    public var seconds: Double
    public init(name: String, seconds: Double) { self.name = name; self.seconds = seconds }
}
public struct MediaStream: Codable, Identifiable {
    public var index: Int
    public var kind: String
    public var codec: String
    public var width: Int?
    public var height: Int?
    public var pixelFormat: String?
    public var frameRate: Double?
    public var fieldOrder: String?
    public var colorTransfer: String?
    public var colorPrimaries: String?
    public var colorSpace: String?
    public var channels: Int?
    public var channelLayout: String?
    public var sampleRate: Int?
    public var language: String?
    public var startTime: Double? = nil
    public var profile: String? = nil
    public var bitRate: Int64? = nil
    public var id: Int { index }
    public var isHDR: Bool { ["smpte2084", "arib-std-b67"].contains(colorTransfer ?? "") || colorPrimaries == "bt2020" }
}
public struct MediaInfo: Codable {
    public var duration: Double
    public var size: Int64
    public var streams: [MediaStream]
    public var chapters: [Chapter]
    public var video: MediaStream? { streams.first { $0.kind == "video" } }
    public var audio: [MediaStream] { streams.filter { $0.kind == "audio" } }
}
public struct DiscTitle: Codable, Identifiable {
    public var id = UUID()
    public var name: String
    public var path: String
    public var media: MediaInfo?
    public var chapters: [Chapter] = [Chapter(name: "Opening", seconds: 0)]
    public var audioIndices: [Int] = []
    public var audioTracks: [AudioTrack]? = nil
    public init(name: String, path: String) { self.name = name; self.path = path }
    public func selectedAudio(defaultMode: AudioMode) -> [AudioTrack] {
        if let audioTracks { return audioTracks }
        guard let media else { return [] }
        return audioIndices.compactMap { index in
            guard let stream = media.audio.first(where: { $0.index == index }) else { return nil }
            return AudioTrack(name: "\(stream.profile ?? stream.codec.uppercased()) · \(stream.channels ?? 0) channels", path: path, streamIndex: index, media: media, mode: defaultMode)
        }
    }
}
public struct MenuStyle: Codable, Equatable {
    public var band = "YOUR BAND"
    public var heading = "Live in concert"
    public var tagline = "A film for the fans"
    public var accent = "D5AE62"
    public var backgroundPath: String?
    public init() {}
}
public struct PlayerTest: Codable, Identifiable {
    public var id = UUID()
    public var buildID: String
    public var player: String
    public var result: String
    public var notes: String
    public var date = Date()
    public init(buildID: String, player: String, result: String, notes: String) {
        self.buildID = buildID; self.player = player; self.result = result; self.notes = notes
    }
}
public struct BuildRecord: Codable, Identifiable {
    public var id: String
    public var date: Date
    public var folder: String
    public var iso: String
    public var sha256: String
    public var projectFingerprint: String
    public var bytes: Int64
}
public struct Project: Codable {
    public var schemaVersion = 1
    public var name = "Untitled concert"
    public var format: DiscFormat = .bluray
    public var capacity: Capacity = .bd25
    public var videoMode: VideoMode = .encode
    public var audioMode: AudioMode = .pcm
    public var contentMode: ContentMode? = nil
    public var albumAutoplay: Bool? = nil
    public var fileBookmarks: [String: Data]? = nil
    public var videoMbps: Int = 25
    public var menu = MenuStyle()
    public var titles: [DiscTitle] = []
    public var plant = ""
    public var plantRequirements = ""
    public var playerTests: [PlayerTest] = []
    public var builds: [BuildRecord] = []
    public init() {}
    public var isAlbum: Bool { contentMode == .album }
    public var duration: Double { titles.reduce(0) { $0 + ($1.media?.duration ?? 0) } }
    public var estimatedBytes: Int64 {
        let bits = titles.reduce(0.0) { total, title in
            let audioRate = title.selectedAudio(defaultMode: audioMode).reduce(0.0) { $0 + $1.bitRate }
            let videoRate = isAlbum && title.media?.video == nil ? 2_000_000 : videoMode == .encode ? Double(videoMbps) * 1_000_000 :
                Double(title.media?.size ?? 0) * 8 / max(1, title.media?.duration ?? 1)
            let duration = title.media?.duration ?? 0
            return total + (duration.isFinite ? max(0, duration) : 0) * (videoRate + audioRate)
        }
        guard bits.isFinite, bits >= 0, bits < Double(Int64.max) / 2 else { return Int64.max / 4 }
        return Int64(bits / 8 * 1.08) + 64_000_000
    }
    public func save(to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
    public static func open(_ url: URL) throws -> Project {
        let result = try JSONDecoder().decode(Project.self, from: Data(contentsOf: url))
        guard result.schemaVersion == 1 else { throw StageError.message("This project uses a newer file format.") }
        return result
    }
    public func fingerprint() throws -> String {
        var copy = self; copy.builds = []; copy.playerTests = []; copy.plant = ""; copy.plantRequirements = ""; copy.fileBookmarks = nil
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return SHA256File.digest(try encoder.encode(copy))
    }
}
public enum StageError: Error, LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
public enum Timecode {
    public static func parse(_ value: String) -> Double? {
        let parts = value.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        let numbers = parts.compactMap { Double($0) }
        guard numbers.count == parts.count, numbers.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        if numbers.count > 1 && numbers.last! >= 60 { return nil }
        if numbers.count == 3 && (numbers[1] >= 60 || numbers[0].rounded() != numbers[0]) { return nil }
        if numbers.count >= 2 && numbers[numbers.count - 2].rounded() != numbers[numbers.count - 2] { return nil }
        return numbers.reduce(0) { $0 * 60 + $1 }
    }
    public static func string(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds < Double(Int.max / 1000) else { return "Unknown" }
        let ms = max(0, Int((seconds * 1000).rounded()))
        return String(format: "%02d:%02d:%02d.%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
    }
}
