import FOKSTerminalCore
import Observation
import SwiftUI

@MainActor
@Observable
final class TerminalStore {
    var snapshot: DashboardSnapshot = .empty
    var selectedProjectID: ProjectStatus.ID?
    var isRefreshing = false
    var isAnalyzing = false
    var aiAnalysis: LocalAIAnalysis = .idle
    var statusMessage = "READ ONLY - no scripts executed"

    private let reader = SystemReader()
    private let aiAdvisor = LocalAIAdvisor()

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        statusMessage = "Refreshing local read model..."
        let nextSnapshot = await reader.readDashboard()
        snapshot = nextSnapshot
        if selectedProjectID == nil {
            selectedProjectID = nextSnapshot.projects.first?.id
        } else if !nextSnapshot.projects.contains(where: { $0.id == selectedProjectID }) {
            selectedProjectID = nextSnapshot.projects.first?.id
        }
        statusMessage = "READ ONLY - no scripts executed"
        isRefreshing = false
    }

    func analyzeWithLocalAI(model: String) async {
        guard !isAnalyzing else { return }
        if snapshot.refreshedAt == .distantPast {
            await refresh()
        }
        isAnalyzing = true
        aiAnalysis = LocalAIAnalysis(provider: "Ollama", model: model, status: .running, text: "Sending local diagnostic bundle to \(model)...")
        statusMessage = "Local AI analysis running with \(model)..."
        aiAnalysis = await aiAdvisor.analyze(snapshot: snapshot, selectedProjectID: selectedProjectID, model: model)
        statusMessage = aiAnalysis.status == .ready ? "Local AI analysis ready - no fixes executed" : "Local AI analysis failed"
        isAnalyzing = false
    }
}

struct TerminalView: View {
    @State private var store = TerminalStore()
    @AppStorage("foks.fontScale") private var fontScale = 1.0
    @AppStorage("foks.theme") private var themeName = TerminalTheme.amber.rawValue
    @AppStorage("foks.localAIModel") private var localAIModel = "llama3.2:latest"

