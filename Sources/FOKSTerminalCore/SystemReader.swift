import Foundation

public struct SystemReader: Sendable {
    private let shell: Shell

    public init(shell: Shell = Shell()) {
        self.shell = shell
    }

    public func readProjects() -> [ProjectStatus] {
        configuredProjects().map { project in
            let url = URL(fileURLWithPath: project.path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return ProjectStatus(
                    id: project.id,
                    shortName: project.short,
                    name: project.name,
                    path: project.path,
                    health: .missing,
                    reason: "missing path"
                )
            }

            guard isGitRepository(project.path) else {
                return ProjectStatus(
                    id: project.id,
                    shortName: project.short,
                    name: project.name,
                    path: project.path,
                    health: .notGit,
                    reason: "not a git repo"
                )
            }

            return readGitProject(project)
        }
        .sorted { lhs, rhs in
            if lhs.health.priority != rhs.health.priority {
                return lhs.health.priority > rhs.health.priority
            }
            return lhs.shortName < rhs.shortName
        }
    }

    public func readProcesses() -> [ProcessSnapshot] {
        do {
            let result = try shell.zsh("ps axo pid=,pcpu=,rss=,command= | egrep 'python|ollama|LM Studio|streamlit|yabai|swift|FOKS|Home Assistant' | egrep -v 'egrep|zsh -lc' | head -40", timeout: 4)
            return result.output
                .split(separator: "\n")
                .compactMap(parseProcessLine)
        } catch {
            return []
        }
    }

    public func readLaunchAgents() -> [LaunchAgentSnapshot] {
        do {
            let result = try shell.zsh("launchctl list | egrep -i 'foks|gmc|yabai|home|fulofilo|life|workspace' | head -40", timeout: 4)
            return result.output
                .split(separator: "\n")
                .compactMap(parseLaunchAgentLine)
        } catch {
            return []
        }
    }

    public func readRecentLogs() -> [LogEntry] {
        let candidates = [
            "\(NSHomeDirectory())/foks/logs/foks-monitor.jsonl",
            "\(NSHomeDirectory())/foks/logs/workspace_launch.log",
            "\(NSHomeDirectory())/Library/Logs/FOKS/workspace_launch.log"
        ]

        for path in candidates where FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                return text
                    .split(separator: "\n")
                    .suffix(12)
                    .map { LogEntry(source: url.lastPathComponent, message: String($0).prefixText(160)) }
            }
        }

        return [LogEntry(source: "SYSTEM", message: "No FoKS log file found in ~/foks/logs or ~/Library/Logs/FOKS", level: "WARN")]
    }

    private func configuredProjects() -> [(id: String, short: String, name: String, path: String)] {
        [
            ("foks", "FOKS", "FOKS Bloomberg Terminal", "/Users/eduardofgiovannini/Documents/GitHub/FOKS_BLOOMBERG"),
            ("ffa", "FFA", "FuloFilo Analytics", "/Users/eduardofgiovannini/Documents/GitHub/fulofilo-analytics"),
            ("life", "LIFE", "Personal Life OS", "/Users/eduardofgiovannini/Documents/GitHub/PersonalLifeOS"),
            ("gfin", "GFIN", "Giovannini Finance", "/Users/eduardofgiovannini/Documents/GitHub/giovannini-finance"),
            ("gmc", "GMC", "GMC", "/Users/eduardofgiovannini/Documents/GitHub/GMC")
        ]
    }

    private func parseProcessLine(_ line: Substring) -> ProcessSnapshot? {
        let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard parts.count == 4 else { return nil }
        let rssKB = Int(parts[2]) ?? 0
        let memory = rssKB > 1_048_576 ? "\(rssKB / 1_048_576)GB" : "\(rssKB / 1024)MB"
        return ProcessSnapshot(pid: String(parts[0]), command: String(parts[3]), cpu: "\(parts[1])%", memory: memory)
    }

    private func parseLaunchAgentLine(_ line: Substring) -> LaunchAgentSnapshot? {
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return nil }
        return LaunchAgentSnapshot(pid: String(parts[0]), status: String(parts[1]), label: String(parts[2]))
    }

    private func isGitRepository(_ path: String) -> Bool {
        do {
            let result = try shell.zsh("git -C \(quoted(path)) rev-parse --is-inside-work-tree", timeout: 3)
            return result.exitCode == 0 && result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
        } catch {
            return false
        }
    }

    private func readGitProject(_ project: (id: String, short: String, name: String, path: String)) -> ProjectStatus {
        do {
            let branch = try readFirstLine("git -C \(quoted(project.path)) branch --show-current", fallback: "DETACHED")
            let dirtyOutput = try shell.zsh("git -C \(quoted(project.path)) status --porcelain", timeout: 4).output
            let dirtyFiles = dirtyOutput.split(separator: "\n").count
            let remoteURL = (try? readFirstLine("git -C \(quoted(project.path)) remote get-url origin", fallback: "")) ?? ""
            let upstream = (try? readFirstLine("git -C \(quoted(project.path)) rev-parse --abbrev-ref --symbolic-full-name @{u}", fallback: "")) ?? ""

            let divergence = upstream.isEmpty
                ? (ahead: 0, behind: 0)
                : readDivergence(path: project.path, upstream: upstream)

            let health: ProjectStatus.Health
            let reason: String

            if dirtyFiles > 0 {
                health = .dirty
                reason = "\(dirtyFiles) dirty file\(dirtyFiles == 1 ? "" : "s")"
            } else if divergence.ahead > 0 {
                health = .unpushed
                reason = "\(divergence.ahead) unpushed commit\(divergence.ahead == 1 ? "" : "s")"
            } else if remoteURL.isEmpty || upstream.isEmpty {
                health = .unknown
                reason = remoteURL.isEmpty ? "no remote" : "no upstream"
            } else if divergence.behind > 0 {
                health = .unknown
                reason = "\(divergence.behind) behind remote"
            } else {
                health = .ok
                reason = "clean and synced"
            }

            return ProjectStatus(
                id: project.id,
                shortName: project.short,
                name: project.name,
                path: project.path,
                health: health,
                reason: reason,
                branch: branch.isEmpty ? "DETACHED" : branch,
                dirtyFiles: dirtyFiles,
                ahead: divergence.ahead,
                behind: divergence.behind,
                remoteURL: remoteURL
            )
        } catch {
            return ProjectStatus(
                id: project.id,
                shortName: project.short,
                name: project.name,
                path: project.path,
                health: .unknown,
                reason: "git error: \(error.localizedDescription)"
            )
        }
    }

    private func readFirstLine(_ command: String, fallback: String) throws -> String {
        let result = try shell.zsh(command, timeout: 4)
        guard result.exitCode == 0 else { return fallback }
        return result.output.split(separator: "\n").first.map(String.init) ?? fallback
    }

    private func readDivergence(path: String, upstream: String) -> (ahead: Int, behind: Int) {
        do {
            let result = try shell.zsh("git -C \(quoted(path)) rev-list --left-right --count HEAD...\(quoted(upstream))", timeout: 4)
            let parts = result.output.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { return (0, 0) }
            return (Int(parts[0]) ?? 0, Int(parts[1]) ?? 0)
        } catch {
            return (0, 0)
        }
    }

    private func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private extension ProjectStatus.Health {
    var priority: Int {
        switch self {
        case .missing: 60
        case .dirty: 50
        case .unpushed: 40
        case .unknown: 30
        case .notGit: 20
        case .ok: 10
        }
    }
}

private extension String {
    func prefixText(_ limit: Int) -> String {
        count <= limit ? self : String(prefix(limit)) + "..."
    }
}
