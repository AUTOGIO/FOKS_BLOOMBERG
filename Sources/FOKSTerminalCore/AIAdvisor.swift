import Foundation

public struct DiagnosticBundleBuilder: Sendable {
    public init() {}

    public func build(snapshot: DashboardSnapshot, selectedProjectID: ProjectStatus.ID?, provider: AIAnalysisProvider = .local) -> String {
        let selected = snapshot.projects.first { $0.id == selectedProjectID } ?? snapshot.projects.first
        let dirtyProjects = snapshot.projects.filter { $0.health == .dirty }
        let failedAgents = snapshot.launchAgents.filter { $0.health == .failed }
        let stoppedAgents = snapshot.launchAgents.filter { $0.health == .stopped }
        let actions = ActionCenterBuilder().build(snapshot: snapshot)
        let heading: String
        let rules: String
        switch provider {
        case .local:
            heading = "FOKS TERMINAL LOCAL DIAGNOSTIC BUNDLE"
            rules = "Rules: local-only analysis; do not suggest cloud services; do not suggest destructive git reset; do not claim you can execute fixes; provide commands only as manual review steps."
        case .cloud:
            heading = "FOKS TERMINAL CLOUD DIAGNOSTIC BUNDLE"
            rules = "Rules: cloud-assisted advisory analysis was explicitly selected; do not request credentials; do not suggest destructive git reset; do not claim you can execute fixes; provide commands only as manual review steps."
        }

        var lines: [String] = [
            heading,
            rules,
            "",
            "Global health score: \(snapshot.globalHealthScore)/100",
            "System health score: \(snapshot.system.healthScore)/100",
            "System resources: CPU \(metric(snapshot.system.cpuPercent, available: snapshot.system.cpuAvailable)); memory \(metric(snapshot.system.memoryUsedPercent, available: snapshot.system.memoryAvailable)); disk \(metric(snapshot.system.diskUsedPercent, available: snapshot.system.diskAvailable)); uptime \(snapshot.system.uptimeAvailable ? snapshot.system.uptime : "unavailable")",
            "",
            "Portfolio summary:",
            "- projects: \(snapshot.projects.count)",
            "- clean: \(snapshot.projects.filter { $0.health == .clean }.count)",
            "- dirty: \(dirtyProjects.count)",
            "- unpushed: \(snapshot.projects.filter { $0.health == .unpushed }.count)",
            "- missing: \(snapshot.projects.filter { $0.health == .missing }.count)",
            "",
            "Action Center:",
        ]

        for action in actions.prefix(6) {
            lines.append("- \(action.severity.rawValue) \(action.scope): \(action.title)")
            lines.append("  evidence: \(action.evidence)")
            lines.append("  next: \(action.nextStep)")
        }

        lines.append("")
        lines.append("Incidents:")
        if snapshot.incidents.isEmpty {
            lines.append("- none")
        } else {
            for incident in snapshot.incidents.prefix(8) {
                lines.append("- \(incident.severity.rawValue) \(incident.scope): \(incident.title); \(incident.evidence.prefixText(160))")
            }
        }

        lines.append(contentsOf: [
            "",
            "Selected project:"
        ])

        if let selected {
            lines.append(contentsOf: projectLines(selected, dirtyLimit: 12))
        } else {
            lines.append("- none")
        }

        lines.append("")
        lines.append("Dirty projects:")
        if dirtyProjects.isEmpty {
            lines.append("- none")
        } else {
            for project in dirtyProjects {
                lines.append(contentsOf: projectLines(project, dirtyLimit: 8))
            }
        }

        lines.append("")
        lines.append("LaunchAgent failures:")
        if failedAgents.isEmpty {
            lines.append("- none")
        } else {
            for agent in failedAgents {
                lines.append("- \(agent.label): \(agent.reason); state=\(agent.state); plist=\(agent.plistPath.nonEmpty(or: "unknown"))")
            }
        }

        lines.append("")
        lines.append("Stopped/scheduled LaunchAgents:")
        let scheduledOrStopped = stoppedAgents + snapshot.launchAgents.filter { $0.health == .scheduled }
        if scheduledOrStopped.isEmpty {
            lines.append("- none")
        } else {
            for agent in scheduledOrStopped.prefix(10) {
                lines.append("- \(agent.label): \(agent.health.rawValue); \(agent.reason)")
            }
        }

        lines.append("")
        lines.append("Recent actionable logs:")
        let actionableLogs = snapshot.logs.filter { $0.level == "ERROR" || $0.level == "WARN" || $0.level == "INCIDENT" }
        if actionableLogs.isEmpty {
            lines.append("- none")
        } else {
            for log in actionableLogs.prefix(8) {
                lines.append("- \(log.level) \(log.category.rawValue)/\(log.source): \(log.message.prefixText(180))")
            }
        }

        lines.append("")
        lines.append("Process watchlist:")
        if snapshot.processes.isEmpty {
            lines.append("- none")
        } else {
            for process in snapshot.processes.prefix(12) {
                lines.append("- pid \(process.pid): cpu=\(process.cpu), mem=\(process.memory), cmd=\(process.command.prefixText(120))")
            }
        }

        lines.append("")
        lines.append("Expected response:")
        lines.append("Start immediately with the exact heading NOW.")
        lines.append("Use only these headings: NOW, NEXT, LATER.")
        lines.append("Do not write an intro like 'Based on the provided information'.")
        lines.append("For each issue, include: risk, evidence, likely root cause, and minimal safe manual commands.")
        lines.append("Commands must use explicit binaries and arguments. Do not suggest destructive git reset, deletion, kill, unload, or writes.")
        lines.append("Keep it under 350 words.")

        return lines.joined(separator: "\n")
    }

