import Foundation

public enum ProjectConfigLoader {
    public static let defaultConfigPath = "/Users/eduardofgiovannini/Documents/GitHub/FOKS_BLOOMBERG/config/projects.json"

    public static func load(from url: URL = URL(fileURLWithPath: defaultConfigPath)) -> [ProjectConfig] {
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? decode(data)
        else {
            return defaultProjects
        }
        return decoded.projects.filter(\.enabled)
    }

    public static func decode(_ data: Data) throws -> ProjectsConfigFile {
        try JSONDecoder().decode(ProjectsConfigFile.self, from: data)
    }

    public static let defaultProjects: [ProjectConfig] = [
        ProjectConfig(
            id: "foks",
            shortName: "FOKS",
            displayName: "FOKS Bloomberg Terminal",
            path: "/Users/eduardofgiovannini/Documents/GitHub/FOKS_BLOOMBERG",
            group: "OPS",
            enabled: true
        ),
        ProjectConfig(
            id: "ffa",
            shortName: "FFA",
            displayName: "FuloFilo Analytics",
            path: "/Users/eduardofgiovannini/Documents/GitHub/fulofilo-analytics",
            group: "BUSINESS",
            enabled: true
        ),
        ProjectConfig(
            id: "gmc",
            shortName: "GMC",
            displayName: "GMC",
            path: "/Users/eduardofgiovannini/Documents/GitHub/GMC",
            group: "FINANCE",
            enabled: true
        ),
        ProjectConfig(
            id: "gfin",
            shortName: "GFIN",
            displayName: "Giovannini Finance",
            path: "/Users/eduardofgiovannini/Documents/GitHub/giovannini-finance",
            group: "FINANCE",
            enabled: true
        ),
        ProjectConfig(
            id: "life",
            shortName: "LIFE",
            displayName: "Personal Life OS",
            path: "/Users/eduardofgiovannini/Documents/GitHub/PersonalLifeOS",
            group: "LIFE",
            enabled: true
        )
    ]
}

public enum GitStatusParser {
    public static func dirtyFileCount(from porcelain: String) -> Int {
        porcelain
            .split(separator: "\n", omittingEmptySubsequences: true)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
    }

    public static func divergence(from text: String) -> (ahead: Int, behind: Int) {
        let parts = text.split(whereSeparator: \.isWhitespace)
        guard parts.count >= 2 else { return (0, 0) }
        return (Int(parts[0]) ?? 0, Int(parts[1]) ?? 0)
    }

    public static func dirtyItems(from porcelain: String, limit: Int = 12) -> [String] {
        porcelain
            .split(separator: "\n", omittingEmptySubsequences: true)
            .prefix(limit)
            .map { rawLine in
                let line = String(rawLine)
                guard line.count > 3 else { return line }
                let status = String(line.prefix(2)).trimmingCharacters(in: .whitespaces)
                let path = String(line.dropFirst(3))
                return status.isEmpty ? path : "\(status) \(path)"
            }
    }

    public static func health(
        pathExists: Bool,
        isGitRepository: Bool,
        dirtyFiles: Int,
        ahead: Int,
        behind: Int,
        remoteURL: String,
        upstream: String
    ) -> (ProjectStatus.Health, String) {
        guard pathExists else { return (.missing, "missing path") }
        guard isGitRepository else { return (.notGit, "not a git repo") }

        if dirtyFiles > 0 {
            return (.dirty, "\(dirtyFiles) dirty file\(dirtyFiles == 1 ? "" : "s")")
        }
        if ahead > 0 {
            return (.unpushed, "\(ahead) unpushed commit\(ahead == 1 ? "" : "s")")
        }
        if remoteURL.isEmpty {
            return (.unknown, "no remote")
        }
        if upstream.isEmpty {
            return (.unknown, "no upstream")
        }
        if behind > 0 {
            return (.unknown, "\(behind) behind remote")
        }
        return (.clean, "clean and synced")
    }
}

public enum ProcessParser {
    public static func parsePSLine(_ line: String) -> ProcessSnapshot? {
        let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard parts.count == 4 else { return nil }

        let rssKB = Int(parts[2]) ?? 0
        let memory: String
        if rssKB >= 1_048_576 {
            memory = "\(rssKB / 1_048_576) GB"
        } else {
            memory = "\(max(rssKB / 1024, 0)) MB"
        }

        return ProcessSnapshot(
            pid: String(parts[0]),
            cpu: "\(parts[1])%",
            memory: memory,
            command: String(parts[3])
        )
    }
}

public enum LaunchAgentParser {
    public static func parseLaunchctlLine(_ line: String) -> LaunchAgentSnapshot? {
        let tabParts = line.split(separator: "\t", omittingEmptySubsequences: false)
        if tabParts.count >= 3 {
            return LaunchAgentSnapshot(
                pid: cleanLaunchctlValue(String(tabParts[0])),
                status: cleanLaunchctlValue(String(tabParts[1])),
                label: cleanLaunchctlValue(String(tabParts[2]))
            )
        }

        let parts = line.split(whereSeparator: \.isWhitespace)
        guard parts.count >= 3 else { return nil }
        return LaunchAgentSnapshot(
            pid: cleanLaunchctlValue(String(parts[0])),
            status: cleanLaunchctlValue(String(parts[1])),
            label: parts.dropFirst(2).joined(separator: " ")
        )
    }

    public static func analyze(label: String, listPID: String, listStatus: String, printOutput: String) -> LaunchAgentSnapshot {
        let state = firstValue(in: printOutput, prefix: "state = ").nonEmpty(or: listPID == "none" ? "not running" : "running")
        let plistPath = firstValue(in: printOutput, prefix: "path = ")
        let stdoutPath = firstValue(in: printOutput, prefix: "stdout path = ")
        let stderrPath = firstValue(in: printOutput, prefix: "stderr path = ")
        let lastExitCode = firstValue(in: printOutput, prefix: "last exit code = ")
        let lastSignal = firstValue(in: printOutput, prefix: "last terminating signal = ")
        let runs = firstValue(in: printOutput, prefix: "runs = ")

        let health: LaunchAgentSnapshot.Health
        let reason: String

        if state == "running" {
            health = .running
            reason = lastSignal.isEmpty ? "running" : "running; prior signal \(lastSignal)"
        } else if !lastExitCode.isEmpty, lastExitCode != "0", lastExitCode != "(never exited)" {
            health = .failed
            reason = "last exit \(lastExitCode); runs \(runs.nonEmpty(or: "?"))"
        } else if state.contains("scheduled") {
            health = .scheduled
            reason = "scheduled; runs \(runs.nonEmpty(or: "0"))"
        } else if state == "not running" || listPID == "none" {
            health = .stopped
            reason = lastExitCode.isEmpty ? "not running" : "not running; last exit \(lastExitCode)"
        } else {
            health = .unknown
            reason = state
        }

        return LaunchAgentSnapshot(
            pid: listPID,
            status: listStatus,
            label: label,
            state: state,
            health: health,
            reason: reason,
            plistPath: plistPath,
            stdoutPath: stdoutPath,
            stderrPath: stderrPath
        )
    }

    private static func cleanLaunchctlValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "-" ? "none" : trimmed
    }

    private static func firstValue(in text: String, prefix: String) -> String {
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }
}

public enum ByteFormatter {
    public static func memoryString(bytes: UInt64) -> String {
        let gib = Double(bytes) / 1_073_741_824
        if gib >= 10 {
            return "\(Int(gib.rounded())) GB"
        }
        return String(format: "%.1f GB", gib)
    }
}

private extension String {
    func nonEmpty(or fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
