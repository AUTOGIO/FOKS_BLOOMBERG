import Foundation

public struct ProjectConfig: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let shortName: String
    public let displayName: String
    public let path: String
    public let group: String
    public let enabled: Bool

    public init(
        id: String,
        shortName: String,
        displayName: String,
        path: String,
        group: String,
        enabled: Bool
    ) {
        self.id = id
        self.shortName = shortName
        self.displayName = displayName
        self.path = path
        self.group = group
        self.enabled = enabled
    }
}

public struct ProjectsConfigFile: Codable, Sendable, Equatable {
    public let projects: [ProjectConfig]

    public init(projects: [ProjectConfig]) {
        self.projects = projects
    }
}

public struct ProjectConfigSyncResult: Sendable, Equatable {
    public let added: [ProjectConfig]
    public let removed: [ProjectConfig]
    public let total: Int
    public let configPath: String

    public var message: String {
        "Projects sync complete: +\(added.count) / -\(removed.count) / \(total) total"
    }

    public init(added: [ProjectConfig], removed: [ProjectConfig], total: Int, configPath: String) {
        self.added = added
        self.removed = removed
        self.total = total
        self.configPath = configPath
    }
}

public struct ProjectStatus: Identifiable, Sendable, Equatable {
    public let id: String
    public let shortName: String
    public let displayName: String
    public let path: String
    public let group: String
    public let health: Health
    public let healthScore: Int
    public let reason: String
    public let branch: String
    public let dirtyFiles: Int
    public let ahead: Int
    public let behind: Int
    public let remoteURL: String
    public let enabled: Bool
    public let dirtyItems: [String]
    public let lastActivity: Date?
    public let missingDependencies: [String]
    public let warnings: [String]

    public enum Health: String, Sendable, CaseIterable {
        case clean = "CLEAN"
        case dirty = "DIRTY"
        case unpushed = "UNPUSHED"
        case missing = "MISSING"
        case notGit = "NOT GIT"
        case unknown = "UNKNOWN"

        public var priority: Int {
            switch self {
            case .missing: return 60
            case .dirty: return 50
            case .unpushed: return 40
            case .unknown: return 30
            case .notGit: return 20
            case .clean: return 10
            }
        }
    }

    public var gitSummary: String {
        var parts = ["branch \(branch)", "\(dirtyFiles) dirty"]
        if ahead > 0 || behind > 0 {
            parts.append("ahead \(ahead) / behind \(behind)")
        }
        if remoteURL.isEmpty {
            parts.append("no remote")
        }
        return parts.joined(separator: " | ")
    }

    public var recommendedAction: String {
        switch health {
        case .clean:
            return "No manual action needed."
        case .dirty:
            return "Review local changes, then commit or discard intentionally."
        case .unpushed:
            return "Push committed work or inspect branch divergence before switching tasks."
        case .missing:
            return "Restore this folder or update config/projects.json."
        case .notGit:
            return "Initialize git only if this folder should be source-controlled."
        case .unknown:
            return "Inspect git configuration before relying on this state."
        }
    }

    public init(
        id: String,
        shortName: String,
        displayName: String,
        path: String,
        group: String,
        health: Health,
        reason: String,
        branch: String = "-",
        dirtyFiles: Int = 0,
        ahead: Int = 0,
        behind: Int = 0,
        remoteURL: String = "",
        enabled: Bool = true,
        dirtyItems: [String] = [],
        lastActivity: Date? = nil,
        missingDependencies: [String] = [],
        warnings: [String] = [],
        healthScore: Int? = nil
    ) {
        self.id = id
        self.shortName = shortName
        self.displayName = displayName
        self.path = path
        self.group = group
        self.health = health
        self.healthScore = healthScore ?? ProjectScoreCalculator.score(
            health: health,
            dirtyFiles: dirtyFiles,
            ahead: ahead,
            behind: behind,
            missingDependencies: missingDependencies,
            warnings: warnings
        )
        self.reason = reason
        self.branch = branch
        self.dirtyFiles = dirtyFiles
        self.ahead = ahead
        self.behind = behind
        self.remoteURL = remoteURL
        self.enabled = enabled
        self.dirtyItems = dirtyItems
        self.lastActivity = lastActivity
        self.missingDependencies = missingDependencies
        self.warnings = warnings
    }
}

