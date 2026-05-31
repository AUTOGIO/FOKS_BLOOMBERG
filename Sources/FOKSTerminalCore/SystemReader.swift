import Foundation

public struct SystemReader: Sendable {
    private let runner: CommandRunner
    private let configURL: URL

    public init(
        runner: CommandRunner = CommandRunner(),
        configURL: URL = URL(fileURLWithPath: ProjectConfigLoader.defaultConfigPath)
    ) {
        self.runner = runner
        self.configURL = configURL
    }

    public func readDashboard() async -> DashboardSnapshot {
        async let projects = readProjects()
        async let hardware = readHardware()
        async let processes = readProcesses()
        async let launchAgents = readLaunchAgents()
        async let logs = readRecentLogs()

        return await DashboardSnapshot(
            projects: projects,
            hardware: hardware,
            processes: processes,
            launchAgents: launchAgents,
            logs: logs,
            refreshedAt: Date()
        )
    }

    public func readProjects() async -> [ProjectStatus] {
        let configs = ProjectConfigLoader.load(from: configURL)
        var statuses: [ProjectStatus] = []

        for config in configs {
            statuses.append(await readProject(config))
        }

        return statuses.sorted { lhs, rhs in
            if lhs.health.priority != rhs.health.priority {
                return lhs.health.priority > rhs.health.priority
            }
            return lhs.shortName < rhs.shortName
        }
    }

    public func readHardware() async -> HardwareSnapshot {
        async let model = firstLine("/usr/sbin/sysctl", ["-n", "hw.model"])
        async let chip = firstLine("/usr/sbin/sysctl", ["-n", "machdep.cpu.brand_string"])
        async let memoryRaw = firstLine("/usr/sbin/sysctl", ["-n", "hw.memsize"])
        async let coreCount = firstLine("/usr/sbin/sysctl", ["-n", "hw.physicalcpu"])
        async let performanceCores = firstLine("/usr/sbin/sysctl", ["-n", "hw.perflevel0.physicalcpu"])
        async let efficiencyCores = firstLine("/usr/sbin/sysctl", ["-n", "hw.perflevel1.physicalcpu"])
        async let osVersion = swVers()
        async let uptime = firstLine("/usr/bin/uptime", [])

        let memoryBytes = UInt64(await memoryRaw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let pCores = await performanceCores
        let eCores = await efficiencyCores
        let cores: String
        if !pCores.isEmpty, !eCores.isEmpty {
            cores = "\(pCores) performance + \(eCores) efficiency"
        } else {
            let count = await coreCount
            cores = count.isEmpty ? "unknown" : "\(count) physical"
        }

        return await HardwareSnapshot(
            targetProfile: HardwareSnapshot.empty.targetProfile,
            modelIdentifier: model.nonEmpty(or: "unknown"),
            chip: chip.nonEmpty(or: "Apple Silicon"),
            coreSummary: cores,
            memory: memoryBytes > 0 ? ByteFormatter.memoryString(bytes: memoryBytes) : "unknown",
            osVersion: osVersion.nonEmpty(or: "unknown"),
            uptime: uptime.nonEmpty(or: "unknown")
        )
    }

    public func readProcesses() async -> [ProcessSnapshot] {
        let result = await runner.run(
            "/bin/ps",
            ["axo", "pid=,pcpu=,rss=,command="],
            timeout: 4
        )
        guard result.exitCode == 0 else { return [] }

        let watchTerms = [
            "python", "ollama", "LM Studio", "streamlit", "yabai",
            "swift", "FOKS", "Home Assistant", "homeassistant"
        ]

        return result.output
            .split(separator: "\n")
            .map(String.init)
            .filter { line in
                watchTerms.contains { line.localizedCaseInsensitiveContains($0) }
            }
            .filter { !$0.localizedCaseInsensitiveContains("egrep") }
            .compactMap(ProcessParser.parsePSLine)
            .prefix(60)
            .map { $0 }
    }

    public func readLaunchAgents() async -> [LaunchAgentSnapshot] {
        let result = await runner.run("/bin/launchctl", ["list"], timeout: 4)
        guard result.exitCode == 0 else { return [] }

        let watchTerms = ["foks", "gmc", "yabai", "home", "fulofilo", "life", "workspace"]

        return await result.output
            .split(separator: "\n")
            .map(String.init)
            .filter { line in
                watchTerms.contains { line.localizedCaseInsensitiveContains($0) }
            }
            .prefix(60)
            .compactMap(LaunchAgentParser.parseLaunchctlLine)
            .asyncMap { await analyzeLaunchAgent($0) }
    }

    public func readRecentLogs() async -> [LogEntry] {
        let paths = [
            "\(NSHomeDirectory())/foks/logs/foks-monitor.jsonl",
            "\(NSHomeDirectory())/foks/logs/workspace_launch.log",
            "\(NSHomeDirectory())/Library/Logs/FOKS/workspace_launch.log"
        ]

        for path in paths where FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }

            return text
                .split(separator: "\n")
                .suffix(16)
                .map {
                    LogEntry(
                        source: url.lastPathComponent,
                        message: String($0).prefixText(180),
                        level: "INFO"
                    )
                }
        }

