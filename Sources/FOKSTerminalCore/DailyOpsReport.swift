import Foundation

public struct DailyOpsReportBuilder: Sendable {
    public init() {}

    public func build(snapshot: DashboardSnapshot, actions: [OperationalAction], generatedAt: Date = Date()) -> String {
        let dirtyProjects = snapshot.projects.filter { $0.health == .dirty }
        let unpushedProjects = snapshot.projects.filter { $0.health == .unpushed }
        let failedAgents = snapshot.launchAgents.filter { $0.health == .failed }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        var lines: [String] = [
            "# FoKS Daily Ops Report",
            "",
            "Generated: \(formatter.string(from: generatedAt))",
            "",
            "## Summary",
            "- Projects: \(snapshot.projects.count)",
            "- Dirty repos: \(dirtyProjects.count)",
            "- Unpushed repos: \(unpushedProjects.count)",
            "- Failed LaunchAgents: \(failedAgents.count)",
            "- Open actions: \(actions.count)",
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

        return lines.joined(separator: "\n")
    }
}
