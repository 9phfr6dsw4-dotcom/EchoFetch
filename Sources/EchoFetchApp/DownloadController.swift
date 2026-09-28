import AppKit
import EchoFetchCore
import Foundation
import Observation

/// The Download tab: the link, its preview, and the one download that can run at a time.
@MainActor
@Observable
final class DownloadController {
    enum PreviewState: Equatable {
        case empty
        case loading
        case loaded(MediaInfo)
        case failed(String)
    }

    struct Job: Equatable {
        let kind: DownloadKind
        let audioFormat: AudioFormat
        let title: String
        let isPlaylist: Bool
        let totalItems: Int
        var progress = DownloadProgressState()
    }

    struct Finished: Equatable {
        let record: DownloadRecord
        let savedCount: Int
        let totalItems: Int
        let failedCount: Int
        let problem: String?
    }

    enum JobState: Equatable {
        case idle
        case running(Job)
        case finished(Finished)
        case failed(String)
        case cancelled
    }

    static let notALinkMessage = "That doesn't look like a link. Copy the address of a video or playlist and paste it here."

    var linkText = ""
    private(set) var wholePlaylist = false
    private(set) var preview: PreviewState = .empty
    private(set) var job: JobState = .idle
    /// Set when the link is a YouTube video opened from a playlist.
    private(set) var playlistOffer: String?
    private(set) var lastKind: DownloadKind?

    private let tools: ToolsController
    private let history: HistoryController
    private var previewedLink: String?
    private var previewedWholePlaylist = false
    private var previewGeneration = 0
    private var previewProcess: ToolProcess?
    private var downloadProcess: ToolProcess?
    private var lookupDelay: Task<Void, Never>?
    private var lastPasteboardChangeCount = -1
    private var lastFilledLink: String?

    init(tools: ToolsController, history: HistoryController) {
        self.tools = tools
        self.history = history
    }

    var isDownloading: Bool {
        if case .running = job { return true }
        return false
    }

    var canDownload: Bool {
        guard case .loaded = preview else { return false }
        return !isDownloading && tools.setupState == .ready
    }

    // MARK: Link

