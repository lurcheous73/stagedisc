import SwiftUI
import AppKit
import StageDiscCore

@main struct StageDiscApp: App {
    @StateObject private var store = Store()
    var body: some Scene {
        WindowGroup { MainView().environmentObject(store).preferredColorScheme(.dark).frame(minWidth: 1080, minHeight: 740) }
            .windowStyle(.titleBar)
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("New Project") { store.newProject() }.keyboardShortcut("n").disabled(store.busy)
                    Button("Open Project…") { store.openProject() }.keyboardShortcut("o").disabled(store.busy)
                    Button("Save Project…") { store.save() }.keyboardShortcut("s").disabled(store.busy)
                    Button("Save Project As…") { store.save(as: true) }.keyboardShortcut("s", modifiers: [.command, .shift]).disabled(store.busy)
                }
            }
    }
}
enum Section: String, CaseIterable, Identifiable {
    case project = "Project", films = "Media & audio", menu = "Disc menu", build = "Build & test", handoff = "Factory handoff"
    var id: String { rawValue }
    var icon: String {
        switch self { case .project: return "slider.horizontal.3"; case .films: return "film.stack"; case .menu: return "rectangle.3.group"; case .build: return "opticaldisc"; case .handoff: return "shippingbox" }
    }
}
struct MainView: View {
    @EnvironmentObject var store: Store
    @State private var section: Section = .project
    @State private var showTools = false
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 25) {
                HStack(spacing: 12) {
                    Image(systemName: "opticaldisc.fill").font(.system(size: 30)).foregroundStyle(Color.stageGold)
                    VStack(alignment: .leading, spacing: 2) { Text("STAGEDISC").font(.system(size: 17, weight: .bold, design: .rounded)); Text("FROM STAGE TO DISC").font(.system(size: 9, weight: .medium)).tracking(1.4).foregroundStyle(.secondary) }
                }.padding(.top, 25)
                VStack(spacing: 6) {
                    ForEach(Section.allCases) { item in
                        Button { section = item } label: {
                            HStack(spacing: 12) { Image(systemName: item.icon).frame(width: 20); Text(item.rawValue); Spacer() }
                                .font(.system(size: 13, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 13)
                                .foregroundStyle(section == item ? Color.stageGold : Color.white.opacity(0.7))
                                .background(section == item ? Color.stageGold.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain)
                    }
                }
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(store.project.titles.count) titles · \(store.project.capacity.label)").font(.caption).foregroundStyle(.secondary)
                    Text("Native macOS · Preview build").font(.caption2).foregroundStyle(.tertiary)
                    Button("Tools & dependencies", systemImage: "wrench.and.screwdriver") { showTools = true }.buttonStyle(.plain).foregroundStyle(Color.stageGold)
                }.padding(.bottom, 24)
            }.padding(.horizontal, 18).frame(minWidth: 215).background(Color.stagePanel)
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) { Text(section.rawValue).font(.system(size: 29, weight: .semibold)); Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Open", systemImage: "folder") { store.openProject() }
                    Button("Save", systemImage: "square.and.arrow.down") { store.save() }
                }.padding(28).disabled(store.busy)
                Divider()
                Group {
                    switch section { case .project: ProjectView(); case .films: FilmsView(); case .menu: DiscMenuView(); case .build: BuildView(); case .handoff: HandoffView() }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).disabled(store.busy)
                Divider()
                HStack(spacing: 12) {
                    if store.busy { ProgressView().controlSize(.small) } else { Circle().fill(Color.stageGold).frame(width: 6, height: 6) }
                    Text(store.status).font(.caption).lineLimit(1)
                    Spacer()
                    if store.busy { ProgressView(value: store.progress).frame(width: 150); Button("Cancel") { store.cancel() } }
                    else { Text("\(store.project.name)").font(.caption).foregroundStyle(.secondary) }
                }.padding(.horizontal, 24).padding(.vertical, 14)
            }.background(Color.stageBackground)
        }
        .tint(Color.stageGold)
        .sheet(isPresented: $showTools) { ToolsView().environmentObject(store) }
        .alert("Needs attention", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
    var subtitle: String {
        switch section { case .project: return "Set up the release and choose your test-disc format."; case .films: return store.project.isAlbum ? "A continuous album master, song chapters and separate audio mixes." : "Concert, extras and separate stereo, surround or immersive mixes."; case .menu: return "Design the menu your fans will see on their television."; case .build: return "Create an image, burn a test disc and record real-player results."; case .handoff: return "Keep the tested build and factory requirements together." }
    }
}
extension Color {
    static let stageGold = Color(red: 0.835, green: 0.682, blue: 0.384)
    static let stagePanel = Color(red: 0.065, green: 0.078, blue: 0.096)
    static let stageBackground = Color(red: 0.045, green: 0.055, blue: 0.070)
}
struct Card<Content: View>: View {
    let title: String; @ViewBuilder var content: () -> Content
    var body: some View { VStack(alignment: .leading, spacing: 18) { Text(title).font(.system(size: 16, weight: .semibold)); content() }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(Color.stagePanel, in: RoundedRectangle(cornerRadius: 13)) }
}
struct ProjectView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack(spacing: 20) {
                    Card(title: "The release") {
                        TextField("Project name", text: $store.project.name).textFieldStyle(.roundedBorder)
                        Picker("Release type", selection: Binding(get: { store.project.contentMode ?? .film }, set: { store.project.contentMode = $0 })) { ForEach(ContentMode.allCases) { Text($0.label).tag($0) } }
                        Picker("Disc format", selection: $store.project.format) { ForEach(DiscFormat.allCases) { Text($0.label).tag($0) } }
                        Picker("Test-disc capacity", selection: $store.project.capacity) { ForEach(Capacity.allCases) { Text($0.label).tag($0) } }
                        if store.project.isAlbum { Toggle("Play album automatically on insertion", isOn: Binding(get: { store.project.albumAutoplay != false }, set: { store.project.albumAutoplay = $0 })) }
                        Text("25 GB and 50 GB refer to the recordable test media. The plant will confirm the final replicated layout.").font(.caption).foregroundStyle(.secondary)
                    }
                    Card(title: "Picture & sound") {
                        Picker("Video", selection: $store.project.videoMode) { ForEach(VideoMode.allCases) { Text($0.label).tag($0) } }
                        Picker("Default audio", selection: $store.project.audioMode) { ForEach(AudioMode.allCases) { Text($0.label).tag($0) } }
                        if store.project.videoMode == .encode {
                            Stepper("Video target · \(store.project.videoMbps) Mb/s", value: $store.project.videoMbps, in: 5...35)
                        }
                        Text(store.project.format == .uhd ? "UHD accepts prepared 2160p HEVC Main 10. HDR video is copied without re-encoding. UHD playback needs physical testing." : "LPCM keeps uncompressed concert audio. Encoding supports progressive SDR sources at 23.976, 24, 25 and 29.97 fps.").font(.caption).foregroundStyle(.secondary)
                        Text("Set each mix’s format in Media & audio. Prepared DTS/DTS-HD, TrueHD and Atmos are copied; creating immersive masters requires an external encoder.").font(.caption).foregroundStyle(.secondary)
                        if store.project.isAlbum { Text("Audio-only sources receive an artwork video. A continuous master plus chapters avoids gaps between songs. Coloured remote buttons select the first four mixes.").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Card(title: "A repeatable route to the pressing plant") {
                    HStack(alignment: .top, spacing: 24) {
                        step("01", "Author", "Films, song chapters and your band’s menu.")
                        step("02", "Test", "Burn the ISO. Check menus, sync and playback on real players.")
                        step("03", "Handoff", "Send the accepted format with checksums and test notes.")
                    }
                    Divider()
                    Text("Factory acceptance is still to be confirmed. This app creates test ISO / BDMV outputs; BDCMF or UHD-BDCMF conversion may be required.").font(.callout).foregroundStyle(.secondary)
                }
                HStack { Button(store.project.isAlbum ? "Import album & bonus content…" : "Import concert & extras…", systemImage: "plus") { store.importMedia() }.buttonStyle(.borderedProminent); Button("Try the sample project") { store.demo() }; Spacer() }
            }.padding(28)
        }
    }
    func step(_ number: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(number).font(.system(size: 25, weight: .light)).foregroundStyle(Color.stageGold); Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
