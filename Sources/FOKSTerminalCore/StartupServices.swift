import Foundation
import ShellRunner

public enum StartupServiceKind: String, CaseIterable, Codable, Sendable, Hashable {
    case localAI
    case cloudflareTunnel

    public var displayName: String {
        switch self {
        case .localAI: "Local AI"
        case .cloudflareTunnel: "Cloudflare Tunnel"
        }
    }
}

public enum StartupServiceState: String, Codable, Sendable, Equatable {
    case waiting = "WAITING"
    case disabled = "DISABLED"
    case running = "RUNNING"
    case failed = "FAILED"
}

public struct StartupServiceSnapshot: Identifiable, Sendable, Equatable {
    public var id: String { kind.rawValue }
    public let kind: StartupServiceKind
    public let state: StartupServiceState
    public let detail: String
    public let command: String
    public let updatedAt: Date

    public init(
        kind: StartupServiceKind,
        state: StartupServiceState,
        detail: String,
        command: String = "",
        updatedAt: Date = Date()
    ) {
        self.kind = kind
        self.state = state
        self.detail = detail
        self.command = command
        self.updatedAt = updatedAt
    }
}

public struct StartupServicesSnapshot: Sendable, Equatable {
    public let services: [StartupServiceSnapshot]
    public let startedAt: Date

    public static let idle = StartupServicesSnapshot(
        services: StartupServiceKind.allCases.map {
            StartupServiceSnapshot(kind: $0, state: .waiting, detail: "Startup service has not run yet.")
        },
        startedAt: .distantPast
    )

    public var status: String {
        if services.contains(where: { $0.state == .failed }) { return "FAILED" }
        if services.contains(where: { $0.state == .waiting }) { return "WAITING" }
        if services.allSatisfy({ $0.state == .disabled }) { return "DISABLED" }
        if services.contains(where: { $0.state == .running }) { return "RUNNING" }
        return "WAITING"
    }

    public var summary: String {
        services.map { "\($0.kind.displayName): \($0.state.rawValue)" }.joined(separator: " | ")
    }

    public init(services: [StartupServiceSnapshot], startedAt: Date = Date()) {
        self.services = services
        self.startedAt = startedAt
    }
}

public struct LocalAIStartupConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var binaryPath: String
    public var healthURL: String
    public var startupTimeoutSeconds: Double

    public init(
        enabled: Bool = true,
        binaryPath: String = "/opt/homebrew/bin/ollama",
        healthURL: String = "http://127.0.0.1:11434/api/tags",
        startupTimeoutSeconds: Double = 8
    ) {
        self.enabled = enabled
        self.binaryPath = binaryPath
        self.healthURL = healthURL
        self.startupTimeoutSeconds = startupTimeoutSeconds
    }

    public var launchArguments: [String] {
        ["serve"]
    }
}

public struct CloudflareTunnelStartupConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var binaryPath: String
    public var tunnelName: String
    public var configPath: String

    public init(
        enabled: Bool = false,
        binaryPath: String = "/opt/homebrew/bin/cloudflared",
        tunnelName: String = "",
        configPath: String = ""
    ) {
        self.enabled = enabled
        self.binaryPath = binaryPath
        self.tunnelName = tunnelName
        self.configPath = configPath
    }

    public var launchArguments: [String] {
        var arguments = ["tunnel"]
        if !configPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append(contentsOf: ["--config", configPath])
        }
        arguments.append(contentsOf: ["--no-autoupdate", "run", tunnelName])
        return arguments
    }
}

