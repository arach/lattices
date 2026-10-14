import Darwin
import Foundation

/// Names the process on the other end of an agent connection.
///
/// `agent` on a drive lease is whatever the caller chose to call itself. This
/// is what the agent saw: the loopback peer's process and its parent, e.g.
/// `bun 41250 ← claude 41012`. It is resolved once per connection, at the
/// first drive.begin, because lsof is too slow for every request.
enum ActionAgentPeer {
    static func describe(localPort: UInt16) -> String? {
        guard let pid = peerPID(localPort: localPort) else {
            return nil
        }
        var parts = [label(for: pid)]
        if let parent = parentPID(of: pid), parent > 1 {
            parts.append(label(for: parent))
        }
        return parts.compactMap { $0 }.joined(separator: " ← ").nilIfBlank
    }

    /// The pid holding the client end of the socket whose source port is `localPort`.
    private static func peerPID(localPort: UInt16) -> pid_t? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-a", "-iTCP@127.0.0.1:\(localPort)", "-sTCP:ESTABLISHED", "-Fp"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let ownPID = getpid()
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { $0.hasPrefix("p") ? pid_t($0.dropFirst()) : nil }
            .first { $0 != ownPID }
    }

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else {
            return nil
        }
        return pid_t(info.pbi_ppid)
    }

    private static func label(for pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else {
            return nil
        }
        let path = String(cString: buffer)
        return "\(URL(fileURLWithPath: path).lastPathComponent) \(pid)"
    }
}

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}
