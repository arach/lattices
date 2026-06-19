import Darwin
import Foundation

public enum ProcessQuery {
    public static let defaultInterestingCommands: Set<String> = [
        "claude", "node", "bun", "deno", "python", "python3",
        "ruby", "go", "cargo", "nvim", "vim", "npm", "npx",
        "pnpm", "swift", "make", "git"
    ]

    private static let shellCommands: Set<String> = [
        "bash", "zsh", "fish", "sh", "dash", "tcsh", "csh"
    ]

    public static func snapshot() -> [Int: ProcessEntry] {
        let raw = shell([
            "/bin/ps", "-eo", "pid,ppid,pgid,tty,comm,args"
        ])
        guard !raw.isEmpty else { return [:] }

        var table: [Int: ProcessEntry] = [:]
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: true)

        for line in lines.dropFirst() {
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)
            guard parts.count >= 6 else { continue }

            guard let pid = Int(parts[0]),
                  let ppid = Int(parts[1]),
                  let pgid = Int(parts[2])
            else { continue }

            let commFull = String(parts[4])
            let comm = (commFull as NSString).lastPathComponent

            table[pid] = ProcessEntry(
                pid: pid,
                ppid: ppid,
                pgid: pgid,
                tty: String(parts[3]),
                comm: comm,
                args: String(parts[5])
            )
        }

        return table
    }

    public static func batchCWD(pids: [Int]) -> [Int: String] {
        guard !pids.isEmpty else { return [:] }

        let pidList = pids.map(String.init).joined(separator: ",")
        let raw = shell([
            "/usr/sbin/lsof", "-a", "-d", "cwd", "-p", pidList, "-Fn"
        ])
        guard !raw.isEmpty else { return [:] }

        var result: [Int: String] = [:]
        var currentPid: Int?

        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let s = String(line)
            if s.hasPrefix("p") {
                currentPid = Int(s.dropFirst())
            } else if s.hasPrefix("n"), let pid = currentPid {
                result[pid] = String(s.dropFirst())
            }
        }

        return result
    }

    public static func filterInteresting(
        _ table: [Int: ProcessEntry],
        commands: Set<String> = defaultInterestingCommands
    ) -> [ProcessEntry] {
        table.values
            .filter { commands.contains($0.comm) }
            .sorted { $0.pid < $1.pid }
    }

    public static func snapshotWithCWDs(commands: Set<String> = defaultInterestingCommands) -> (
        table: [Int: ProcessEntry],
        interesting: [ProcessEntry]
    ) {
        var table = snapshot()
        let interestingEntries = filterInteresting(table, commands: commands)
        let cwdPids = Set(interestingEntries.map(\.pid) + table.values
            .filter { shellCommands.contains($0.comm) && TerminalQuery.normalizeTTY($0.tty).hasPrefix("ttys") }
            .map(\.pid))
        let cwds = batchCWD(pids: Array(cwdPids))

        for (pid, cwd) in cwds {
            table[pid]?.cwd = cwd
        }

        let interesting = interestingEntries.compactMap { table[$0.pid] }
        return (table, interesting)
    }

    public static func childrenMap(from table: [Int: ProcessEntry]) -> [Int: [Int]] {
        var children: [Int: [Int]] = [:]
        for (pid, entry) in table {
            children[entry.ppid, default: []].append(pid)
        }
        for parent in children.keys {
            children[parent]?.sort()
        }
        return children
    }

    public static func descendants(of pid: Int, in table: [Int: ProcessEntry]) -> [ProcessEntry] {
        let children = childrenMap(from: table)
        var result: [ProcessEntry] = []
        var queue = children[pid] ?? []
        var visited: Set<Int> = [pid]

        while !queue.isEmpty {
            let childPid = queue.removeFirst()
            guard !visited.contains(childPid) else { continue }
            visited.insert(childPid)

            if let entry = table[childPid] {
                result.append(entry)
            }
            queue.append(contentsOf: children[childPid] ?? [])
        }

        return result
    }

    public static func shell(_ args: [String]) -> String {
        var pipeFds: [Int32] = [0, 0]
        guard pipe(&pipeFds) == 0 else { return "" }

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_adddup2(&fileActions, pipeFds[1], STDOUT_FILENO)
        posix_spawn_file_actions_addopen(&fileActions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addclose(&fileActions, pipeFds[0])
        posix_spawn_file_actions_addclose(&fileActions, pipeFds[1])

        let cArgs = args.map { strdup($0) } + [nil]
        defer { cArgs.compactMap { $0 }.forEach { free($0) } }

        var pid: pid_t = 0
        let spawnResult = args[0].withCString { path in
            posix_spawn(&pid, path, &fileActions, nil, cArgs, environ)
        }
        posix_spawn_file_actions_destroy(&fileActions)

        close(pipeFds[1])

        guard spawnResult == 0 else {
            close(pipeFds[0])
            return ""
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            let count = read(pipeFds[0], &buffer, buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        close(pipeFds[0])

        var status: Int32 = 0
        waitpid(pid, &status, 0)

        guard status == 0 else { return "" }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
