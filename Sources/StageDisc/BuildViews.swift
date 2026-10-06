import SwiftUI
import AppKit
import StageDiscCore

struct BuildView: View {
    @EnvironmentObject var store: Store
    @State var showBurn = false
    @State var player = ""
    @State var result = "Pass"
    @State var notes = ""
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Card(title: "Build a test image") {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(ByteCountFormatter.string(fromByteCount: store.project.estimatedBytes, countStyle: .file)) estimated / \(store.project.capacity.label)").font(.title3)
                            Text("A new build gets its own folder, source snapshot and SHA-256 checksum.").font(.caption).foregroundStyle(.secondary)
                        }; Spacer()
                        Button("Build test ISO", systemImage: "opticaldisc") { store.buildDisc() }.buttonStyle(.borderedProminent).disabled(store.issues.contains { $0.severity == .error })
                    }
                    ForEach(store.issues) { issue in
                        HStack(alignment: .top, spacing: 8) { Image(systemName: issue.severity == .error ? "exclamationmark.circle.fill" : "info.circle").foregroundStyle(issue.severity == .error ? .red : Color.stageGold); Text(issue.message).font(.caption).foregroundStyle(issue.severity == .error ? Color.primary : .secondary) }
                    }
                }
                if let build = store.build {
                    Card(title: "The exact build you’re testing") {
                        Picker("Build", selection: $store.selectedBuild) { ForEach(store.project.builds) { Text($0.id).tag(Optional($0.id)) } }
                        Text("SHA-256  \(build.sha256)").font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                        if (try? store.project.fingerprint()) != build.projectFingerprint { Text("Project settings have changed since this image was built. Existing player tests still refer to this image.").font(.caption).foregroundStyle(Color.stageGold) }
                        HStack {
                            Button("Reveal ISO", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: build.iso)]) }
                            Button("Verify checksum") { store.verifyBuild() }
                            Button("Burn test disc…", systemImage: "flame") { showBurn = true }.buttonStyle(.borderedProminent)
                        }
                    }
                    Card(title: "Record a physical-player test") {
                        HStack { TextField("Player model / firmware", text: $player).textFieldStyle(.roundedBorder); Picker("Result", selection: $result) { Text("Pass").tag("Pass"); Text("Fail").tag("Fail"); Text("Partial").tag("Partial") }.frame(width: 170) }
                        TextField("Menu, song seek, audio sync, extras, return behaviour…", text: $notes, axis: .vertical).textFieldStyle(.roundedBorder)
                        HStack { Spacer(); Button("Record result") {
                            store.project.playerTests.append(PlayerTest(buildID: build.id, player: player, result: result, notes: notes)); player = ""; notes = ""
                            if let url = store.projectURL { try? store.project.save(to: url) }
                        }.disabled(player.trimmingCharacters(in: .whitespaces).isEmpty) }
                        ForEach(store.project.playerTests.filter { $0.buildID == build.id }) { test in
                            HStack(alignment: .top) { Text(test.result).foregroundStyle(test.result == "Pass" ? .green : Color.stageGold); VStack(alignment: .leading) { Text(test.player); Text(test.notes).font(.caption).foregroundStyle(.secondary) }; Spacer() }
                        }
                    }
                }
                if !store.log.isEmpty { Card(title: "Build log") { ScrollView { Text(store.log).font(.system(.caption2, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 180) } }
            }.padding(28)
        }.sheet(isPresented: $showBurn) { BurnSheet().environmentObject(store) }
    }
}
struct BurnSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State var devices = "Loading burners…"
    @State var device = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Burn a test disc").font(.title2.bold())
            Text("Insert a blank disc of the selected capacity. The ISO checksum is checked first, then the burn is verified. This writes permanently to recordable media.").foregroundStyle(.secondary)
            ScrollView { Text(devices).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(height: 120)
            TextField("Burner device path from the list", text: $device).textFieldStyle(.roundedBorder)
            Text("Use the device path listed above, for example IOService:/… . A Blu-ray-capable burner is required.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Burn & verify") { dismiss(); store.burn(device: device) }.buttonStyle(.borderedProminent).disabled(device.trimmingCharacters(in: .whitespaces).isEmpty) }
        }.padding(28).frame(width: 600)
        .task {
            do { let result = try await ProcessRunner().run(Command("/usr/bin/hdiutil", ["burn", "-list"], label: "List burners")); devices = String(decoding: result.stdout, as: UTF8.self) }
            catch { devices = error.localizedDescription }
        }
    }
}
struct HandoffView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Card(title: "Factory requirements") {
                    TextField("Pressing plant / mastering service", text: $store.project.plant).textFieldStyle(.roundedBorder)
                    TextField("Accepted format, conversion service, capacity, protection, contact…", text: $store.project.plantRequirements, axis: .vertical).lineLimit(3...6).textFieldStyle(.roundedBorder)
                    Text("Ask whether they accept ISO or BDMV for conversion, or require BDCMF / UHD-BDCMF. Confirm who supplies the final conformance check and production check disc.").font(.callout).foregroundStyle(.secondary)
                }
                Card(title: "Handoff package") {
                    if let build = store.build {
                        Text(build.id).font(.system(.caption, design: .monospaced)).foregroundStyle(Color.stageGold)
                        Text("The build folder contains the test ISO, authored disc tree, project snapshot, menu map, command log, checksums and handoff report. Player results are tied to the build ID.").foregroundStyle(.secondary)
                        Button("Update report & reveal package", systemImage: "shippingbox") { store.exportReport() }.buttonStyle(.borderedProminent)
                    } else { Text("Build a test image first, then record your player tests here before handing over the release.").foregroundStyle(.secondary) }
                    Divider()
                    Text("Factory master status: conversion / acceptance required").font(.headline).foregroundStyle(Color.stageGold)
                    Text("StageDisc does not generate BDCMF, AACS protection or a plant-certified master. After conversion, test the factory’s production master or check disc again before authorising pressing.").font(.callout).foregroundStyle(.secondary)
                }
                Card(title: "What to confirm on the test burn") {
                    Text("Cold start → menu → concert → every song → every extra → return to menu.\nCheck audio selection, lip sync, chapter skip, stop/resume and eject/reload.\nUse at least two standalone player models. For UHD, check colour and HDR signalling on the intended display.").font(.callout).lineSpacing(9).foregroundStyle(.secondary)
                }
            }.padding(28)
        }
    }
}
struct ToolsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tools & dependencies").font(.title2.bold())
            Text("FFmpeg, FFprobe, tsMuxer, the UDF writer and disc-menu runtime are included. No Homebrew or Java installation is needed to author discs.").font(.callout).foregroundStyle(.secondary)
            if !Toolchain.isAppStore {
                path("FFmpeg", $store.tools.ffmpeg); path("FFprobe", $store.tools.ffprobe); path("tsMuxer", $store.tools.tsmuxer)
                path("UDF writer", $store.tools.udf); path("Menu runtime JAR", $store.tools.menuRuntime)
            }
            Link("Open-source licences & corresponding source", destination: URL(string: "https://github.com/lurcheous73/stagedisc")!)
            Button("Grant access to a source folder…") { store.grantSourceFolder() }
            HStack { Text(store.tools.missing.isEmpty ? "All tools located" : "Missing: " + store.tools.missing.joined(separator: ", ")).font(.caption).foregroundStyle(store.tools.missing.isEmpty ? .green : Color.stageGold); Spacer(); Button("Reset detection") { store.tools = Toolchain() }; Button("Done") { store.persistTools(); dismiss() }.buttonStyle(.borderedProminent) }
        }.padding(28).frame(width: 780)
    }
    func path(_ label: String, _ binding: Binding<String>) -> some View {
        HStack { Text(label).frame(width: 135, alignment: .leading); TextField("Path", text: binding).textFieldStyle(.roundedBorder); Button("Choose…") { let panel = NSOpenPanel(); if panel.runModal() == .OK, let url = panel.url { binding.wrappedValue = url.path } } }
    }
}
