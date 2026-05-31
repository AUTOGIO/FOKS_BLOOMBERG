import Foundation

public struct ProjectStatus: Identifiable, Sendable, Equatable {
    public let id: String
    public let shortName: String
    public let name: String
    public let path: String
    public let gitSummary: String
    public let health: Health

    public enum Health: String, Sendable {
        case ok = "OK"
        case warning = "WARN"
        case missing = "MISSING"
    }

    public init(id: String, shortName: String, name: String, path: String, gitSummary: String, health: Health) {
        self.id = id
        self.shortName = shortName
        self.name = name
        self.path = path
        self.gitSummary = gitSummary
        self.health = health
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
