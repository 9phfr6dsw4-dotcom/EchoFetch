import AppKit
import Combine
import EchoFetchCore
import SwiftUI

@main
@MainActor
struct EchoFetchApp: App {
    @NSApplicationDelegateAdaptor(EchoFetchApplicationDelegate.self) private var applicationDelegate
    @State private var runtime = EchoFetchRuntime()

    var body: some Scene {
        WindowGroup("EchoFetch") {
            TabView {
                DownloadView()
                    .tabItem { Label("Download", systemImage: "arrow.down.circle") }
                HistoryView()
                    .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }
            .environment(runtime)
            .navigationTitle("EchoFetch")
            .task { await runtime.start() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                runtime.downloads.fillInCopiedLink()
            }
        }
        .defaultSize(width: 920, height: 760)
    }
}

@MainActor
final class EchoFetchApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Stop yt-dlp too, so a download doesn't carry on after EchoFetch quits.
        RunningApp.runtime?.downloads.stopEverything()
    }
}
