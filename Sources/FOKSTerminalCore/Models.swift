import Foundation

public struct ProjectStatus: Identifiable, Sendable, Equatable {
    public let id: String
    public let shortName: String
    public let name: String
    public let path: String
    public let health: Health
    public let reason: String
    public let branch: String
    public let dirtyFiles: Int
    public let ahead: Int
    public let behind: Int
    public let remoteURL: String

    public enum Health: String, Sendable {
        case ok = "CLEAN"
        case dirty = "DIRTY"
        case unpushed = "UNPUSHED"
        case missing = "MISSING"
        case notGit = "NOT GIT"
        case unknown = "UNKNOWN"
    }

    public var gitSummary: String {
        var parts = ["branch \(branch)", "\(dirtyFiles) dirty"]
        if ahead > 0 || behind > 0 {
            parts.append("ahead \(ahead) / behind \(behind)")
        }
        if remoteURL.isEmpty {
            parts.append("no remote")
        }
        return parts.joined(separator: " · ")
    }

    public var recommendedAction: String {
        switch health {
        case .ok:
            return "No manual action needed."
        case .dirty:
            return "Review local changes, then commit or discard intentionally."
        case .unpushed:
            return "Push committed work or inspect branch divergence before switching tasks."
        case .missing:
            return "Restore the expected folder or update the project path list."
        case .notGit:
            return "Initialize git only if this folder should be source-controlled."
        case .unknown:
            return "Inspect git configuration before relying on this project state."
        }
    }

    public init(
        id: String,
        shortName: String,
        name: String,
        path: String,
        health: Health,
        reason: String,
        branch: String = "-",
        dirtyFiles: Int = 0,
        ahead: Int = 0,
        behind: Int = 0,
        remoteURL: String = ""
    ) {
        self.id = id
        self.shortName = shortName
        self.name = name
        self.path = path
        self.health = health
        self.reason = reason
        self.branch = branch
        self.dirtyFiles = dirtyFiles
        self.ahead = ahead
        self.behind = behind
        self.remoteURL = remoteURL
    }
}

public struct ProcessSnapshot: Identifiable, Sendable, Equatable {
    public let id: String
    public let pid: String
    public let command: String
    public let cpu: String
    public let memory: String

    public init(pid: String, command: String, cpu: String, memory: String) {
        self.id = pid
        self.pid = pid
        self.command = command
        self.cpu = cpu
        self.memory = memory
    }
}

public struct LaunchAgentSnapshot: Identifiable, Sendable, Equatable {
    public let id: String
    public let pid: String
    public let status: String
    public let label: String

    public init(pid: String, status: String, label: String) {
        self.id = label
        self.pid = pid
        self.status = status
        self.label = label
    }
}

public struct LogEntry: Identifiable, Sendable, Equatable {
    public let id = UUID()
    public let source: String
    public let message: String
    public let level: String
    public let timestamp: Date

    public init(source: String, message: String, level: String = "INFO", timestamp: Date = Date()) {
        self.source = source
        self.message = message
        self.level = level
        self.timestamp = timestamp
    }
}
