import EchoFetchCore
import Foundation
import Observation

@MainActor
@Observable
final class HistoryController {
    private(set) var records: [DownloadRecord]
    var errorMessage: String?
    private let store: DownloadHistoryStore

    init(store: DownloadHistoryStore = .standard()) {
        self.store = store
        self.records = store.load()
    }

    func add(_ record: DownloadRecord) {
        records = DownloadHistoryStore.adding(record, to: records)
        persist()
    }

    /// Removes the entry only. The downloaded file stays where it is.
    func remove(_ record: DownloadRecord) {
        records.removeAll { $0.id == record.id }
        persist()
    }

    func clear() {
        records = []
        persist()
    }

    private func persist() {
        do {
            try store.save(records)
            errorMessage = nil
        } catch {
            errorMessage = "EchoFetch couldn't save its history: \(error.localizedDescription)"
        }
    }
}