    private func projectLines(_ project: ProjectStatus, dirtyLimit: Int) -> [String] {
        var lines = [
            "- \(project.shortName) \(project.displayName)",
            "  path: \(project.path)",
            "  health: \(project.health.rawValue); score: \(project.healthScore); reason: \(project.reason)",
            "  branch: \(project.branch); dirty: \(project.dirtyFiles); ahead: \(project.ahead); behind: \(project.behind)"
        ]
        if let lastActivity = project.lastActivity {
            lines.append("  last activity: \(lastActivity.formatted(date: .abbreviated, time: .shortened))")
        }
        if !project.missingDependencies.isEmpty {
            lines.append("  missing dependencies: \(project.missingDependencies.joined(separator: ", "))")
        }
        if !project.warnings.isEmpty {
            lines.append("  warnings: \(project.warnings.joined(separator: ", "))")
        }
        if !project.dirtyItems.isEmpty {
            lines.append("  dirty items:")
            for item in project.dirtyItems.prefix(dirtyLimit) {
                lines.append("  - \(item)")
            }
            if project.dirtyFiles > dirtyLimit {
                lines.append("  - +\(project.dirtyFiles - dirtyLimit) more")
            }
        }
        return lines
    }

    private func metric(_ value: Double, available: Bool) -> String {
        available ? String(format: "%.0f%%", value) : "unavailable"
    }
}

public struct LocalAIAdvisor: Sendable {
    private let builder: DiagnosticBundleBuilder
    private let endpoint: URL

    public init(
        builder: DiagnosticBundleBuilder = DiagnosticBundleBuilder(),
        endpoint: URL = URL(string: "http://127.0.0.1:11434/api/generate")!
    ) {
        self.builder = builder
        self.endpoint = endpoint
    }

    public func analyze(
        snapshot: DashboardSnapshot,
        selectedProjectID: ProjectStatus.ID?,
        model: String = "llama3.2:latest"
    ) async -> LocalAIAnalysis {
        let prompt = builder.build(snapshot: snapshot, selectedProjectID: selectedProjectID, provider: .local)
        let body = OllamaGenerateRequest(
            model: model,
            prompt: prompt,
            stream: false,
            options: OllamaOptions(temperature: 0.2, numPredict: 700)
        )

        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 120
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return LocalAIAnalysis(
                    provider: "Ollama",
                    model: model,
                    status: .failed,
                    text: "Ollama returned HTTP \(http.statusCode). Confirm the local service is running on 127.0.0.1:11434."
                )
            }

            let decoded = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
            if let error = decoded.error, !error.isEmpty {
                return LocalAIAnalysis(provider: "Ollama", model: model, status: .failed, text: error)
            }
            let text = decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                return LocalAIAnalysis(provider: "Ollama", model: model, status: .failed, text: "Ollama returned an empty response.")
            }
            return LocalAIAnalysis(
                provider: "Ollama",
                model: model,
                status: .ready,
                text: text
            )
        } catch {
            return LocalAIAnalysis(
                provider: "Ollama",
                model: model,
                status: .failed,
                text: "Local Ollama request failed: \(error.localizedDescription)"
            )
        }
    }
}

public enum CloudAIConfigurationError: Error, Sendable, Equatable, LocalizedError {
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        }
    }
}

public struct CloudAIConfiguration: Sendable, Equatable {
    public let endpoint: URL
    public let apiKey: String
    public let model: String

