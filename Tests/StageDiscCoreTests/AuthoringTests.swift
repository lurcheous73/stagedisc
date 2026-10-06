import XCTest
@testable import StageDiscCore

final class AuthoringTests: XCTestCase {
    func project() -> Project {
        var project = Project()
        var title = DiscTitle(name: "Concert", path: "/source with spaces & punctuation.mov")
        title.media = MediaInfo(duration: 120, size: 400_000_000, streams: [
            MediaStream(index: 0, kind: "video", codec: "prores", width: 3840, height: 2160, pixelFormat: "yuv422p10le", frameRate: 23.976, fieldOrder: "progressive", colorTransfer: "bt709", colorPrimaries: "bt709", colorSpace: "bt709"),
            MediaStream(index: 1, kind: "audio", codec: "pcm_s24le", channels: 2, channelLayout: "stereo", sampleRate: 48000, language: "eng")], chapters: [])
        title.audioIndices = [1]; title.chapters = [Chapter(name: "Opening", seconds: 0), Chapter(name: "Second song", seconds: 60)]
        project.titles = [title]; return project
    }
    func testTimecodesRejectInvalidAndNonFiniteTimes() {
        XCTAssertEqual(Timecode.parse("01:02:03.5"), 3723.5)
        XCTAssertEqual(Timecode.string(3723.5), "01:02:03.500")
        for invalid in ["NaN", "infinity", "-1", "00:60:00", "00:00:60", "01::03", "1.5:02:03", "1:2:3:4"] { XCTAssertNil(Timecode.parse(invalid), invalid) }
    }
    func testChaptersCannotRunPastEndOrGoBackwards() {
        var project = project()
        project.titles[0].chapters = [Chapter(name: "Start", seconds: 0), Chapter(name: "Past end", seconds: 121)]
        let issues = Preflight.inspect(project, tools: Toolchain(), checkFiles: false)
        XCTAssertTrue(issues.contains { $0.message.contains("outside the film") })
        project.titles[0].chapters = [Chapter(name: "Start", seconds: 0), Chapter(name: "Later", seconds: 50), Chapter(name: "Earlier", seconds: 20)]
        XCTAssertTrue(Preflight.inspect(project, tools: Toolchain(), checkFiles: false).contains { $0.message.contains("strictly increasing") })
    }
    func testHDRCannotBeSilentlyConvertedToSDR() {
        var project = project(); project.titles[0].media!.streams[0].colorTransfer = "smpte2084"
        XCTAssertTrue(Preflight.inspect(project, tools: Toolchain(), checkFiles: false).contains { $0.severity == .error && $0.message.contains("HDR cannot") })
    }
    func testUHDEncodingIsExplicitlyBlocked() {
        var project = project(); project.format = .uhd
        XCTAssertTrue(Preflight.inspect(project, tools: Toolchain(), checkFiles: false).contains { $0.severity == .error && $0.message.contains("UHD currently requires") })
    }
    func testCommandArgumentsKeepSourcePathIntactAndPCMUncompressed() throws {
        let project = project()
        let plan = try AuthoringPlan.title(project.titles[0], number: 1, project: project, tools: Toolchain(), folder: URL(fileURLWithPath: "/build with spaces"))
        XCTAssertTrue(plan.video.arguments.contains(project.titles[0].path))
        XCTAssertTrue(plan.video.arguments.contains("libx264"))
        XCTAssertTrue(plan.audio[0].arguments.contains("pcm_s24le"))
        XCTAssertFalse(plan.audio[0].arguments.contains("-ac")) // no implicit channel downmix
        XCTAssertTrue(plan.meta.contains("--custom-chapters=00:00:00.000;00:01:00.000"))
        XCTAssertTrue(plan.meta.contains("--mplsOffset=1 --m2tsOffset=1"))
    }
    func testEverySongAndExtraIsReachableThroughPagedMenus() {
        var project = project()
        project.titles[0].chapters = (0..<22).map { Chapter(name: "Song \($0)", seconds: Double($0 * 5)) }
        project.titles += (1..<12).map { DiscTitle(name: "Extra \($0)", path: "/extra\($0).mov") }
        let pages = MenuPlan.pages(project)
        XCTAssertTrue(pages.allSatisfy { $0.buttons.count <= 9 })
        let buttons = pages.flatMap(\.buttons)
        let songs = buttons.filter { $0.playlist == 1 && $0.label != "Play concert" && $0.audioSlot == nil }
        XCTAssertEqual(songs.count, 22)
        XCTAssertEqual(Set(buttons.compactMap(\.playlist)), Set(1...12))
        for target in buttons.compactMap(\.targetPage) { XCTAssertTrue(pages.contains { $0.id == target }) }
    }
    func testFingerprintInvalidatesContentEditsButIgnoresTestNotes() throws {
        var project = project(); let original = try project.fingerprint()
        project.plant = "Chosen plant"
        project.playerTests = [PlayerTest(buildID: "123", player: "Player", result: "Pass", notes: "Works")]
        XCTAssertEqual(try project.fingerprint(), original)
        project.titles[0].chapters[1].seconds = 65
        XCTAssertNotEqual(try project.fingerprint(), original)
    }
    func testCopyModeNeverDecodesOrDropsImmersiveExtensions() throws {
        var project = project()
        let media = MediaInfo(duration: 120, size: 1000, streams: [MediaStream(index: 0, kind: "audio", codec: "truehd", channels: 8, channelLayout: "7.1", sampleRate: 48000), MediaStream(index: 1, kind: "audio", codec: "ac3", channels: 6, sampleRate: 48000)], chapters: [])
        let track = AudioTrack(name: "Atmos", path: "/mixes/album.thd+ac3", streamIndex: 0, media: media, mode: .preserve)
        project.titles[0].audioTracks = [track]
        let plan = try AuthoringPlan.title(project.titles[0], number: 1, project: project, tools: Toolchain(), folder: URL(fileURLWithPath: "/build"))
        XCTAssertEqual(plan.audio[0].tool, "/bin/cp")
        XCTAssertFalse(plan.meta.contains("down-to-ac3"))
        XCTAssertFalse(plan.meta.contains("down-to-dts"))
        XCTAssertTrue(plan.meta.contains("A_AC3"))
        XCTAssertTrue(plan.meta.contains("--new-audio-pes")) // TrueHD/core require distinct PES substream identifiers
        XCTAssertTrue(Preflight.inspect(project, tools: Toolchain(), checkFiles: false).contains { $0.message.contains("include a compatible") })
        var containerTrack = track; containerTrack.path = "/mixes/album.mkv"
        XCTAssertThrowsError(try AudioAuthoring.command(containerTrack, number: 0, tools: Toolchain(), folder: URL(fileURLWithPath: "/build")))
        containerTrack.media.streams[0].codec = "dts"
        let (command, _, _) = try AudioAuthoring.command(containerTrack, number: 0, tools: Toolchain(), folder: URL(fileURLWithPath: "/build"))
        XCTAssertTrue(command.arguments.contains("copy")); XCTAssertFalse(command.arguments.contains("-af")); XCTAssertFalse(command.arguments.contains("-ar"))
    }
    func testAudioAlbumNeedsNoSourceVideoAndHasReachableMixSelection() throws {
        var project = project(); project.contentMode = .album
        project.titles[0].media!.streams.removeFirst()
        project.titles[0].audioTracks = (0..<12).map { AudioTrack(name: "Mix \($0)", path: project.titles[0].path, streamIndex: 1, media: project.titles[0].media!, mode: .pcm16) }
        let issues = Preflight.inspect(project, tools: Toolchain(), checkFiles: false)
        XCTAssertFalse(issues.contains { $0.message.contains("has no video") || $0.message.contains("inspect the source") })
        let plan = try AuthoringPlan.title(project.titles[0], number: 1, project: project, tools: Toolchain(), folder: URL(fileURLWithPath: "/build"))
        XCTAssertTrue(plan.video.arguments.contains("/build/album.png"))
        let pages = MenuPlan.pages(project)
        XCTAssertEqual(pages.flatMap(\.buttons).compactMap(\.audioSlot), Array(1...12))
        XCTAssertTrue(pages.allSatisfy { $0.buttons.count <= 9 })
        XCTAssertTrue(MenuPlan.properties(pages, project: project).contains("album.autoplay=true"))
    }
    func testHighResolutionAndSurroundAudioAreValidatedWithoutImplicitDownmix() {
        let project = project(); var media = project.titles[0].media!
        media.streams[1].channels = 8; media.streams[1].channelLayout = "7.1"
        var track = AudioTrack(name: "7.1", path: project.titles[0].path, streamIndex: 1, media: media, mode: .pcm96)
        XCTAssertFalse(AudioAuthoring.inspect(track, title: project.titles[0], checkFiles: false).contains { $0.severity == .error })
        track.mode = .pcm192
        XCTAssertTrue(AudioAuthoring.inspect(track, title: project.titles[0], checkFiles: false).contains { $0.severity == .error })
        track.mode = .ac3
        XCTAssertTrue(AudioAuthoring.inspect(track, title: project.titles[0], checkFiles: false).contains { $0.message.contains("No automatic downmix") })
        track.mode = .preserve
        XCTAssertTrue(AudioAuthoring.inspect(track, title: project.titles[0], checkFiles: false).contains { $0.message.contains("copy mode accepts") })
    }
    func testIndexPatchPreservesVersionAndUHDData() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var data = Data(repeating: 0, count: 160)
        data.replaceSubrange(0..<8, with: Data("INDX0300".utf8)); data[11] = 64
        data[64 + 29] = 1; data[150] = 0xAB
        let file = folder.appendingPathComponent("index.bdmv"); try data.write(to: file)
        try BuildEngine.patchIndex(file)
        let patched = try Data(contentsOf: file)
        XCTAssertEqual(patched.prefix(8), Data("INDX0300".utf8)); XCTAssertEqual(patched[150], 0xAB)
        for offset in [68, 80, 94] { XCTAssertEqual(patched[offset], 0x80); XCTAssertEqual(String(decoding: patched[(offset + 6)..<(offset + 11)], as: UTF8.self), "00000") }
        XCTAssertEqual(patched.count, data.count)
    }
    func testSHA256KnownValue() { XCTAssertEqual(SHA256File.digest(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") }
}