        return [
            LogEntry(
                source: "SYSTEM",
                message: "No FoKS log file found in ~/foks/logs or ~/Library/Logs/FOKS",
                level: "WARN"
            )
        ]
    }

    private func readProject(_ config: ProjectConfig) async -> ProjectStatus {
        let exists = FileManager.default.fileExists(atPath: config.path)
        guard exists else {
            return status(from: config, health: .missing, reason: "missing path")
        }

        let isGit = await isGitRepository(config.path)
        guard isGit else {
            return status(from: config, health: .notGit, reason: "not a git repo")
        }

        async let branch = gitFirstLine(config.path, ["branch", "--show-current"], fallback: "DETACHED")
        async let porcelain = gitOutput(config.path, ["status", "--porcelain"])
        async let remote = gitFirstLine(config.path, ["remote", "get-url", "origin"], fallback: "")
        async let upstream = gitFirstLine(
            config.path,
            ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"],
            fallback: ""
        )

        let dirtyFiles = GitStatusParser.dirtyFileCount(from: await porcelain)
        let dirtyItems = GitStatusParser.dirtyItems(from: await porcelain)
        let remoteURL = await remote
        let upstreamName = await upstream
        let divergence = upstreamName.isEmpty ? (ahead: 0, behind: 0) : await readDivergence(path: config.path, upstream: upstreamName)
        let evaluated = GitStatusParser.health(
            pathExists: true,
            isGitRepository: true,
            dirtyFiles: dirtyFiles,
            ahead: divergence.ahead,
            behind: divergence.behind,
            remoteURL: remoteURL,
            upstream: upstreamName
        )

        return ProjectStatus(
            id: config.id,
            shortName: config.shortName,
            displayName: config.displayName,
            path: config.path,
            group: config.group,
            health: evaluated.0,
            reason: evaluated.1,
            branch: await branch.nonEmpty(or: "DETACHED"),
            dirtyFiles: dirtyFiles,
            ahead: divergence.ahead,
            behind: divergence.behind,
            remoteURL: remoteURL,
            enabled: config.enabled,
            dirtyItems: dirtyItems
        )
    }

    private func analyzeLaunchAgent(_ snapshot: LaunchAgentSnapshot) async -> LaunchAgentSnapshot {
        let result = await runner.run(
            "/bin/launchctl",
            ["print", "gui/\(getuid())/\(snapshot.label)"],
            timeout: 3
        )
        guard result.exitCode == 0 else { return snapshot }
        return LaunchAgentParser.analyze(
            label: snapshot.label,
            listPID: snapshot.pid,
            listStatus: snapshot.status,
            printOutput: result.output
        )
    }

    private func status(from config: ProjectConfig, health: ProjectStatus.Health, reason: String) -> ProjectStatus {
        ProjectStatus(
            id: config.id,
            shortName: config.shortName,
            displayName: config.displayName,
            path: config.path,
            group: config.group,
            health: health,
            reason: reason,
            enabled: config.enabled
        )
    }

    private func isGitRepository(_ path: String) async -> Bool {
        let result = await runner.run(
            "/usr/bin/git",
            ["-C", path, "rev-parse", "--is-inside-work-tree"],
            timeout: 3
        )
        return result.exitCode == 0 && result.output == "true"
    }

    private func gitOutput(_ path: String, _ args: [String]) async -> String {
        let result = await runner.run("/usr/bin/git", ["-C", path] + args, timeout: 4)
        return result.exitCode == 0 ? result.output : ""
    }

    private func gitFirstLine(_ path: String, _ args: [String], fallback: String) async -> String {
        let output = await gitOutput(path, args)
        return output.split(separator: "\n").first.map(String.init) ?? fallback
    }

    private func readDivergence(path: String, upstream: String) async -> (ahead: Int, behind: Int) {
        let output = await gitOutput(path, ["rev-list", "--left-right", "--count", "HEAD...\(upstream)"])
        return GitStatusParser.divergence(from: output)
    }

    private func firstLine(_ executable: String, _ args: [String]) async -> String {
        let result = await runner.run(executable, args, timeout: 3)
        guard result.exitCode == 0 else { return "" }
        return result.output.split(separator: "\n").first.map(String.init) ?? ""
    }

    private func swVers() async -> String {
        let product = await firstLine("/usr/bin/sw_vers", ["-productVersion"])
        let build = await firstLine("/usr/bin/sw_vers", ["-buildVersion"])
        if product.isEmpty { return "" }
        return build.isEmpty ? "macOS \(product)" : "macOS \(product) (\(build))"
    }
}

private extension Sequence {
    func asyncMap<T>(_ transform: (Element) async -> T) async -> [T] {
        var values: [T] = []
        for element in self {
            values.append(await transform(element))
        }
        return values
    }
}

private extension String {
    func nonEmpty(or fallback: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    func prefixText(_ limit: Int) -> String {
        count <= limit ? self : String(prefix(limit)) + "..."
    }
}