    private var theme: TerminalTheme {
        TerminalTheme(rawValue: themeName) ?? .amber
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            statsBar
            HSplitView {
                projectPanel
                    .frame(minWidth: 280, idealWidth: 340)
                detailPanel
                    .frame(minWidth: 420)
                systemPanel
                    .frame(minWidth: 440, idealWidth: 520)
            }
            bottomBar
        }
        .font(.system(size: 11 * fontScale, design: .monospaced))
        .foregroundStyle(theme.text)
        .background(theme.background)
        .task {
            await store.refresh()
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Text("FOKS TERMINAL")
                .foregroundStyle(theme.accent)
                .fontWeight(.black)
                .tracking(2)
            Text("APPLE NATIVE SWIFTUI")
                .foregroundStyle(theme.muted)
            Text("READ ONLY")
                .foregroundStyle(theme.green)
                .fontWeight(.bold)
            Spacer()
            Text(store.snapshot.refreshedAt == .distantPast ? "not refreshed" : store.snapshot.refreshedAt.formatted(date: .omitted, time: .standard))
                .foregroundStyle(theme.cyan)
            Button("A-") { fontScale = max(0.8, fontScale - 0.1) }
            Button("A+") { fontScale = min(1.5, fontScale + 0.1) }
            Picker("", selection: $themeName) {
                ForEach(TerminalTheme.allCases) { theme in
                    Text(theme.rawValue).tag(theme.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            Button(store.isRefreshing ? "WAIT" : "REFRESH") {
                Task { await store.refresh() }
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(store.isRefreshing)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(theme.topBackground)
        .overlay(Rectangle().fill(theme.accent.opacity(0.7)).frame(height: 1), alignment: .bottom)
    }

    private var statsBar: some View {
        HStack(spacing: 0) {
            stat("PROJECTS", "\(store.snapshot.projects.count)", theme.text)
            stat("CLEAN", "\(count(.clean))", theme.green)
            stat("DIRTY", "\(count(.dirty))", theme.accent)
            stat("UNPUSHED", "\(count(.unpushed))", theme.cyan)
            stat("MISSING", "\(count(.missing))", theme.red)
            stat("PROCESSES", "\(store.snapshot.processes.count)", theme.green)
            stat("AGENTS", "\(store.snapshot.launchAgents.count)", theme.cyan)
            stat("FAILED", "\(launchAgentIssueCount)", launchAgentIssueCount > 0 ? theme.red : theme.green)
        }
        .background(theme.panel)
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .foregroundStyle(theme.muted)
                .font(.system(size: 9 * fontScale, design: .monospaced))
            Text(value)
                .foregroundStyle(color)
                .fontWeight(.black)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .overlay(Rectangle().stroke(theme.border, lineWidth: 1))
    }

    private var projectPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("PORTFOLIO", right: "config/projects.json", color: theme.accent)
            List(selection: $store.selectedProjectID) {
                ForEach(store.snapshot.projects) { project in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(project.shortName)
                                .foregroundStyle(color(for: project.health))
                                .fontWeight(.black)
                            Text(project.group)
                                .foregroundStyle(theme.muted)
                            Spacer()
                            Text(project.health.rawValue)
                                .foregroundStyle(color(for: project.health))
                                .fontWeight(.bold)
                        }
                        Text(project.displayName)
                            .foregroundStyle(theme.text)
                        Text(project.reason)
                            .foregroundStyle(color(for: project.health))
                        Text(project.path)
                            .foregroundStyle(theme.dim)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .tag(project.id)
                    .padding(.vertical, 5)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(theme.background)
    }

    private var detailPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("PROJECT DETAIL", color: theme.green)
            if let project = selectedProject {
                VStack(alignment: .leading, spacing: 10) {
                    detailRow("SHORT", project.shortName, color(for: project.health))
                    detailRow("STATUS", project.health.rawValue, color(for: project.health))
                    detailRow("REASON", project.reason, color(for: project.health))
                    detailRow("NAME", project.displayName, theme.text)
                    detailRow("GROUP", project.group, theme.cyan)
                    detailRow("PATH", project.path, theme.text)
                    detailRow("BRANCH", project.branch, theme.cyan)
                    detailRow("DIRTY", "\(project.dirtyFiles)", project.dirtyFiles > 0 ? theme.accent : theme.green)
                    detailRow("AHEAD", "\(project.ahead)", project.ahead > 0 ? theme.cyan : theme.muted)
                    detailRow("BEHIND", "\(project.behind)", project.behind > 0 ? theme.accent : theme.muted)
                    detailRow("REMOTE", project.remoteURL.isEmpty ? "none" : project.remoteURL, project.remoteURL.isEmpty ? theme.accent : theme.text)
                    detailRow("NEXT", project.recommendedAction, color(for: project.health))
                    detailRow("MODE", "READ ONLY - no script execution", theme.accent)

                    if !project.dirtyItems.isEmpty {
                        Divider()
                            .background(theme.border)
                        Text("DIRTY FILES")
                            .foregroundStyle(theme.accent)
                            .fontWeight(.black)
                        ForEach(project.dirtyItems, id: \.self) { item in
                            Text(item)
                                .foregroundStyle(theme.muted)
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if project.dirtyFiles > project.dirtyItems.count {
                            Text("+ \(project.dirtyFiles - project.dirtyItems.count) more")
                                .foregroundStyle(theme.dim)
                        }
                    }
                }
                .padding(14)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No project selected.")
                        .foregroundStyle(theme.muted)
                    Text("Refresh reads local state only. It does not run project scripts.")
                        .foregroundStyle(theme.accent)
                }
                .padding(14)
            }

            Spacer(minLength: 0)
            sectionHeader("RECENT FOKS LOGS", color: theme.cyan)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.snapshot.logs) { log in
                        HStack(alignment: .top, spacing: 10) {
                            Text(log.source)
                                .foregroundStyle(theme.cyan)
                                .frame(width: 150, alignment: .leading)
                            Text(log.message)
                                .foregroundStyle(log.level == "WARN" ? theme.accent : theme.muted)
                                .textSelection(.enabled)
                            Spacer()
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 170, idealHeight: 210)
        }
        .background(theme.panel)
    }

    private var systemPanel: some View {
        VStack(spacing: 0) {
            sectionHeader("HARDWARE OVERVIEW", right: "MacBook Air M4 profile", color: theme.cyan)
            VStack(alignment: .leading, spacing: 9) {
                detailRow("TARGET", store.snapshot.hardware.targetProfile, theme.green)
                detailRow("MODEL", store.snapshot.hardware.modelIdentifier, theme.text)
                detailRow("CHIP", store.snapshot.hardware.chip, theme.text)
                detailRow("CORES", store.snapshot.hardware.coreSummary, theme.text)
                detailRow("MEMORY", store.snapshot.hardware.memory, theme.text)
                detailRow("OS", store.snapshot.hardware.osVersion, theme.text)
                detailRow("UPTIME", store.snapshot.hardware.uptime, theme.muted)
            }
            .padding(12)

            sectionHeader("PROCESS WATCHLIST", right: "\(store.snapshot.processes.count)", color: theme.green)
            Table(store.snapshot.processes) {
                TableColumn("PID") { process in
                    Text(process.pid).foregroundStyle(theme.muted)
                }
                .width(70)
                TableColumn("CPU") { process in
                    Text(process.cpu).foregroundStyle(theme.green)
                }
                .width(70)
                TableColumn("MEM") { process in
                    Text(process.memory).foregroundStyle(theme.cyan)
                }
                .width(80)
                TableColumn("COMMAND") { process in
                    Text(process.command).foregroundStyle(theme.text)
                }
            }
            .frame(minHeight: 210)

            sectionHeader(
                "LAUNCHCTL WATCHLIST",
                right: launchAgentIssueCount > 0 ? "\(launchAgentIssueCount) FAILED" : "OK",
                color: launchAgentIssueCount > 0 ? theme.red : theme.accent
            )
            Table(store.snapshot.launchAgents) {
                TableColumn("PID") { agent in
                    Text(agent.pid).foregroundStyle(theme.muted)
                }
                .width(70)
                TableColumn("HEALTH") { agent in
                    Text(agent.health.rawValue).foregroundStyle(color(for: agent.health))
                }
                .width(90)
                TableColumn("STATE") { agent in
                    Text(agent.state).foregroundStyle(theme.text)
                }
                .width(110)
                TableColumn("LABEL") { agent in
                    Text(agent.label).foregroundStyle(theme.text)
                }
                TableColumn("REASON") { agent in
                    Text(agent.reason).foregroundStyle(color(for: agent.health))
                }
                .width(min: 160, ideal: 220)
            }
            .frame(minHeight: 180)

            if launchAgentIssueCount > 0 {
                sectionHeader("LAUNCHAGENT ISSUES", color: theme.red)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(store.snapshot.launchAgents.filter { $0.health == .failed }) { agent in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(agent.label)
                                    .foregroundStyle(theme.red)
                                    .fontWeight(.bold)
                                Text(agent.reason)
                                    .foregroundStyle(theme.accent)
                                if !agent.plistPath.isEmpty {
                                    Text(agent.plistPath)
                                        .foregroundStyle(theme.dim)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(10)
                }
                .frame(maxHeight: 120)
            }

            sectionHeader(
                "LOCAL AI ADVISOR",
                right: "\(store.aiAnalysis.provider) \(store.aiAnalysis.status.rawValue)",
                color: color(for: store.aiAnalysis.status)
            )
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("MODEL")
                        .foregroundStyle(theme.muted)
                    Picker("", selection: $localAIModel) {
                        Text("llama3.2").tag("llama3.2:latest")
                        Text("tinyllama").tag("tinyllama:1.1b")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 210)

                    Button(store.isAnalyzing ? "ANALYZING" : "ANALYZE METRICS") {
                        Task { await store.analyzeWithLocalAI(model: localAIModel) }
                    }
                    .disabled(store.isAnalyzing || store.isRefreshing)

                    Spacer()
                }
                Text("Local Ollama HTTP only. The model receives diagnostics and returns advice; it cannot execute fixes.")
                    .foregroundStyle(theme.dim)
                    .lineLimit(2)
                ScrollView {
                    Text(store.aiAnalysis.text)
                        .foregroundStyle(color(for: store.aiAnalysis.status))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 90)
            }
            .padding(10)
        }
        .background(theme.background)
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Text("CMD>")
                .foregroundStyle(theme.accent)
                .fontWeight(.black)
            Text(store.statusMessage)
                .foregroundStyle(store.isRefreshing || store.isAnalyzing ? theme.cyan : theme.muted)
            Spacer()
            Text("Local AI advice only | no auto-fix execution")
                .foregroundStyle(theme.accent.opacity(0.9))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(theme.panel)
        .overlay(Rectangle().fill(theme.border).frame(height: 1), alignment: .top)
    }

    private var selectedProject: ProjectStatus? {
        store.snapshot.projects.first { $0.id == store.selectedProjectID }
    }

    private var launchAgentIssueCount: Int {
        store.snapshot.launchAgents.filter { $0.health == .failed }.count
    }

    private func count(_ health: ProjectStatus.Health) -> Int {
        store.snapshot.projects.filter { $0.health == health }.count
    }

    private func sectionHeader(_ title: String, right: String? = nil, color: Color) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(color)
                .fontWeight(.black)
                .tracking(1.5)
            Spacer()
            if let right {
                Text(right)
                    .foregroundStyle(theme.muted)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(theme.header)
        .overlay(Rectangle().stroke(theme.border, lineWidth: 1))
    }

    private func detailRow(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .foregroundStyle(theme.muted)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .foregroundStyle(color)
                .textSelection(.enabled)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
    }

    private func color(for health: ProjectStatus.Health) -> Color {
        switch health {
        case .clean: theme.green
        case .dirty: theme.accent
        case .unpushed: theme.cyan
        case .missing: theme.red
        case .notGit: theme.accent
        case .unknown: theme.accent
        }
    }

    private func color(for health: LaunchAgentSnapshot.Health) -> Color {
        switch health {
        case .running: theme.green
        case .scheduled: theme.cyan
        case .failed: theme.red
        case .stopped: theme.accent
        case .unknown: theme.accent
        }
    }

    private func color(for status: LocalAIAnalysis.Status) -> Color {
        switch status {
        case .idle: theme.muted
        case .running: theme.cyan
        case .ready: theme.green
        case .failed: theme.red
        }
    }
}

enum TerminalTheme: String, CaseIterable, Identifiable {
    case amber = "AMBER"
    case blue = "BLUE"

