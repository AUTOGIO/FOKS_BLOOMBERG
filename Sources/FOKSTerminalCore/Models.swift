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

public struct ProjectStatus: Identifiable, Sendable, Equatable {
    public let id: String
    public let shortName: String
    public let displayName: String
    public let path: String
    public let group: String
    public let health: Health
    public let reason: String
    public let branch: String
    public let dirtyFiles: Int
    public let ahead: Int
    public let behind: Int
    public let remoteURL: String
    public let enabled: Bool
    public let dirtyItems: [String]

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
        dirtyItems: [String] = []
    ) {
        self.id = id
        self.shortName = shortName
        self.displayName = displayName
        self.path = path
        self.group = group
        self.health = health
        self.reason = reason
        self.branch = branch
        self.dirtyFiles = dirtyFiles
        self.ahead = ahead
        self.behind = behind
        self.remoteURL = remoteURL
        self.enabled = enabled
        self.dirtyItems = dirtyItems
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
        targetProfile: "MacBook Air | Apple M4 | 8 cores | 16 GB | macOS 26.6",
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

public struct LaunchAgentSnapshot: Identifiable, Sendable, Equatable {
    public let id: String
    public let pid: String
    public let status: String
    public let label: String
    public let state: String
    public let health: Health
    public let reason: String
    public let plistPath: String

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
        plistPath: String = ""
    ) {
        self.id = label
        self.pid = pid
        self.status = status
        self.label = label
        self.state = state
        self.health = health
        self.reason = reason
        self.plistPath = plistPath
    }
}

public struct LogEntry: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let source: String
    public let message: String
    public let level: String
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        source: String,
        message: String,
        level: String = "INFO",
        timestamp: Date = Date()
    ) {
        self.id = id
        self.source = source
        self.message = message
        self.level = level
        self.timestamp = timestamp
    }
}

public struct DashboardSnapshot: Sendable, Equatable {
    public let projects: [ProjectStatus]
    public let hardware: HardwareSnapshot
    public let processes: [ProcessSnapshot]
    public let launchAgents: [LaunchAgentSnapshot]
    public let logs: [LogEntry]
    public let refreshedAt: Date

    public static let empty = DashboardSnapshot(
        projects: [],
        hardware: .empty,
        processes: [],
        launchAgents: [],
        logs: [],
        refreshedAt: .distantPast
    )

    public init(
        projects: [ProjectStatus],
        hardware: HardwareSnapshot,
        processes: [ProcessSnapshot],
        launchAgents: [LaunchAgentSnapshot],
        logs: [LogEntry],
        refreshedAt: Date = Date()
    ) {
        self.projects = projects
        self.hardware = hardware
        self.processes = processes
        self.launchAgents = launchAgents
        self.logs = logs
        self.refreshedAt = refreshedAt
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