public enum ProjectScoreCalculator {
    public static func score(
        health: ProjectStatus.Health,
        dirtyFiles: Int,
        ahead: Int,
        behind: Int,
        missingDependencies: [String],
        warnings: [String]
    ) -> Int {
        let base: Int
        switch health {
        case .clean: base = 100
        case .unpushed: base = 82
        case .dirty: base = 72
        case .unknown: base = 62
        case .notGit: base = 48
        case .missing: base = 0
        }

        let dirtyPenalty = min(dirtyFiles * 2, 24)
        let divergencePenalty = min((ahead + behind) * 3, 18)
        let dependencyPenalty = min(missingDependencies.count * 8, 24)
        let warningPenalty = min(warnings.count * 5, 20)
        return max(0, min(100, base - dirtyPenalty - divergencePenalty - dependencyPenalty - warningPenalty))
    }
}

public struct HardwareSnapshot: Sendable, Equatable {
    public let targetProfile: String
    public let modelIdentifier: String
    public let chip: String
    public let coreSummary: String
    public let memory: String
    public let osVersion: String
    public let uptime: String

    public static let empty = HardwareSnapshot(
        targetProfile: "-",
        modelIdentifier: "-",
        chip: "-",
        coreSummary: "-",
        memory: "-",
        osVersion: "-",
        uptime: "-"
    )

    public init(
        targetProfile: String,
        modelIdentifier: String,
        chip: String,
        coreSummary: String,
        memory: String,
        osVersion: String,
        uptime: String
    ) {
        self.targetProfile = targetProfile
        self.modelIdentifier = modelIdentifier
        self.chip = chip
        self.coreSummary = coreSummary
        self.memory = memory
        self.osVersion = osVersion
        self.uptime = uptime
    }
}

public struct ProcessSnapshot: Identifiable, Sendable, Equatable {
    public let id: String
    public let pid: String
    public let cpu: String
    public let memory: String
    public let command: String

    public init(pid: String, cpu: String, memory: String, command: String) {
        self.id = pid
        self.pid = pid
        self.cpu = cpu
        self.memory = memory
        self.command = command
    }
}

public struct SystemMetricsSnapshot: Sendable, Equatable {
    public let cpuPercent: Double
    public let cpuAvailable: Bool
    public let memoryUsedBytes: UInt64
    public let memoryTotalBytes: UInt64
    public let memoryAvailable: Bool
    public let diskUsedPercent: Double
    public let diskFreeBytes: UInt64
    public let diskAvailable: Bool
    public let networkReceivedBytes: UInt64
    public let networkTransmittedBytes: UInt64
    public let networkAvailable: Bool
    public let uptime: String
    public let uptimeAvailable: Bool

    public var memoryUsedPercent: Double {
        guard memoryAvailable, memoryTotalBytes > 0 else { return 0 }
        return (Double(memoryUsedBytes) / Double(memoryTotalBytes)) * 100
    }

    public var healthScore: Int {
        guard cpuAvailable || memoryAvailable || diskAvailable else { return 0 }
        var score = 100
        if cpuAvailable {
            if cpuPercent >= 90 { score -= 25 } else if cpuPercent >= 75 { score -= 14 }
        }
        if memoryAvailable {
            if memoryUsedPercent >= 90 { score -= 25 } else if memoryUsedPercent >= 80 { score -= 14 }
        }
        if diskAvailable {
            if diskUsedPercent >= 92 { score -= 25 } else if diskUsedPercent >= 85 { score -= 14 }
        }
        return max(0, score)
    }

    public static let empty = SystemMetricsSnapshot(
        cpuPercent: 0,
        cpuAvailable: false,
        memoryUsedBytes: 0,
        memoryTotalBytes: 0,
        memoryAvailable: false,
        diskUsedPercent: 0,
        diskFreeBytes: 0,
        diskAvailable: false,
        networkReceivedBytes: 0,
        networkTransmittedBytes: 0,
        networkAvailable: false,
        uptime: "-",
        uptimeAvailable: false
    )

    public init(
        cpuPercent: Double,
        cpuAvailable: Bool = true,
        memoryUsedBytes: UInt64,
        memoryTotalBytes: UInt64,
        memoryAvailable: Bool = true,
        diskUsedPercent: Double,
        diskFreeBytes: UInt64,
        diskAvailable: Bool = true,
        networkReceivedBytes: UInt64,
        networkTransmittedBytes: UInt64,
        networkAvailable: Bool = true,
        uptime: String,
        uptimeAvailable: Bool = true
    ) {
        self.cpuPercent = cpuPercent
        self.cpuAvailable = cpuAvailable
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.memoryAvailable = memoryAvailable
        self.diskUsedPercent = diskUsedPercent
        self.diskFreeBytes = diskFreeBytes
        self.diskAvailable = diskAvailable
        self.networkReceivedBytes = networkReceivedBytes
        self.networkTransmittedBytes = networkTransmittedBytes
        self.networkAvailable = networkAvailable
        self.uptime = uptime
        self.uptimeAvailable = uptimeAvailable
    }
}

