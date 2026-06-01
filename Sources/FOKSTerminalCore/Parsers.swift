import Foundation

public enum ProjectConfigLoader {
    public static let defaultConfigPath = "/Users/eduardofgiovannini/Documents/GitHub/FOKS_BLOOMBERG/config/projects.json"

    public static func load(from url: URL = URL(fileURLWithPath: defaultConfigPath)) -> [ProjectConfig] {
        guard
            let data = try? Data(contentsOf: url),
            let decoded = try? decode(data)
        else {
            return []
        }
        return decoded.projects.filter(\.enabled)
    }

    public static func decode(_ data: Data) throws -> ProjectsConfigFile {
        try JSONDecoder().decode(ProjectsConfigFile.self, from: data)
    }
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

    public static func analyze(
        label: String,
        listPID: String,
        listStatus: String,
        printOutput: String,
        domain: LaunchAgentSnapshot.Domain = .agent
    ) -> LaunchAgentSnapshot {
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
            stderrPath: stderrPath,
            domain: domain
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

public enum AutomationMetadataParser {
    public static func purpose(from text: String, fallbackName: String) -> String {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .prefix(40)
            .map(String.init)

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#!") || line.hasPrefix("set -") {
                continue
            }

            if let docstring = inlineDocstring(from: line) {
                return docstring
            }

            if line.hasPrefix("#") {
                let comment = line
                    .drop(while: { $0 == "#" || $0 == " " })
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !comment.isEmpty {
                    return comment.prefixText(180)
                }
            }

            if line.hasPrefix("import ") || line.hasPrefix("from ") {
                continue
            }

            break
        }

        return "Run \(fallbackName.replacingOccurrences(of: "-", with: " ")) automation."
    }

    public static func runRequirement(from text: String) -> String {
        for rawLine in text.split(separator: "\n").prefix(80) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.localizedCaseInsensitiveContains("usage:") else { continue }
            let usage = line
                .replacingOccurrences(of: "echo ", with: "")
                .replacingOccurrences(of: "\"", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return "Requires arguments: \(usage.prefixText(140))"
        }
        return ""
    }

    private static func inlineDocstring(from line: String) -> String? {
        for marker in ["\"\"\"", "'''"] {
            guard line.hasPrefix(marker) else { continue }
            let content = line
                .dropFirst(marker.count)
                .replacingOccurrences(of: marker, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                return content.prefixText(180)
            }
        }
        return nil
    }
}

public enum ResourceParser {
    public static func cpuPercent(fromPSOutput output: String, logicalCores: Int) -> Double {
        let total = output
            .split(separator: "\n")
            .compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .reduce(0, +)
        let cores = max(logicalCores, 1)
        return min(max(total / Double(cores), 0), 100)
    }

    public static func memoryUsedBytes(fromVMStat output: String, totalBytes: UInt64) -> UInt64 {
        guard totalBytes > 0 else { return 0 }
        let pageSize = pageSizeBytes(fromVMStat: output)
        let activePages = pageCount(fromVMStat: output, label: "Pages active")
        let wiredPages = pageCount(fromVMStat: output, label: "Pages wired down")
        let compressedPages = pageCount(fromVMStat: output, label: "Pages occupied by compressor")
        let usedPages = max(activePages + wiredPages + compressedPages, 0)
        let usedBytes = UInt64(usedPages) * UInt64(pageSize)
        return min(usedBytes, totalBytes)
    }

    public static func memoryUsedBytes(fromMemoryPressure output: String, totalBytes: UInt64) -> UInt64? {
        guard totalBytes > 0 else { return nil }
        guard let freePercent = freePercent(fromMemoryPressure: output) else { return nil }
        let boundedFree = min(max(freePercent, 0), 100)
        let usedPercent = 100 - boundedFree
        return UInt64((Double(totalBytes) * Double(usedPercent)) / 100.0)
    }

    public static func diskUsage(fromDFOutput output: String) -> (usedPercent: Double, freeBytes: UInt64)? {
        guard let line = output.split(separator: "\n").dropFirst().first else {
            return nil
        }

        let parts = line.split(whereSeparator: \.isWhitespace)
        guard parts.count >= 5, let availableKB = UInt64(parts[3]) else { return nil }
        let percentText = parts[4].replacingOccurrences(of: "%", with: "")
        guard let usedPercent = Double(percentText) else { return nil }
        return (usedPercent, availableKB * 1024)
    }

    public static func networkBytes(fromNetstatOutput output: String) -> (received: UInt64, transmitted: UInt64) {
        var received: UInt64 = 0
        var transmitted: UInt64 = 0
        var seenRows = Set<String>()

        for rawLine in output.split(separator: "\n") {
            let line = String(rawLine)
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 10 else { continue }
            let interface = String(parts[0])
            guard interface != "lo0", interface != "Name" else { continue }
            let address = String(parts[2])
            let key = "\(interface)-\(address)"
            guard !seenRows.contains(key) else { continue }
            seenRows.insert(key)
            received += UInt64(parts[6]) ?? 0
            transmitted += UInt64(parts[9]) ?? 0
        }

        return (received, transmitted)
    }

