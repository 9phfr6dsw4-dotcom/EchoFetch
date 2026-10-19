import Foundation

/// When EchoFetch may quit to install an update that has already downloaded.
public enum UpdateInstallPolicy {
    /// How often the waiting installer asks again while EchoFetch is busy.
    public static let retryInterval: TimeInterval = 15

    /// A download, the first-run tool setup or a download-engine update is under way. Stopping
    /// one would lose its work, so the update waits, however long that takes. Quitting EchoFetch
    /// still installs the update straight away.
    public static func canInstallNow(isBusy: Bool) -> Bool {
        !isBusy
    }
}