    public init(endpoint: URL, apiKey: String, model: String) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.model = model
    }

    public static func fromProcessEnvironment() -> Result<CloudAIConfiguration, CloudAIConfigurationError> {
        fromEnvironment(ProcessInfo.processInfo.environment)
    }

    public static func fromEnvironment(_ environment: [String: String]) -> Result<CloudAIConfiguration, CloudAIConfigurationError> {
        let endpointValue = cleaned(environment["FOKS_CLOUD_AI_ENDPOINT"])
        let apiKey = cleaned(environment["FOKS_CLOUD_AI_API_KEY"])
        let model = cleaned(environment["FOKS_CLOUD_AI_MODEL"])
        var missing: [String] = []
        if endpointValue == nil { missing.append("FOKS_CLOUD_AI_ENDPOINT") }
        if apiKey == nil { missing.append("FOKS_CLOUD_AI_API_KEY") }
        if model == nil { missing.append("FOKS_CLOUD_AI_MODEL") }
        guard missing.isEmpty else {
            return .failure(.invalid("Cloud AI requires \(missing.joined(separator: ", ")) in the app environment. No request was sent."))
        }

        guard let endpointString = endpointValue, let endpoint = URL(string: endpointString), endpoint.scheme == "https", endpoint.host != nil else {
            return .failure(.invalid("FOKS_CLOUD_AI_ENDPOINT must be a valid HTTPS URL. No request was sent."))
        }

        return .success(
            CloudAIConfiguration(
                endpoint: endpoint,
                apiKey: apiKey ?? "",
                model: model ?? ""
            )
        )
    }

    private static func cleaned(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct CloudAIAdvisor: Sendable {
    private let builder: DiagnosticBundleBuilder

    public init(builder: DiagnosticBundleBuilder = DiagnosticBundleBuilder()) {
        self.builder = builder
    }

    public func analyze(
        snapshot: DashboardSnapshot,
        selectedProjectID: ProjectStatus.ID?
    ) async -> LocalAIAnalysis {
        switch CloudAIConfiguration.fromProcessEnvironment() {
        case .success(let configuration):
            return await analyze(snapshot: snapshot, selectedProjectID: selectedProjectID, configuration: configuration)
        case .failure(let error):
            return LocalAIAnalysis(provider: "Cloud AI", model: "unconfigured", status: .failed, text: error.localizedDescription)
        }
    }

    public func analyze(
        snapshot: DashboardSnapshot,
        selectedProjectID: ProjectStatus.ID?,
        configuration: CloudAIConfiguration
    ) async -> LocalAIAnalysis {
        let prompt = builder.build(snapshot: snapshot, selectedProjectID: selectedProjectID, provider: .cloud)
        let body = CloudAIChatRequest(
            model: configuration.model,
            messages: [
                CloudAIMessage(
                    role: "system",
                    content: "You are FOKS Terminal's advisory cloud AI reviewer. Analyze only the supplied diagnostic bundle, keep advice non-destructive, and never claim that you executed fixes."
                ),
                CloudAIMessage(role: "user", content: prompt)
            ],
            temperature: 0.2,
            maxTokens: 700
        )

        do {
            var request = URLRequest(url: configuration.endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 120
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let detail = String(data: data, encoding: .utf8)?.prefixText(300).nonEmpty(or: "empty response body") ?? "empty response body"
                return LocalAIAnalysis(
                    provider: "Cloud AI",
                    model: configuration.model,
                    status: .failed,
                    text: "Cloud AI returned HTTP \(http.statusCode): \(detail)"
                )
            }

            let decoded = try JSONDecoder().decode(CloudAIChatResponse.self, from: data)
            if let message = decoded.error?.message, !message.isEmpty {
                return LocalAIAnalysis(provider: "Cloud AI", model: configuration.model, status: .failed, text: message)
            }
            let text = decoded.choices?
                .compactMap { choice in
                    choice.message?.content ?? choice.text
                }
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else {
                return LocalAIAnalysis(provider: "Cloud AI", model: configuration.model, status: .failed, text: "Cloud AI returned an empty response.")
            }
            return LocalAIAnalysis(provider: "Cloud AI", model: configuration.model, status: .ready, text: text)
        } catch {
            return LocalAIAnalysis(
                provider: "Cloud AI",
                model: configuration.model,
                status: .failed,
                text: "Cloud AI request failed: \(error.localizedDescription)"
            )
        }
    }
}

private struct OllamaGenerateRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
    let options: OllamaOptions
}

private struct OllamaOptions: Encodable {
    let temperature: Double
    let numPredict: Int

    enum CodingKeys: String, CodingKey {
        case temperature
        case numPredict = "num_predict"
    }
}

private struct OllamaGenerateResponse: Decodable {
    let response: String
    let error: String?
}

private struct CloudAIChatRequest: Encodable {
    let model: String
    let messages: [CloudAIMessage]
    let temperature: Double
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
    }
}

private struct CloudAIMessage: Encodable {
    let role: String
    let content: String
}

private struct CloudAIChatResponse: Decodable {
    let choices: [Choice]?
    let error: CloudAIError?

    struct Choice: Decodable {
        let message: Message?
        let text: String?

        struct Message: Decodable {
            let content: String?
        }
    }
}

private struct CloudAIError: Decodable {
    let message: String?
}

private extension String {
    func nonEmpty(or fallback: String) -> String {
        isEmpty ? fallback : self
    }

    func prefixText(_ limit: Int) -> String {
        count <= limit ? self : String(prefix(limit)) + "..."
    }
}
