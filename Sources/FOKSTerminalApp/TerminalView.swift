import SwiftUI
import FOKSTerminalCore

@MainActor
final class TerminalModel: ObservableObject {
    @Published var projects: [ProjectStatus] = []
    @Published var processes: [ProcessSnapshot] = []
    @Published var launchAgents: [LaunchAgentSnapshot] = []
    @Published var logs: [LogEntry] = []
    @Published var selectedProjectID: ProjectStatus.ID?
    @Published var lastRefresh: Date?

    private let reader = SystemReader()

    func refresh() {
        projects = reader.readProjects()
        processes = reader.readProcesses()
        launchAgents = reader.readLaunchAgents()
        logs = reader.readRecentLogs()
        lastRefresh = Date()
    }
}

struct TerminalView: View {
    @StateObject private var model = TerminalModel()
    @AppStorage("foks.fontScale") private var fontScale: Double = 1.0

    private let amber = Color(red: 0.96, green: 0.62, blue: 0.04)
    private let green = Color(red: 0.64, green: 0.90, blue: 0.21)
    private let cyan = Color(red: 0.13, green: 0.83, blue: 0.93)
    private let red = Color(red: 1.00, green: 0.20, blue: 0.20)

    var body: some View {
        VStack(spacing: 0) {
            topBar
            statsBar
            HSplitView {
                projectPanel
                    .frame(minWidth: 260, idealWidth: 320)
                centerPanel
                    .frame(minWidth: 420)
                rightPanel
                    .frame(minWidth: 460)
            }
            bottomLog
        }
        .font(.system(size: 11 * fontScale, design: .monospaced))
        .foregroundStyle(.gray)
        .background(Color.black)
        .task { model.refresh() }
    }

    private var topBar: some View {
        HStack {
            Text("FOKS TERMINAL · NATIVE SWIFTUI MVP · READ ONLY")
                .foregroundStyle(amber)
                .fontWeight(.bold)
            Spacer()
            if let lastRefresh = model.lastRefresh {
                Text(lastRefresh.formatted(date: .omitted, time: .standard))
                    .foregroundStyle(cyan)
            }
            Button("A-") { fontScale = max(0.75, fontScale - 0.1) }
            Button("A+") { fontScale = min(1.6, fontScale + 0.1) }
            Button("REFRESH") { model.refresh() }
                .keyboardShortcut("r", modifiers: [.command])
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(red: 0.08, green: 0.06, blue: 0.01))
        .border(amber.opacity(0.5), width: 1)
    }

    private var statsBar: some View {
        HStack(spacing: 0) {
            stat("PROJECTS", "\(model.projects.count)", amber)
            stat("CLEAN", "\(model.projects.filter { $0.health == .ok }.count)", green)
            stat("DIRTY", "\(model.projects.filter { $0.health == .dirty }.count)", amber)
            stat("UNPUSHED", "\(model.projects.filter { $0.health == .unpushed }.count)", cyan)
            stat("MISSING", "\(model.projects.filter { $0.health == .missing }.count)", red)
            stat("SERVICES", "\(model.launchAgents.count)", green)
        }
        .background(Color(red: 0.03, green: 0.03, blue: 0.03))
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label).foregroundStyle(.secondary)
            Text(value).foregroundStyle(color).fontWeight(.bold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .border(Color.white.opacity(0.08), width: 1)
    }

    private var projectPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("PORTFOLIO", amber)
            List(selection: $model.selectedProjectID) {
                ForEach(model.projects) { project in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(project.shortName).foregroundStyle(color(for: project.health)).fontWeight(.bold)
                            Spacer()
                            Text(project.health.rawValue).foregroundStyle(color(for: project.health))
                        }
                        Text(project.name).foregroundStyle(.white.opacity(0.75))
                        Text(project.reason).foregroundStyle(color(for: project.health))
                        Text(project.path).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .tag(project.id)
                    .padding(.vertical, 4)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(Color.black)
    }

    private var centerPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("PROJECT DETAIL", green)
            if let selected = model.projects.first(where: { $0.id == model.selectedProjectID }) {
                detailRows(for: selected)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Select a project to inspect triage facts.")
                        .foregroundStyle(.secondary)
                    Text("Manual success before automation. This MVP only reads system state.")
                        .foregroundStyle(amber)
                }
                .padding(14)
            }
            Spacer()
            header("RECENT FOKS LOGS", cyan)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.logs) { log in
                        HStack(alignment: .top) {
                            Text(log.source).foregroundStyle(cyan).frame(width: 160, alignment: .leading)
                            Text(log.message).foregroundStyle(log.level == "WARN" ? amber : .secondary)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 180)
        }
        .background(Color(red: 0.01, green: 0.01, blue: 0.01))
    }

    private func detailRows(for project: ProjectStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            row("SHORT", project.shortName, color(for: project.health))
            row("STATUS", project.health.rawValue, color(for: project.health))
            row("REASON", project.reason, color(for: project.health))
            row("NAME", project.name, .white.opacity(0.8))
            row("PATH", project.path, .secondary)
            row("BRANCH", project.branch, cyan)
            row("DIRTY", "\(project.dirtyFiles)", project.dirtyFiles > 0 ? amber : green)
            row("AHEAD", "\(project.ahead)", project.ahead > 0 ? cyan : .secondary)
            row("BEHIND", "\(project.behind)", project.behind > 0 ? amber : .secondary)
            row("REMOTE", project.remoteURL.isEmpty ? "none" : project.remoteURL, project.remoteURL.isEmpty ? amber : .secondary)
            row("NEXT", project.recommendedAction, color(for: project.health))
            row("GIT", project.gitSummary, .secondary)
            row("MODE", "READ ONLY - no scripts executed", amber)
        }
        .padding(14)
    }

    private var rightPanel: some View {
        VStack(spacing: 0) {
            header("LIVE PROCESSES", cyan)
            Table(model.processes) {
                TableColumn("PID", value: \.pid).width(60)
                TableColumn("CPU", value: \.cpu).width(70)
                TableColumn("MEM", value: \.memory).width(80)
                TableColumn("COMMAND", value: \.command)
            }
            header("LAUNCHCTL WATCHLIST", amber)
            Table(model.launchAgents) {
                TableColumn("PID", value: \.pid).width(80)
                TableColumn("STATUS", value: \.status).width(90)
                TableColumn("LABEL", value: \.label)
            }
        }
        .background(Color.black)
    }

    private var bottomLog: some View {
        HStack {
            Text("CMD>").foregroundStyle(amber).fontWeight(.bold)
            Text("projects-first read-only cockpit; use REFRESH or Cmd+R")
                .foregroundStyle(.secondary)
            Spacer()
            Text("No shell actions are executed from buttons.")
                .foregroundStyle(red.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color(red: 0.02, green: 0.02, blue: 0.02))
        .border(Color.white.opacity(0.08), width: 1)
    }

    private func header(_ title: String, _ color: Color) -> some View {
        Text(title)
            .foregroundStyle(color)
            .fontWeight(.bold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(red: 0.04, green: 0.04, blue: 0.04))
            .border(Color.white.opacity(0.08), width: 1)
    }

    private func row(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
            Text(value).foregroundStyle(color).textSelection(.enabled)
        }
    }

    private func color(for health: ProjectStatus.Health) -> Color {
        switch health {
        case .ok: green
        case .dirty: amber
        case .unpushed: cyan
        case .missing: red
        case .notGit: amber
        case .unknown: amber
        }
    }
}
