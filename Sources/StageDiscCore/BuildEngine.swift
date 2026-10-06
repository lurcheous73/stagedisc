import Foundation

public final class BuildEngine: @unchecked Sendable {
    public let runner = ProcessRunner()
    public init() {}
    public func cancel() { runner.cancel() }
    public func build(project input: Project, tools: Toolchain, destination: URL,
                      update: @escaping @Sendable (String, Double) -> Void,
                      log: @escaping @Sendable (String) -> Void) async throws -> BuildRecord {
        var project = input
        for i in project.titles.indices {
            update("Inspecting \(project.titles[i].name)", 0.01)
            project.titles[i].media = try await Probe.read(project.titles[i].path, tools: tools, runner: runner)
            if var tracks = project.titles[i].audioTracks {
                for n in tracks.indices { tracks[n].media = try await Probe.read(tracks[n].path, tools: tools, runner: runner) }
                project.titles[i].audioTracks = tracks
            }
        }
        let issues = Preflight.inspect(project, tools: tools).filter { $0.severity == .error }
        guard issues.isEmpty else { throw StageError.message(issues.map(\.message).joined(separator: "\n")) }
        let id = "\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-"))-\(UUID().uuidString.prefix(8))"
        let root = destination.appendingPathComponent(id, isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let values = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        let filesystemFree = ((try? fm.attributesOfFileSystem(forPath: root.path)[.systemFreeSize]) as? NSNumber)?.int64Value ?? 0
        let free = max(values.volumeAvailableCapacityForImportantUsage ?? 0, Int64(values.volumeAvailableCapacity ?? 0), filesystemFree)
        guard free > project.estimatedBytes * 4 else { throw StageError.message("The build needs about \(ByteCountFormatter.string(fromByteCount: project.estimatedBytes * 4, countStyle: .file)) of free space for prepared media, disc folders and ISO.") }
        let marker = root.appendingPathComponent("BUILD-INCOMPLETE.txt")
        try "Build incomplete. Do not burn or deliver partial files.\n".write(to: marker, atomically: true, encoding: .utf8)
        // Factory snapshots describe the sources without exporting this Mac's
        // persistent sandbox access tokens. The editable project keeps them.
        var snapshot = project
        snapshot.fileBookmarks = nil
        try snapshot.save(to: root.appendingPathComponent("project.stagedisc"))
        let disc = root.appendingPathComponent("disc-root", isDirectory: true)
        try fm.createDirectory(at: disc, withIntermediateDirectories: true)
        let fullLog = BuildLog(root.appendingPathComponent("build.log"))
        let logBoth: @Sendable (String) -> Void = { text in fullLog.append(text); log(text) }
        var commands: [Command] = []
        func execute(_ command: Command) async throws {
            commands.append(command)
            logBoth("\n— \(command.label) —\n")
            _ = try await runner.run(command, log: logBoth)
            if Task.isCancelled { throw CancellationError() }
        }
        for (index, title) in project.titles.enumerated() {
            let number = index + 1
            let work = root.appendingPathComponent("work/title-\(number)", isDirectory: true)
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            if project.isAlbum && title.media?.video == nil {
                let albumProject = project
                try await MainActor.run { try MenuRenderer.albumArtwork(project: albumProject, title: title, to: work.appendingPathComponent("album.png")) }
            }
            let plan = try AuthoringPlan.title(title, number: number, project: project, tools: tools, folder: work)
            let fraction = Double(index) / Double(project.titles.count)
            update("Preparing \(title.name) · video", 0.05 + fraction * 0.65)
            try await execute(plan.video)
            for command in plan.audio {
                update(command.label, 0.10 + fraction * 0.65); try await execute(command)
            }
            let meta = work.appendingPathComponent("title.meta")
            try plan.meta.write(to: meta, atomically: true, encoding: .utf8)
            let titleDisc = work.appendingPathComponent("muxed", isDirectory: true)
            update("Authoring \(title.name)", 0.15 + fraction * 0.65)
            try await execute(Command(tools.tsmuxer, [meta.path, titleDisc.path], label: "Mux \(title.name)"))
            let source = titleDisc.appendingPathComponent("BDMV", isDirectory: true)
            if index == 0 {
                try fm.copyItem(at: source, to: disc.appendingPathComponent("BDMV"))
                let certificate = titleDisc.appendingPathComponent("CERTIFICATE")
                if fm.fileExists(atPath: certificate.path) { try fm.copyItem(at: certificate, to: disc.appendingPathComponent("CERTIFICATE")) }
            } else {
                let basename = String(format: "%05d", number)
                for (dir, ext) in [("STREAM", "m2ts"), ("CLIPINF", "clpi"), ("PLAYLIST", "mpls")] {
                    let file = "\(dir)/\(basename).\(ext)"
                    try fm.copyItem(at: source.appendingPathComponent(file), to: disc.appendingPathComponent("BDMV/" + file))
                }
            }
        }
        update("Rendering branded menu", 0.76)
        let menuAssets = root.appendingPathComponent("work/menu", isDirectory: true)
        let pages = MenuPlan.pages(project)
        let menuProject = project
        try await MainActor.run { try MenuRenderer.write(project: menuProject, pages: pages, to: menuAssets) }
        let pagesData = try JSONEncoder().encode(pages)
        try pagesData.write(to: root.appendingPathComponent("menu-map.json"))
        update("Installing Blu-ray Java menu", 0.80)
        let menuBundle = root.appendingPathComponent("work/menu-bundle", isDirectory: true)
        try fm.createDirectory(at: menuBundle, withIntermediateDirectories: true)
        try await execute(Command("/usr/bin/ditto", ["-x", "-k", tools.menuRuntime, menuBundle.path], label: "Unpack menu runtime"))
        for file in try fm.contentsOfDirectory(at: menuAssets, includingPropertiesForKeys: nil) { try fm.copyItem(at: file, to: menuBundle.appendingPathComponent(file.lastPathComponent)) }
        let jarFolder = disc.appendingPathComponent("BDMV/JAR", isDirectory: true)
        let bdjoFolder = disc.appendingPathComponent("BDMV/BDJO", isDirectory: true)
        try fm.createDirectory(at: jarFolder, withIntermediateDirectories: true)
        try fm.createDirectory(at: bdjoFolder, withIntermediateDirectories: true)
        try fm.copyItem(at: URL(fileURLWithPath: tools.menuTemplate), to: bdjoFolder.appendingPathComponent("00000.bdjo"))
        try await execute(Command("/usr/bin/ditto", ["-c", "-k", menuBundle.path, jarFolder.appendingPathComponent("00000.jar").path], label: "Install BD-J menu"))
        try Self.writeTestDiscID(disc)
        // Keep the first title's UHD extension data while routing first-play/top-menu to our Java title.
        let bdmv = disc.appendingPathComponent("BDMV", isDirectory: true)
        try Self.patchIndex(bdmv.appendingPathComponent("index.bdmv"))
        let backup = bdmv.appendingPathComponent("BACKUP", isDirectory: true)
        if fm.fileExists(atPath: backup.path) { try fm.removeItem(at: backup) }
        try fm.createDirectory(at: backup, withIntermediateDirectories: true)
        for name in ["index.bdmv", "MovieObject.bdmv", "BDJO", "CLIPINF", "PLAYLIST"] {
            let source = bdmv.appendingPathComponent(name)
            if fm.fileExists(atPath: source.path) { try fm.copyItem(at: source, to: backup.appendingPathComponent(name)) }
        }
        let streamBytes = try Self.totalSize(disc)
        guard streamBytes <= project.capacity.rawValue else { throw StageError.message("The actual authored content exceeds the selected test disc capacity.") }
        update("Writing UDF 2.50 test image", 0.85)
        let iso = root.appendingPathComponent("test-disc.iso")
        try await execute(Command(tools.udf, [disc.path, iso.path, "STAGEDISC"], label: "Create test ISO"))
        let bytes = (try fm.attributesOfItem(atPath: iso.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard bytes > 0 && bytes <= project.capacity.rawValue else { throw StageError.message("The finished ISO does not fit the selected disc.") }
        update("Checking build and calculating SHA-256", 0.95)
        let fingerprint = try project.fingerprint()
        let checksum = try SHA256File.hash(iso)
        let record = BuildRecord(id: id, date: Date(), folder: root.path, iso: iso.path, sha256: checksum, projectFingerprint: fingerprint, bytes: bytes)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(commands).write(to: root.appendingPathComponent("commands.json"))
        try encoder.encode(record).write(to: root.appendingPathComponent("build.json"))
        try await handoff(project: project, build: record, update: { _ in })
        try fm.removeItem(at: marker)
        update("Test image ready", 1)
        return record
    }
    public static func patchIndex(_ url: URL) throws {
        var data = try Data(contentsOf: url)
        guard data.count >= 16, String(decoding: data.prefix(4), as: UTF8.self) == "INDX" else { throw StageError.message("Invalid index.bdmv.") }
        let offset = data[8..<12].reduce(0) { ($0 << 8) | Int($1) }
        guard offset >= 40 && data.count >= offset + 42, data[offset + 28] == 0, data[offset + 29] == 1 else { throw StageError.message("Unexpected tsMuxer index structure. Refusing to patch menu routes.") }
        let entry: [UInt8] = [0x80, 0, 0, 0, 0xC0, 0, 0x30, 0x30, 0x30, 0x30, 0x30, 0]
        for start in [offset + 4, offset + 16, offset + 30] { data.replaceSubrange(start..<start + 12, with: entry) }
        try data.write(to: url, options: .atomic)
    }
    private static func writeTestDiscID(_ disc: URL) throws {
        // Development organisation ID only. The mastering facility must assign production IDs.
        let certificate = disc.appendingPathComponent("CERTIFICATE", isDirectory: true)
        let backup = certificate.appendingPathComponent("BACKUP", isDirectory: true)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        var data = Data("BDID0200".utf8)
        data.append(Data(repeating: 0, count: 32))
        data.append(contentsOf: [0x53, 0x54, 0x47, 0x44])
        var uuid = UUID().uuid
        withUnsafeBytes(of: &uuid) { data.append(contentsOf: $0) }
        data.append(Data(repeating: 0, count: 44))
        try data.write(to: certificate.appendingPathComponent("id.bdmv"))
        try data.write(to: backup.appendingPathComponent("id.bdmv"))
    }
    public static func totalSize(_ folder: URL) throws -> Int64 {
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])!
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values.isRegularFile == true { total += Int64(values.fileSize ?? 0) }
        }
        return total
    }
    public func verify(_ build: BuildRecord) async throws {
        let checksum = try await Task.detached { try SHA256File.hash(URL(fileURLWithPath: build.iso)) }.value
        guard checksum == build.sha256 else { throw StageError.message("The ISO has changed since this build. Rebuild before burning or delivering it.") }
        guard !FileManager.default.fileExists(atPath: URL(fileURLWithPath: build.folder).appendingPathComponent("BUILD-INCOMPLETE.txt").path) else {
            throw StageError.message("This build is incomplete.")
        }
    }
    public func burn(_ build: BuildRecord, device: String, log: @escaping @Sendable (String) -> Void) async throws {
        try await verify(build)
        guard !device.isEmpty else { throw StageError.message("Choose a burner device first.") }
        _ = try await runner.run(Command("/usr/bin/hdiutil", ["burn", "-device", device, "-verifyburn", "-noaddpmap", "-nosynthesize", "-forceclose", "-speed", "2", build.iso], label: "Burn and verify test disc"), log: log)
    }
    public func handoff(project: Project, build: BuildRecord, update: @escaping @Sendable (String) -> Void) async throws {
        try await verifyForReport(build)
        let root = URL(fileURLWithPath: build.folder)
        let authoredProject = try Project.open(root.appendingPathComponent("project.stagedisc"))
        let disc = root.appendingPathComponent("disc-root")
        let urls = try Self.regularFiles(disc)
        var checksumRows = ["\(build.sha256)  test-disc.iso"]
        for url in urls.sorted(by: { $0.path < $1.path }) {
            update("Hashing \(url.lastPathComponent)")
            let hash = try SHA256File.hash(url)
            checksumRows.append("\(hash)  " + String(url.path.dropFirst(root.path.count + 1)))
        }
        let checksumFile = root.appendingPathComponent("SHA256SUMS.txt")
        let checksumText = checksumRows.joined(separator: "\n") + "\n"
        if FileManager.default.fileExists(atPath: checksumFile.path) {
            guard try String(contentsOf: checksumFile, encoding: .utf8) == checksumText else { throw StageError.message("The authored disc tree has changed since the build. Rebuild before updating the handoff package.") }
        } else { try checksumText.write(to: checksumFile, atomically: true, encoding: .utf8) }
        let tests = project.playerTests.filter { $0.buildID == build.id }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(tests).write(to: root.appendingPathComponent("player-tests.json"), options: .atomic)
        let tested = tests.filter { $0.result == "Pass" }.count
        let text = """
        # StageDisc handoff report

        Project: \(authoredProject.name)
        Build: \(build.id)
        Format: \(authoredProject.format.label)
        Test ISO: test-disc.iso
        ISO size: \(build.bytes) bytes
        ISO SHA-256: \(build.sha256)
        Passing player tests recorded for this build: \(tested)

        This package contains a BDMV disc folder and UDF 2.50 test image with a BD-J menu.
        Development organisation/disc IDs are used. The mastering facility must assign production IDs.
        It is NOT a BDCMF/UHD-BDCMF replication master and has no AACS encryption.
        Automated checks are basic preparation checks, not full disc conformance verification.
        Obtain the plant's written acceptance or a mastering conversion service before delivery.
        Test the converted/encrypted production master or plant check disc again before approving pressing.

        Pressing plant: \(project.plant.isEmpty ? "Not chosen" : project.plant)
        Requirements / acceptance notes: \(project.plantRequirements.isEmpty ? "Not confirmed" : project.plantRequirements)

        ## Content and menu
        \(authoredProject.titles.enumerated().map { "\($0.offset + 1). \($0.element.name) — \(Timecode.string($0.element.media?.duration ?? 0)), \($0.element.chapters.count) chapters" }.joined(separator: "\n"))

        ## Audio mixes
        \(authoredProject.titles.flatMap { title in title.selectedAudio(defaultMode: authoredProject.audioMode).map { "- \(title.name) / \($0.name): \($0.mode.label), \($0.stream?.channels ?? 0) channels; source \($0.stream?.profile ?? $0.stream?.codec ?? "unknown"); manual offset \($0.delayMS) ms" } }.joined(separator: "\n"))
        Bitstream copying preserves supplied codec extensions; this report does not certify Atmos/DTS:X presence.
        Audio album mode: \(authoredProject.isAlbum ? "Yes (Pure Audio/AES-21id conformance unverified)" : "No")

        ## Player tests for this exact build
        \(tests.isEmpty ? "No physical player tests recorded." : tests.map { "- \($0.player): \($0.result). \($0.notes)" }.joined(separator: "\n"))

        ## Test before approving production
        - Cold-start disc to branded menu; check arrow keys, Enter and Back/Menu.
        - Play the complete concert; check sync and all selected audio tracks.
        - Enter every song from the selection menu; check skip forward/back.
        - Play every extra and confirm return to the menu at the end.
        - Check stop, resume, eject/reload and at least two standalone player models.
        - UHD: confirm colour/HDR signalling with the intended display and player.
        - Confirm factory format, mastering conversion, layer layout and protection requirements.
        """
        try text.write(to: root.appendingPathComponent("HANDOFF.md"), atomically: true, encoding: .utf8)
    }
    private func verifyForReport(_ build: BuildRecord) async throws {
        let checksum = try SHA256File.hash(URL(fileURLWithPath: build.iso))
        guard checksum == build.sha256 else { throw StageError.message("Build ISO checksum no longer matches.") }
    }
    private static func regularFiles(_ folder: URL) throws -> [URL] {
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])!
        var urls: [URL] = []
        for case let url as URL in enumerator { if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true { urls.append(url) } }
        return urls
    }
}
private final class BuildLog: @unchecked Sendable {
    private let lock = NSLock(); private let url: URL
    init(_ url: URL) { self.url = url; FileManager.default.createFile(atPath: url.path, contents: nil) }
    func append(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        guard let file = try? FileHandle(forWritingTo: url) else { return }
        defer { try? file.close() }
        _ = try? file.seekToEnd(); try? file.write(contentsOf: Data(text.utf8))
    }
}
