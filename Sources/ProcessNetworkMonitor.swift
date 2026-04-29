import Foundation

class ProcessNetworkMonitor {
    private var lastBytesIn: Int64 = 0
    private var lastBytesOut: Int64 = 0
    private var lastTime: Date = Date()
    private var pid: Int32
    
    init(pid: Int32) {
        self.pid = pid
    }
    
    func getSpeed() -> String? {
        let task = Process()
        task.launchPath = "/usr/bin/nettop"
        // Use -k to exclude heavy columns, similar to 'stats'
        task.arguments = ["-P", "-L", "1", "-n", "-k", "time,interface,state,rx_dupe,rx_ooo,re-tx,rtt_avg,rcvsize,tx_win,tc_class,tc_mgt,cc_algo,P,C,R,W,arch"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe() // Suppress errors
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                return parseNettopOutput(output)
            }
        } catch {
            print("Network monitor error: \(error)")
        }
        return nil
    }
    
    private func parseNettopOutput(_ output: String) -> String? {
        let lines = output.components(separatedBy: .newlines)
        let pidSuffix = ".\(pid)"
        
        for line in lines {
            let parts = line.components(separatedBy: ",")
            guard parts.count >= 3 else { continue }
            
            let processPart = parts[0]
            if processPart.hasSuffix(pidSuffix) {
                // nettop output with -k optimization:
                // Column 0: process.pid
                // Column 1: bytes_in
                // Column 2: bytes_out
                if let currentBytesIn = Int64(parts[1]), let currentBytesOut = Int64(parts[2]) {
                    let now = Date()
                    let dt = now.timeIntervalSince(lastTime)
                    
                    if lastBytesIn > 0 && dt > 0.1 {
                        let dbIn = currentBytesIn - lastBytesIn
                        
                        // We primarily care about download speed for model downloading
                        if dbIn >= 0 {
                            let speed = Double(dbIn) / dt
                            let result = formatSpeed(speed)
                            lastBytesIn = currentBytesIn
                            lastBytesOut = currentBytesOut
                            lastTime = now
                            return result
                        }
                    }
                    lastBytesIn = currentBytesIn
                    lastBytesOut = currentBytesOut
                    lastTime = now
                }
                break
            }
        }
        return nil
    }
    
    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        // Stats-like formatting (1000-based, consistent units)
        if bytesPerSecond >= 1_000_000_000 {
            return String(format: "%.1f GB/s", bytesPerSecond / 1_000_000_000)
        } else if bytesPerSecond >= 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000)
        } else if bytesPerSecond >= 1_000 {
            return String(format: "%.1f KB/s", bytesPerSecond / 1_000)
        } else if bytesPerSecond > 0 {
            return String(format: "%.0f B/s", bytesPerSecond)
        } else {
            return "0 B/s"
        }
    }
}
