import Foundation
import AppKit
import StageDiscCore

@main struct StageDiscCLI {
    @MainActor static func main() async {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
        var args = Array(CommandLine.arguments.dropFirst())
        var resources = ProcessInfo.processInfo.environment["STAGEDISC_RESOURCES"]
        if let index = args.firstIndex(of: "--resources"), args.count > index + 1 {
            resources = args[index + 1]; args.removeSubrange(index...index + 1)
        }
        let tools = Toolchain(resources: resources)
        do {
            guard let verb = args.first else { throw StageError.message("Usage: stagedisc probe FILE | demo PROJECT CONCERT EXTRA | check PROJECT | build PROJECT DESTINATION [--resources PATH]") }
            switch verb {
            case "probe":
                guard args.count == 2 else { throw StageError.message("probe FILE") }
                let info = try await Probe.read(args[1], tools: tools, runner: ProcessRunner())
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                print(String(decoding: try encoder.encode(info), as: UTF8.self))
            case "demo":
                guard args.count == 4 else { throw StageError.message("demo PROJECT CONCERT EXTRA") }
                var project = Project(); project.name = "StageDisc verification"; project.menu.band = "THE NIGHT SIGNAL"
                project.menu.heading = "One night.\nAll the noise."; project.menu.tagline = "Live at the waterfront"
                for (i, path) in args.dropFirst(2).enumerated() {
                    var title = DiscTitle(name: i == 0 ? "The concert" : "Behind the scenes", path: URL(fileURLWithPath: path).path)
                    title.media = try await Probe.read(title.path, tools: tools, runner: ProcessRunner())
                    title.audioIndices = title.media!.audio.map(\.index)
                    if i == 0 { title.chapters = [Chapter(name: "Lights up", seconds: 0), Chapter(name: "The last song", seconds: 3)] }
                    project.titles.append(title)
                }
                try project.save(to: URL(fileURLWithPath: args[1])); print("Demo project saved")
            case "check":
                guard args.count == 2 else { throw StageError.message("check PROJECT") }
                let project = try Project.open(URL(fileURLWithPath: args[1]))
                let issues = Preflight.inspect(project, tools: tools)
                for issue in issues { print("\(issue.severity == .error ? "ERROR" : "NOTE"): \(issue.message)") }
                if issues.contains(where: { $0.severity == .error }) { exit(1) }
            case "build":
                guard args.count == 3 else { throw StageError.message("build PROJECT DESTINATION") }
                let project = try Project.open(URL(fileURLWithPath: args[1]))
                let build = try await BuildEngine().build(project: project, tools: tools, destination: URL(fileURLWithPath: args[2]),
                    update: { name, fraction in print(String(format: "[%3.0f%%] %@", fraction * 100, name)) }, log: { text in
                        FileHandle.standardOutput.write(Data(text.utf8))
                    })
                print("\nBUILD_READY=\(build.folder)")
            default: throw StageError.message("Unknown command \(verb)")
            }
        } catch { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1) }
    }
}
