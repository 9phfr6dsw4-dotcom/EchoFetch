import EchoFetchCore
import Foundation
import Observation

/// Everything the three tabs share.
@MainActor
@Observable
final class EchoFetchRuntime {
    let tools: ToolsController
    let history: HistoryController
    let downloads: DownloadController
    private var hasStarted = false

    init() {
        let tools = ToolsController()
        let history = HistoryController()
        self.tools = tools
        self.history = history
        self.downloads = DownloadController(tools: tools, history: history)
        RunningApp.runtime = self
    }

    /// Sets up the download tools (only slow the very first time), fills in a copied link, then
    /// looks for a newer download engine if a day has passed since the last check.
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await tools.prepare()
        downloads.fillInCopiedLink()
        await tools.checkForEngineUpdateIfDue()
    }
}

/// The running app's runtime, so the app delegate can stop downloads when EchoFetch quits.
@MainActor
enum RunningApp {
    static var runtime: EchoFetchRuntime?
}
