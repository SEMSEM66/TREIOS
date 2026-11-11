import AVFoundation
import os
import UIKit
import VideoToolbox

/// What the log and the compat probe record about the phone: the exact iOS version and build, the model, the chip,
/// memory, and whether VideoToolbox has a hardware decoder for each movie format.
enum DeviceInfo {
    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    static func sysctlInt(_ name: String) -> Int64? {
        var value: Int64 = 0   // a 32-bit answer fills the low half
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }

    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    /// "iPhone17,3" on an iPhone 16. In the simulator, the model it stands for.
    static var modelIdentifier: String {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return sim }
        return sysctlString("hw.machine") ?? "unknown"
    }

    /// The models this build is aimed at, by name and chip. Any other model is logged by its identifier alone.
    private static let known: [String: (name: String, chip: String)] = [
        "iPhone17,3": ("iPhone 16", "A18"),
        "iPhone17,4": ("iPhone 16 Plus", "A18"),
        "iPhone17,1": ("iPhone 16 Pro", "A18 Pro"),
        "iPhone17,2": ("iPhone 16 Pro Max", "A18 Pro"),
        "iPhone17,5": ("iPhone 16e", "A18"),
        "iPhone16,1": ("iPhone 15 Pro", "A17 Pro"),
        "iPhone16,2": ("iPhone 15 Pro Max", "A17 Pro"),
        "iPhone15,4": ("iPhone 15", "A16 Bionic"),
        "iPhone15,5": ("iPhone 15 Plus", "A16 Bionic"),
    ]
    static var modelName: String { known[modelIdentifier]?.name ?? modelIdentifier }
    static var chipName: String {
        if isSimulator { return "simulator on \(sysctlString("machdep.cpu.brand_string") ?? "a Mac")" }
        return known[modelIdentifier]?.chip ?? sysctlString("machdep.cpu.brand_string") ?? "unknown"
    }

    static func fourCC(_ s: String) -> CMVideoCodecType {
        s.utf8.reduce(CMVideoCodecType(0)) { ($0 << 8) | CMVideoCodecType($1) }
    }
    static func hardwareDecode(_ code: String) -> Bool { VTIsHardwareDecodeSupported(fourCC(code)) }

    /// Bytes this app may still take before iOS ends it, and what it holds now. (The page lives in WebKit's own content
    /// process, whose memory is not in these numbers; these are the shell's.)
    static var availableMemory: Int64 { Int64(os_proc_available_memory()) }
    static var footprint: Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int64(info.phys_footprint) : -1
    }
    static func mb(_ bytes: Int64) -> String { String(format: "%.0f MB", Double(bytes) / 1_048_576) }
    static func memorySummary() -> String {
        "app footprint \(mb(footprint)), available to app \(mb(availableMemory)), physical \(mb(Int64(ProcessInfo.processInfo.physicalMemory)))"
    }

    static func freeDisk() -> Int64? {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        if let v = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage, v > 0 {
            return v
        }
        if let v = try? home.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity { return Int64(v) }
        return nil
    }

    static func snapshot() -> [String: Any] {
        let p = ProcessInfo.processInfo
        let v = p.operatingSystemVersion
        let screen = UIScreen.main
        var d: [String: Any] = [
            "app": Config.version,
            "commit": Config.gitCommit,
            "bundleID": Config.bundleID,
            "simulator": isSimulator,
            "system": "\(UIDevice.current.systemName) \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)",
            "systemBuild": sysctlString("kern.osversion") ?? "",
            "model": modelIdentifier,
            "modelName": modelName,
            "chip": chipName,
            "cpuBrand": sysctlString("machdep.cpu.brand_string") ?? "",
            "cpuFamily": String(format: "0x%08llx", UInt64(bitPattern: sysctlInt("hw.cpufamily") ?? 0) & 0xffff_ffff),
            "cores": p.processorCount,
            "physicalMemoryMB": Int(p.physicalMemory / 1_048_576),
            "availableMemoryMB": Int(availableMemory / 1_048_576),
            "screenPoints": "\(Int(screen.bounds.width))x\(Int(screen.bounds.height))",
            "screenScale": Double(screen.scale),
            "maxFPS": screen.maximumFramesPerSecond,
            "lowPowerMode": p.isLowPowerModeEnabled,
            "thermalState": p.thermalState.rawValue,
            "hardwareDecodeAV1": hardwareDecode("av01"),
            "hardwareDecodeHEVC": hardwareDecode("hvc1"),
            "hardwareDecodeH264": hardwareDecode("avc1"),
            "locale": Locale.current.identifier,
        ]
        if let free = freeDisk() { d["freeDiskMB"] = Int(free / 1_048_576) }
        if let host = sysctlString("hw.model"), isSimulator { d["simulatorHost"] = host }
        return d
    }

    static func logHeader() {
        let d = snapshot()
        let line = d.keys.sorted().map { "\($0)=\(d[$0]!)" }.joined(separator: ", ")
        tlog("device", line)
    }
}
