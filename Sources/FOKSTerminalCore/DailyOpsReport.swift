import Foundation

public struct DailyOpsReportBuilder: Sendable {
    public init() {}

    public func build(
        snapshot: DashboardSnapshot,
        actions: [OperationalAction],
        aiSummary: String? = nil,
        generatedAt: Date = Date()
    ) -> String {
        let dirtyProjects = snapshot.projects.filter { $0.health == .dirty }
        let unpushedProjects = snapshot.projects.filter { $0.health == .unpushed }
        let missingProjects = snapshot.projects.filter { $0.health == .missing }
        let failedAgents = snapshot.launchAgents.filter { $0.health == .failed }
        let failedDaemons = snapshot.launchDaemons.filter { $0.health == .failed }
        let severeLogs = snapshot.logs.filter { $0.level == "ERROR" || $0.level == "INCIDENT" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        var lines: [String] = [
            "# FoKS Daily Ops Report",
            "",
            "Generated: \(formatter.string(from: generatedAt))",
            "",
            "## Summary",
            "- Global health score: \(snapshot.globalHealthScore)/100",
            "- System health score: \(snapshot.system.healthScore)/100",
            "- Projects: \(snapshot.projects.count)",
            "- Dirty repos: \(dirtyProjects.count)",
            "- Unpushed repos: \(unpushedProjects.count)",
            "- Missing projects: \(missingProjects.count)",
            "- Failed LaunchAgents: \(failedAgents.count)",
            "- Failed LaunchDaemons: \(failedDaemons.count)",
            "- Critical incidents: \(snapshot.incidents.filter { $0.severity == .critical }.count)",
            "- Severe log entries: \(severeLogs.count)",
            "- Open actions: \(actions.count)",
            "",
            "## System Health",
            "- CPU: \(metric(snapshot.system.cpuPercent, available: snapshot.system.cpuAvailable))",
            "- Memory: \(metric(snapshot.system.memoryUsedPercent, available: snapshot.system.memoryAvailable)) used",
            "- Disk: \(metric(snapshot.system.diskUsedPercent, available: snapshot.system.diskAvailable)) used",
            "- Free disk: \(snapshot.system.diskAvailable ? ByteFormatter.memoryString(bytes: snapshot.system.diskFreeBytes) : "unavailable")",
            "- Uptime: \(snapshot.system.uptimeAvailable ? snapshot.system.uptime : "unavailable")",
            "",
            "## Top Actions"
        ]

        if actions.isEmpty {
            lines.append("- No open actions.")
        } else {
            for action in actions.prefix(5) {
                lines.append("- [\(action.severity.rawValue)] \(action.scope): \(action.title)")
                lines.append("  - Evidence: \(action.evidence)")
                lines.append("  - Next: \(action.nextStep)")
            }
        }

        lines.append("")
        lines.append("## Project Health")
        if snapshot.projects.isEmpty {
            lines.append("- No configured projects.")
        } else {
            for project in snapshot.projects {
                lines.append("- \(project.shortName): \(project.healthScore)/100, \(project.health.rawValue), \(project.reason)")
                if !project.missingDependencies.isEmpty {
                    lines.append("  - Missing dependencies: \(project.missingDependencies.joined(separator: ", "))")
                }
                if !project.warnings.isEmpty {
                    lines.append("  - Warnings: \(project.warnings.prefix(4).joined(separator: ", "))")
                }
            }
        }

        lines.append("")
        lines.append("## Critical Incidents")
        let criticalIncidents = snapshot.incidents.filter { $0.severity == .critical }
        if criticalIncidents.isEmpty {
            lines.append("- None")
        } else {
            for incident in criticalIncidents.prefix(10) {
                lines.append("- \(incident.scope): \(incident.title)")
                lines.append("  - Evidence: \(incident.evidence)")
            }
        }

        lines.append("")
        lines.append("## Dirty Repos")
        if dirtyProjects.isEmpty {
            lines.append("- None")
        } else {
            for project in dirtyProjects {
                lines.append("- \(project.shortName): \(project.reason)")
                if !project.dirtyItems.isEmpty {
                    lines.append("  - \(project.dirtyItems.prefix(5).joined(separator: ", "))")
                }
            }
        }

        lines.append("")
        lines.append("## Unpushed")
        if unpushedProjects.isEmpty {
            lines.append("- None")
        } else {
            for project in unpushedProjects {
                lines.append("- \(project.shortName): \(project.ahead) ahead on \(project.branch)")
            }
        }

        lines.append("")
        lines.append("## Failed LaunchAgents")
        if failedAgents.isEmpty {
            lines.append("- None")
        } else {
            for agent in failedAgents {
                lines.append("- \(agent.label): \(agent.reason)")
                if !agent.stderrPath.isEmpty {
                    lines.append("  - stderr: \(agent.stderrPath)")
                }
            }
        }

        lines.append("")
        lines.append("## Failed LaunchDaemons")
        if failedDaemons.isEmpty {
            lines.append("- None")
        } else {
            for daemon in failedDaemons {
                lines.append("- \(daemon.label): \(daemon.reason)")
                if !daemon.stderrPath.isEmpty {
                    lines.append("  - stderr: \(daemon.stderrPath)")
                }
            }
        }

        lines.append("")
        lines.append("## Recent Severe Logs")
        if severeLogs.isEmpty {
            lines.append("- None")
        } else {
            for log in severeLogs.prefix(12) {
                lines.append("- [\(log.level)] \(log.category.rawValue)/\(log.source): \(log.message)")
            }
        }

        lines.append("")
        lines.append("## AI Summary")
        if let aiSummary, !aiSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(aiSummary.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            lines.append("No local AI summary generated.")
        }

        return lines.joined(separator: "\n")
    }

    public func buildPlainText(snapshot: DashboardSnapshot, actions: [OperationalAction], aiSummary: String? = nil, generatedAt: Date = Date()) -> String {
        build(snapshot: snapshot, actions: actions, aiSummary: aiSummary, generatedAt: generatedAt)
            .replacingOccurrences(of: "# ", with: "")
            .replacingOccurrences(of: "## ", with: "")
            .replacingOccurrences(of: "- ", with: "* ")
    }

    private func metric(_ value: Double, available: Bool) -> String {
        available ? String(format: "%.0f%%", value) : "unavailable"
    }
}
