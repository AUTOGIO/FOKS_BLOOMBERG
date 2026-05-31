import Foundation

public struct DiagnosticBundleBuilder: Sendable {
    public init() {}

    public func build(snapshot: DashboardSnapshot, selectedProjectID: ProjectStatus.ID?) -> String {
        let selected = snapshot.projects.first { $0.id == selectedProjectID } ?? snapshot.projects.first
        let dirtyProjects = snapshot.projects.filter { $0.health == .dirty }
        let failedAgents = snapshot.launchAgents.filter { $0.health == .failed }
        let stoppedAgents = snapshot.launchAgents.filter { $0.health == .stopped }

        var lines: [String] = [
            "FOKS TERMINAL LOCAL DIAGNOSTIC BUNDLE",
            "Rules: local-only analysis; do not suggest cloud services; do not suggest destructive git reset; provide commands only as review steps, not auto-execution.",
            "",
            "Hardware:",
            "- target: \(snapshot.hardware.targetProfile)",
            "- model: \(snapshot.hardware.modelIdentifier)",
            "- chip: \(snapshot.hardware.chip)",
            "- cores: \(snapshot.hardware.coreSummary)",
            "- memory: \(snapshot.hardware.memory)",
            "- os: \(snapshot.hardware.osVersion)",
            "- uptime: \(snapshot.hardware.uptime)",
            "",
            "Portfolio summary:",
            "- projects: \(snapshot.projects.count)",
            "- clean: \(snapshot.projects.filter { $0.health == .clean }.count)",
            "- dirty: \(dirtyProjects.count)",
            "- unpushed: \(snapshot.projects.filter { $0.health == .unpushed }.count)",
            "- missing: \(snapshot.projects.filter { $0.health == .missing }.count)",
            "",
            "Selected project:"
        ]

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
        lines.append("1. State the top 3 issues by operational risk.")
        lines.append("2. For each issue, explain the likely root cause from the evidence.")
        lines.append("3. Give the minimal safe fix path with concrete terminal commands for manual review.")
        lines.append("4. Separate actions into NOW / NEXT / LATER.")
        lines.append("5. Keep it under 350 words.")

        return lines.joined(separator: "\n")
    }

    private func projectLines(_ project: ProjectStatus, dirtyLimit: Int) -> [String] {
        var lines = [
            "- \(project.shortName) \(project.displayName)",
            "  path: \(project.path)",
            "  health: \(project.health.rawValue); reason: \(project.reason)",
            "  branch: \(project.branch); dirty: \(project.dirtyFiles); ahead: \(project.ahead); behind: \(project.behind)"
        ]
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
        let prompt = builder.build(snapshot: snapshot, selectedProjectID: selectedProjectID)
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

private extension String {
    func nonEmpty(or fallback: String) -> String {
        isEmpty ? fallback : self
    }

    func prefixText(_ limit: Int) -> String {
        count <= limit ? self : String(prefix(limit)) + "..."
    }
}
