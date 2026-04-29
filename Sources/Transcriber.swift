import Foundation
import Combine

enum TranscriberState: Equatable {
    case idle
    case extractingAudio
    case transcribing(String)
    case completed(String, [TranscriptionSegment])
    case error(String)
}

struct TranscriptionSegment: Codable, Equatable {
    let id: Int
    let text: String
    let start: Double
    let end: Double
}

struct PythonMessage: Codable {
    let type: String
    let progress: Double?
    let speed: String?
    let text: String?
    let segments: [TranscriptionSegment]?
    let message: String?
}

actor ErrorCapture {
    private(set) var output = ""
    func append(_ text: String) { output += text }
}

class Transcriber: ObservableObject {
    @Published var state: TranscriberState = .idle
    @Published var downloadPercent: Double? = nil
    @Published var downloadSpeed: String = ""
    @Published var transcriptionPercent: Double? = nil
    private var process: Process?
    
    // Configurable parameters
    @Published var temperature: Double = 0.0
    @Published var logprobThreshold: Double = -1.0
    @Published var compressionRatioThreshold: Double = 2.4
    
    func transcribe(fileURL: URL, modelID: String) {
        Task {
            do {
                await MainActor.run { 
                    self.state = .extractingAudio 
                    self.downloadPercent = nil
                    self.downloadSpeed = ""
                    self.transcriptionPercent = nil
                }
                
                let extractor = AudioExtractor()
                let wavURL = try await extractor.extractToWav(from: fileURL)
                defer { try? FileManager.default.removeItem(at: wavURL) }
                
                await MainActor.run { self.state = .transcribing("Starting MLX Whisper...") }
                
                try await runPythonTranscription(wavURL: wavURL, modelID: modelID)
                
            } catch {
                await MainActor.run { self.state = .error(error.localizedDescription) }
            }
        }
    }
    
    private func runPythonTranscription(wavURL: URL, modelID: String) async throws {
        guard let scriptPath = Bundle.main.path(forResource: "transcribe", ofType: "py") else {
            throw NSError(domain: "Transcriber", code: 3, userInfo: [NSLocalizedDescriptionKey: "transcribe.py not found in Resources"])
        }
        
        let pythonExecutable = getEmbeddedPythonPath()
        guard FileManager.default.fileExists(atPath: pythonExecutable) else {
            throw NSError(domain: "Transcriber", code: 4, userInfo: [NSLocalizedDescriptionKey: "Embedded python3 not found at \(pythonExecutable)"])
        }
        
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelDir = appSupport.appendingPathComponent("MLXWhisperApp/Models")
        try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: pythonExecutable)
        var env = ProcessInfo.processInfo.environment
        env["HF_HOME"] = modelDir.path
        
        // Enable download acceleration and mirrors
        env["HF_HUB_ENABLE_HF_TRANSFER"] = "1"
        if let mirror = UserDefaults.standard.string(forKey: "hfMirror"), !mirror.isEmpty {
            env["HF_ENDPOINT"] = mirror
        } else if let sysMirror = ProcessInfo.processInfo.environment["HF_ENDPOINT"] {
            env["HF_ENDPOINT"] = sysMirror
        }
        
        // Add bundled FFmpeg to PATH so mlx-whisper can find it
        if let resourcePath = Bundle.main.resourcePath {
            let currentPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            env["PATH"] = "\(resourcePath):\(currentPath)"
        }
        
        task.environment = env
        
        task.arguments = [
            scriptPath,
            "--audio", wavURL.path,
            "--model", modelID,
            "--temperature", String(temperature),
            "--logprob_threshold", String(logprobThreshold),
            "--compression_ratio_threshold", String(compressionRatioThreshold)
        ]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        process = task
        
        let outHandle = pipe.fileHandleForReading
        Task {
            for try await line in outHandle.bytes.lines {
                self.handlePythonOutputLine(line)
            }
        }
        
        let errPipe = Pipe()
        task.standardError = errPipe
        let errHandle = errPipe.fileHandleForReading
        let errorCapture = ErrorCapture()
        
        Task {
            for try await line in errHandle.bytes.lines {
                await errorCapture.append(line + "\n")
            }
        }
        