public struct StartupServicesConfig: Codable, Sendable, Equatable {
    public static let defaultConfigPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Mobile Documents/com~apple~CloudDocs/Documents/GitHub/FOKS_BLOOMBERG/config/startup_services.json"
    }()

    public var startOnAppLaunch: Bool
    public var localAI: LocalAIStartupConfig
    public var cloudflareTunnel: CloudflareTunnelStartupConfig

    public init(
        startOnAppLaunch: Bool = true,
        localAI: LocalAIStartupConfig = LocalAIStartupConfig(),
        cloudflareTunnel: CloudflareTunnelStartupConfig = CloudflareTunnelStartupConfig()
    ) {
        self.startOnAppLaunch = startOnAppLaunch
        self.localAI = localAI
        self.cloudflareTunnel = cloudflareTunnel
    }

    public static func load(
        from url: URL = URL(fileURLWithPath: defaultConfigPath),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> StartupServicesConfig {
        var config: StartupServicesConfig
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            config = try JSONDecoder().decode(StartupServicesConfig.self, from: data)
        } else {
            config = StartupServicesConfig()
        }

        config.applyEnvironment(environment)
        return config
    }

    private mutating func applyEnvironment(_ environment: [String: String]) {
        if let value = Self.bool(environment["FOKS_STARTUP_SERVICES_ENABLED"]) {
            startOnAppLaunch = value
        }
        if let value = Self.bool(environment["FOKS_LOCAL_AI_ENABLED"]) {
            localAI.enabled = value
        }
        if let value = Self.cleaned(environment["FOKS_OLLAMA_BIN"]) {
            localAI.binaryPath = value
        }
        if let value = Self.cleaned(environment["FOKS_OLLAMA_HEALTH_URL"]) {
            localAI.healthURL = value
        }
        if let value = Self.bool(environment["FOKS_CLOUDFLARE_TUNNEL_ENABLED"]) {
            cloudflareTunnel.enabled = value
        }
        if let value = Self.cleaned(environment["FOKS_CLOUDFLARED_BIN"]) {
            cloudflareTunnel.binaryPath = value
        }
        if let value = Self.cleaned(environment["FOKS_CLOUDFLARE_TUNNEL_NAME"]) {
            cloudflareTunnel.tunnelName = value
        }
        if let value = Self.cleaned(environment["FOKS_CLOUDFLARE_CONFIG"]) {
            cloudflareTunnel.configPath = value
        }
    }

    private static func bool(_ value: String?) -> Bool? {
        switch cleaned(value)?.lowercased() {
        case "1", "true", "yes", "on": true
        case "0", "false", "no", "off": false
        default: nil
        }
    }

    private static func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