    private static func pageSizeBytes(fromVMStat output: String) -> Int {
        guard let firstLine = output.split(separator: "\n").first else { return 4096 }
        let digits = firstLine.filter(\.isNumber)
        return Int(String(digits)) ?? 4096
    }

    private static func pageCount(fromVMStat output: String, label: String) -> Int {
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix(label) else { continue }
            let value = line
                .dropFirst(label.count)
                .replacingOccurrences(of: ":", with: "")
                .replacingOccurrences(of: ".", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(value) ?? 0
        }
        return 0
    }

    private static func freePercent(fromMemoryPressure output: String) -> Int? {
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.localizedCaseInsensitiveContains("System-wide memory free percentage:") else { continue }
            guard let value = line.split(separator: ":").last?.trimmingCharacters(in: .whitespacesAndNewlines) else { continue }
            let digits = value.replacingOccurrences(of: "%", with: "")
            return Int(digits)
        }
        return nil
    }
}

public enum DependencyInspector {
    public static func inspect(path: String, fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)) -> (missing: [String], warnings: [String]) {
        var missing: [String] = []
        var warnings: [String] = []

        func has(_ relative: String) -> Bool {
            fileExists(URL(fileURLWithPath: path).appendingPathComponent(relative).path)
        }

        if has("package.json"), !has("node_modules") {
            missing.append("node_modules not present")
        }
        if (has("requirements.txt") || has("pyproject.toml")), !has(".venv"), !has("venv") {
            missing.append("Python virtual environment not present")
        }
        if has("Package.swift"), !has(".build") {
            warnings.append("Swift build cache not present")
        }
        if has("Gemfile"), !has("vendor/bundle") {
            warnings.append("Ruby bundle cache not present")
        }

        return (missing, warnings)
    }
}

public enum LogClassifier {
    public static func level(for line: String) -> String {
        let lower = line.lowercased()
        if lower.contains("critical") || lower.contains("panic") || lower.contains("fatal") || lower.contains("incident") {
            return "INCIDENT"
        }
        if lower.contains("error") || lower.contains("exception") || lower.contains("traceback") || lower.contains("failed") {
            return "ERROR"
        }
        if lower.contains("warn") || lower.contains("deprecat") || lower.contains("timeout") {
            return "WARN"
        }
        return "INFO"
    }
}

public struct IncidentAggregator: Sendable {
    public init() {}

    public func build(snapshot: DashboardSnapshot) -> [Incident] {
        var incidents: [Incident] = []

        for project in snapshot.projects where project.health == .missing {
            incidents.append(
                Incident(
                    id: "project-missing-\(project.id)",
                    severity: .critical,
                    scope: project.shortName,
                    title: "Project path missing",
                    evidence: project.path
                )
            )
        }

        for service in (snapshot.launchAgents + snapshot.launchDaemons) where service.health == .failed {
            incidents.append(
                Incident(
                    id: "launch-\(service.id)",
                    severity: .critical,
                    scope: service.label,
                    title: "Launch service failed",
                    evidence: service.reason
                )
            )
        }

        for log in snapshot.logs where log.level == "ERROR" || log.level == "INCIDENT" {
            incidents.append(
                Incident(
                    id: "log-\(log.id.uuidString)",
                    severity: log.level == "INCIDENT" ? .critical : .warning,
                    scope: log.source,
                    title: "Log \(log.level.lowercased())",
                    evidence: log.message,
                    timestamp: log.timestamp
                )
            )
        }

        if snapshot.system.cpuPercent >= 90 {
            incidents.append(
                Incident(
                    id: "system-cpu",
                    severity: .critical,
                    scope: "System",
                    title: "High CPU pressure",
                    evidence: String(format: "CPU %.0f%%", snapshot.system.cpuPercent)
                )
            )
        }

        if snapshot.system.diskUsedPercent >= 92 {
            incidents.append(
                Incident(
                    id: "system-disk",
                    severity: .critical,
                    scope: "System",
                    title: "Low disk headroom",
                    evidence: String(format: "Disk %.0f%% used", snapshot.system.diskUsedPercent)
                )
            )
        }

        return incidents.sorted { lhs, rhs in
            if lhs.severity.priority != rhs.severity.priority {
                return lhs.severity.priority > rhs.severity.priority
            }
            return lhs.timestamp > rhs.timestamp
        }
    }
}

private extension String {
    func nonEmpty(or fallback: String) -> String {
        isEmpty ? fallback : self
    }

    func prefixText(_ limit: Int) -> String {
        count <= limit ? self : String(prefix(limit)) + "..."
    }
}
