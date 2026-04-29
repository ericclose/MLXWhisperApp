import Foundation

class AudioExtractor {
    func extractToWav(from sourceURL: URL) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let outputURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("wav")
        
        guard let ffmpegPath = Bundle.main.path(forResource: "ffmpeg", ofType: nil) else {
            // Fallback for development if not bundled yet
            let fallbackPath = "/opt/homebrew/bin/ffmpeg"
            if FileManager.default.fileExists(atPath: fallbackPath) {
                return try await runFFmpeg(executable: fallbackPath, input: sourceURL, output: outputURL)
            }
            throw NSError(domain: "AudioExtractor", code: 1, userInfo: [NSLocalizedDescriptionKey: "ffmpeg binary not found. Please build the app with build.sh to bundle it."])
        }
        
        return try await runFFmpeg(executable: ffmpegPath, input: sourceURL, output: outputURL)
    }
    
    private func runFFmpeg(executable: String, input: URL, output: URL) async throws -> URL {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        
        // Ensure we handle file paths correctly
        task.arguments = [
            "-i", input.path,
            "-ar", "16000",
            "-ac", "1",
            "-c:a", "pcm_s16le",
            output.path,
            "-y"
        ]
        
        let errorPipe = Pipe()
        task.standardError = errorPipe
        
        return try await withCheckedThrowingContinuation { continuation in
            do {
                task.terminationHandler = { process in
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: output)
                    } else {
                        let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: NSError(domain: "AudioExtractor", code: 2, userInfo: [NSLocalizedDescriptionKey: "FFmpeg failed: \(msg)"]))
                    }
                }
                try task.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
