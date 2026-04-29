import Foundation

struct TranscriptionHistoryItem: Identifiable, Codable {
    let id: UUID
    let date: Date
    let text: String
    let segments: [TranscriptionSegment]
    let sourceFileName: String
}

class HistoryManager: ObservableObject {
    @Published var history: [TranscriptionHistoryItem] = [] {
        didSet {
            save()
        }
    }
    
    private let fileURL: URL
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("MLXWhisperApp")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.fileURL = appDir.appendingPathComponent("history.json")
        
        load()
    }
    
    func addItem(text: String, segments: [TranscriptionSegment], sourceFileName: String) {
        let item = TranscriptionHistoryItem(id: UUID(), date: Date(), text: text, segments: segments, sourceFileName: sourceFileName)
        history.insert(item, at: 0)
    }
    
    func deleteItems(at indices: IndexSet, filteredItems: [TranscriptionHistoryItem]) {
        let itemsToDelete = indices.map { filteredItems[$0] }
        history.removeAll { h in itemsToDelete.contains { $0.id == h.id } }
    }
    
    func clearAll() {
        history.removeAll()
    }
    
    private func save() {
        do {
            let data = try JSONEncoder().encode(history)
            try data.write(to: fileURL)
        } catch {
            print("Failed to save history: \(error)")
        }
    }
    
    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            self.history = try JSONDecoder().decode([TranscriptionHistoryItem].self, from: data)
        } catch {
            print("Failed to load history: \(error)")
        }
    }
}
