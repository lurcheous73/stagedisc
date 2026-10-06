import Foundation

public struct PreflightIssue: Identifiable {
    public enum Severity { case error, note }
    public var id: String { message }
    public var severity: Severity
    public var message: String
}
public enum Preflight {
    public static func inspect(_ project: Project, tools: Toolchain, checkFiles: Bool = true) -> [PreflightIssue] {
        var issues: [PreflightIssue] = []
        func error(_ text: String) { issues.append(.init(severity: .error, message: text)) }
        func note(_ text: String) { issues.append(.init(severity: .note, message: text)) }
        for tool in tools.missing { error("\(tool) is missing. Locate it in Tools.") }
        if project.titles.isEmpty { error(project.isAlbum ? "Add the continuous album master first." : "Add the concert film first.") }
        if project.isAlbum && project.format == .uhd { error("Audio album mode currently uses standard Blu-ray. Choose Blu-ray for the generated artwork video.") }
        if project.format == .bluray && project.capacity == .bd100 { error("Choose a 25 GB or 50 GB test disc for standard Blu-ray.") }
        if project.videoMbps < 5 || project.videoMbps > 35 { error("The Blu-ray video target must be 5–35 Mb/s.") }
        if project.format == .uhd && project.videoMode == .encode { error("UHD currently requires prepared 2160p HEVC Main 10 video. Choose ‘Use prepared disc video’. HDR encoding is not implemented.") }
        if project.menu.accent.range(of: "^[0-9A-Fa-f]{6}$", options: .regularExpression) == nil { error("Menu accent must be six hexadecimal digits.") }
        if let background = project.menu.backgroundPath, checkFiles && !FileManager.default.fileExists(atPath: background) { error("The menu background image is missing.") }
        for title in project.titles {
            let prefix = "\(title.name): "
            if checkFiles && !FileManager.default.fileExists(atPath: title.path) { error(prefix + "source file is missing.") }
            guard let media = title.media else { error(prefix + "inspect the source before building."); continue }
            let artworkVideo = project.isAlbum && media.video == nil
            if !artworkVideo && media.video == nil { error(prefix + "this source has no video. Use audio album mode for audio-only masters."); continue }
            if media.duration <= 0 || !media.duration.isFinite { error(prefix + "duration is unknown.") }
            let rates = project.format == .bluray ? [23.976, 24, 25, 29.97] : [23.976, 24, 25, 29.97, 50, 59.94]
            if let video = media.video {
            if !rates.contains(where: { abs($0 - (video.frameRate ?? 0)) < 0.015 }) { error(prefix + "frame rate is unsupported by this version. Prepare a constant-frame-rate disc master externally.") }
            if project.videoMode == .encode {
                if video.isHDR { error(prefix + "HDR cannot be converted to SDR here. Supply a colour-managed SDR master.") }
                if ![nil, "progressive", "unknown"].contains(video.fieldOrder) { error(prefix + "interlaced sources need external preparation before encoding.") }
                if (video.width ?? 0) < 1920 { note(prefix + "video will be upscaled to 1920 × 1080.") }
            } else {
                if project.format == .bluray {
                    if video.codec != "h264" || video.width != 1920 || video.height != 1080 || video.pixelFormat != "yuv420p" {
                        error(prefix + "prepared Blu-ray video must be 1920 × 1080, 8-bit H.264 4:2:0.")
                    }
                    if video.isHDR { error(prefix + "standard Blu-ray needs an SDR master.") }
                } else {
                    if video.codec != "hevc" || video.width != 3840 || video.height != 2160 || video.pixelFormat != "yuv420p10le" {
                        error(prefix + "UHD video must be prepared 3840 × 2160, 10-bit HEVC 4:2:0.")
                    }
                }
                note(prefix + "prepared video is copied. Full bitstream conformance requires a mastering verifier.")
            }
            }
            let tracks = title.selectedAudio(defaultMode: project.audioMode)
            if tracks.isEmpty { error(prefix + "select at least one audio track.") }
            if tracks.count > 32 { error(prefix + "Blu-ray accepts at most 32 primary audio streams.") }
            for track in tracks { issues += AudioAuthoring.inspect(track, title: title, checkFiles: checkFiles) }
            if !tracks.contains(where: { $0.mode != .preserve || ["ac3", "dts"].contains($0.stream?.codec ?? "") }) {
                error(prefix + "include a compatible LPCM, Dolby Digital or DTS mix alongside optional TrueHD/DD+ tracks.")
            }
            let audioPeak = tracks.reduce(0.0) { $0 + $1.bitRate }
            if project.format == .bluray && audioPeak + Double(artworkVideo ? 2 : project.videoMbps) * 1_000_000 > 47_000_000 {
                error(prefix + "combined audio and video budget exceeds 47 Mb/s. Reduce the video target or the number/rate of simultaneous audio tracks.")
            }
            if title.chapters.isEmpty || title.chapters.first?.seconds != 0 { error(prefix + "the first chapter must start at 00:00:00.") }
            for (i, chapter) in title.chapters.enumerated() {
                if !chapter.seconds.isFinite || chapter.seconds < 0 || chapter.seconds >= media.duration { error(prefix + "chapter ‘\(chapter.name)’ is outside the film.") }
                if i > 0 && chapter.seconds <= title.chapters[i - 1].seconds { error(prefix + "chapter times must be strictly increasing.") }
            }
        }
        if project.estimatedBytes > project.capacity.rawValue { error("Estimated content exceeds the selected test disc. Lower the video target or choose a larger disc.") }
        if project.format == .uhd { note("UHD recordable playback is experimental and varies by player and medium. A successful test burn does not certify a UHD replication master.") }
        if project.isAlbum { note("Audio album mode adds a low-bitrate artwork video, automatic playback and remote mix selection. Use one continuous album master with song chapters for gapless playback. Pure Audio/AES-21id conformance is not certified.") }
        if project.plant.isEmpty { note("Pressing plant not chosen. Confirm BDMV/ISO conversion, BDCMF or UHD-BDCMF delivery with the plant before handoff.") }
        note("This build creates a Java menu and a test image. It does not create BDCMF, AACS encryption or a certified replication master.")
        return issues
    }
}
public struct TitlePlan {
    public var video: Command
    public var audio: [Command]
    public var meta: String
}
public enum AuthoringPlan {
    public static func title(_ title: DiscTitle, number: Int, project: Project, tools: Toolchain, folder: URL) throws -> TitlePlan {
        guard let media = title.media else { throw StageError.message("Inspect the source first.") }
        let stream = media.video
        let artworkVideo = project.isAlbum && stream == nil
        guard artworkVideo || stream != nil else { throw StageError.message("Film titles need a video stream.") }
        let fps = stream?.frameRate ?? 24
        let rational = fps < 24 && fps > 23 ? "24000/1001" : fps > 29 && fps < 30 ? "30000/1001" : fps > 59 && fps < 60 ? "60000/1001" : String(Int(fps.rounded()))
        let ext = project.format == .bluray ? "h264" : "hevc"
        let videoPath = folder.appendingPathComponent("video." + ext).path
        let tracks = title.selectedAudio(defaultMode: project.audioMode)
        let maximumVideoKbps = min(35_000, Int((47_000_000 - tracks.reduce(0.0) { $0 + $1.bitRate }) / 1000))
        var args = ["-hide_banner", "-nostdin", "-n"]
        if artworkVideo { args += ["-loop", "1", "-framerate", "24", "-i", folder.appendingPathComponent("album.png").path, "-t", String(media.duration), "-an", "-sn", "-dn"] }
        else { args += ["-i", title.path, "-map", "0:\(stream!.index)", "-an", "-sn", "-dn"] }
        if project.videoMode == .prepared && !artworkVideo {
            args += ["-c:v", "copy", "-bsf:v", project.format == .bluray ? "h264_mp4toannexb" : "hevc_mp4toannexb"]
        } else {
            let gop = Int(fps.rounded())
            var x264 = "bluray-compat=1:vbv-maxrate=\(maximumVideoKbps):vbv-bufsize=30000:nal-hrd=vbr:open-gop=1:keyint=\(gop):min-keyint=1:slices=4:ref=4:b-pyramid=strict:aud=1:force-cfr=1"
            if fps >= 25 { x264 += ":fake-interlaced=1" }
            args += ["-vf", "setpts=PTS-STARTPTS,scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2,setsar=1",
                     "-c:v", "libx264", "-preset", "slow", "-profile:v", "high", "-level:v", "4.1", "-pix_fmt", "yuv420p", "-r", rational,
                     "-b:v", "\(artworkVideo ? 2 : project.videoMbps)M", "-maxrate", "\(maximumVideoKbps)k", "-bufsize", "30M", "-x264-params", x264,
                     "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709"]
        }
        args += ["-f", ext, videoPath]
        var audioCommands: [Command] = []
        let chapterTimes = title.chapters.map { Timecode.string($0.seconds) }.joined(separator: ";")
        // Explicit PES extensions distinguish TrueHD from its interleaved AC-3
        // core. tsMuxer 2.7.0 does not reliably enable them from --blu-ray alone.
        var meta = "MUXOPT \(project.format == .bluray ? "--blu-ray" : "--blu-ray-v3") --new-audio-pes --vbr --custom-chapters=\(chapterTimes) --mplsOffset=\(number) --m2tsOffset=\(number)\n"
        let codec = project.format == .bluray ? "V_MPEG4/ISO/AVC" : "V_MPEGH/ISO/HEVC"
        meta += "\(codec), \"\(try quoteMeta(videoPath))\", fps=\(rational)\(project.format == .bluray ? ", insertSEI, contSPS" : "")\n"
        for (i, track) in tracks.enumerated() {
            guard let audio = track.stream else { throw StageError.message("Audio selection is invalid.") }
            let (command, audioPath, muxCodec) = try AudioAuthoring.command(track, number: i, tools: tools, folder: folder)
            audioCommands.append(command)
            let language = track.language
            let lang = language.range(of: "^[a-z]{3}$", options: .regularExpression) != nil ? language : "und"
            let skew = track.path == title.path && !artworkVideo ? (audio.startTime ?? 0) - (stream?.startTime ?? 0) : 0
            let delay = Int(skew * 1000) + track.delayMS
            meta += "\(muxCodec), \"\(try quoteMeta(audioPath))\", lang=\(lang)\(delay != 0 ? ", timeshift=\(delay)ms" : "")\(i == 0 ? ", default" : "")\n"
        }
        return TitlePlan(video: Command(tools.ffmpeg, args, label: "Prepare video · \(title.name)"), audio: audioCommands, meta: meta)
    }
    static func quoteMeta(_ value: String) throws -> String {
        guard !value.contains("\"") && !value.contains("\n") && !value.contains("\r") else { throw StageError.message("Use a build folder without quotes or line breaks in its path.") }
        return value
    }
}
public struct MenuButton: Codable {
    public var label: String
    public var targetPage: Int?
    public var playlist: Int?
    public var seconds: Double?
    public var audioSlot: Int?
    public init(label: String, targetPage: Int? = nil, playlist: Int? = nil, seconds: Double? = nil, audioSlot: Int? = nil) {
        self.label = label; self.targetPage = targetPage; self.playlist = playlist; self.seconds = seconds; self.audioSlot = audioSlot
    }
}
public struct MenuPage: Codable, Identifiable {
    public var id: Int
    public var name: String
    public var buttons: [MenuButton]
}
public enum MenuPlan {
    public static func pages(_ project: Project) -> [MenuPage] {
        let chapters = project.titles.first?.chapters ?? []
        let songCount = max(1, (chapters.count + 6) / 7)
        let extraCount = max(1, (max(0, project.titles.count - 1) + 6) / 7)
        let extraStart = 1 + songCount
        let audioStart = extraStart + (project.titles.count > 1 ? extraCount : 0)
        let mixes: [MenuButton] = project.titles.enumerated().flatMap { titleIndex, title in
            title.selectedAudio(defaultMode: project.audioMode).enumerated().map { trackIndex, track in
                MenuButton(label: (titleIndex == 0 ? "" : title.name + " · ") + track.name, playlist: titleIndex + 1, audioSlot: trackIndex + 1)
            }
        }
        var main = [MenuButton(label: project.isAlbum ? "Play album" : "Play concert", playlist: 1, seconds: 0), MenuButton(label: "Song selection", targetPage: 1)]
        if project.titles.count > 1 { main.append(MenuButton(label: "Extras", targetPage: extraStart)) }
        if !mixes.isEmpty { main.append(MenuButton(label: "Audio mixes", targetPage: audioStart)) }
        var result = [MenuPage(id: 0, name: "Main menu", buttons: main)]
        for page in 0..<songCount {
            let start = page * 7, end = min(start + 7, chapters.count)
            var buttons: [MenuButton] = start < end ? (start..<end).map { MenuButton(label: String(format: "%02d  %@", $0 + 1, chapters[$0].name), playlist: 1, seconds: chapters[$0].seconds) } : []
            buttons.append(MenuButton(label: "Main menu", targetPage: 0))
            if songCount > 1 { buttons.append(MenuButton(label: "More songs →", targetPage: 1 + (page + 1) % songCount)) }
            result.append(MenuPage(id: 1 + page, name: songCount > 1 ? "Song selection · \(page + 1) / \(songCount)" : "Song selection", buttons: buttons))
        }
        if project.titles.count > 1 {
            for page in 0..<extraCount {
                let start = 1 + page * 7, end = min(start + 7, project.titles.count)
                var buttons = (start..<end).map { MenuButton(label: project.titles[$0].name, playlist: $0 + 1, seconds: 0) }
                buttons.append(MenuButton(label: "Main menu", targetPage: 0))
                if extraCount > 1 { buttons.append(MenuButton(label: "More extras →", targetPage: extraStart + (page + 1) % extraCount)) }
                result.append(MenuPage(id: extraStart + page, name: "Extras", buttons: buttons))
            }
        }
        let audioCount = (mixes.count + 6) / 7
        for page in 0..<audioCount {
            var buttons = Array(mixes[(page * 7)..<min(page * 7 + 7, mixes.count)])
            buttons.append(MenuButton(label: "Main menu", targetPage: 0))
            if audioCount > 1 { buttons.append(MenuButton(label: "More mixes →", targetPage: audioStart + (page + 1) % audioCount)) }
            result.append(MenuPage(id: audioStart + page, name: "Audio mixes", buttons: buttons))
        }
        return result
    }
    public static func properties(_ pages: [MenuPage], project: Project? = nil) -> String {
        var rows = ["pages=\(pages.count)", "album.autoplay=\(project?.isAlbum == true && project?.albumAutoplay != false ? "true" : "false")"]
        for page in pages {
            rows.append("page.\(page.id).count=\(page.buttons.count)")
            for (i, button) in page.buttons.enumerated() {
                let action = button.audioSlot.map { "audio:\(button.playlist ?? 1):\($0)" } ?? button.targetPage.map { "page:\($0)" } ?? "play:\(button.playlist ?? 1):\(button.seconds ?? 0)"
                rows.append("page.\(page.id).button.\(i)=\(action)")
            }
        }
        return rows.joined(separator: "\n") + "\n"
    }
}