    /// Called whenever the link box changes. Looks the link up after a short pause in typing.
    func linkTextChanged() {
        lookupDelay?.cancel()
        guard let url = LinkPolicy.link(from: linkText) else {
            cancelPreview()
            preview = .empty
            playlistOffer = nil
            return
        }
        guard url.absoluteString != previewedLink else { return }
        lookupDelay = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.lookUp(showProblems: false)
        }
    }

    /// Looks up the link in the box now (Return key, Paste button, or a copied link).
    func lookUp(showProblems: Bool = true) {
        lookupDelay?.cancel()
        guard let url = LinkPolicy.link(from: linkText) else {
            cancelPreview()
            let isEmpty = linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            preview = (isEmpty || !showProblems) ? .empty : .failed(Self.notALinkMessage)
            playlistOffer = nil
            return
        }
        let link = url.absoluteString
        let offer = LinkPolicy.playlistOffer(for: url)
        if offer != playlistOffer { wholePlaylist = false }
        playlistOffer = offer
        let wantsPlaylist = offer != nil && wholePlaylist
        if link == previewedLink, wantsPlaylist == previewedWholePlaylist, preview != .empty {
            if case .failed = preview {} else { return }
        }

        cancelPreview()
        previewGeneration += 1
        let generation = previewGeneration
        previewedLink = link
        previewedWholePlaylist = wantsPlaylist
        preview = .loading
        Task { [weak self] in
            await self?.fetchPreview(link: link, wholePlaylist: wantsPlaylist, generation: generation)
        }
    }

    func setWholePlaylist(_ value: Bool) {
        guard value != wholePlaylist else { return }
        wholePlaylist = value
        lookUp()
    }

    func pasteLink() {
        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string) else { return }
        lastPasteboardChangeCount = pasteboard.changeCount
        lastFilledLink = nil
        linkText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        lookUp()
    }

    func clearLink() {
        lookupDelay?.cancel()
        cancelPreview()
        linkText = ""
        lastFilledLink = nil
        preview = .empty
        playlistOffer = nil
    }

    /// When EchoFetch comes to the front with a new link on the clipboard, puts it in the box and
    /// looks it up. A link the user typed or pasted themselves is never replaced.
    func fillInCopiedLink() {
        guard Preferences.fillInCopiedLinks, tools.setupState == .ready else { return }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastPasteboardChangeCount else { return }
        lastPasteboardChangeCount = pasteboard.changeCount
        guard let text = pasteboard.string(forType: .string), let url = LinkPolicy.link(from: text) else { return }
        let link = url.absoluteString
        let current = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard current.isEmpty || current == lastFilledLink, link != current else { return }
        linkText = link
        lastFilledLink = link
        lookUp()
    }

    private func cancelPreview() {
        previewGeneration += 1
        previewProcess?.cancel()
        previewProcess = nil
        previewedLink = nil
    }

    private func fetchPreview(link: String, wholePlaylist: Bool, generation: Int) async {
        guard await tools.waitUntilReady() else {
            if generation == previewGeneration {
                preview = .failed(tools.setupProblem ?? "The download tools aren't ready.")
            }
            return
        }
        guard generation == previewGeneration else { return }
        let process = ToolProcess(
            executableURL: tools.paths.ytDLP,
            arguments: DownloadCommand.previewArguments(link: link, wholePlaylist: wholePlaylist, tools: tools.paths)
        )
        previewProcess = process
        do {
            let result = try await process.run(collectOutput: true)
            guard generation == previewGeneration, !result.wasCancelled else { return }
            previewProcess = nil
            let json = Data(result.standardOutput.joined(separator: "\n").utf8)
            if result.exitCode == 0, let info = try? MediaInfoParser.parse(json) {
                preview = .loaded(info)
            } else {
                preview = .failed(DownloadErrorExplainer.explain(errorLines: result.standardError, exitCode: result.exitCode))
            }
        } catch {
            guard generation == previewGeneration else { return }
            previewProcess = nil
            preview = .failed(error.localizedDescription)
        }
    }

    // MARK: Download

    func download(_ kind: DownloadKind) {
        guard !isDownloading, case .loaded(let info) = preview, let link = previewedLink else { return }
        let request: DownloadRequest
        let totalItems: Int
        switch info {
        case .single:
            totalItems = 1
            request = DownloadRequest(link: link, kind: kind, audioFormat: Preferences.audioFormat, isPlaylist: false, allowsAV1: VideoSupport.playsAV1)
        case .playlist(let playlist):
            totalItems = playlist.entries.count
            request = DownloadRequest(link: link, kind: kind, audioFormat: Preferences.audioFormat, isPlaylist: true, allowsAV1: VideoSupport.playsAV1)
        }
        lastKind = kind
        job = .running(Job(kind: kind, audioFormat: request.audioFormat, title: info.title, isPlaylist: request.isPlaylist, totalItems: totalItems))
        Task { [weak self] in
            await self?.runDownload(request: request, info: info)
        }
    }

    func retry() {
        guard let lastKind else { return }
        download(lastKind)
    }

    func cancelDownload() {
        downloadProcess?.cancel()
    }

    /// Stops any running tools right away (EchoFetch is quitting).
    func stopEverything() {
        downloadProcess?.cancel()
        previewProcess?.cancel()
    }

    private func runDownload(request: DownloadRequest, info: MediaInfo) async {
        guard await tools.waitUntilReady() else {
            job = .failed(tools.setupProblem ?? "The download tools aren't ready.")
            return
        }
        let fileManager = FileManager.default
        let destination = Preferences.saveFolder
        let partial = AppSupportDirectory.partialDownloads.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: partial, withIntermediateDirectories: true)
        } catch {
            job = .failed("EchoFetch couldn't use the download folder: \(error.localizedDescription)")
            return
        }
        defer { try? fileManager.removeItem(at: partial) }

        let process = ToolProcess(
            executableURL: tools.paths.ytDLP,
            arguments: DownloadCommand.downloadArguments(for: request, destination: destination, temporaryDirectory: partial, tools: tools.paths)
        )
        downloadProcess = process
        let log = DownloadEventLog()
        do {
            let result = try await process.run { line in
                guard let event = DownloadEventParser.parse(line) else { return }
                log.record(event)
                Task { @MainActor [weak self] in
                    self?.apply(event)
                }
            }
            downloadProcess = nil
            finish(result: result, files: log.files, request: request, info: info)
        } catch {
            downloadProcess = nil
            job = .failed(error.localizedDescription)
        }
    }

    private func apply(_ event: DownloadEvent) {
        guard case .running(var current) = job else { return }
        current.progress.apply(event)
        job = .running(current)
    }

    private func finish(result: ToolProcessResult, files: [String], request: DownloadRequest, info: MediaInfo) {
        if result.wasCancelled {
            job = .cancelled
            return
        }
        guard let location = DownloadOutcome.savedLocation(files: files, isPlaylist: request.isPlaylist) else {
            job = .failed(DownloadErrorExplainer.explain(errorLines: result.standardError, exitCode: result.exitCode))
            return
        }
        let failedCount = request.isPlaylist ? DownloadOutcome.failedItemCount(in: result.standardError) : 0
        let uploader: String?
        let thumbnail: URL?
        let totalItems: Int
        switch info {
        case .single(let item):
            uploader = item.uploader
            thumbnail = item.thumbnailURL
            totalItems = 1
        case .playlist(let playlist):
            uploader = playlist.uploader
            thumbnail = playlist.displayThumbnailURL
            totalItems = playlist.entries.count
        }
        let record = DownloadRecord(
            title: info.title,
            uploader: uploader,
            sourceURL: request.link,
            thumbnailURL: thumbnail?.absoluteString,
            kind: request.kind,
            fileExtension: (files[0] as NSString).pathExtension.lowercased(),
            path: location.path,
            isFolder: location.isFolder,
            itemCount: files.count,
            byteCount: files.reduce(Int64(0)) { $0 + Self.fileSize($1) },
            createdAt: Date()
        )
        history.add(record)
        job = .finished(Finished(
            record: record,
            savedCount: files.count,
            totalItems: totalItems,
            failedCount: failedCount,
            problem: failedCount > 0 ? DownloadErrorExplainer.explain(errorLines: result.standardError, exitCode: result.exitCode) : nil
        ))
    }

    private static func fileSize(_ path: String) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
