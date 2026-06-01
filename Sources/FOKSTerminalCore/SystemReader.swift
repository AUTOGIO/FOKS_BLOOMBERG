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
        async let system = readSystemMetrics()
        async let processes = readProcesses()
        async let launchAgents = readLaunchAgents()
        async let launchDaemons = readLaunchDaemons()
        async let automations = readAutomations()

        let resolvedProjects = await projects
        let resolvedHardware = await hardware
        let resolvedSystem = await system
        let resolvedProcesses = await processes
        let resolvedAgents = await launchAgents
        let resolvedDaemons = await launchDaemons
        let resolvedAutomations = await automations
        let resolvedAppBundles = await readAppBundles(projects: resolvedProjects)
        let resolvedLogs = await readRecentLogs(projects: resolvedProjects)
        let baseSnapshot = DashboardSnapshot(
            projects: resolvedProjects,
            hardware: resolvedHardware,
            system: resolvedSystem,
            processes: resolvedProcesses,
            launchAgents: resolvedAgents,
            launchDaemons: resolvedDaemons,
            automations: resolvedAutomations,
            appBundles: resolvedAppBundles,
            logs: resolvedLogs,
            refreshedAt: Date()
        )

        return DashboardSnapshot(
            projects: baseSnapshot.projects,
            hardware: baseSnapshot.hardware,
            system: baseSnapshot.system,
            processes: baseSnapshot.processes,
            launchAgents: baseSnapshot.launchAgents,
            launchDaemons: baseSnapshot.launchDaemons,
            automations: baseSnapshot.automations,
            appBundles: baseSnapshot.appBundles,
            logs: baseSnapshot.logs,
            incidents: IncidentAggregator().build(snapshot: baseSnapshot),
            refreshedAt: baseSnapshot.refreshedAt
        )
    }

    public func readProjects() async -> [ProjectStatus] {
        let configs = ProjectConfigLoader.load(from: configURL)
        let statuses = await withTaskGroup(of: ProjectStatus.self) { group in
            for config in configs {
                group.addTask {
                    await readProject(config)
                }
            }

            var values: [ProjectStatus] = []
            for await status in group {
                values.append(status)
            }
            return values
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

        let resolvedModel = await model.nonEmpty(or: "unknown")
        let resolvedChip = await chip.nonEmpty(or: "unknown")
        let resolvedMemory = memoryBytes > 0 ? ByteFormatter.memoryString(bytes: memoryBytes) : "unknown"
        let resolvedOS = await osVersion.nonEmpty(or: "unknown")
        let resolvedUptime = await uptime.nonEmpty(or: "unknown")

        return HardwareSnapshot(
            targetProfile: [
                resolvedModel,
                resolvedChip,
                cores,
                resolvedMemory,
                resolvedOS
            ].joined(separator: " | "),
            modelIdentifier: resolvedModel,
            chip: resolvedChip,
            coreSummary: cores,
            memory: resolvedMemory,
            osVersion: resolvedOS,
            uptime: resolvedUptime
        )
    }

    public func readSystemMetrics() async -> SystemMetricsSnapshot {
        async let cpuRaw = runner.run("/bin/ps", ["-A", "-o", "%cpu="], timeout: 4)
        async let logicalCores = firstLine("/usr/sbin/sysctl", ["-n", "hw.logicalcpu"])
        async let memoryRaw = firstLine("/usr/sbin/sysctl", ["-n", "hw.memsize"])
        async let vmStat = runner.run("/usr/bin/vm_stat", [], timeout: 3)
        async let memoryPressure = runner.run("/usr/bin/memory_pressure", [], timeout: 3)
        async let disk = runner.run("/bin/df", ["-k", "/"], timeout: 3)
        async let network = runner.run("/usr/sbin/netstat", ["-ibn"], timeout: 4)
        async let uptime = firstLine("/usr/bin/uptime", [])

        let cpuResult = await cpuRaw
        let coreCount = Int(await logicalCores) ?? 1
        let totalMemory = UInt64(await memoryRaw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let vmResult = await vmStat
        let memoryPressureResult = await memoryPressure
        let diskResult = await disk
        let networkResult = await network
        let cpuAvailable = cpuResult.exitCode == 0 && !cpuResult.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let memoryAvailable = vmResult.exitCode == 0 && !vmResult.output.isEmpty && totalMemory > 0
        let diskUsage = diskResult.exitCode == 0 ? ResourceParser.diskUsage(fromDFOutput: diskResult.output) : nil
        let diskAvailable = diskUsage != nil
        let networkAvailable = networkResult.exitCode == 0 && !networkResult.output.isEmpty
        let networkBytes = networkAvailable ? ResourceParser.networkBytes(fromNetstatOutput: networkResult.output) : (received: 0, transmitted: 0)
        let resolvedUptime = await uptime.nonEmpty(or: "")

        let memoryUsedBytes: UInt64 = {
            if memoryPressureResult.exitCode == 0,
               let value = ResourceParser.memoryUsedBytes(fromMemoryPressure: memoryPressureResult.output, totalBytes: totalMemory) {
                return value
            }
            if memoryAvailable {
                return ResourceParser.memoryUsedBytes(fromVMStat: vmResult.output, totalBytes: totalMemory)
            }
            return 0
        }()

        return SystemMetricsSnapshot(
            cpuPercent: cpuAvailable ? ResourceParser.cpuPercent(fromPSOutput: cpuResult.output, logicalCores: coreCount) : 0,
            cpuAvailable: cpuAvailable,
            memoryUsedBytes: memoryUsedBytes,
            memoryTotalBytes: totalMemory,
            memoryAvailable: memoryAvailable,
            diskUsedPercent: diskUsage?.usedPercent ?? 0,
            diskFreeBytes: diskUsage?.freeBytes ?? 0,
            diskAvailable: diskAvailable,
            networkReceivedBytes: networkBytes.received,
            networkTransmittedBytes: networkBytes.transmitted,
            networkAvailable: networkAvailable,
            uptime: resolvedUptime.nonEmpty(or: "-"),
            uptimeAvailable: !resolvedUptime.isEmpty
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

    public func readLaunchDaemons() async -> [LaunchAgentSnapshot] {
        await discoverLaunchDaemonPlists()
            .prefix(60)
            .map { path -> LaunchAgentSnapshot in
                let label = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                return LaunchAgentSnapshot(
                    pid: "unknown",
                    status: "configured",
                    label: label,
                    state: "configured",
                    health: .unknown,
                    reason: "plist configured; runtime queried on refresh",
                    plistPath: path,
                    domain: .daemon
                )
            }
            .asyncMap { await analyzeLaunchDaemon($0) }
    }

    public func readAutomations(
        rootPath: String = "\(NSHomeDirectory())/Developer/automation"
    ) async -> [AutomationSnapshot] {
        let root = URL(fileURLWithPath: rootPath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return []
        }

        async let processes = runner.run("/bin/ps", ["axo", "pid=,command="], timeout: 4)
        let processResult = await processes
        let processOutput = processResult.exitCode == 0 ? processResult.output : ""
        let logsRoot = root.appendingPathComponent("logs")

        return discoverAutomationFiles(root: root)
            .prefix(100)
            .compactMap { automationSnapshot(for: $0, logsRoot: logsRoot, processOutput: processOutput) }
            .sorted { lhs, rhs in
                if lhs.isRunning != rhs.isRunning {
                    return lhs.isRunning && !rhs.isRunning
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    public func readAppBundles(projects: [ProjectStatus] = []) async -> [AppBundleSnapshot] {
        async let processes = runner.run("/bin/ps", ["axo", "pid=,command="], timeout: 4)
        let processResult = await processes
        let processOutput = processResult.exitCode == 0 ? processResult.output : ""

        return discoverAppBundleURLs(projects: projects)
            .prefix(100)
            .compactMap { appBundleSnapshot(for: $0, processOutput: processOutput) }
            .sorted { lhs, rhs in
                if lhs.isRunning != rhs.isRunning {
                    return lhs.isRunning && !rhs.isRunning
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    public func readRecentLogs(projects: [ProjectStatus] = []) async -> [LogEntry] {
        var entries: [LogEntry] = []

        let foksPaths = [
            "\(NSHomeDirectory())/foks/logs/foks-monitor.jsonl",
            "\(NSHomeDirectory())/foks/logs/workspace_launch.log",
            "\(NSHomeDirectory())/Library/Logs/FOKS/workspace_launch.log"
        ]

        for path in foksPaths {
            entries.append(contentsOf: readLogFile(path: path, category: .foks, projectID: nil, limit: 120))
        }

        for project in projects.prefix(80) {
            for path in discoverProjectLogPaths(project.path).prefix(4) {
                entries.append(contentsOf: readLogFile(path: path, category: .project, projectID: project.id, limit: 80))
            }
        }

        entries.append(contentsOf: readLogFile(path: "/var/log/system.log", category: .system, projectID: nil, limit: 80))

        return Array(entries.sorted { $0.timestamp > $1.timestamp }.prefix(500))
    }

    private func readProject(_ config: ProjectConfig) async -> ProjectStatus {
        let exists = FileManager.default.fileExists(atPath: config.path)
        guard exists else {
            return status(from: config, health: .missing, reason: "missing path")
        }

        let dependencies = DependencyInspector.inspect(path: config.path)
        let fallbackActivity = folderModificationDate(config.path)
        let isGit = await isGitRepository(config.path)
        guard isGit else {
            return status(
                from: config,
                health: .notGit,
                reason: "not a git repo",
                lastActivity: fallbackActivity,
                missingDependencies: dependencies.missing,
                warnings: dependencies.warnings
            )
        }

        async let branch = gitFirstLine(config.path, ["branch", "--show-current"], fallback: "DETACHED")
        async let porcelain = gitOutput(config.path, ["status", "--porcelain"])
        async let remote = gitFirstLine(config.path, ["remote", "get-url", "origin"], fallback: "")
        async let upstream = gitFirstLine(
            config.path,
            ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"],
            fallback: ""
        )
        async let lastCommit = gitFirstLine(config.path, ["log", "-1", "--format=%ct"], fallback: "")

        let dirtyFiles = GitStatusParser.dirtyFileCount(from: await porcelain)
        let dirtyItems = GitStatusParser.dirtyItems(from: await porcelain)
        let remoteURL = await remote
        let upstreamName = await upstream
        let branchName = await branch.nonEmpty(or: "DETACHED")
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
        var warnings = dependencies.warnings
        if remoteURL.isEmpty {
            warnings.append("git remote origin missing")
        }
        if upstreamName.isEmpty {
            warnings.append("upstream branch missing")
        }
        if divergence.behind > 0 {
            warnings.append("\(divergence.behind) commit\(divergence.behind == 1 ? "" : "s") behind upstream")
        }
        if branchName == "DETACHED" {
            warnings.append("detached HEAD")
        }
        if dirtyFiles >= 25 {
            warnings.append("large dirty file set")
        }

        return ProjectStatus(
            id: config.id,
            shortName: config.shortName,
            displayName: config.displayName,
            path: config.path,
            group: config.group,
            health: evaluated.0,
            reason: evaluated.1,
            branch: branchName,
            dirtyFiles: dirtyFiles,
            ahead: divergence.ahead,
            behind: divergence.behind,
            remoteURL: remoteURL,
            enabled: config.enabled,
            dirtyItems: dirtyItems,
            lastActivity: parseGitTimestamp(await lastCommit) ?? fallbackActivity,
            missingDependencies: dependencies.missing,
            warnings: warnings
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
            printOutput: result.output,
            domain: .agent
        )
    }

    private func analyzeLaunchDaemon(_ snapshot: LaunchAgentSnapshot) async -> LaunchAgentSnapshot {
        let result = await runner.run(
            "/bin/launchctl",
            ["print", "system/\(snapshot.label)"],
            timeout: 2
        )
        guard result.exitCode == 0 else { return snapshot }
        return LaunchAgentParser.analyze(
            label: snapshot.label,
            listPID: snapshot.pid,
            listStatus: snapshot.status,
            printOutput: result.output,
            domain: .daemon
        )
    }

    private func status(
        from config: ProjectConfig,
        health: ProjectStatus.Health,
        reason: String,
        lastActivity: Date? = nil,
        missingDependencies: [String] = [],
        warnings: [String] = []
    ) -> ProjectStatus {
        ProjectStatus(
            id: config.id,
            shortName: config.shortName,
            displayName: config.displayName,
            path: config.path,
            group: config.group,
            health: health,
            reason: reason,
            enabled: config.enabled,
            lastActivity: lastActivity,
            missingDependencies: missingDependencies,
            warnings: warnings
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

    private func parseGitTimestamp(_ raw: String) -> Date? {
        guard let seconds = TimeInterval(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return Date(timeIntervalSince1970: seconds)
    }

    private func folderModificationDate(_ path: String) -> Date? {
        guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey]) else {
            return nil
        }
        return values.contentModificationDate
    }

    private func discoverLaunchDaemonPlists() -> [String] {
        let watchTerms = ["foks", "gmc", "yabai", "home", "fulofilo", "life", "workspace", "ollama"]
        let roots = ["/Library/LaunchDaemons", "/System/Library/LaunchDaemons"]
        var paths: [String] = []

        for root in roots {
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            for file in files where file.hasSuffix(".plist") {
                let path = URL(fileURLWithPath: root).appendingPathComponent(file).path
                if watchTerms.contains(where: { path.localizedCaseInsensitiveContains($0) }) {
                    paths.append(path)
                }
            }
        }

        return paths.sorted()
    }

    private func discoverAutomationFiles(root: URL) -> [URL] {
        let candidateRoots = [
            root.appendingPathComponent("bin"),
            root.appendingPathComponent("scripts"),
            root
        ]
        var seen = Set<String>()
        var files: [URL] = []

        for candidateRoot in candidateRoots where FileManager.default.fileExists(atPath: candidateRoot.path) {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: candidateRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for child in children where isAutomationCandidate(child) {
                guard seen.insert(child.path).inserted else { continue }
                files.append(child)
            }
        }

        return files.sorted { $0.path < $1.path }
    }

    private func automationSnapshot(
        for url: URL,
        logsRoot: URL,
        processOutput: String
    ) -> AutomationSnapshot? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
              values.isRegularFile == true
        else {
            return nil
        }

        let name = url.deletingPathExtension().lastPathComponent
        let scriptText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let latestLog = latestAutomationLog(baseName: name, logsRoot: logsRoot)
        let isExecutable = fileIsExecutable(url.path)
        let scriptType = automationType(url: url, executable: isExecutable)

        return AutomationSnapshot(
            id: url.path,
            name: name,
            path: url.path,
            purpose: AutomationMetadataParser.purpose(from: scriptText, fallbackName: name),
            scriptType: scriptType,
            logPath: latestLog?.path ?? logsRoot.path,
            lastRunAt: latestLog.flatMap(fileModificationDate),
            modifiedAt: values.contentModificationDate,
            isRunning: automationIsRunning(path: url.path, name: url.lastPathComponent, processOutput: processOutput),
            isExecutable: isExecutable,
            runRequirement: AutomationMetadataParser.runRequirement(from: scriptText),
            runExecutable: url.path
        )
    }

    private func isAutomationCandidate(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
              values.isRegularFile == true
        else {
            return false
        }

        let allowedExtensions = ["command", "py", "sh", "swift"]
        if allowedExtensions.contains(url.pathExtension.lowercased()) {
            return true
        }

        return url.pathExtension.isEmpty && fileIsExecutable(url.path)
    }

    private func automationType(url: URL, executable: Bool) -> String {
        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty { return ext.uppercased() }
        return executable ? "EXEC" : "FILE"
    }

    private func automationIsRunning(path: String, name: String, processOutput: String) -> Bool {
        processOutput
            .split(separator: "\n")
            .map(String.init)
            .contains { line in
                line.contains(path) || line.contains("/\(name)") || line.hasSuffix(" \(name)")
            }
    }

    private func latestAutomationLog(baseName: String, logsRoot: URL) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: logsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return files
            .filter { file in
                guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey]),
                      values.isRegularFile == true
                else {
                    return false
                }
                return file.deletingPathExtension().lastPathComponent.hasPrefix(baseName)
            }
            .max { lhs, rhs in
                (fileModificationDate(lhs) ?? .distantPast) < (fileModificationDate(rhs) ?? .distantPast)
            }
    }

    private func fileIsExecutable(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    private func fileModificationDate(_ url: URL) -> Date? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]) else {
            return nil
        }
        return values.contentModificationDate
    }

    private func discoverAppBundleURLs(projects: [ProjectStatus]) -> [URL] {
        var roots = projects.map { URL(fileURLWithPath: $0.path) }
        roots.append(URL(fileURLWithPath: ProjectConfigLoader.defaultConfigPath).deletingLastPathComponent().deletingLastPathComponent())
        roots.append(URL(fileURLWithPath: "\(NSHomeDirectory())/Applications"))

        var seenRoots = Set<String>()
        var seenApps = Set<String>()
        var apps: [URL] = []

        for root in roots {
            guard seenRoots.insert(root.path).inserted else { continue }
            for app in collectAppBundles(root: root, maxDepth: 3) {
                guard seenApps.insert(app.path).inserted else { continue }
                apps.append(app)
            }
        }

        return apps.sorted { $0.path < $1.path }
    }

    private func collectAppBundles(root: URL, maxDepth: Int) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var apps: [URL] = []
        for case let url as URL in enumerator {
            let depth = url.pathComponents.count - root.pathComponents.count
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }

            if url.pathExtension.lowercased() == "app" {
                apps.append(url)
                enumerator.skipDescendants()
            }
        }

        return apps
    }

    private func appBundleSnapshot(for url: URL, processOutput: String) -> AppBundleSnapshot? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }

        let info = appInfoPlist(url)
        let executableName = info["CFBundleExecutable"] as? String ?? url.deletingPathExtension().lastPathComponent
        let executablePath = url
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent(executableName)
            .path
        let bundleID = info["CFBundleIdentifier"] as? String ?? ""
        let kind = appKind(bundleIdentifier: bundleID, executablePath: executablePath)

        return AppBundleSnapshot(
            id: url.path,
            name: url.deletingPathExtension().lastPathComponent,
            path: url.path,
            kind: kind,
            bundleIdentifier: bundleID.isEmpty ? "unknown" : bundleID,
            executablePath: executablePath,
            modifiedAt: fileModificationDate(url),
            isRunning: appBundleIsRunning(appPath: url.path, executablePath: executablePath, processOutput: processOutput),
            runArguments: [url.path]
        )
    }

    private func appInfoPlist(_ appURL: URL) -> [String: Any] {
        let infoURL = appURL.appendingPathComponent("Contents").appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any]
        else {
            return [:]
        }
        return dictionary
    }

    private func appKind(bundleIdentifier: String, executablePath: String) -> String {
        let text = "\(bundleIdentifier) \(executablePath)".lowercased()
        if text.contains("electron") || text.contains("webapp") || text.contains("safari") || text.contains("chrome") {
            return "WEB APP"
        }
        return "NATIVE APP"
    }

    private func appBundleIsRunning(appPath: String, executablePath: String, processOutput: String) -> Bool {
        processOutput
            .split(separator: "\n")
            .map(String.init)
            .contains { line in
                line.contains(appPath) || line.contains(executablePath)
            }
    }

    private func discoverProjectLogPaths(_ projectPath: String) -> [String] {
        let roots = [
            URL(fileURLWithPath: projectPath).appendingPathComponent("logs"),
            URL(fileURLWithPath: projectPath).appendingPathComponent("log"),
            URL(fileURLWithPath: projectPath).appendingPathComponent(".logs")
        ]
        var paths: [String] = []

        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
                continue
            }
            for file in files where ["log", "jsonl", "txt"].contains(file.pathExtension.lowercased()) {
                paths.append(file.path)
            }
        }

        return paths.sorted()
    }

    private func readLogFile(path: String, category: LogCategory, projectID: String?, limit: Int) -> [LogEntry] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        let url = URL(fileURLWithPath: path)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        return text
            .split(separator: "\n")
            .suffix(limit)
            .map { rawLine in
                let line = String(rawLine)
                return LogEntry(
                    source: url.lastPathComponent,
                    message: line.prefixText(220),
                    level: LogClassifier.level(for: line),
                    category: category,
                    projectID: projectID,
                    filePath: path
                )
            }
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
