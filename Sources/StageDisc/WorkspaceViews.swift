import SwiftUI
import AppKit
import StageDiscCore

struct FilmsView: View {
    @EnvironmentObject var store: Store
    @State private var chapterEditor = false
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Button(store.project.isAlbum ? "Add album / bonus…" : "Add films…", systemImage: "plus") { store.importMedia() }.buttonStyle(.borderedProminent)
                ForEach(Array(store.project.titles.enumerated()), id: \.element.id) { index, title in
                    Button { store.selectedTitle = title.id } label: {
                        HStack(spacing: 12) {
                            Image(systemName: index == 0 ? "play.rectangle.fill" : "film").foregroundStyle(Color.stageGold)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(title.name).font(.system(size: 13, weight: .medium)).lineLimit(2)
                                Text(index == 0 ? (store.project.isAlbum ? "MAIN ALBUM" : "MAIN CONCERT") : "EXTRA \(index)").font(.system(size: 9)).foregroundStyle(.secondary)
                            }; Spacer()
                        }.padding(14).background(store.selectedTitle == title.id ? Color.stageGold.opacity(0.14) : Color.stagePanel, in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain)
                }
                if store.project.titles.isEmpty { Text(store.project.isAlbum ? "Add one continuous WAV, AIFF or FLAC album master. Add song chapters and separate stereo, surround or immersive mixes." : "Add your concert film, followed by any interviews, music videos or backstage extras.").font(.callout).foregroundStyle(.secondary).padding(.top, 20) }
                Spacer()
            }.frame(width: 220)
            if let index = store.titleIndex {
                ScrollView {
                    VStack(spacing: 20) {
                        Card(title: index == 0 ? (store.project.isAlbum ? "The album" : "The concert") : "Extra") {
                            TextField("Film title", text: $store.project.titles[index].name).textFieldStyle(.roundedBorder)
                            Text(URL(fileURLWithPath: store.project.titles[index].path).lastPathComponent).font(.caption).foregroundStyle(.secondary)
                            if let media = store.project.titles[index].media, let video = media.video {
                                HStack(spacing: 18) { metric("Duration", Timecode.string(media.duration)); metric("Picture", "\(video.width ?? 0) × \(video.height ?? 0)"); metric("Rate", String(format: "%.3f fps", video.frameRate ?? 0)) }
                                HStack { Text(video.codec.uppercased()); if video.isHDR { Text("HDR").foregroundStyle(Color.stageGold) } }.font(.caption).foregroundStyle(.secondary)
                            }
                            else if let media = store.project.titles[index].media { Text("\(Timecode.string(media.duration)) · audio master · artwork video will be generated").font(.callout).foregroundStyle(.secondary) }
                            HStack {
                                Button("Preview source", systemImage: "play") { NSWorkspace.shared.open(URL(fileURLWithPath: store.project.titles[index].path)) }
                                if index != 0 { Button("Set as main title") { store.project.titles.swapAt(0, index) } }
                                Spacer(); Button("Remove") { store.project.titles.remove(at: index); store.selectedTitle = store.project.titles.first?.id }
                            }
                        }
                        Card(title: "Audio tracks") {
                            HStack { Button("Add separate mixes…", systemImage: "plus") { store.importAudio(index) }; Spacer(); Text("First mix is the default").font(.caption).foregroundStyle(.secondary) }
                            ForEach(Array((store.project.titles[index].audioTracks ?? []).enumerated()), id: \.element.id) { n, track in
                                AudioTrackRow(track: Binding(get: {
                                    store.project.titles[index].audioTracks?.first { $0.id == track.id } ?? track
                                }, set: { value in
                                    if let position = store.project.titles[index].audioTracks?.firstIndex(where: { $0.id == track.id }) { store.project.titles[index].audioTracks![position] = value }
                                }), slot: n + 1, move: {
                                    if n > 0 { store.project.titles[index].audioTracks!.swapAt(n, n - 1) }
                                }, duplicate: {
                                    var copy = track; copy.id = UUID(); copy.name += " (alternative)"; store.project.titles[index].audioTracks!.append(copy)
                                }, remove: { store.project.titles[index].audioTracks!.removeAll { $0.id == track.id } })
                            }
                            if let media = store.project.titles[index].media {
                                Menu("Add embedded track") { ForEach(media.audio) { stream in
                                    Button("Stream \(stream.index) · \(stream.profile ?? stream.codec.uppercased())") { store.project.titles[index].audioTracks!.append(store.track(for: stream, media: media, url: URL(fileURLWithPath: store.project.titles[index].path))) }
                                } }
                            }
                            Text("No automatic downmix or loudness processing. Copy mode preserves supplied DTS-HD / DTS:X and TrueHD / Atmos bitstreams. An Atmos ADM session needs external delivery encoding first.").font(.caption).foregroundStyle(.secondary)
                        }
                        Card(title: "Song chapters") {
                            HStack { Text("\(store.project.titles[index].chapters.count) chapters").foregroundStyle(.secondary); Spacer(); Button("Edit song list…") { chapterEditor = true } }
                            ForEach(store.project.titles[index].chapters) { chapter in
                                HStack { Text(Timecode.string(chapter.seconds)).monospacedDigit().font(.caption).foregroundStyle(Color.stageGold); Text(chapter.name); Spacer() }.font(.callout)
                            }
                        }
                    }
                }.onAppear { store.ensureTracks(index) }.onChange(of: store.selectedTitle) { store.ensureTracks(index) }
            } else { Spacer(); Text("Select a title to edit its songs and audio.").foregroundStyle(.secondary); Spacer() }
        }.padding(28)
        .sheet(isPresented: $chapterEditor) { if let index = store.titleIndex { ChapterEditor(index: index).environmentObject(store) } }
    }
    func metric(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(name).font(.caption).foregroundStyle(.secondary); Text(value).font(.system(size: 13, weight: .medium)).monospacedDigit() }
    }
}
struct AudioTrackRow: View {
    @Binding var track: AudioTrack
    let slot: Int
    let move: () -> Void
    let duplicate: () -> Void
    let remove: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("\(slot)").foregroundStyle(Color.stageGold); TextField("Mix label, e.g. Stereo / 5.1 / Dolby Atmos", text: $track.name).textFieldStyle(.roundedBorder); Button("↑", action: move).disabled(slot == 1); Button("Duplicate", action: duplicate); Button("Remove", action: remove) }
            Text("\(URL(fileURLWithPath: track.path).lastPathComponent) · stream \(track.streamIndex) · \(track.stream?.profile ?? track.stream?.codec.uppercased() ?? "Unknown") · \(track.stream?.channelLayout ?? "\(track.stream?.channels ?? 0) channels") · \((track.stream?.sampleRate ?? 0) / 1000) kHz").font(.caption).foregroundStyle(.secondary)
            Picker("Output", selection: $track.mode) { ForEach(AudioMode.allCases) { Text($0.label).tag($0) } }
            HStack { TextField("Language (ISO 3 letters)", text: $track.language).frame(width: 180); Text("Offset (ms)").font(.caption); TextField("0", value: $track.delayMS, format: .number).frame(width: 90); Spacer() }.textFieldStyle(.roundedBorder)
        }.padding(12).background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
    }
}
struct ChapterEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    var index: Int
    @State var text = ""
    @State var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Song chapters").font(.title2.bold())
            Text("One song per line: time | song name. Start the first at zero and keep times in order.").foregroundStyle(.secondary)
            Text("00:00:00.000 | Opening song\n00:04:32.500 | Second song").font(.system(.caption, design: .monospaced)).foregroundStyle(Color.stageGold)
            TextEditor(text: $text).font(.system(.body, design: .monospaced)).frame(width: 600, height: 330).border(.white.opacity(0.1))
            if let message { Text(message).foregroundStyle(.red).font(.caption) }
            HStack {
                Button("Import text file…") {
                    let panel = NSOpenPanel(); panel.allowedFileTypes = ["txt", "csv", "tsv"]
                    if panel.runModal() == .OK, let url = panel.url { do { text = try String(contentsOf: url, encoding: .utf8) } catch { message = error.localizedDescription } }
                }
                Spacer(); Button("Cancel") { dismiss() }; Button("Save song list") { commit() }.buttonStyle(.borderedProminent)
            }
        }.padding(28).onAppear { text = store.project.titles[index].chapters.map { "\(Timecode.string($0.seconds)) | \($0.name)" }.joined(separator: "\n") }
    }
    func commit() {
        var chapters: [Chapter] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "|", maxSplits: 1)
            guard parts.count == 2, let seconds = Timecode.parse(String(parts[0])), !parts[1].trimmingCharacters(in: .whitespaces).isEmpty else { message = "Use time | song name on every line."; return }
            chapters.append(Chapter(name: parts[1].trimmingCharacters(in: .whitespaces), seconds: seconds))
        }
        guard chapters.first?.seconds == 0 else { message = "The first chapter must start at 00:00:00."; return }
        for (i, chapter) in chapters.enumerated() {
            guard chapter.seconds < (store.project.titles[index].media?.duration ?? 0), i == 0 || chapter.seconds > chapters[i - 1].seconds else { message = "Times must increase and stay within the film."; return }
        }
        store.project.titles[index].chapters = chapters; dismiss()
    }
}
struct DiscMenuView: View {
    @EnvironmentObject var store: Store
    @State var pageID = 0
    @State var selection = 0
    var pages: [MenuPage] { MenuPlan.pages(store.project) }
    var page: MenuPage { pages.first { $0.id == pageID } ?? pages[0] }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image(nsImage: MenuRenderer.image(project: store.project, page: page, selection: selection))
                    .resizable().aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08)))
                HStack(spacing: 12) {
                    Picker("Page", selection: $pageID) { ForEach(pages) { Text($0.name).tag($0.id) } }.frame(width: 280)
                    Button { selection = (selection + page.buttons.count - 1) % max(1, page.buttons.count) } label: { Image(systemName: "arrow.up") }
                    Button { selection = (selection + 1) % max(1, page.buttons.count) } label: { Image(systemName: "arrow.down") }
                    Button("Enter") {
                        guard page.buttons.indices.contains(selection) else { return }
                        let button = page.buttons[selection]
                        if let next = button.targetPage { pageID = next; selection = 0 }
                        else if let slot = button.audioSlot { store.status = "Selected mix \(slot) for title \(button.playlist ?? 1) in the disc preview"; pageID = 0; selection = 0 }
                        else { store.status = "Preview action · \(button.label) at \(Timecode.string(button.seconds ?? 0)). Test playback in the built disc." }
                    }
                    Button("Main menu") { pageID = 0; selection = 0 }; Spacer()
                }
                Card(title: "Your band’s identity") {
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Band name", text: $store.project.menu.band)
                            TextField("Film heading", text: $store.project.menu.heading, axis: .vertical).lineLimit(1...3)
                            TextField("Tagline", text: $store.project.menu.tagline)
                        }.textFieldStyle(.roundedBorder)
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Accent", selection: $store.project.menu.accent) {
                                Text("Warm gold").tag("D5AE62"); Text("Ice blue").tag("83D8E8"); Text("Coral").tag("F49885"); Text("White").tag("EEEEEE")
                            }
                            Button("Choose background image…") {
                                let panel = NSOpenPanel(); panel.allowedFileTypes = ["png", "jpg", "jpeg", "tiff"]
                                if panel.runModal() == .OK, let url = panel.url { store.remember(url); store.project.menu.backgroundPath = url.path }
                            }
                            if store.project.menu.backgroundPath != nil { Button("Use stage-light background") { store.project.menu.backgroundPath = nil } }
                        }.frame(width: 250)
                    }
                    Text("The preview uses the same artwork exported to the disc. Menus contain playback, song selection, audio mixes and extras. Coloured remote buttons select the first four mixes during playback. Check navigation and mix switching on physical players.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(28)
        }.onChange(of: pageID) { selection = 0 }
    }
}
