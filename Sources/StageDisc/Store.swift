import SwiftUI
import AppKit
import StageDiscCore

@MainActor final class Store: ObservableObject {
    @Published var project = Project()
    @Published var tools = Toolchain()
    @Published var selectedTitle: UUID?
    @Published var busy = false
    @Published var progress = 0.0
    @Published var status = "Ready to create your first disc"
    @Published var log = ""
    @Published var error: String?
    @Published var projectURL: URL?
    @Published var selectedBuild: String?
    var job: Task<Void, Never>?
    let engine = BuildEngine()
    let access = FileAccess()
    var build: BuildRecord? { project.builds.first { $0.id == selectedBuild } ?? project.builds.last }
    var titleIndex: Int? { project.titles.firstIndex { $0.id == selectedTitle } }
    var issues: [PreflightIssue] { Preflight.inspect(project, tools: tools) }
    init() {
        if !Toolchain.isAppStore, let data = UserDefaults.standard.data(forKey: "StageDisc.tools"), let saved = try? JSONDecoder().decode(Toolchain.self, from: data) { tools = saved }
    }
    func persistTools() { UserDefaults.standard.set(try? JSONEncoder().encode(tools), forKey: "StageDisc.tools") }
    func append(_ text: String) { log += text; if log.count > 120_000 { log = String(log.suffix(120_000)) } }
    func run(_ name: String, action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true; status = name; progress = 0; log = ""
        job = Task {
            do { try await action(); if !Task.isCancelled { status = "\(name) complete" } }
            catch { if Task.isCancelled { status = "Cancelled · partial build retained" } else { self.error = error.localizedDescription; status = "Needs attention" } }
            busy = false; job = nil
        }
    }
    func cancel() { job?.cancel(); engine.cancel() }
    func importMedia() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.allowedFileTypes = ["mov", "mp4", "mkv", "m2ts", "mts", "ts", "mxf"] + (project.isAlbum ? ["wav", "aif", "aiff", "flac", "caf", "m4a", "mka"] : [])
        guard panel.runModal() == .OK else { return }; let urls = panel.urls
        run("Inspecting media") { for url in urls { try await self.add(url) } }
    }
    func add(_ url: URL) async throws {
        remember(url)
        var title = DiscTitle(name: url.deletingPathExtension().lastPathComponent, path: url.path)
        let media = try await Probe.read(url.path, tools: tools, runner: engine.runner)
        guard media.video != nil || (project.isAlbum && !media.audio.isEmpty) else { throw StageError.message("\(url.lastPathComponent) has no video. Choose Audio album mode to import an audio-only master.") }
        title.media = media; title.audioIndices = media.audio.map(\.index)
        title.audioTracks = media.audio.map { self.track(for: $0, media: media, url: url) }
        if !media.chapters.isEmpty {
            title.chapters = media.chapters
            if title.chapters.first?.seconds != 0 { title.chapters.insert(Chapter(name: "Opening", seconds: 0), at: 0) }
        }
        project.titles.append(title); selectedTitle = title.id
    }
    func track(for stream: MediaStream, media: MediaInfo, url: URL) -> AudioTrack {
        AudioTrack(name: "\(stream.profile ?? stream.codec.uppercased()) · \(stream.channelLayout ?? "\(stream.channels ?? 0) channels")", path: url.path, streamIndex: stream.index, media: media,
                   mode: AudioAuthoring.passthroughCodecs.contains(stream.codec) ? .preserve : project.audioMode)
    }
    func ensureTracks(_ index: Int) {
        if project.titles[index].audioTracks == nil { project.titles[index].audioTracks = project.titles[index].selectedAudio(defaultMode: project.audioMode) }
    }
    func importAudio(_ index: Int) {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.allowedFileTypes = ["wav", "aif", "aiff", "flac", "caf", "ac3", "eac3", "dts", "dtshd", "thd", "truehd", "mka", "mkv", "mp4", "m4a"]
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        for url in urls { remember(url) }
        ensureTracks(index)
        run("Inspecting separate audio mixes") {
            for url in urls {
                let media = try await Probe.read(url.path, tools: self.tools, runner: self.engine.runner)
                guard !media.audio.isEmpty else { throw StageError.message("No audio in \(url.lastPathComponent). Supply an encoded delivery file, not an ADM/object session.") }
                let streams = media.audio.contains { $0.codec == "truehd" } && ["thd", "thd+ac3", "truehd"].contains(url.pathExtension.lowercased()) ? media.audio.filter { $0.codec == "truehd" } : media.audio
                for stream in streams {
                    var track = self.track(for: stream, media: media, url: url)
                    track.name = url.deletingPathExtension().lastPathComponent + " · " + (stream.channelLayout ?? stream.codec.uppercased())
                    self.project.titles[index].audioTracks!.append(track)
                }
            }
        }
    }
    func demo() {
        guard let root = Bundle.main.resourceURL else { return }
        run("Loading demo project") {
            self.project = Project(); self.project.name = "StageDisc demo"
            self.project.menu.band = "THE NIGHT SIGNAL"; self.project.menu.heading = "One night.\nAll the noise."
            self.project.menu.tagline = "Live at the waterfront"
            try await self.add(root.appendingPathComponent("demo/concert.mp4"))
            self.project.titles[0].name = "The concert"
            self.project.titles[0].chapters = [Chapter(name: "Lights up", seconds: 0), Chapter(name: "The last song", seconds: 3)]
            try await self.add(root.appendingPathComponent("demo/extra.mp4"))
            self.project.titles[1].name = "Behind the scenes"
            self.selectedTitle = self.project.titles[0].id
        }
    }
    func save(as: Bool = false) {
        var target = projectURL
        if target == nil || `as` {
            let panel = NSSavePanel(); panel.allowedFileTypes = ["stagedisc"]; panel.nameFieldStringValue = project.name + ".stagedisc"
            guard panel.runModal() == .OK else { return }; target = panel.url
        }
        do { remember(target!); try project.save(to: target!); projectURL = target; status = "Project saved" } catch { self.error = error.localizedDescription }
    }
    func openProject() {
        let panel = NSOpenPanel(); panel.allowedFileTypes = ["stagedisc"]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { project = try Project.open(url); access.restore(project.fileBookmarks ?? [:]); remember(url); projectURL = url; selectedTitle = project.titles.first?.id; selectedBuild = project.builds.last?.id; status = "Project opened" }
        catch { self.error = error.localizedDescription }
    }
    func newProject() { project = Project(); projectURL = nil; selectedTitle = nil; selectedBuild = nil; status = "New project" }
    func buildDisc() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.prompt = "Build here"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        remember(folder)
        let snapshot = project, toolSnapshot = tools
        run("Building test disc") {
            let record = try await self.engine.build(project: snapshot, tools: toolSnapshot, destination: folder, update: { name, progress in
                Task { @MainActor in self.status = name; self.progress = progress }
            }, log: { text in Task { @MainActor in self.append(text) } })
            self.project.builds.append(record); self.selectedBuild = record.id
            if let url = self.projectURL { try self.project.save(to: url) }
        }
    }
    func verifyBuild() {
        guard let build else { return }
        run("Verifying ISO checksum") { try await self.engine.verify(build); self.append("SHA-256 matches the original build.\n") }
    }
    func burn(device: String) {
        guard let build else { return }
        run("Burning and verifying disc") {
            try await self.engine.burn(build, device: device, log: { text in Task { @MainActor in self.append(text) } })
        }
    }
    func exportReport() {
        guard let build else { return }
        let snapshot = project
        run("Updating handoff report") {
            try await self.engine.handoff(project: snapshot, build: build, update: { text in Task { @MainActor in self.status = text } })
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: build.folder).appendingPathComponent("HANDOFF.md")])
        }
    }
    func remember(_ url: URL) {
        guard let bookmark = access.remember(url) else { return }
        if project.fileBookmarks == nil { project.fileBookmarks = [:] }
        project.fileBookmarks![url.path] = bookmark
    }
    func grantSourceFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "Allow access"
        guard panel.runModal() == .OK, let url = panel.url else { return }; remember(url)
        status = "Source-folder access granted for this project"
    }
}
