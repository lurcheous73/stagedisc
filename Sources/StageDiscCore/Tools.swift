import Foundation
import CryptoKit

public enum SHA256File {
    public static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    public static func hash(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var hash = SHA256()
        while let chunk = try file.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            if Task.isCancelled { throw CancellationError() }
            hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
public struct Toolchain: Codable {
    public var ffmpeg: String
    public var ffprobe: String
    public var tsmuxer: String
    public var udf: String
    public var java: String
    public var menuTools: String
    public var menuRuntime: String
    public var menuTemplate: String { URL(fileURLWithPath: menuRuntime).deletingLastPathComponent().appendingPathComponent("menu.bdjo").path }
    public init(resources: String? = nil) {
        let base = resources ?? Bundle.main.resourcePath ?? ""
        ffmpeg = Self.find("ffmpeg", bundled: base + "/bin/ffmpeg")
        ffprobe = Self.find("ffprobe", bundled: base + "/bin/ffprobe")
        tsmuxer = Self.find("tsMuxeR", bundled: base + "/bin/tsMuxeR")
        udf = Self.find("stagedisc-udf", bundled: base + "/bin/stagedisc-udf")
        java = ["/Library/Java/JavaVirtualMachines/temurin-8.jdk/Contents/Home/bin/java",
                "/Library/Java/JavaVirtualMachines/microsoft-11.jdk/Contents/Home/bin/java",
                "/opt/homebrew/opt/openjdk/bin/java", "/usr/bin/java"].first { FileManager.default.isExecutableFile(atPath: $0) } ?? ""
        menuTools = base + "/menu/menu-tools.jar"
        menuRuntime = base + "/menu/menu-runtime.jar"
    }
    public static func find(_ name: String, bundled: String? = nil) -> String {
        if Self.isAppStore { return bundled ?? "" }
        let dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] +
            (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let paths = (bundled.map { [$0] } ?? []) + dirs.map { $0 + "/" + name }
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) } ?? ""
    }
    public static var isAppStore: Bool { Bundle.main.object(forInfoDictionaryKey: "StageDiscDistribution") as? String == "app-store" }
    public var missing: [String] {
        [("FFmpeg", ffmpeg), ("FFprobe", ffprobe), ("tsMuxer", tsmuxer), ("UDF image writer", udf)]
            .filter { !FileManager.default.isExecutableFile(atPath: $0.1) }.map { $0.0 } +
        [("Menu descriptor", menuTemplate), ("Menu runtime", menuRuntime)].filter { !FileManager.default.fileExists(atPath: $0.1) }.map { $0.0 }
    }
}
public struct Command: Codable, Sendable {
    public var tool: String
    public var arguments: [String]
    public var label: String
    public init(_ tool: String, _ arguments: [String], label: String) { self.tool = tool; self.arguments = arguments; self.label = label }
}
public struct ProcessResult { public var stdout: Data; public var stderr: Data; public var status: Int32 }
public final class ProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var active: Process?
    private var wasCancelled = false
    public init() {}
    public func cancel() { lock.lock(); wasCancelled = true; let process = active; lock.unlock(); if process?.isRunning == true { process?.terminate() } }
    public func run(_ command: Command, log: @escaping @Sendable (String) -> Void = { _ in }) async throws -> ProcessResult {
        if Task.isCancelled { throw CancellationError() }
        resetCancellation()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do { continuation.resume(returning: try self.execute(command, log: log)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { self.cancel() })
    }
    private func resetCancellation() { lock.lock(); wasCancelled = false; lock.unlock() }
    private func execute(_ command: Command, log: @escaping @Sendable (String) -> Void) throws -> ProcessResult {
        guard FileManager.default.isExecutableFile(atPath: command.tool) else { throw StageError.message("Missing tool for \(command.label). Check Tools settings.") }
        let process = Process(); process.executableURL = URL(fileURLWithPath: command.tool); process.arguments = command.arguments
        process.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        process.environment = environment
        let out = Pipe(), err = Pipe(); process.standardOutput = out; process.standardError = err
        let collector = OutputCollector(), group = DispatchGroup()
        lock.lock(); let cancelledBeforeStart = wasCancelled; active = process; lock.unlock()
        defer { lock.lock(); active = nil; lock.unlock() }
        if cancelledBeforeStart { throw CancellationError() }
        try process.run()
        lock.lock(); let cancelledAfterStart = wasCancelled; lock.unlock()
        if cancelledAfterStart && process.isRunning { process.terminate() }
        for (pipe, isError) in [(out, false), (err, true)] {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                defer { group.leave() }
                while true {
                    let data = pipe.fileHandleForReading.availableData
                    if data.isEmpty { break }
                    collector.append(data, error: isError)
                    log(String(decoding: data, as: UTF8.self))
                }
            }
        }
        process.waitUntilExit(); group.wait()
        let result = ProcessResult(stdout: collector.out, stderr: collector.err, status: process.terminationStatus)
        guard result.status == 0 else {
            throw StageError.message("\(command.label) failed (\(result.status)).\n" + String(decoding: result.stderr.suffix(3000), as: UTF8.self))
        }
        return result
    }
}
private final class OutputCollector: @unchecked Sendable {
    let lock = NSLock(); var out = Data(); var err = Data()
    func append(_ data: Data, error: Bool) {
        lock.lock(); defer { lock.unlock() }
        // FFprobe JSON remains complete; process diagnostics retain the last 4 MB.
        if error { err.append(data); if err.count > 4_000_000 { err = err.suffix(4_000_000) } }
        else { out.append(data); if out.count > 32_000_000 { out = out.suffix(32_000_000) } }
    }
}
public enum Probe {
    public static func read(_ path: String, tools: Toolchain, runner: ProcessRunner) async throws -> MediaInfo {
        let command = Command(tools.ffprobe, ["-v", "error", "-show_format", "-show_streams", "-show_chapters", "-of", "json", path], label: "Inspect media")
        let result = try await runner.run(command)
        var media = try parse(result.stdout)
        // FFprobe's raw TrueHD demuxer omits the interleaved AC-3 compatibility
        // stream. Ask the actual disc muxer to confirm it before permitting copy.
        if ["thd", "truehd", "thd+ac3"].contains(URL(fileURLWithPath: path).pathExtension.lowercased()),
           let trueHD = media.audio.first(where: { $0.codec == "truehd" }) {
            let inspection = try await runner.run(Command(tools.tsmuxer, [path], label: "Inspect TrueHD disc compatibility"))
            let description = String(decoding: inspection.stdout, as: UTF8.self)
            if description.contains("AC3 core + TRUE-HD") {
                media.streams.append(MediaStream(index: (media.streams.map(\.index).max() ?? 0) + 1,
                    kind: "audio", codec: "ac3", channels: min(trueHD.channels ?? 6, 6),
                    channelLayout: nil, sampleRate: trueHD.sampleRate, language: nil,
                    profile: "Interleaved compatibility core"))
            }
        }
        return media
    }
    public static func parse(_ data: Data) throws -> MediaInfo {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw StageError.message("Invalid FFprobe response.") }
        let format = json["format"] as? [String: Any] ?? [:]
        let rows = json["streams"] as? [[String: Any]] ?? []
        let streams: [MediaStream] = rows.compactMap { row in
            guard let index = row["index"] as? Int, let type = row["codec_type"] as? String else { return nil }
            let tags = row["tags"] as? [String: String] ?? [:]
            let rate = row["avg_frame_rate"] as? String ?? row["r_frame_rate"] as? String ?? ""
            let parts = rate.split(separator: "/").compactMap { Double($0) }
            let fps = parts.count == 2 && parts[1] != 0 ? parts[0] / parts[1] : nil
            return MediaStream(index: index, kind: type, codec: row["codec_name"] as? String ?? "unknown", width: row["width"] as? Int,
                height: row["height"] as? Int, pixelFormat: row["pix_fmt"] as? String, frameRate: fps, fieldOrder: row["field_order"] as? String,
                colorTransfer: row["color_transfer"] as? String, colorPrimaries: row["color_primaries"] as? String, colorSpace: row["color_space"] as? String,
                channels: row["channels"] as? Int, channelLayout: row["channel_layout"] as? String, sampleRate: Int(row["sample_rate"] as? String ?? ""),
                language: tags["language"], startTime: Double(row["start_time"] as? String ?? ""), profile: row["profile"] as? String,
                bitRate: Int64(row["bit_rate"] as? String ?? ""))
        }
        let chapters = (json["chapters"] as? [[String: Any]] ?? []).enumerated().map { i, row -> Chapter in
            let tags = row["tags"] as? [String: String] ?? [:]
            return Chapter(name: tags["title"] ?? "Song \(i + 1)", seconds: Double(row["start_time"] as? String ?? "0") ?? 0)
        }
        return MediaInfo(duration: Double(format["duration"] as? String ?? "0") ?? 0, size: Int64(format["size"] as? String ?? "0") ?? 0,
                         streams: streams, chapters: chapters)
    }
}
