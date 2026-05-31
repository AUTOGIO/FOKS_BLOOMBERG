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
                    gitSummary: "path not found",
                    health: .missing
                )
            }

            let summary: String
            let health: ProjectStatus.Health
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) {
                do {
                    let result = try shell.zsh("git -C \(quoted(project.path)) status --short --branch", timeout: 4)
                    summary = result.output.isEmpty ? "clean" : result.output.replacingOccurrences(of: "\n", with: " | ")
                    health = result.exitCode == 0 && result.output.trimmingCharacters(in: .whitespacesAndNewlines).contains("##") ? .ok : .warning
                } catch {
                    summary = "git error: \(error.localizedDescription)"
                    health = .warning
                }
            } else {
                summary = "not a git repo"
                health = .warning
            }

            return ProjectStatus(
                id: project.id,
                shortName: project.short,
                name: project.name,
                path: project.path,
                gitSummary: summary,
                health: health
            )
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

    private func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private extension String {
    func prefixText(_ limit: Int) -> String {
        count <= limit ? self : String(prefix(limit)) + "..."
    }
}
