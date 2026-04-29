import Foundation
import IOKit
import MachO

class SystemMonitor: ObservableObject {
    @Published var cpuUsage: Double = 0.0
    @Published var memoryUsage: Double = 0.0
    @Published var memoryUsedGB: Double = 0.0
    @Published var memoryTotalGB: Double = 0.0
    @Published var gpuUsage: Double = 0.0
    
    private var timer: Timer?
    private var previousCpuInfo = host_cpu_load_info()
    private var hasPrevCpuInfo = false
    
    init() {
        startMonitoring()
    }
    
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMetrics()
        }
    }
    
    private func updateMetrics() {
        updateCPU()
        updateMemory()
        updateGPU()
    }
    
    private func updateCPU() {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        var cpuLoadInfo = host_cpu_load_info()
        
        let result = withUnsafeMutablePointer(to: &cpuLoadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        
        if result == KERN_SUCCESS {
            if hasPrevCpuInfo {
                let userDiff = Double(cpuLoadInfo.cpu_ticks.0 &- previousCpuInfo.cpu_ticks.0)
                let sysDiff  = Double(cpuLoadInfo.cpu_ticks.1 &- previousCpuInfo.cpu_ticks.1)
                let idleDiff = Double(cpuLoadInfo.cpu_ticks.2 &- previousCpuInfo.cpu_ticks.2)
                let niceDiff = Double(cpuLoadInfo.cpu_ticks.3 &- previousCpuInfo.cpu_ticks.3)
                let totalTicks = sysDiff + userDiff + niceDiff + idleDiff
                
                if totalTicks > 0 {
                    let usage = (sysDiff + userDiff + niceDiff) / totalTicks
                    DispatchQueue.main.async {
                        self.cpuUsage = usage * 100
                    }
                }
            }
            previousCpuInfo = cpuLoadInfo
            hasPrevCpuInfo = true
        }
    }
    
    private func updateMemory() {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        
        if result == KERN_SUCCESS {
            let pageSize = UInt64(vm_kernel_page_size)
            let used = UInt64(stats.active_count + stats.wire_count + stats.compressor_page_count) * pageSize
            
            DispatchQueue.main.async {
                self.memoryUsedGB = Double(used) / 1_073_741_824.0
                self.memoryTotalGB = Double(total) / 1_073_741_824.0
                self.memoryUsage = (Double(used) / Double(total)) * 100
            }
        } else {
            DispatchQueue.main.async {
                self.memoryTotalGB = Double(total) / 1_073_741_824.0
            }
        }
    }
    
    private func updateGPU() {
        // Implementation inspired by https://github.com/exelban/stats
        let match = IOServiceMatching(kIOAcceleratorClassName)
        var iterator: io_iterator_t = 0
        
        if IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) == kIOReturnSuccess {
            var service = IOIteratorNext(iterator)
            var maxUtilization: Double = 0
            
            while service != 0 {
                if let props = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] {
                    if let util = props["Device Utilization %"] as? Int {
                        maxUtilization = max(maxUtilization, Double(util))
                    } else if let util = props["GPU Activity(%)"] as? Int {
                        maxUtilization = max(maxUtilization, Double(util))
                    }
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
            
            DispatchQueue.main.async {
                self.gpuUsage = maxUtilization
            }
        }
    }
}