public struct LaunchAgentSnapshot: Identifiable, Sendable, Equatable {
    public let id: String
    public let pid: String
    public let status: String
    public let label: String
    public let state: String
    public let health: Health
    public let reason: String
    public let plistPath: String
    public let stdoutPath: String
    public let stderrPath: String
    public let domain: Domain

    public enum Domain: String, Sendable, CaseIterable {
        case agent = "AGENT"
        case daemon = "DAEMON"
    }

    public enum Health: String, Sendable, CaseIterable {
        case running = "RUNNING"
        case scheduled = "SCHEDULED"
        case failed = "FAILED"
        case stopped = "STOPPED"
        case unknown = "UNKNOWN"
    }

    public init(
        pid: String,
        status: String,
        label: String,
        state: String = "unknown",
        health: Health = .unknown,
        reason: String = "launchctl list only",
        plistPath: String = "",
        stdoutPath: String = "",
        stderrPath: String = "",
        domain: Domain = .agent
    ) {
        self.id = "\(domain.rawValue)-\(label)"
        self.pid = pid
        self.status = status
        self.label = label
        self.state = state
        self.health = health
        self.reason = reason
        self.plistPath = plistPath
        self.stdoutPath = stdoutPath
        self.stderrPath = stderrPath
        self.domain = domain
    }
}

public enum LogCategory: String, Sendable, CaseIterable {
    case foks = "FOKS"
    case project = "PROJECT"
    case system = "SYSTEM"
}

public struct LogEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let source: String
    public let message: String
    public let level: String
    public let timestamp: Date
    public let category: LogCategory
    public let projectID: String?
    public let filePath: String

    public init(
        id: UUID = UUID(),
        source: String,
        message: String,
        level: String = "INFO",
        timestamp: Date = Date(),
        category: LogCategory = .foks,
        projectID: String? = nil,
        filePath: String = ""
    ) {
        self.id = id
        self.source = source
        self.message = message
        self.level = level
        self.timestamp = timestamp
        self.category = category
        self.projectID = projectID
        self.filePath = filePath
    }
}

