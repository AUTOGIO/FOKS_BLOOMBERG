import Foundation

public struct ActionCenterBuilder: Sendable {
    public init() {}

    public func build(snapshot: DashboardSnapshot) -> [OperationalAction] {
        var actions: [OperationalAction] = []

        actions.append(contentsOf: launchAgentActions(snapshot.launchAgents))
        actions.append(contentsOf: projectActions(snapshot.projects))
        actions.append(contentsOf: logActions(snapshot.logs))

        if actions.isEmpty {
            actions.append(
                OperationalAction(
                    id: "all-clear",
                    severity: .info,
                    title: "No urgent operational issues",
                    scope: "FoKS",
                    evidence: "No failed LaunchAgents, dirty projects, missing repos, or log warnings in the current snapshot.",
                    nextStep: "Keep working. Refresh after changing repos or services.",
                    command: "cd /Users/eduardofgiovannini/Documents/GitHub/FOKS_BLOOMBERG && ./scripts/validate.sh"
                )
            )
        }

        return actions.sorted { lhs, rhs in
            if lhs.severity.priority != rhs.severity.priority {
                return lhs.severity.priority > rhs.severity.priority
            }
            return lhs.title < rhs.title
        }
    }

    private func launchAgentActions(_ agents: [LaunchAgentSnapshot]) -> [OperationalAction] {
        agents
            .filter { $0.health == .failed }
            .map { agent in
                let stderr = agent.stderrPath.nonEmpty(or: "/tmp/\(agent.label).err")
                let stdout = agent.stdoutPath.nonEmpty(or: "/tmp/\(agent.label).log")
                let plist = agent.plistPath.nonEmpty(or: "~/Library/LaunchAgents/\(agent.label).plist")
                return OperationalAction(
                    id: "agent-\(agent.label)",
                    severity: .critical,
                    title: "Fix failing LaunchAgent",
                    scope: agent.label,
                    evidence: "\(agent.reason); state \(agent.state)",
                    nextStep: "Inspect the plist and recent stderr before restarting the agent.",
                    command: [
                        "launchctl print gui/$(id -u)/\(agent.label)",
                        "plutil -p '\(plist)'",
                        "tail -80 '\(stderr)'",
                        "tail -40 '\(stdout)'"
                    ].joined(separator: "\n")
                )
            }
    }

    private func projectActions(_ projects: [ProjectStatus]) -> [OperationalAction] {
        projects.flatMap { project -> [OperationalAction] in
            var actions: [OperationalAction] = []

            if project.health == .missing {
                actions.append(
                    OperationalAction(
                        id: "project-missing-\(project.id)",
                        severity: .critical,
                        title: "Restore missing project path",
                        scope: project.shortName,
                        evidence: project.path,
                        nextStep: "Confirm the folder was moved or update config/projects.json.",
                        command: "ls -la '\(project.path)'\nopen '\(URL(fileURLWithPath: project.path).deletingLastPathComponent().path)'"
                    )
                )
            }

            if project.health == .dirty {
                actions.append(
                    OperationalAction(
                        id: "project-dirty-\(project.id)",
                        severity: .warning,
                        title: "Review dirty repo",
                        scope: project.shortName,
                        evidence: dirtyEvidence(project),
                        nextStep: "Classify changes as keep, archive, ignore, or discard manually.",
                        command: "cd '\(project.path)' && git status --short\ncd '\(project.path)' && git diff --stat"
                    )
                )
            }

            if project.health == .unpushed {
                actions.append(
                    OperationalAction(
                        id: "project-unpushed-\(project.id)",
                        severity: .warning,
                        title: "Review unpushed commits",
                        scope: project.shortName,
                        evidence: "\(project.ahead) commit\(project.ahead == 1 ? "" : "s") ahead on \(project.branch)",
                        nextStep: "Inspect commits, then push if they are intentional.",
                        command: "cd '\(project.path)' && git log --oneline --decorate -n 8\ncd '\(project.path)' && git status --branch --short"
                    )
                )
            }

            return actions
        }
    }

    private func logActions(_ logs: [LogEntry]) -> [OperationalAction] {
        guard logs.contains(where: { $0.level == "WARN" && $0.message.contains("No FoKS log file") }) else {
            return []
        }

        return [
            OperationalAction(
                id: "logs-missing",
                severity: .info,
                title: "Create FoKS log location",
                scope: "Logs",
                evidence: "No FoKS log file found in ~/foks/logs or ~/Library/Logs/FOKS.",
                nextStep: "Create the folder before wiring future monitors.",
                command: "mkdir -p ~/Library/Logs/FOKS\nls -la ~/Library/Logs/FOKS"
            )
        ]
    }

    private func dirtyEvidence(_ project: ProjectStatus) -> String {
        if project.dirtyItems.isEmpty {
            return project.reason
        }
        return "\(project.reason): " + project.dirtyItems.prefix(4).joined(separator: ", ")
    }
}

private extension String {
    func nonEmpty(or fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
