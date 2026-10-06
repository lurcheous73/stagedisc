import Foundation

public enum AudioAuthoring {
    public static let passthroughCodecs = ["ac3", "eac3", "dts", "truehd"]
    public static func inspect(_ track: AudioTrack, title: DiscTitle, checkFiles: Bool) -> [PreflightIssue] {
        var issues: [PreflightIssue] = []
        func issue(_ severity: PreflightIssue.Severity, _ text: String) { issues.append(.init(severity: severity, message: "\(title.name) / \(track.name): " + text)) }
        if checkFiles && !FileManager.default.fileExists(atPath: track.path) { issue(.error, "audio source is missing.") }
        guard let stream = track.stream else { issue(.error, "selected audio stream no longer exists."); return issues }
        let channels = stream.channels ?? 0
        if track.mode == .preserve {
            if !passthroughCodecs.contains(stream.codec) { issue(.error, "copy mode accepts prepared AC-3, E-AC-3, DTS/DTS-HD or TrueHD. Convert WAV/FLAC/AIFF/AAC to LPCM or Dolby Digital.") }
            if channels < 1 || channels > 8 { issue(.error, "a prepared Blu-ray audio bed must have 1–8 channels. An ADM/object master needs external encoding first.") }
            if stream.codec == "eac3" { issue(.note, "DD+ copying is experimental. Have its Blu-ray substream structure checked by a mastering verifier.") }
            if stream.codec == "truehd" {
                let ext = URL(fileURLWithPath: track.path).pathExtension.lowercased()
                if !["thd", "thd+ac3", "truehd"].contains(ext) || !track.media.audio.contains(where: { $0.codec == "ac3" }) {
                    issue(.error, "TrueHD/Atmos requires a prepared elementary TrueHD+AC-3 master with its interleaved compatibility substream. A bare .thd or extraction from MKV would lose disc compatibility.")
                }
                issue(.note, "the combined TrueHD+AC-3 master is copied intact. Atmos presence and bitstream alignment require external mastering/player verification.")
            }
            if stream.codec == "dts" { issue(.note, "DTS extensions are copied without down-to-dts filtering. Verify the HD/X metadata and backwards-compatible core in a mastering tool.") }
        } else {
            let allowed = track.mode == .ac3 ? [1, 2, 6] : track.mode == .pcm192 ? [1, 2, 3, 4, 5, 6] : [1, 2, 3, 4, 5, 6, 7, 8]
            if !allowed.contains(channels) { issue(.error, track.mode == .ac3 ? "Dolby Digital encoding supports mono, stereo and 5.1. No automatic downmix is applied." : "this LPCM rate does not support the supplied channel count (192 kHz allows at most 6 channels).") }
            if track.mode.isPCM, let rate = stream.sampleRate, rate < track.mode.sampleRate { issue(.note, "upsampling does not add source resolution. Choose the source rate when practical.") }
            if ["truehd", "eac3", "dts"].contains(stream.codec) { issue(.note, "encoding retains channel audio only. Immersive/codec metadata survives only in Copy mode; use a separate prepared track for Atmos or DTS:X.") }
        }
        if !(-600_000...600_000).contains(track.delayMS) { issue(.error, "audio offset must be within ±10 minutes.") }
        if track.path != title.path, track.media.duration > 0, let duration = title.media?.duration,
           abs(track.media.duration + Double(track.delayMS) / 1000 - duration) > 1 {
            issue(.error, "external mix length plus offset must match the title within one second. Prepare a synchronised continuous master first.")
        }
        if track.path != title.path && track.media.duration <= 0 {
            issue(.note, "this elementary master's duration cannot be probed. Verify its full running time and sync on a player.")
        }
        return issues
    }
    public static func command(_ track: AudioTrack, number: Int, tools: Toolchain, folder: URL) throws -> (Command, String, String) {
        guard let stream = track.stream else { throw StageError.message("Invalid audio stream selection.") }
        if track.mode == .preserve && stream.codec == "truehd" {
            let errors = inspect(track, title: DiscTitle(name: track.name, path: track.path), checkFiles: false).filter { $0.severity == .error }
            guard errors.isEmpty else { throw StageError.message(errors.map(\.message).joined(separator: "\n")) }
        }
        let ext: String, muxCodec: String, outputFormat: String
        if track.mode.isPCM { ext = "w64"; muxCodec = "A_LPCM"; outputFormat = "w64" }
        else if track.mode == .ac3 { ext = "ac3"; muxCodec = "A_AC3"; outputFormat = "ac3" }
        else {
            guard passthroughCodecs.contains(stream.codec) else { throw StageError.message("Unsupported audio bitstream copy: \(stream.codec).") }
            ext = stream.codec == "truehd" ? "thd" : stream.codec
            muxCodec = stream.codec == "dts" ? "A_DTS" : "A_AC3"
            outputFormat = stream.codec
        }
        let path = folder.appendingPathComponent("audio-\(number)." + ext).path
        // Copy elementary TrueHD+AC-3 files intact, including embedded compatibility/Atmos data.
        let sourceExt = URL(fileURLWithPath: track.path).pathExtension.lowercased()
        if track.mode == .preserve && ["thd", "truehd", "thd+ac3", "ac3", "eac3", "dts", "dtshd"].contains(sourceExt) {
            return (Command("/bin/cp", [track.path, path], label: "Copy prepared \(track.name)"), path, muxCodec)
        }
        var args = ["-hide_banner", "-nostdin", "-n", "-i", track.path, "-map", "0:\(track.streamIndex)", "-vn", "-sn", "-dn"]
        if track.mode == .preserve { args += ["-c:a", "copy"] }
        else {
            args += ["-af", "asetpts=PTS-STARTPTS", "-ar", String(track.mode.sampleRate)]
            if track.mode.isPCM { args += ["-c:a", track.mode.bitDepth == 16 ? "pcm_s16le" : "pcm_s24le"] }
            else { args += ["-c:a", "ac3", "-b:a", "640k"] }
        }
        args += ["-f", outputFormat, path]
        return (Command(tools.ffmpeg, args, label: "Prepare \(track.name)"), path, muxCodec)
    }
}
