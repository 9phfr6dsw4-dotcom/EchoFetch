import EchoFetchCore
import Foundation
import Observation

/// Sets up yt-dlp, ffmpeg, ffprobe and Deno from inside the app, and keeps yt-dlp (the download
/// engine) up to date on its own.
@MainActor
@Observable
final class ToolsController {
    enum SetupState: Equatable {
        case preparing
        case ready
        case failed(String)
    }

    enum EngineCheckState: Equatable {
        case idle
        case checking
        case upToDate
        case updated(String)
        case failed(String)
    }

    private(set) var setupState: SetupState = .preparing
    private(set) var engineCheck: EngineCheckState = .idle
    private(set) var installed = InstalledTools()
    private(set) var bundled: [ToolManifestEntry] = []
    private(set) var lastEngineCheck: Date? = Preferences.lastEngineCheck

    let paths = ToolPaths(directory: AppSupportDirectory.tools)

    var engineVersion: String? {
        version(of: "yt-dlp")
    }

    func version(of name: String) -> String? {
        installed.tools[name]?.version ?? bundled.first(where: { $0.name == name })?.version
    }

    var setupProblem: String? {
        if case .failed(let message) = setupState { return message }
        return nil
    }

    /// Unpacks any tools that are missing or older than the ones inside this copy of the app.
    func prepare() async {
        setupState = .preparing
        let source = Bundle.main.resourceURL?.appendingPathComponent("Tools", isDirectory: true)
        let directory = paths.directory
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try ToolInstaller(sourceDirectory: source, toolsDirectory: directory).installMissingTools()
            }.value
            installed = result.installed
            bundled = result.bundled
            setupState = .ready
        } catch {
            setupState = .failed(error.localizedDescription)
        }
    }

    /// Waits while the tools are being set up or the engine is being updated.
    /// Returns false when the tools couldn't be set up.
    func waitUntilReady() async -> Bool {
        while setupState == .preparing || engineCheck == .checking {
            if Task.isCancelled { return false }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return setupState == .ready
    }

    func checkForEngineUpdateIfDue() async {
        guard EngineUpdatePolicy.isCheckDue(lastCheck: lastEngineCheck, now: Date()) else { return }
        await checkForEngineUpdate()
    }

    /// Runs `yt-dlp --update`, which downloads the newest official release from GitHub, checks
    /// its checksum and replaces itself. Then reads the version it ended up with.
    func checkForEngineUpdate() async {
        guard setupState == .ready, engineCheck != .checking else { return }
        engineCheck = .checking
        let tools = paths
        let previous = installed.tools["yt-dlp"]?.version
        do {
            let update = try await ToolProcess(executableURL: tools.ytDLP, arguments: DownloadCommand.updateArguments()).run(collectOutput: true)
            let versionResult = try await ToolProcess(executableURL: tools.ytDLP, arguments: DownloadCommand.versionArguments()).run(collectOutput: true)
            let version = versionResult.standardOutput
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first(where: { !$0.isEmpty })

            if let version, versionResult.exitCode == 0 {
                installed.tools["yt-dlp"] = InstalledTool(version: version, sha256: installed.tools["yt-dlp"]?.sha256 ?? "")
                try? installed.save(to: tools.directory)
            }
            guard update.exitCode == 0 else {
                engineCheck = .failed(DownloadErrorExplainer.explainUpdateFailure(errorLines: update.standardError))
                return
            }
            let now = Date()
            lastEngineCheck = now
            Preferences.lastEngineCheck = now
            if let version, let previous, version != previous {
                engineCheck = .updated(version)
            } else {
                engineCheck = .upToDate
            }
        } catch {
            engineCheck = .failed(error.localizedDescription)
        }
    }
}