public actor StartupServiceManager {
    private let runner: CommandRunner
    private var launchedProcesses: [StartupServiceKind: Process] = [:]

    private enum LaunchResult {
        case success
        case failure(String)
    }

    public init(runner: CommandRunner = CommandRunner()) {
        self.runner = runner
    }

    public func startConfiguredServices(
        configURL: URL = URL(fileURLWithPath: StartupServicesConfig.defaultConfigPath)
    ) async -> StartupServicesSnapshot {
        let config: StartupServicesConfig
        do {
            config = try StartupServicesConfig.load(from: configURL)
        } catch {
            return StartupServicesSnapshot(services: [
                StartupServiceSnapshot(kind: .localAI, state: .failed, detail: "Startup config failed: \(error.localizedDescription)"),
                StartupServiceSnapshot(kind: .cloudflareTunnel, state: .failed, detail: "Startup config failed: \(error.localizedDescription)")
            ])
        }

        guard config.startOnAppLaunch else {
            return StartupServicesSnapshot(services: [
                StartupServiceSnapshot(kind: .localAI, state: .disabled, detail: "Startup services are disabled in config."),
                StartupServiceSnapshot(kind: .cloudflareTunnel, state: .disabled, detail: "Startup services are disabled in config.")
            ])
        }

        let localAI = await ensureLocalAI(config.localAI)
        let tunnel = await ensureCloudflareTunnel(config.cloudflareTunnel)
        return StartupServicesSnapshot(services: [localAI, tunnel])
    }

    private func ensureLocalAI(_ config: LocalAIStartupConfig) async -> StartupServiceSnapshot {
        guard config.enabled else {
            return StartupServiceSnapshot(kind: .localAI, state: .disabled, detail: "Local AI startup disabled.")
        }
        guard let healthURL = URL(string: config.healthURL) else {
            return StartupServiceSnapshot(kind: .localAI, state: .failed, detail: "Invalid Ollama health URL: \(config.healthURL)")
        }
        if await httpReady(healthURL) {
            return StartupServiceSnapshot(
                kind: .localAI,
                state: .running,
                detail: "Ollama already reachable at \(config.healthURL).",
                command: displayCommand(config.binaryPath, config.launchArguments)
            )
        }
        guard let binary = resolveBinary(config.binaryPath, candidates: ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"]) else {
            return StartupServiceSnapshot(kind: .localAI, state: .failed, detail: "Ollama binary not found.", command: displayCommand(config.binaryPath, config.launchArguments))
        }

        switch launchDetached(kind: .localAI, executable: binary, arguments: config.launchArguments) {
        case .success:
            let ready = await waitForHTTPReady(healthURL, timeout: config.startupTimeoutSeconds)
            return StartupServiceSnapshot(
                kind: .localAI,
                state: ready ? .running : .failed,
                detail: ready ? "Started Ollama at \(config.healthURL)." : "Started Ollama, but \(config.healthURL) did not become ready.",
                command: displayCommand(binary, config.launchArguments)
            )
        case .failure(let detail):
            return StartupServiceSnapshot(kind: .localAI, state: .failed, detail: detail, command: displayCommand(binary, config.launchArguments))
        }
    }

    private func ensureCloudflareTunnel(_ config: CloudflareTunnelStartupConfig) async -> StartupServiceSnapshot {
        guard config.enabled else {
            return StartupServiceSnapshot(kind: .cloudflareTunnel, state: .disabled, detail: "Cloudflare Tunnel startup disabled.")
        }
        let tunnelName = config.tunnelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tunnelName.isEmpty else {
            return StartupServiceSnapshot(kind: .cloudflareTunnel, state: .failed, detail: "Cloudflare Tunnel name is required.")
        }
        guard let binary = resolveBinary(config.binaryPath, candidates: ["/opt/homebrew/bin/cloudflared", "/usr/local/bin/cloudflared"]) else {
            return StartupServiceSnapshot(kind: .cloudflareTunnel, state: .failed, detail: "cloudflared binary not found.", command: displayCommand(config.binaryPath, config.launchArguments))
        }
        if await isCloudflareTunnelRunning(named: tunnelName) {
            return StartupServiceSnapshot(
                kind: .cloudflareTunnel,
                state: .running,
                detail: "Cloudflare Tunnel already running: \(tunnelName).",
                command: displayCommand(binary, config.launchArguments)
            )
        }

        switch launchDetached(kind: .cloudflareTunnel, executable: binary, arguments: config.launchArguments) {
        case .success:
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let launchedProcessIsRunning = launchedProcesses[.cloudflareTunnel]?.isRunning == true
            let matchedProcessIsRunning = await isCloudflareTunnelRunning(named: tunnelName)
            let isRunning = launchedProcessIsRunning || matchedProcessIsRunning
            return StartupServiceSnapshot(
                kind: .cloudflareTunnel,
                state: isRunning ? .running : .failed,
                detail: isRunning ? "Started Cloudflare Tunnel: \(tunnelName)." : "cloudflared exited before the tunnel stayed running: \(tunnelName).",
                command: displayCommand(binary, config.launchArguments)
            )
        case .failure(let detail):
            return StartupServiceSnapshot(kind: .cloudflareTunnel, state: .failed, detail: detail, command: displayCommand(binary, config.launchArguments))
        }
    }

    private func isCloudflareTunnelRunning(named tunnelName: String) async -> Bool {
        let result = await runner.run("/usr/bin/pgrep", ["-fl", "cloudflared"], timeout: 2)
        guard result.exitCode == 0 else { return false }
        return result.output.split(separator: "\n").contains { line in
            line.localizedCaseInsensitiveContains("cloudflared")
                && line.localizedCaseInsensitiveContains("tunnel")
                && line.localizedCaseInsensitiveContains("run")
                && line.localizedCaseInsensitiveContains(tunnelName)
        }
    }

    private func waitForHTTPReady(_ url: URL, timeout: Double) async -> Bool {
        let attempts = max(1, Int(timeout / 0.5))
        for _ in 0..<attempts {
            if await httpReady(url) { return true }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    private func httpReady(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    private func launchDetached(kind: StartupServiceKind, executable: String, arguments: [String]) -> LaunchResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")

        do {
            try process.run()
            launchedProcesses[kind] = process
            return .success
        } catch {
            return .failure("Launch failed for \(kind.displayName): \(error.localizedDescription)")
        }
    }

    private func resolveBinary(_ configuredPath: String, candidates: [String]) -> String? {
        let paths = ([configuredPath] + candidates)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func displayCommand(_ executable: String, _ arguments: [String]) -> String {
        ([executable] + arguments).map(quote).joined(separator: " ")
    }

    private func quote(_ value: String) -> String {
        if value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil && !value.contains("'") {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
