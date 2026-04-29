import Foundation
import AppKit

struct HFCollectionResponse: Codable {
    let items: [HFItem]
}

struct HFItem: Codable {
    let id: String
    let type: String
}

@MainActor
class ModelManager: ObservableObject {
    @Published var availableModels: [String] = []
    @Published var modelSizes: [String: Double] = [:]
    @Published var downloadedModels: Set<String> = []
    @Published var selectedModel: String {
        didSet {
            UserDefaults.standard.set(selectedModel, forKey: "selectedModel")
        }
    }
    @Published var customModelInput: String = ""
    @Published var hfMirror: String {
        didSet {
            UserDefaults.standard.set(hfMirror, forKey: "hfMirror")
        }
    }
    
    init() {
        self.selectedModel = UserDefaults.standard.string(forKey: "selectedModel") ?? "mlx-community/whisper-large-v3-mlx"
        self.hfMirror = UserDefaults.standard.string(forKey: "hfMirror") ?? ""
        fetchCollection()
        checkDownloadedModels()
    }
    
    func openModelsFolder() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelDir = appSupport.appendingPathComponent("MLXWhisperApp/Models")
        try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(modelDir)
    }
    
    func deleteModel(_ modelID: String) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let hubDir = appSupport.appendingPathComponent("MLXWhisperApp/Models/hub")
        let hfModelID = "models--" + modelID.replacingOccurrences(of: "/", with: "--")
        let modelPath = hubDir.appendingPathComponent(hfModelID)
        
        try? FileManager.default.removeItem(at: modelPath)
        checkDownloadedModels()
    }
    
    func checkDownloadedModels() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let hubDir = appSupport.appendingPathComponent("MLXWhisperApp/Models/hub")
        
        var downloaded = Set<String>()
        
        if let items = try? FileManager.default.contentsOfDirectory(atPath: hubDir.path) {
            for item in items where item.hasPrefix("models--") {
                // Convert models--mlx-community--whisper-tiny-mlx back to mlx-community/whisper-tiny-mlx
                let parts = item.components(separatedBy: "--")
                if parts.count >= 3 {
                    let modelID = parts[1] + "/" + parts.suffix(from: 2).joined(separator: "--")
                    // Basic check: if snapshots directory exists and has content
                    let snapshotsPath = hubDir.appendingPathComponent(item).appendingPathComponent("snapshots")
                    if let snapshots = try? FileManager.default.contentsOfDirectory(atPath: snapshotsPath.path), !snapshots.isEmpty {
                        downloaded.insert(modelID)
                    }
                }
            }
        }
        self.downloadedModels = downloaded
    }
    
    private func getHFURL(path: String) -> URL? {
        let base = hfMirror.isEmpty ? "https://huggingface.co" : hfMirror
        return URL(string: "\(base)\(path)")
    }
    
    func fetchCollection() {
        Task {
            guard let url = getHFURL(path: "/api/collections/mlx-community/whisper") else { return }
            
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let collection = try JSONDecoder().decode(HFCollectionResponse.self, from: data)
                let models = collection.items.filter { $0.type == "model" }.map { $0.id }
                
                if !models.isEmpty {
                    self.availableModels = models
                    if !models.contains(self.selectedModel) {
                        self.selectedModel = models.first ?? ""
                    }
                    self.fetchSizes(for: models)
                }
            } catch {
                print("Failed to fetch collection: \(error)")
                self.availableModels = [
                    "mlx-community/whisper-large-v3-mlx",
                    "mlx-community/whisper-large-v2-mlx",
                    "mlx-community/whisper-small-mlx",
                    "mlx-community/whisper-tiny-mlx"
                ]
            }
        }
    }
    
    private func fetchSizes(for models: [String]) {
        Task {
            await withTaskGroup(of: (String, Double?).self) { group in
                for model in models {
                    group.addTask {
                        return (model, await self.fetchSingleModelSize(modelID: model))
                    }
                }
                
                for await (model, size) in group {
                    self.modelSizes[model] = size ?? -1
                }
            }
        }
    }
    
    private func fetchSingleModelSize(modelID: String) async -> Double? {
        guard let url = getHFURL(path: "/api/models/\(modelID)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Try usedStorage first (can be Int or Double)
                var size: Double = 0
                if let used = json["usedStorage"] as? Double {
                    size = used
                } else if let used = json["usedStorage"] as? Int {
                    size = Double(used)
                }
                
                if size > 0 { return size }
                
                // Fallback: Sum up siblings if usedStorage is missing or 0
                if let siblings = json["siblings"] as? [[String: Any]] {
                    let total = siblings.compactMap { $0["size"] as? Double ?? ($0["size"] as? Int).map(Double.init) }.reduce(0, +)
                    if total > 0 { return total }
                }
            }
        } catch {
            print("Failed size fetch for \(modelID): \(error)")
        }
        return nil
    }
    
    func addCustomModel() {
        let trimmed = customModelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && !availableModels.contains(trimmed) {
            availableModels.append(trimmed)
            selectedModel = trimmed
            customModelInput = ""
            fetchSizes(for: [trimmed])
        }
    }
    
    func displaySize(for modelID: String) -> String {
        guard let bytes = modelSizes[modelID] else { return "Loading size..." }
        if bytes < 0 { return "Size Unknown" }
        
        if bytes >= 1_000_000_000 {
            return String(format: "%.2f GB", bytes / 1_000_000_000)
        } else if bytes >= 1_000_000 {
            return String(format: "%d MB", Int(bytes / 1_000_000))
        } else {
            return "Size Unknown"
        }
    }
}