    var id: String { rawValue }

    var background: Color {
        switch self {
        case .amber: return Color(red: 0.0, green: 0.0, blue: 0.0)
        case .blue: return Color(red: 0.0, green: 0.02, blue: 0.05)
        }
    }

    var panel: Color {
        switch self {
        case .amber: return Color(red: 0.02, green: 0.02, blue: 0.02)
        case .blue: return Color(red: 0.0, green: 0.04, blue: 0.08)
        }
    }

    var header: Color {
        switch self {
        case .amber: return Color(red: 0.04, green: 0.04, blue: 0.04)
        case .blue: return Color(red: 0.0, green: 0.06, blue: 0.10)
        }
    }

    var topBackground: Color {
        switch self {
        case .amber: return Color(red: 0.08, green: 0.055, blue: 0.0)
        case .blue: return Color(red: 0.0, green: 0.04, blue: 0.10)
        }
    }

    var accent: Color {
        switch self {
        case .amber: return Color(red: 0.96, green: 0.62, blue: 0.04)
        case .blue: return Color(red: 0.20, green: 0.62, blue: 1.0)
        }
    }

    var green: Color { Color(red: 0.64, green: 0.90, blue: 0.21) }
    var cyan: Color { Color(red: 0.13, green: 0.83, blue: 0.93) }
    var red: Color { Color(red: 1.0, green: 0.20, blue: 0.20) }
    var text: Color { Color(red: 0.78, green: 0.78, blue: 0.76) }
    var muted: Color { Color(red: 0.48, green: 0.48, blue: 0.48) }
    var dim: Color { Color(red: 0.28, green: 0.28, blue: 0.28) }
    var border: Color { Color.white.opacity(0.08) }
}