        try task.run()
        task.waitUntilExit()
        
        // Final capture of any remaining data in pipes
        if let remainingErr = try? errHandle.readToEnd() {
            if let str = String(data: remainingErr, encoding: .utf8) {
                await errorCapture.append(str)
            }
        }
        
        // Clean up
        outHandle.readabilityHandler = nil
        
        if task.terminationStatus != 0 {
            let errorMsg = await errorCapture.output
            await MainActor.run { 
                self.state = .error("Python Error (Code \(task.terminationStatus)):\n\(errorMsg.isEmpty ? "Unknown Error (Check logs)" : errorMsg)") 
            }
        }
    }
    
    private func handlePythonOutputLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = dict["type"] as? String else {
            return
        }
        
        DispatchQueue.main.async {
            if type == "status", let msg = dict["data"] as? String {
                if msg == "Transcribing..." {
                    self.downloadPercent = nil
                    self.downloadSpeed = ""
                }
                self.state = .transcribing(msg)
            } else if type == "download_progress" {
                self.state = .transcribing("Downloading Model...")
                
                if let progressData = dict["data"] as? [String: Any] {
                    // Try structured data first
                    if let p = progressData["percent"] as? Double {
                        self.downloadPercent = p
                    } else if let p = progressData["percent"] as? Int {
                        self.downloadPercent = Double(p)
                    }
                    
                    if let s = progressData["speed"] as? String {
                        self.downloadSpeed = s
                    }
                    
                    // Fallback for raw string if structured parsing failed in Python
                    if let msg = progressData["raw"] as? String {
                        let isOverall = msg.contains("Fetching")
                        if self.downloadPercent == nil {
                            if let range = msg.range(of: "(\\d+)%", options: .regularExpression) {
                                let percentStr = msg[range].dropLast()
                                if let p = Double(percentStr) {
                                    self.downloadPercent = p
                                }
                            }
                        }
                        if self.downloadSpeed.isEmpty {
                            if let speedRange = msg.range(of: "(\\d+(?:\\.\\d+)?[a-zA-Z]+/s)", options: .regularExpression) {
                                self.downloadSpeed = String(msg[speedRange])
                            }
                        }
                    }
                }
            } else if type == "transcription_progress" {
                self.downloadPercent = nil
                self.downloadSpeed = ""
                self.state = .transcribing("Transcribing Audio...")
                
                if let progressData = dict["data"] as? [String: Any] {
                    if let p = progressData["percent"] as? Double {
                        self.transcriptionPercent = p
                    } else if let p = progressData["percent"] as? Int {
                        self.transcriptionPercent = Double(p)
                    } else if let msg = progressData["raw"] as? String {
                        if let range = msg.range(of: "(\\d+)%", options: .regularExpression) {
                            let percentStr = msg[range].dropLast()
                            if let p = Double(percentStr) {
                                self.transcriptionPercent = p
                            }
                    }
                }
            } else if type == "error", let msg = dict["data"] as? String {
                self.state = .error(msg)
            } else if type == "success", let result = dict["data"] as? [String: Any] {
                let text = result["text"] as? String ?? ""
                let segmentsRaw = result["segments"] as? [Any] ?? []
                
                var parsedSegments = [TranscriptionSegment]()
                for (index, segAny) in segmentsRaw.enumerated() {
                    if let seg = segAny as? [String: Any],
                       let text = seg["text"] as? String,
                       let start = seg["start"] as? Double,
                       let end = seg["end"] as? Double {
                        let id = seg["id"] as? Int ?? index
                        parsedSegments.append(TranscriptionSegment(id: id, text: text, start: start, end: end))
                    }
                }
                
                self.state = .completed(text, parsedSegments)
            }
        }
    }
    
    private func getEmbeddedPythonPath() -> String {
        guard let resourceURL = Bundle.main.resourceURL else {
            return "/usr/bin/python3" // fallback
        }
        let pythonPath = resourceURL.appendingPathComponent("python/bin/python3")
        return pythonPath.path
    }
    
    func cancel() {
        process?.terminate()
        state = .idle
    }
}
