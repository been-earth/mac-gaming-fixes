import Darwin
import Foundation

public struct ProcessEntry: Hashable {
    public let pid: pid_t
    /// Last path component of argv[0]: "deadlock.exe" for a Wine game, "dota2" for a native one.
    public let name: String
    public let isWine: Bool
}

/// argv[0] of a Wine process is the Windows path of the .exe; of a native one, a Unix path.
public func processName(argv0: String) -> (name: String, isWine: Bool) {
    let windows = argv0.contains("\\")
    let name = argv0.split(separator: windows ? "\\" : "/").last.map(String.init) ?? argv0
    return (name, windows || name.lowercased().hasSuffix(".exe"))
}

/// Running processes by name. Argument lists are read once per pid.
/// ponytail: polled by the caller every couple of seconds; a pid reused between two polls would keep
/// its old name. Move to kqueue NOTE_EXIT if that ever shows.
public final class ProcessList: @unchecked Sendable {
    private var known: [pid_t: ProcessEntry] = [:]

    public init() {}

    public func snapshot() -> [ProcessEntry] {
        var pids = [pid_t](repeating: 0, count: Int(proc_listallpids(nil, 0)) + 64)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        guard count > 0 else { return Array(known.values) }
        let alive = Set(pids.prefix(count).filter { $0 > 0 })
        known = known.filter { alive.contains($0.key) }
        for pid in alive where known[pid] == nil {
            guard let argv0 = Self.argv0(of: pid), !argv0.isEmpty else { continue }
            let (name, isWine) = processName(argv0: argv0)
            known[pid] = ProcessEntry(pid: pid, name: name, isWine: isWine)
        }
        return Array(known.values)
    }

    /// KERN_PROCARGS2: int argc, the executable path, NUL padding, then argv[0]…
    static func argv0(of pid: pid_t) -> String? {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        var i = MemoryLayout<Int32>.size
        while i < size, buffer[i] != 0 { i += 1 }   // executable path
        while i < size, buffer[i] == 0 { i += 1 }   // padding
        let start = i
        while i < size, buffer[i] != 0 { i += 1 }
        return start < i ? String(decoding: buffer[start..<i], as: UTF8.self) : nil
    }
}