public struct AutomationSnapshot: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let path: String
    public let purpose: String
    public let scriptType: String
    public let logPath: String
    public let lastRunAt: Date?
    public let modifiedAt: Date?
    public let isRunning: Bool
    public let isExecutable: Bool
    public let runRequirement: String
    public let runExecutable: String
    public let runArguments: [String]

    public var canRun: Bool {
        isExecutable && runRequirement.isEmpty
    }

    public var displayCommand: String {
        ([runExecutable] + runArguments.map(Self.quoteIfNeeded)).joined(separator: " ")
    }

    public init(
        id: String,
        name: String,
        path: String,
        purpose: String,
        scriptType: String,
        logPath: String,
        lastRunAt: Date?,
        modifiedAt: Date?,
        isRunning: Bool,
        isExecutable: Bool,
        runRequirement: String = "",
        runExecutable: String,
        runArguments: [String] = []
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.purpose = purpose
        self.scriptType = scriptType
        self.logPath = logPath
        self.lastRunAt = lastRunAt
        self.modifiedAt = modifiedAt
        self.isRunning = isRunning
        self.isExecutable = isExecutable
        self.runRequirement = runRequirement
        self.runExecutable = runExecutable
        self.runArguments = runArguments
    }

    private static func quoteIfNeeded(_ value: String) -> String {
        guard value.contains(where: { $0.isWhitespace || $0 == "'" }) else { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public struct AppBundleSnapshot: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let path: String
    public let kind: String
    public let bundleIdentifier: String
    public let executablePath: String
    public let modifiedAt: Date?
    public let isRunning: Bool
    public let runExecutable: String
    public let runArguments: [String]

    public var displayCommand: String {
        ([runExecutable] + runArguments.map(Self.quoteIfNeeded)).joined(separator: " ")
    }

    public init(
        id: String,
        name: String,
        path: String,
        kind: String,
        bundleIdentifier: String,
        executablePath: String,
        modifiedAt: Date?,
        isRunning: Bool,
        runExecutable: String = "/usr/bin/open",
        runArguments: [String]
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.kind = kind
        self.bundleIdentifier = bundleIdentifier
        self.executablePath = executablePath
        self.modifiedAt = modifiedAt
        self.isRunning = isRunning
        self.runExecutable = runExecutable
        self.runArguments = runArguments
    }

    private static func quoteIfNeeded(_ value: String) -> String {
        guard value.contains(where: { $0.isWhitespace || $0 == "'" }) else { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public struct Incident: Identifiable, Sendable, Equatable {
    public let id: String
    public let severity: OperationalAction.Severity
    public let scope: String
    public let title: String
    public let evidence: String
    public let timestamp: Date

    public init(
        id: String,
        severity: OperationalAction.Severity,
        scope: String,
        title: String,
        evidence: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.severity = severity
        self.scope = scope
        self.title = title
        self.evidence = evidence
        self.timestamp = timestamp
    }
}

public struct HealthTrendPoint: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let globalHealthScore: Int
    public let systemHealthScore: Int
    public let activeIssueCount: Int

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        globalHealthScore: Int,
        systemHealthScore: Int,
        activeIssueCount: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.globalHealthScore = globalHealthScore
        self.systemHealthScore = systemHealthScore
        self.activeIssueCount = activeIssueCount
    }
}

public struct DashboardSnapshot: Sendable, Equatable {
    public let projects: [ProjectStatus]
    public let hardware: HardwareSnapshot
    public let system: SystemMetricsSnapshot
    public let processes: [ProcessSnapshot]
    public let launchAgents: [LaunchAgentSnapshot]
    public let launchDaemons: [LaunchAgentSnapshot]
    public let automations: [AutomationSnapshot]
    public let appBundles: [AppBundleSnapshot]
    public let logs: [LogEntry]
    public let incidents: [Incident]
    public let refreshedAt: Date

    public var activeIssueCount: Int {
        let projectIssues = projects.filter { $0.health != .clean }.count
        let launchFailures = launchAgents.filter { $0.health == .failed }.count
            + launchDaemons.filter { $0.health == .failed }.count
        let severeLogs = logs.filter { $0.level == "ERROR" || $0.level == "INCIDENT" }.count
        let systemIssues = [
            system.cpuAvailable && system.cpuPercent >= 75,
            system.memoryAvailable && system.memoryUsedPercent >= 80,
            system.diskAvailable && system.diskUsedPercent >= 85
        ].filter { $0 }.count

        return projectIssues + launchFailures + severeLogs + systemIssues
    }

    public var globalHealthScore: Int {
        let hasSystemMetrics = system.cpuAvailable || system.memoryAvailable || system.diskAvailable
        guard !projects.isEmpty || hasSystemMetrics else { return 0 }
        let projectScore = projects.isEmpty ? nil : projects.map(\.healthScore).reduce(0, +) / projects.count
        let systemScore = hasSystemMetrics ? system.healthScore : nil
        let launchPenalty = min(
            (launchAgents + launchDaemons).filter { $0.health == .failed }.count * 12,
            36
        )
        let logPenalty = min(logs.filter { $0.level == "ERROR" || $0.level == "INCIDENT" }.count * 3, 24)
        let score: Int
        switch (projectScore, systemScore) {
        case let (.some(project), .some(system)):
            score = Int((Double(project) * 0.55) + (Double(system) * 0.45))
        case let (.some(project), .none):
            score = project
        case let (.none, .some(system)):
            score = system
        case (.none, .none):
            score = 0
        }
        return max(0, score - launchPenalty - logPenalty)
    }

    public static let empty = DashboardSnapshot(
        projects: [],
        hardware: .empty,
        system: .empty,
        processes: [],
        launchAgents: [],
        launchDaemons: [],
        automations: [],
        appBundles: [],
        logs: [],
        incidents: [],
        refreshedAt: .distantPast
    )

    public init(
        projects: [ProjectStatus],
        hardware: HardwareSnapshot,
        system: SystemMetricsSnapshot = .empty,
        processes: [ProcessSnapshot],
        launchAgents: [LaunchAgentSnapshot],
        launchDaemons: [LaunchAgentSnapshot] = [],
        automations: [AutomationSnapshot] = [],
        appBundles: [AppBundleSnapshot] = [],
        logs: [LogEntry],
        incidents: [Incident] = [],
        refreshedAt: Date = Date()
    ) {
        self.projects = projects
        self.hardware = hardware
        self.system = system
        self.processes = processes
        self.launchAgents = launchAgents
        self.launchDaemons = launchDaemons
        self.automations = automations
        self.appBundles = appBundles
        self.logs = logs
        self.incidents = incidents
        self.refreshedAt = refreshedAt
    }
}

public enum AIAnalysisProvider: String, CaseIterable, Sendable, Equatable {
    case local
    case cloud

    public var displayName: String {
        switch self {
        case .local: "Local AI"
        case .cloud: "Cloud AI"
        }
    }
}

public struct LocalAIAnalysis: Sendable, Equatable {
    public let provider: String
    public let model: String
    public let status: Status
    public let text: String
    public let generatedAt: Date

    public enum Status: String, Sendable, Equatable {
        case idle = "IDLE"
        case running = "RUNNING"
        case ready = "READY"
        case failed = "FAILED"
    }

    public static let idle = LocalAIAnalysis(
        provider: "Ollama",
        model: "llama3.2:latest",
        status: .idle,
        text: "No AI analysis yet.",
        generatedAt: .distantPast
    )

    public init(provider: String, model: String, status: Status, text: String, generatedAt: Date = Date()) {
        self.provider = provider
        self.model = model
        self.status = status
        self.text = text
        self.generatedAt = generatedAt
    }
}

public struct OperationalAction: Identifiable, Sendable, Equatable {
    public let id: String
    public let severity: Severity
    public let title: String
    public let scope: String
    public let evidence: String
    public let nextStep: String
    public let manualCommands: [ManualCommand]
    public let check: ReadOnlyCheck?

    public var command: String {
        manualCommands.map(\.displayCommand).joined(separator: "\n")
    }

    public enum Severity: String, Sendable, Equatable {
        case critical = "CRITICAL"
        case warning = "WARNING"
        case info = "INFO"

        var priority: Int {
            switch self {
            case .critical: return 100
            case .warning: return 60
            case .info: return 20
            }
        }
    }

    public init(
        id: String,
        severity: Severity,
        title: String,
        scope: String,
        evidence: String,
        nextStep: String,
        manualCommands: [ManualCommand],
        check: ReadOnlyCheck? = nil
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.scope = scope
        self.evidence = evidence
        self.nextStep = nextStep
        self.manualCommands = manualCommands
        self.check = check
    }
}

public struct ManualCommand: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let executable: String
    public let arguments: [String]
    public let intent: String

    public var displayCommand: String {
        ([executable] + arguments.map(Self.quoteIfNeeded)).joined(separator: " ")
    }

    public init(
        id: String,
        title: String,
        executable: String,
        arguments: [String],
        intent: String
    ) {
        self.id = id
        self.title = title
        self.executable = executable
        self.arguments = arguments
        self.intent = intent
    }

    private static func quoteIfNeeded(_ value: String) -> String {
        guard value.contains(where: { $0.isWhitespace || $0 == "'" }) else { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public struct ReadOnlyCheck: Sendable, Equatable {
    public let title: String
    public let executable: String
    public let arguments: [String]
    public let timeoutSeconds: Double

    public var displayCommand: String {
        ([executable] + arguments.map(Self.quoteIfNeeded)).joined(separator: " ")
    }

    public init(title: String, executable: String, arguments: [String], timeoutSeconds: Double = 6) {
        self.title = title
        self.executable = executable
        self.arguments = arguments
        self.timeoutSeconds = timeoutSeconds
    }

    private static func quoteIfNeeded(_ value: String) -> String {
        guard value.contains(where: { $0.isWhitespace || $0 == "'" }) else { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public struct ReadOnlyCheckResult: Sendable, Equatable {
    public let actionID: String
    public let title: String
    public let command: String
    public let exitCode: Int32
    public let output: String
    public let error: String
    public let timedOut: Bool
    public let ranAt: Date

    public var combinedOutput: String {
        let text = [output, error].filter { !$0.isEmpty }.joined(separator: "\n")
        return text.isEmpty ? "(no output)" : text
    }

    public init(
        actionID: String,
        title: String,
        command: String,
        exitCode: Int32,
        output: String,
        error: String,
        timedOut: Bool,
        ranAt: Date = Date()
    ) {
        self.actionID = actionID
        self.title = title
        self.command = command
        self.exitCode = exitCode
        self.output = output
        self.error = error
        self.timedOut = timedOut
        self.ranAt = ranAt
    }
}

public struct AutomationRunResult: Sendable, Equatable {
    public let automationID: String
    public let name: String
    public let command: String
    public let exitCode: Int32
    public let output: String
    public let error: String
    public let timedOut: Bool
    public let ranAt: Date

    public var combinedOutput: String {
        let text = [output, error].filter { !$0.isEmpty }.joined(separator: "\n")
        return text.isEmpty ? "(no output)" : text
    }

    public init(
        automationID: String,
        name: String,
        command: String,
        exitCode: Int32,
        output: String,
        error: String,
        timedOut: Bool,
        ranAt: Date = Date()
    ) {
        self.automationID = automationID
        self.name = name
        self.command = command
        self.exitCode = exitCode
        self.output = output
        self.error = error
        self.timedOut = timedOut
        self.ranAt = ranAt
    }
}
