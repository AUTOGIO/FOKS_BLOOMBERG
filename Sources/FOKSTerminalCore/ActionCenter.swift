import Foundation

public struct ActionCenterBuilder: Sendable {
    public init() {}

    public func build(snapshot: DashboardSnapshot) -> [OperationalAction] {
        var actions: [OperationalAction] = []

        actions.append(contentsOf: launchServiceActions(snapshot.launchAgents + snapshot.launchDaemons))
        actions.append(contentsOf: projectActions(snapshot.projects))
        actions.append(contentsOf: systemActions(snapshot.system))
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
                    manualCommands: [
                        ManualCommand(
                            id: "foks-git-status",
                            title: "Check FOKS git state",
                            executable: "/usr/bin/git",
                            arguments: ["-C", "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Mobile Documents/com~apple~CloudDocs/Documents/GitHub/FOKS_BLOOMBERG", "status", "--short", "--branch"],
                            intent: "Confirm the FOKS Terminal repository still has no unexpected local changes."
                        )
                    ],
                    check: ReadOnlyCheck(
                        title: "Check FOKS git state",
                        executable: "/usr/bin/git",
                        arguments: ["-C", "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Mobile Documents/com~apple~CloudDocs/Documents/GitHub/FOKS_BLOOMBERG", "status", "--short", "--branch"]
                    )
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

    private func launchServiceActions(_ services: [LaunchAgentSnapshot]) -> [OperationalAction] {
        services
            .filter { $0.health == .failed }
            .map { service in
                let stderr = service.stderrPath.nonEmpty(or: "/tmp/\(service.label).err")
                let stdout = service.stdoutPath.nonEmpty(or: "/tmp/\(service.label).log")
                let fallbackPlist = service.domain == .agent
                    ? "\(NSHomeDirectory())/Library/LaunchAgents/\(service.label).plist"
                    : "/Library/LaunchDaemons/\(service.label).plist"
                let plist = service.plistPath.nonEmpty(or: fallbackPlist)
                let launchctlTarget = service.domain == .agent
                    ? "gui/\(getuid())/\(service.label)"
                    : "system/\(service.label)"
                return OperationalAction(
                    id: "\(service.domain.rawValue.lowercased())-\(service.label)",
                    severity: .critical,
                    title: "Inspect failing \(service.domain.rawValue.lowercased())",
                    scope: service.label,
                    evidence: "\(service.reason); state \(service.state)",
                    nextStep: "Inspect the launchd state, plist, and recent stderr before any manual restart.",
                    manualCommands: [
                        ManualCommand(
                            id: "\(service.label)-launchctl-print",
                            title: "Print launchd state",
                            executable: "/bin/launchctl",
                            arguments: ["print", launchctlTarget],
                            intent: "Read the current launchd state without changing it."
                        ),
                        ManualCommand(
                            id: "\(service.label)-plist",
                            title: "Inspect plist",
                            executable: "/usr/bin/plutil",
                            arguments: ["-p", plist],
                            intent: "Validate the configured plist fields."
                        ),
                        ManualCommand(
                            id: "\(service.label)-stderr",
                            title: "Read stderr tail",
                            executable: "/usr/bin/tail",
                            arguments: ["-80", stderr],
                            intent: "Inspect the most recent failure output."
                        ),
                        ManualCommand(
                            id: "\(service.label)-stdout",
                            title: "Read stdout tail",
                            executable: "/usr/bin/tail",
                            arguments: ["-40", stdout],
                            intent: "Inspect recent normal output."
                        )
                    ],
                    check: ReadOnlyCheck(
                        title: "Tail launch service stderr",
                        executable: "/usr/bin/tail",
                        arguments: ["-80", stderr]
                    )
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
                        manualCommands: [
                            ManualCommand(
                                id: "\(project.id)-list-parent",
                                title: "List parent folder",
                                executable: "/bin/ls",
                                arguments: ["-la", URL(fileURLWithPath: project.path).deletingLastPathComponent().path],
                                intent: "Check whether the project folder was moved or deleted."
                            )
                        ],
                        check: ReadOnlyCheck(
                            title: "List parent folder",
                            executable: "/bin/ls",
                            arguments: ["-la", URL(fileURLWithPath: project.path).deletingLastPathComponent().path]
                        )
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
                        manualCommands: [
                            ManualCommand(
                                id: "\(project.id)-git-status",
                                title: "Show dirty files",
                                executable: "/usr/bin/git",
                                arguments: ["-C", project.path, "status", "--short"],
                                intent: "List local changes without modifying the repository."
                            ),
                            ManualCommand(
                                id: "\(project.id)-git-diff-stat",
                                title: "Show diff summary",
                                executable: "/usr/bin/git",
                                arguments: ["-C", project.path, "diff", "--stat"],
                                intent: "Review the size and location of local edits."
                            )
                        ],
                        check: ReadOnlyCheck(
                            title: "Check git dirty files",
                            executable: "/usr/bin/git",
                            arguments: ["-C", project.path, "status", "--short"]
                        )
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
                        manualCommands: [
                            ManualCommand(
                                id: "\(project.id)-git-log",
                                title: "Show recent commits",
                                executable: "/usr/bin/git",
                                arguments: ["-C", project.path, "log", "--oneline", "--decorate", "-n", "8"],
                                intent: "Inspect unpushed commits before any manual push."
                            ),
                            ManualCommand(
                                id: "\(project.id)-git-branch-status",
                                title: "Show branch status",
                                executable: "/usr/bin/git",
                                arguments: ["-C", project.path, "status", "--branch", "--short"],
                                intent: "Confirm branch divergence."
                            )
                        ],
                        check: ReadOnlyCheck(
                            title: "Review unpushed commits",
                            executable: "/usr/bin/git",
                            arguments: ["-C", project.path, "log", "--oneline", "--decorate", "-n", "8"]
                        )
                    )
                )
            }

            if !project.missingDependencies.isEmpty {
                actions.append(
                    OperationalAction(
                        id: "project-dependencies-\(project.id)",
                        severity: .warning,
                        title: "Review missing local dependencies",
                        scope: project.shortName,
                        evidence: project.missingDependencies.joined(separator: ", "),
                        nextStep: "Open the project README or setup notes and rebuild dependencies manually if this project is active.",
                        manualCommands: [
                            ManualCommand(
                                id: "\(project.id)-list-project",
                                title: "List project root",
                                executable: "/bin/ls",
                                arguments: ["-la", project.path],
                                intent: "Inspect the local project root before running setup commands manually."
                            )
                        ],
                        check: ReadOnlyCheck(
                            title: "List project root",
                            executable: "/bin/ls",
                            arguments: ["-la", project.path]
                        )
                    )
                )
            }

            return actions
        }
    }

    private func systemActions(_ metrics: SystemMetricsSnapshot) -> [OperationalAction] {
        var actions: [OperationalAction] = []

        if metrics.cpuPercent >= 75 {
            actions.append(
                OperationalAction(
                    id: "system-cpu-high",
                    severity: metrics.cpuPercent >= 90 ? .critical : .warning,
                    title: "CPU pressure is high",
                    scope: "System",
                    evidence: String(format: "CPU %.0f%%", metrics.cpuPercent),
                    nextStep: "Review top processes before starting heavier local AI or build tasks.",
                    manualCommands: [
                        ManualCommand(
                            id: "system-ps-cpu",
                            title: "List top CPU processes",
                            executable: "/bin/ps",
                            arguments: ["axo", "pid=,pcpu=,pmem=,command="],
                            intent: "Read process CPU usage without changing process state."
                        )
                    ],
                    check: ReadOnlyCheck(
                        title: "List top CPU processes",
                        executable: "/bin/ps",
                        arguments: ["axo", "pid=,pcpu=,pmem=,command="]
                    )
                )
            )
        }

        if metrics.memoryUsedPercent >= 80 {
            actions.append(
                OperationalAction(
                    id: "system-memory-high",
                    severity: metrics.memoryUsedPercent >= 90 ? .critical : .warning,
                    title: "Memory pressure is elevated",
                    scope: "System",
                    evidence: String(format: "Memory %.0f%% used", metrics.memoryUsedPercent),
                    nextStep: "Inspect memory-heavy processes before running additional local models.",
                    manualCommands: [
                        ManualCommand(
                            id: "system-vm-stat",
                            title: "Read VM statistics",
                            executable: "/usr/bin/vm_stat",
                            arguments: [],
                            intent: "Read virtual memory counters."
                        )
                    ],
                    check: ReadOnlyCheck(
                        title: "Read VM statistics",
                        executable: "/usr/bin/vm_stat",
                        arguments: []
                    )
                )
            )
        }

        if metrics.diskUsedPercent >= 85 {
            actions.append(
                OperationalAction(
                    id: "system-disk-high",
                    severity: metrics.diskUsedPercent >= 92 ? .critical : .warning,
                    title: "Startup disk is filling",
                    scope: "System",
                    evidence: String(format: "Disk %.0f%% used, %@ free", metrics.diskUsedPercent, ByteFormatter.memoryString(bytes: metrics.diskFreeBytes)),
                    nextStep: "Inspect disk usage manually before large builds, model pulls, or exports.",
                    manualCommands: [
                        ManualCommand(
                            id: "system-df-root",
                            title: "Read root disk usage",
                            executable: "/bin/df",
                            arguments: ["-k", "/"],
                            intent: "Read startup volume capacity."
                        )
                    ],
                    check: ReadOnlyCheck(
                        title: "Read root disk usage",
                        executable: "/bin/df",
                        arguments: ["-k", "/"]
                    )
                )
            )
        }

        return actions
    }

    private func logActions(_ logs: [LogEntry]) -> [OperationalAction] {
        var actions: [OperationalAction] = []

        let severeLogs = logs.filter { $0.level == "ERROR" || $0.level == "INCIDENT" }
        if !severeLogs.isEmpty {
            let evidenceText = severeLogs.prefix(3).map { "\($0.source): \($0.message)" }.joined(separator: " | ")
            let readablePath = severeLogs.first?.filePath ?? ""
            let commands = readablePath.isEmpty
                ? [ManualCommand(
                    id: "logs-list-foks",
                    title: "List FoKS logs",
                    executable: "/bin/ls",
                    arguments: ["-la", "\(NSHomeDirectory())/Library/Logs/FOKS"],
                    intent: "Find the current local FoKS log files."
                )]
                : [ManualCommand(
                    id: "logs-tail-source",
                    title: "Tail source log",
                    executable: "/usr/bin/tail",
                    arguments: ["-80", readablePath],
                    intent: "Read the recent local log context around the incident."
                )]
            actions.append(
                OperationalAction(
                    id: "logs-severe",
                    severity: severeLogs.contains(where: { $0.level == "INCIDENT" }) ? .critical : .warning,
                    title: "Review recent log incidents",
                    scope: "Logs",
                    evidence: evidenceText,
                    nextStep: "Inspect the source log and correlate with the affected project before changing anything.",
                    manualCommands: commands,
                    check: readablePath.isEmpty ? nil : ReadOnlyCheck(
                        title: "Tail source log",
                        executable: "/usr/bin/tail",
                        arguments: ["-80", readablePath]
                    )
                )
            )
        }

        return actions
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
