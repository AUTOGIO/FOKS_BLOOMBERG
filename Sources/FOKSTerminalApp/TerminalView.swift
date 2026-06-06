import FOKSTerminalCore
import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class TerminalStore {
    var snapshot: DashboardSnapshot = .empty
    var actions: [OperationalAction] = []
    var doneActionIDs: Set<OperationalAction.ID> = []
    var ignoredActionIDs: Set<OperationalAction.ID> = []
    var selectedProjectID: ProjectStatus.ID?
    var isRefreshing = false
    var isAnalyzing = false
    var runningCheckActionID: OperationalAction.ID?
    var runningAutomationID: AutomationSnapshot.ID?
    var runningAppID: AppBundleSnapshot.ID?
    var aiAnalysis: LocalAIAnalysis = .idle
    var checkResult: ReadOnlyCheckResult?
    var automationRunResult: AutomationRunResult?
    var trendPoints: [HealthTrendPoint] = []
    var telemetrySnapshot: MetricKitTelemetrySnapshot = .empty
    var startupServices: StartupServicesSnapshot = .idle
    var statusMessage = "Local read model ready - automation runs require button press"
    var isStartingServices = false

    private let reader = SystemReader()
    private let aiAdvisor = LocalAIAdvisor()
    private let cloudAIAdvisor = CloudAIAdvisor()
    private let startupServiceManager = StartupServiceManager()
    private let actionBuilder = ActionCenterBuilder()
    private let reportBuilder = DailyOpsReportBuilder()
    private let commandRunner = CommandRunner()
    private let telemetryCollector = MetricKitTelemetryCollector.shared
    private var launchMeasurementFinished = false

    init() {
        telemetrySnapshot = telemetryCollector.start()
    }

    var openActions: [OperationalAction] {
        actions.filter { !doneActionIDs.contains($0.id) && !ignoredActionIDs.contains($0.id) }
    }

    var selectedProject: ProjectStatus? {
        snapshot.projects.first { $0.id == selectedProjectID }
    }

    func startStartupServices() async {
        guard !isStartingServices else { return }
        isStartingServices = true
        statusMessage = "Starting local AI first, then Cloudflare Tunnel..."
        startupServices = await startupServiceManager.startConfiguredServices()
        statusMessage = "Startup services: \(startupServices.summary)"
        isStartingServices = false
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let telemetry = telemetryCollector.beginInterval(.dashboardRefresh)
        statusMessage = "Refreshing local read model..."
        let nextSnapshot = await reader.readDashboard()
        snapshot = nextSnapshot
        appendTrendPoint(for: nextSnapshot)
        actions = actionBuilder.build(snapshot: nextSnapshot)
        if selectedProjectID == nil || !nextSnapshot.projects.contains(where: { $0.id == selectedProjectID }) {
            selectedProjectID = nextSnapshot.projects.first?.id
        }
        telemetryCollector.endInterval(.dashboardRefresh, signpostID: telemetry)
        if !launchMeasurementFinished {
            telemetryCollector.finishLaunchMeasurement()
            launchMeasurementFinished = true
        }
        telemetrySnapshot = telemetryCollector.snapshot()
        statusMessage = "Local read model refreshed"
        isRefreshing = false
    }

    func analyze(provider: AIAnalysisProvider, localModel: String) async {
        guard !isAnalyzing else { return }
        if snapshot.refreshedAt == .distantPast {
            await refresh()
        }
        isAnalyzing = true
        let telemetry = telemetryCollector.beginInterval(.localAIAnalysis)
        switch provider {
        case .local:
            aiAnalysis = LocalAIAnalysis(provider: "Ollama", model: localModel, status: .running, text: "Sending local diagnostic bundle to \(localModel)...")
            statusMessage = "Local AI analysis running with \(localModel)..."
            aiAnalysis = await aiAdvisor.analyze(snapshot: snapshot, selectedProjectID: selectedProjectID, model: localModel)
        case .cloud:
            aiAnalysis = LocalAIAnalysis(provider: "Cloud AI", model: "configured environment model", status: .running, text: "Sending diagnostic bundle to the configured cloud AI endpoint...")
            statusMessage = "Cloud AI analysis running..."
            aiAnalysis = await cloudAIAdvisor.analyze(snapshot: snapshot, selectedProjectID: selectedProjectID)
        }
        telemetryCollector.endInterval(.localAIAnalysis, signpostID: telemetry)
        telemetrySnapshot = telemetryCollector.snapshot()
        let providerName = provider.displayName
        statusMessage = aiAnalysis.status == .ready ? "\(providerName) analysis ready - no fixes executed" : "\(providerName) analysis failed"
        isAnalyzing = false
    }

    func analyzeWithLocalAI(model: String) async {
        await analyze(provider: .local, localModel: model)
    }

    func runReadOnlyCheck(_ action: OperationalAction) async {
        guard runningCheckActionID == nil else { return }
        guard let check = action.check else {
            statusMessage = "No read-only check available for \(action.scope)"
            return
        }

        runningCheckActionID = action.id
        let telemetry = telemetryCollector.beginInterval(.readOnlyCheck)
        statusMessage = "Running read-only check: \(action.scope)"
        let result = await commandRunner.run(check.executable, check.arguments, timeout: check.timeoutSeconds)
        checkResult = ReadOnlyCheckResult(
            actionID: action.id,
            title: check.title,
            command: check.displayCommand,
            exitCode: result.exitCode,
            output: result.output,
            error: result.error,
            timedOut: result.timedOut
        )
        telemetryCollector.endInterval(.readOnlyCheck, signpostID: telemetry)
        telemetrySnapshot = telemetryCollector.snapshot()
        statusMessage = result.timedOut ? "Read-only check timed out: \(action.scope)" : "Read-only check complete: \(action.scope)"
        runningCheckActionID = nil
    }

    func syncProjects() async {
        let telemetry = telemetryCollector.beginInterval(.projectSync)
        do {
            let result = try ProjectConfigManager.syncDiscoveredProjects()
            statusMessage = result.message
            await refresh()
        } catch {
            statusMessage = "Project sync failed: \(error.localizedDescription)"
        }
        telemetryCollector.endInterval(.projectSync, signpostID: telemetry)
        telemetrySnapshot = telemetryCollector.snapshot()
    }

    func addManualProject(path: String, shortName: String, displayName: String, group: String) async {
        do {
            let result = try ProjectConfigManager.addProject(
                path: path,
                shortName: shortName,
                displayName: displayName,
                group: group
            )
            statusMessage = "Added project: \(result.added.first?.displayName ?? path)"
            await refresh()
            selectedProjectID = result.added.first?.id ?? selectedProjectID
        } catch {
            statusMessage = "Add project failed: \(error.localizedDescription)"
        }
    }

    func removeProject(_ project: ProjectStatus) async {
        do {
            let result = try ProjectConfigManager.removeProject(id: project.id)
            statusMessage = "Removed project from config: \(result.removed.first?.displayName ?? project.displayName)"
            selectedProjectID = nil
            await refresh()
        } catch {
            statusMessage = "Remove project failed: \(error.localizedDescription)"
        }
    }

    func runAutomation(_ automation: AutomationSnapshot) async {
        guard runningAutomationID == nil else { return }
        guard automation.canRun else {
            statusMessage = automation.runRequirement.isEmpty ? "Automation is not executable: \(automation.name)" : automation.runRequirement
            return
        }

        runningAutomationID = automation.id
        let telemetry = telemetryCollector.beginInterval(.automationRun)
        statusMessage = "Running automation: \(automation.name)"
        let result = await commandRunner.run(automation.runExecutable, automation.runArguments, timeout: 900)
        automationRunResult = AutomationRunResult(
            automationID: automation.id,
            name: automation.name,
            command: automation.displayCommand,
            exitCode: result.exitCode,
            output: result.output,
            error: result.error,
            timedOut: result.timedOut
        )
        let completionMessage = result.timedOut ? "Automation timed out: \(automation.name)" : "Automation complete: \(automation.name) exit \(result.exitCode)"
        runningAutomationID = nil
        telemetryCollector.endInterval(.automationRun, signpostID: telemetry)
        await refresh()
        telemetrySnapshot = telemetryCollector.snapshot()
        statusMessage = completionMessage
    }

    func runAppBundle(_ app: AppBundleSnapshot) async {
        guard runningAppID == nil else { return }
        runningAppID = app.id
        let telemetry = telemetryCollector.beginInterval(.appBundleOpen)
        statusMessage = "Opening app: \(app.name)"
        let result = await commandRunner.run(app.runExecutable, app.runArguments, timeout: 10)
        runningAppID = nil
        telemetryCollector.endInterval(.appBundleOpen, signpostID: telemetry)
        await refresh()
        telemetrySnapshot = telemetryCollector.snapshot()
        if result.exitCode == 0 {
            statusMessage = "App open request sent: \(app.name)"
        } else {
            let detail = result.combinedOutput.isEmpty ? "exit \(result.exitCode)" : result.combinedOutput
            statusMessage = "App open failed: \(detail)"
        }
    }

    func dailyOpsReport(format: ReportFormat) -> String {
        let summary = aiAnalysis.status == .ready ? aiAnalysis.text : nil
        switch format {
        case .markdown:
            return reportBuilder.build(snapshot: snapshot, actions: openActions, aiSummary: summary)
        case .plainText:
            return reportBuilder.buildPlainText(snapshot: snapshot, actions: openActions, aiSummary: summary)
        }
    }

    func markDone(_ action: OperationalAction) {
        doneActionIDs.insert(action.id)
        ignoredActionIDs.remove(action.id)
        statusMessage = "Marked done: \(action.scope)"
    }

    func ignore(_ action: OperationalAction) {
        ignoredActionIDs.insert(action.id)
        doneActionIDs.remove(action.id)
        statusMessage = "Ignored: \(action.scope)"
    }

    private func appendTrendPoint(for snapshot: DashboardSnapshot) {
        trendPoints.append(
            HealthTrendPoint(
                timestamp: snapshot.refreshedAt,
                globalHealthScore: snapshot.globalHealthScore,
                systemHealthScore: snapshot.system.healthScore,
                activeIssueCount: snapshot.activeIssueCount
            )
        )
        if trendPoints.count > 96 {
            trendPoints.removeFirst(trendPoints.count - 96)
        }
    }
}

enum CommandCenterSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case projects = "Projects"
    case system = "System"
    case appleMetrics = "Apple Metrics"
    case automations = "Automations"
    case apps = "Apps"
    case logs = "Logs"
    case actions = "Action Center"
    case fixQueue = "Fix Queue"
    case dailyReport = "Daily Report"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.bottom.50percent"
        case .projects: "folder.badge.gearshape"
        case .system: "desktopcomputer"
        case .appleMetrics: "chart.line.uptrend.xyaxis"
        case .automations: "play.rectangle.on.rectangle"
        case .apps: "macwindow"
        case .logs: "doc.text.magnifyingglass"
        case .actions: "exclamationmark.triangle"
        case .fixQueue: "wrench.and.screwdriver"
        case .dailyReport: "doc.plaintext"
        }
    }
}

enum ReportFormat: String, CaseIterable, Identifiable {
    case markdown = "Markdown"
    case plainText = "Plain Text"

    var id: String { rawValue }
}

struct TerminalView: View {
    @State private var store = TerminalStore()
    @State private var selectedSection: CommandCenterSection? = .dashboard
    @State private var showingAIReport = false
    @State private var showingCheckReport = false
    @State private var showingAutomationReport = false
    @AppStorage("foks.fontScale") private var fontScale = 1.0
    @AppStorage("foks.theme") private var themeName = TerminalTheme.graphite.rawValue
    @AppStorage("foks.localAIModel") private var localAIModel = "llama3.2:latest"
    @AppStorage("foks.aiAnalysisProvider") private var aiAnalysisProviderName = AIAnalysisProvider.local.rawValue

    private var theme: TerminalTheme {
        TerminalTheme(rawValue: themeName) ?? .graphite
    }

    private var selectedAIProvider: AIAnalysisProvider {
        AIAnalysisProvider(rawValue: aiAnalysisProviderName) ?? .local
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            VStack(spacing: 0) {
                topBar
                content
                bottomBar
            }
            .font(.system(size: 12 * fontScale, design: .monospaced))
            .foregroundStyle(theme.text)
            .background(theme.background)
        }
        .task {
            await store.startStartupServices()
            await store.refresh()
        }
        .sheet(isPresented: $showingAIReport) {
            AIReportView(analysis: store.aiAnalysis, theme: theme)
                .frame(minWidth: 760, minHeight: 620)
        }
        .sheet(isPresented: $showingCheckReport) {
            CheckReportView(result: store.checkResult, theme: theme)
                .frame(minWidth: 720, minHeight: 520)
        }
        .sheet(isPresented: $showingAutomationReport) {
            AutomationReportView(result: store.automationRunResult, theme: theme)
                .frame(minWidth: 720, minHeight: 520)
        }
    }

    private var sidebar: some View {
        List(selection: $selectedSection) {
            Section("FOKS") {
                ForEach(CommandCenterSection.allCases) { section in
                    SidebarSectionRow(
                        section: section,
                        status: sidebarStatus(for: section),
                        help: sidebarHelp(for: section),
                        theme: theme
                    )
                        .tag(Optional(section))
                        .help(sidebarHelp(for: section))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedSection ?? .dashboard {
        case .dashboard:
            DashboardCenterView(store: store, theme: theme, showAutomationReport: { showingAutomationReport = true })
        case .projects:
            ProjectsCenterView(store: store, theme: theme)
        case .system:
            SystemCenterView(snapshot: store.snapshot, theme: theme)
        case .appleMetrics:
            AppleMetricsCenterView(snapshot: store.telemetrySnapshot, theme: theme)
        case .automations:
            AutomationsCenterView(store: store, theme: theme, showRunReport: { showingAutomationReport = true })
        case .apps:
            AppsCenterView(store: store, theme: theme)
        case .logs:
            LogsCenterView(snapshot: store.snapshot, theme: theme)
        case .actions:
            ActionCenterView(store: store, theme: theme)
        case .fixQueue:
            FixQueueView(store: store, theme: theme, showCheckReport: { showingCheckReport = true })
        case .dailyReport:
            DailyReportView(store: store, theme: theme)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Label("FOKS Terminal", systemImage: "terminal")
                .foregroundStyle(theme.accent)
                .fontWeight(.black)
            ScorePill(label: "Global", score: store.snapshot.globalHealthScore, theme: theme)
            ScorePill(label: "System", score: store.snapshot.system.healthScore, theme: theme)
            Text(store.snapshot.refreshedAt == .distantPast ? "not refreshed" : store.snapshot.refreshedAt.formatted(date: .omitted, time: .standard))
                .foregroundStyle(theme.muted)
            Spacer()
            Picker("AI", selection: $aiAnalysisProviderName) {
                ForEach(AIAnalysisProvider.allCases, id: \.rawValue) { provider in
                    Label(provider.displayName, systemImage: provider.symbol)
                        .tag(provider.rawValue)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)
            .help("Choose whether Analyze uses local Ollama or the configured cloud AI endpoint.")
            if selectedAIProvider == .local {
                Picker("", selection: $localAIModel) {
                    Text("llama3.2").tag("llama3.2:latest")
                    Text("tinyllama").tag("tinyllama:1.1b")
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
            } else {
                Text("FOKS_CLOUD_AI_*")
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.cyan)
                    .help("Cloud AI uses FOKS_CLOUD_AI_ENDPOINT, FOKS_CLOUD_AI_API_KEY, and FOKS_CLOUD_AI_MODEL from the app environment. Keys are not stored.")
            }
            Button {
                Task {
                    await store.analyze(provider: selectedAIProvider, localModel: localAIModel)
                    showingAIReport = true
                }
            } label: {
                Label(store.isAnalyzing ? "Analyzing" : "Analyze", systemImage: selectedAIProvider.symbol)
            }
            .disabled(store.isAnalyzing || store.isRefreshing || store.runningAutomationID != nil || store.runningAppID != nil)
            Button {
                Task { await store.refresh() }
            } label: {
                Label(store.isRefreshing ? "Refreshing" : "Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(store.isRefreshing || store.runningAutomationID != nil || store.runningAppID != nil)
            Button("A-") { fontScale = max(0.85, fontScale - 0.1) }
            Button("A+") { fontScale = min(1.35, fontScale + 0.1) }
            Picker("", selection: $themeName) {
                ForEach(TerminalTheme.allCases) { theme in
                    Text(theme.rawValue).tag(theme.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(theme.topBackground)
        .overlay(Rectangle().fill(theme.border).frame(height: 1), alignment: .bottom)
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Text("MANUAL OPS")
                .foregroundStyle(theme.green)
                .fontWeight(.black)
            Text(store.statusMessage)
                .foregroundStyle(store.isRefreshing || store.isAnalyzing || store.isStartingServices || store.runningCheckActionID != nil || store.runningAutomationID != nil || store.runningAppID != nil ? theme.cyan : theme.muted)
            Spacer()
            Text(selectedAIProvider.footerText + " | AI advice only | explicit checks, app opens, and manual automation runs")
                .foregroundStyle(theme.dim)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(theme.panel)
        .overlay(Rectangle().fill(theme.border).frame(height: 1), alignment: .top)
    }

    private func sidebarStatus(for section: CommandCenterSection) -> String {
        let hasSnapshot = store.snapshot.refreshedAt != .distantPast
        switch section {
        case .dashboard:
            return hasSnapshot ? "\(store.snapshot.globalHealthScore)" : "WAIT"
        case .projects:
            return "\(store.snapshot.projects.count)"
        case .system:
            return systemAvailabilityStatus
        case .appleMetrics:
            return store.telemetrySnapshot.status
        case .automations:
            return "\(store.snapshot.automations.filter(\.isRunning).count)/\(store.snapshot.automations.count)"
        case .apps:
            return "\(store.snapshot.appBundles.filter(\.isRunning).count)/\(store.snapshot.appBundles.count)"
        case .logs:
            return "\(store.snapshot.logs.filter { ["INCIDENT", "ERROR", "WARN"].contains($0.level) }.count)"
        case .actions:
            return "\(store.openActions.count)"
        case .fixQueue:
            return "\(store.openActions.filter { !$0.manualCommands.isEmpty || $0.check != nil }.count)"
        case .dailyReport:
            return hasSnapshot ? "READY" : "WAIT"
        }
    }

    private var systemAvailabilityStatus: String {
        let available = [
            store.snapshot.system.cpuAvailable,
            store.snapshot.system.memoryAvailable,
            store.snapshot.system.diskAvailable
        ].filter { $0 }.count
        return "\(available)/3"
    }

    private func sidebarHelp(for section: CommandCenterSection) -> String {
        switch section {
        case .dashboard:
            return "Dashboard uses the latest local snapshot: global health, active issues, incidents, projects, automations, apps, and live system signals."
        case .projects:
            return "Projects reads config/projects.json and current git state; missing paths stay explicit."
        case .system:
            return "System reads local ps, memory_pressure/vm_stat, df, netstat, sw_vers, sysctl, and launchctl output."
        case .appleMetrics:
            return "Apple Metrics shows MetricKit subscriber state and locally stored payload counts only."
        case .automations:
            return "Automations lists discovered local scripts and exposes manual run buttons only when the script is directly executable."
        case .apps:
            return "Apps lists discovered local .app bundles and opens them through explicit /usr/bin/open arguments."
        case .logs:
            return "Logs shows real allowlisted local log entries with searchable severity, category, project, and time filters."
        case .actions:
            return "Action Center is rebuilt from the latest snapshot and contains prioritized manual recommendations."
        case .fixQueue:
            return "Fix Queue exposes copy-only manual command cards and read-only checks with explicit binaries."
        case .dailyReport:
            return "Daily Report renders the current snapshot and any ready local AI analysis into Markdown or plain text."
        }
    }
}

struct DashboardCenterView: View {
    let store: TerminalStore
    let theme: TerminalTheme
    let showAutomationReport: () -> Void

    private var criticalActions: [OperationalAction] {
        store.openActions.filter { $0.severity == .critical }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ModuleHeader(title: "Dashboard", detail: "Operational overview", theme: theme)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                    MetricTile(title: "Global Health", value: "\(store.snapshot.globalHealthScore)", detail: "score", color: scoreColor(store.snapshot.globalHealthScore), comment: "Computed every refresh from real project scores and available system metrics, with penalties for failed launch services and severe logs.", theme: theme)
                    MetricTile(title: "Active Issues", value: "\(store.snapshot.activeIssueCount)", detail: "snapshot", color: store.snapshot.activeIssueCount == 0 ? theme.green : theme.accent, comment: "Counts non-clean projects, failed launch services, severe logs, and available CPU/memory/disk signals above warning thresholds.", theme: theme)
                    MetricTile(title: "Projects", value: "\(store.snapshot.projects.count)", detail: "\(cleanProjectCount) clean", color: theme.cyan, comment: "Read from config/projects.json, then updated with current git status and local path checks.", theme: theme)
                    MetricTile(title: "Actions", value: "\(store.openActions.count)", detail: "\(criticalActions.count) critical", color: criticalActions.isEmpty ? theme.green : theme.red, comment: "Open Action Center cards after filtering items marked Done or Ignored in this session.", theme: theme)
                    MetricTile(title: "CPU", value: percent(store.snapshot.system.cpuPercent, available: store.snapshot.system.cpuAvailable), detail: store.snapshot.system.cpuAvailable ? "current" : "unavailable", color: systemColor(store.snapshot.system.cpuPercent, available: store.snapshot.system.cpuAvailable), comment: "Derived from /bin/ps CPU samples normalized by logical core count.", theme: theme)
                    MetricTile(title: "Memory", value: percent(store.snapshot.system.memoryUsedPercent, available: store.snapshot.system.memoryAvailable), detail: store.snapshot.system.memoryAvailable ? "used" : "unavailable", color: systemColor(store.snapshot.system.memoryUsedPercent, available: store.snapshot.system.memoryAvailable), comment: "Derived from memory_pressure when available, with vm_stat fallback clearly treated as local runtime data.", theme: theme)
                    MetricTile(title: "Disk", value: percent(store.snapshot.system.diskUsedPercent, available: store.snapshot.system.diskAvailable), detail: store.snapshot.system.diskAvailable ? ByteFormatter.memoryString(bytes: store.snapshot.system.diskFreeBytes) + " free" : "unavailable", color: systemColor(store.snapshot.system.diskUsedPercent, available: store.snapshot.system.diskAvailable), comment: "Derived from /bin/df -k / for the startup volume.", theme: theme)
                    MetricTile(title: "Incidents", value: "\(store.snapshot.incidents.count)", detail: "aggregated", color: store.snapshot.incidents.isEmpty ? theme.green : theme.red, comment: "Aggregated from missing projects, failed launch services, severe logs, and critical system pressure in the current snapshot.", theme: theme)
                    MetricTile(title: "Trend", value: trendSummary, detail: "\(store.trendPoints.count) refreshes", color: trendColor, comment: "In-memory delta across refreshes in this app session; no historical values are invented.", theme: theme)
                    MetricTile(title: "Automations", value: "\(store.snapshot.automations.count)", detail: "\(runningAutomationCount) running", color: runningAutomationCount == 0 ? theme.cyan : theme.green, comment: "Discovered local scripts under the configured automation root, with running state from process matching.", theme: theme)
                    MetricTile(title: "Apps", value: "\(store.snapshot.appBundles.count)", detail: "\(runningAppCount) running", color: runningAppCount == 0 ? theme.cyan : theme.green, comment: "Discovered local .app bundles from configured projects and user app folders.", theme: theme)
                }

                StartupServicesBlock(snapshot: store.startupServices, theme: theme)

                AutomationListBlock(
                    store: store,
                    theme: theme,
                    title: "Automation Runner",
                    detail: "\(NSHomeDirectory())/Developer/automation",
                    showRunReport: showAutomationReport
                )

                AppBundleListBlock(
                    store: store,
                    theme: theme,
                    title: "App Runner",
                    detail: "Local .app bundles"
                )

                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("Recent Incidents", right: "\(store.snapshot.incidents.count)", color: store.snapshot.incidents.isEmpty ? theme.green : theme.red, theme: theme)
                        if store.snapshot.incidents.isEmpty {
                            EmptyState("No critical incidents in the current snapshot.", theme: theme)
                        } else {
                            ForEach(store.snapshot.incidents.prefix(6)) { incident in
                                IncidentRow(incident: incident, theme: theme)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("AI Insights", right: store.aiAnalysis.status.rawValue, color: color(for: store.aiAnalysis.status), theme: theme)
                        Text(store.aiAnalysis.text)
                            .foregroundStyle(color(for: store.aiAnalysis.status))
                            .textSelection(.enabled)
                            .lineLimit(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                SectionHeader("Project Status Overview", right: "\(store.snapshot.projects.count)", color: theme.cyan, theme: theme)
                ForEach(store.snapshot.projects.prefix(8)) { project in
                    ProjectCompactRow(project: project, theme: theme)
                }
            }
            .padding(18)
        }
    }

    private var cleanProjectCount: Int {
        store.snapshot.projects.filter { $0.health == .clean }.count
    }

    private var runningAutomationCount: Int {
        store.snapshot.automations.filter(\.isRunning).count
    }

    private var runningAppCount: Int {
        store.snapshot.appBundles.filter(\.isRunning).count
    }

    private var trendSummary: String {
        guard let first = store.trendPoints.first, let last = store.trendPoints.last, store.trendPoints.count > 1 else {
            return "flat"
        }
        let delta = last.globalHealthScore - first.globalHealthScore
        if delta > 0 { return "+\(delta)" }
        return "\(delta)"
    }

    private var trendColor: Color {
        guard let first = store.trendPoints.first, let last = store.trendPoints.last, store.trendPoints.count > 1 else {
            return theme.muted
        }
        let delta = last.globalHealthScore - first.globalHealthScore
        if delta > 0 { return theme.green }
        if delta < 0 { return theme.red }
        return theme.muted
    }

    private func percent(_ value: Double, available: Bool) -> String {
        available ? String(format: "%.0f%%", value) : "-"
    }

    private func systemColor(_ value: Double, available: Bool) -> Color {
        guard available else { return theme.muted }
        return value >= 90 ? theme.red : value >= 75 ? theme.accent : theme.green
    }

    private func scoreColor(_ score: Int) -> Color {
        score >= 85 ? theme.green : score >= 65 ? theme.accent : theme.red
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

private extension AIAnalysisProvider {
    var symbol: String {
        switch self {
        case .local: "brain"
        case .cloud: "cloud"
        }
    }

    var footerText: String {
        switch self {
        case .local: "Ollama 127.0.0.1:11434"
        case .cloud: "Cloud AI via FOKS_CLOUD_AI_* environment"
        }
    }
}

struct ProjectsCenterView: View {
    @Bindable var store: TerminalStore
    let theme: TerminalTheme

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                ModuleHeader(title: "Projects Center", detail: "Inventory and repository health", theme: theme)
                List(selection: $store.selectedProjectID) {
                    ForEach(store.snapshot.projects) { project in
                        ProjectListRow(project: project, theme: theme)
                            .tag(project.id)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .frame(minWidth: 330, idealWidth: 390)

            ScrollView {
                ProjectManagementBlock(store: store, theme: theme)
                    .padding(.horizontal, 18)
                    .padding(.top, 18)

                if let project = store.selectedProject {
                    ProjectDetailView(project: project, theme: theme)
                        .padding(18)
                } else {
                    EmptyState("No project selected.", theme: theme)
                        .padding(18)
                }
            }
            .frame(minWidth: 520)
        }
    }
}

struct ProjectManagementBlock: View {
    @Bindable var store: TerminalStore
    let theme: TerminalTheme
    @State private var manualPath = ""
    @State private var manualShortName = ""
    @State private var manualDisplayName = ""
    @State private var manualGroup = "MANUAL"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Project Config", right: ProjectConfigLoader.defaultConfigPath, color: theme.cyan, theme: theme)
            HStack(spacing: 10) {
                Button {
                    Task { await store.syncProjects() }
                } label: {
                    Label("Auto Sync", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("Scan ~/Documents/GitHub for Git repositories, add new ones, and remove missing configured paths.")

                Button {
                    if let project = store.selectedProject {
                        Task { await store.removeProject(project) }
                    }
                } label: {
                    Label("Remove Selected", systemImage: "minus.circle")
                }
                .disabled(store.selectedProject == nil)
                .help("Remove the selected project from config only. The folder is not deleted.")

                Spacer()
                Text("\(store.snapshot.projects.count) active")
                    .foregroundStyle(theme.muted)
            }
            .buttonStyle(.bordered)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Path").foregroundStyle(theme.muted).frame(width: 70, alignment: .leading)
                    TextField("/absolute/project/path", text: $manualPath)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Name").foregroundStyle(theme.muted).frame(width: 70, alignment: .leading)
                    TextField("Display name", text: $manualDisplayName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Short", text: $manualShortName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    TextField("Group", text: $manualGroup)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Button {
                        let path = manualPath
                        let shortName = manualShortName
                        let displayName = manualDisplayName
                        let group = manualGroup
                        Task {
                            await store.addManualProject(
                                path: path,
                                shortName: shortName,
                                displayName: displayName,
                                group: group
                            )
                            if !store.statusMessage.localizedCaseInsensitiveContains("failed") {
                                manualPath = ""
                                manualShortName = ""
                                manualDisplayName = ""
                                manualGroup = "MANUAL"
                            }
                        }
                    } label: {
                        Label("Add", systemImage: "plus.circle")
                    }
                    .disabled(manualPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
    }
}

struct ProjectListRow: View {
    let project: ProjectStatus
    let theme: TerminalTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(project.shortName)
                    .foregroundStyle(color(for: project.health))
                    .fontWeight(.black)
                Text(project.group)
                    .foregroundStyle(theme.muted)
                Spacer()
                Text("\(project.healthScore)")
                    .foregroundStyle(scoreColor(project.healthScore))
                    .fontWeight(.bold)
            }
            Text(project.displayName)
                .foregroundStyle(theme.text)
                .lineLimit(1)
            Text(project.reason)
                .foregroundStyle(color(for: project.health))
                .lineLimit(1)
            Text(project.path)
                .foregroundStyle(theme.dim)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 5)
    }

    private func color(for health: ProjectStatus.Health) -> Color {
        healthColor(health, theme: theme)
    }

    private func scoreColor(_ score: Int) -> Color {
        score >= 85 ? theme.green : score >= 65 ? theme.accent : theme.red
    }
}

struct ProjectDetailView: View {
    let project: ProjectStatus
    let theme: TerminalTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(project.displayName)
                    .font(.title2)
                    .foregroundStyle(theme.text)
                    .fontWeight(.bold)
                Spacer()
                ScorePill(label: "Project", score: project.healthScore, theme: theme)
            }

            SectionHeader("Repository", right: project.health.rawValue, color: healthColor(project.health, theme: theme), theme: theme)
            DetailGrid(rows: [
                ("Path", project.path),
                ("Branch", project.branch),
                ("Reason", project.reason),
                ("Remote", project.remoteURL.isEmpty ? "none" : project.remoteURL),
                ("Dirty files", "\(project.dirtyFiles)"),
                ("Ahead / Behind", "\(project.ahead) / \(project.behind)"),
                ("Last activity", project.lastActivity?.formatted(date: .abbreviated, time: .shortened) ?? "unknown")
            ], theme: theme)

            SectionHeader("Repository Warnings", right: "\(project.warnings.count)", color: project.warnings.isEmpty ? theme.green : theme.accent, theme: theme)
            if project.warnings.isEmpty {
                EmptyState("No repository warnings.", theme: theme)
            } else {
                ForEach(project.warnings, id: \.self) { warning in
                    Text(warning)
                        .foregroundStyle(theme.accent)
                        .textSelection(.enabled)
                }
            }

            SectionHeader("Missing Dependencies", right: "\(project.missingDependencies.count)", color: project.missingDependencies.isEmpty ? theme.green : theme.accent, theme: theme)
            if project.missingDependencies.isEmpty {
                EmptyState("No missing dependency markers detected.", theme: theme)
            } else {
                ForEach(project.missingDependencies, id: \.self) { dependency in
                    Text(dependency)
                        .foregroundStyle(theme.accent)
                        .textSelection(.enabled)
                }
            }

            SectionHeader("Dirty File Preview", right: "\(project.dirtyFiles)", color: project.dirtyFiles == 0 ? theme.green : theme.accent, theme: theme)
            if project.dirtyItems.isEmpty {
                EmptyState("No dirty files in preview.", theme: theme)
            } else {
                ForEach(project.dirtyItems, id: \.self) { item in
                    Text(item)
                        .foregroundStyle(theme.muted)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SystemCenterView: View {
    let snapshot: DashboardSnapshot
    let theme: TerminalTheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ModuleHeader(title: "System Center", detail: "Local diagnostics and launchd inspection", theme: theme)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                    MetricTile(title: "CPU", value: percent(snapshot.system.cpuPercent, available: snapshot.system.cpuAvailable), detail: snapshot.system.cpuAvailable ? "ps normalized" : "unavailable", color: pressureColor(snapshot.system.cpuPercent, available: snapshot.system.cpuAvailable), comment: "Read from /bin/ps and normalized by hw.logicalcpu.", theme: theme)
                    MetricTile(title: "Memory", value: percent(snapshot.system.memoryUsedPercent, available: snapshot.system.memoryAvailable), detail: snapshot.system.memoryAvailable ? ByteFormatter.memoryString(bytes: snapshot.system.memoryUsedBytes) : "unavailable", color: pressureColor(snapshot.system.memoryUsedPercent, available: snapshot.system.memoryAvailable), comment: "Read from /usr/bin/memory_pressure with /usr/bin/vm_stat fallback when needed.", theme: theme)
                    MetricTile(title: "Storage", value: percent(snapshot.system.diskUsedPercent, available: snapshot.system.diskAvailable), detail: snapshot.system.diskAvailable ? ByteFormatter.memoryString(bytes: snapshot.system.diskFreeBytes) + " free" : "unavailable", color: pressureColor(snapshot.system.diskUsedPercent, available: snapshot.system.diskAvailable), comment: "Read from /bin/df -k / and shown unavailable if parsing fails.", theme: theme)
                    MetricTile(title: "Network In", value: snapshot.system.networkAvailable ? ByteFormatter.memoryString(bytes: snapshot.system.networkReceivedBytes) : "-", detail: snapshot.system.networkAvailable ? "netstat bytes" : "unavailable", color: snapshot.system.networkAvailable ? theme.cyan : theme.muted, comment: "Read from /usr/sbin/netstat -ibn byte counters.", theme: theme)
                    MetricTile(title: "Network Out", value: snapshot.system.networkAvailable ? ByteFormatter.memoryString(bytes: snapshot.system.networkTransmittedBytes) : "-", detail: snapshot.system.networkAvailable ? "netstat bytes" : "unavailable", color: snapshot.system.networkAvailable ? theme.cyan : theme.muted, comment: "Read from /usr/sbin/netstat -ibn byte counters.", theme: theme)
                    MetricTile(title: "Uptime", value: snapshot.system.uptimeAvailable ? snapshot.system.uptime : "-", detail: snapshot.system.uptimeAvailable ? "local" : "unavailable", color: snapshot.system.uptimeAvailable ? theme.green : theme.muted, comment: "Read from /usr/bin/uptime; unavailable is shown when the command returns no usable output.", theme: theme)
                }

                SectionHeader("Hardware", right: snapshot.hardware.targetProfile, color: theme.cyan, theme: theme)
                DetailGrid(rows: [
                    ("Model", snapshot.hardware.modelIdentifier),
                    ("Chip", snapshot.hardware.chip),
                    ("Cores", snapshot.hardware.coreSummary),
                    ("Memory", snapshot.hardware.memory),
                    ("OS", snapshot.hardware.osVersion),
                    ("Uptime", snapshot.hardware.uptime)
                ], theme: theme)

                SectionHeader("Running Processes", right: "\(snapshot.processes.count)", color: theme.green, theme: theme)
                Table(snapshot.processes) {
                    TableColumn("PID") { Text($0.pid).foregroundStyle(theme.muted) }.width(70)
                    TableColumn("CPU") { Text($0.cpu).foregroundStyle(theme.green) }.width(80)
                    TableColumn("Memory") { Text($0.memory).foregroundStyle(theme.cyan) }.width(90)
                    TableColumn("Command") { Text($0.command).foregroundStyle(theme.text) }
                }
                .frame(minHeight: 170)

                launchTable("Launch Agents", services: snapshot.launchAgents)
                launchTable("Launch Daemons", services: snapshot.launchDaemons)
            }
            .padding(18)
        }
    }

    private func launchTable(_ title: String, services: [LaunchAgentSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title, right: "\(services.count)", color: services.contains(where: { $0.health == .failed }) ? theme.red : theme.accent, theme: theme)
            Table(services) {
                TableColumn("Health") { service in
                    Text(service.health.rawValue).foregroundStyle(launchColor(service.health))
                }
                .width(100)
                TableColumn("State") { Text($0.state).foregroundStyle(theme.text) }.width(130)
                TableColumn("Label") { Text($0.label).foregroundStyle(theme.text) }
                TableColumn("Reason") { Text($0.reason).foregroundStyle(theme.muted) }
            }
            .frame(minHeight: 150)
        }
    }

    private func percent(_ value: Double, available: Bool) -> String {
        available ? String(format: "%.0f%%", value) : "-"
    }

    private func pressureColor(_ value: Double, available: Bool) -> Color {
        guard available else { return theme.muted }
        return value >= 90 ? theme.red : value >= 75 ? theme.accent : theme.green
    }

    private func launchColor(_ health: LaunchAgentSnapshot.Health) -> Color {
        switch health {
        case .running: theme.green
        case .scheduled: theme.cyan
        case .failed: theme.red
        case .stopped: theme.accent
        case .unknown: theme.muted
        }
    }
}

struct AppleMetricsCenterView: View {
    let snapshot: MetricKitTelemetrySnapshot
    let theme: TerminalTheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ModuleHeader(title: "Apple Metrics", detail: "MetricKit payloads, diagnostics, and signposts", theme: theme)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                    MetricTile(title: "MetricKit", value: snapshot.status, detail: snapshot.isRegistered ? "subscriber active" : "not registered", color: statusColor, theme: theme)
                    MetricTile(title: "Metric Payloads", value: "\(snapshot.storedMetricPayloads)", detail: "\(snapshot.deliveredMetricPayloads) delivered", color: snapshot.storedMetricPayloads == 0 ? theme.muted : theme.green, theme: theme)
                    MetricTile(title: "Diagnostics", value: "\(snapshot.storedDiagnosticPayloads)", detail: "\(snapshot.deliveredDiagnosticPayloads) delivered", color: snapshot.storedDiagnosticPayloads == 0 ? theme.muted : theme.accent, theme: theme)
                    MetricTile(title: "Past Reports", value: "\(snapshot.pastMetricPayloads + snapshot.pastDiagnosticPayloads)", detail: "MetricKit cache", color: snapshot.pastMetricPayloads + snapshot.pastDiagnosticPayloads == 0 ? theme.muted : theme.cyan, theme: theme)
                    MetricTile(title: "Launch Task", value: snapshot.launchMeasurementState, detail: "extended launch", color: launchColor, theme: theme)
                    MetricTile(title: "Signposts", value: "7", detail: snapshot.signpostCategory, color: theme.cyan, theme: theme)
                }

                SectionHeader("Local Storage", right: snapshot.storagePath, color: theme.cyan, theme: theme)
                DetailGrid(rows: [
                    ("Runtime", snapshot.isRuntimeAvailable ? "available" : "unavailable"),
                    ("Registered", snapshot.isRegistered ? "yes" : "no"),
                    ("Metric latest", formatDate(snapshot.lastMetricPayloadAt)),
                    ("Diagnostic latest", formatDate(snapshot.lastDiagnosticPayloadAt)),
                    ("Last write", formatDate(snapshot.lastWriteAt)),
                    ("Launch detail", snapshot.launchMeasurementError ?? "none"),
                    ("Metric file", snapshot.latestMetricPayloadPath ?? "none"),
                    ("Diagnostic file", snapshot.latestDiagnosticPayloadPath ?? "none"),
                    ("Last error", snapshot.lastError ?? "none")
                ], theme: theme)

                SectionHeader("Instrumented Critical Paths", right: snapshot.signpostCategory, color: theme.accent, theme: theme)
                DetailGrid(rows: [
                    ("Launch", "AppLaunch + FOKSTerminalInitialRefresh"),
                    ("Refresh", "DashboardRefresh"),
                    ("AI", "LocalAIAnalysis"),
                    ("Checks", "ReadOnlyCheck"),
                    ("Automation", "AutomationRun"),
                    ("Apps", "AppBundleOpen"),
                    ("Projects", "ProjectSync")
                ], theme: theme)
            }
            .padding(18)
        }
    }

    private var statusColor: Color {
        switch snapshot.status {
        case "COLLECTING": theme.green
        case "WAITING": theme.cyan
        case "ERROR": theme.red
        default: theme.muted
        }
    }

    private var launchColor: Color {
        if snapshot.launchMeasurementState == "finished" { return theme.green }
        if snapshot.launchMeasurementState == "active" { return theme.cyan }
        if snapshot.launchMeasurementState.localizedCaseInsensitiveContains("failed") { return theme.red }
        return theme.muted
    }

    private func formatDate(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .standard) ?? "none"
    }
}

struct AutomationsCenterView: View {
    @Bindable var store: TerminalStore
    let theme: TerminalTheme
    let showRunReport: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ModuleHeader(title: "Automations", detail: "Local scripts and manual run controls", theme: theme)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    MetricTile(title: "Configured", value: "\(store.snapshot.automations.count)", detail: "scripts", color: theme.cyan, theme: theme)
                    MetricTile(title: "Running", value: "\(runningCount)", detail: "process match", color: runningCount == 0 ? theme.muted : theme.green, theme: theme)
                    MetricTile(title: "Runnable", value: "\(runnableCount)", detail: "no required args", color: runnableCount == 0 ? theme.accent : theme.green, theme: theme)
                }

                AutomationListBlock(
                    store: store,
                    theme: theme,
                    title: "Automation Inventory",
                    detail: "\(NSHomeDirectory())/Developer/automation",
                    showRunReport: showRunReport
                )
            }
            .padding(18)
        }
    }

    private var runningCount: Int {
        store.snapshot.automations.filter(\.isRunning).count
    }

    private var runnableCount: Int {
        store.snapshot.automations.filter(\.canRun).count
    }
}

struct AppsCenterView: View {
    @Bindable var store: TerminalStore
    let theme: TerminalTheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ModuleHeader(title: "Apps", detail: "Discovered local .app bundles", theme: theme)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    MetricTile(title: "Discovered", value: "\(store.snapshot.appBundles.count)", detail: ".app bundles", color: theme.cyan, theme: theme)
                    MetricTile(title: "Running", value: "\(runningCount)", detail: "process match", color: runningCount == 0 ? theme.muted : theme.green, theme: theme)
                    MetricTile(title: "Native", value: "\(nativeCount)", detail: "bundle type", color: theme.green, theme: theme)
                }

                AppBundleListBlock(
                    store: store,
                    theme: theme,
                    title: "App Runner",
                    detail: "Native and web .app bundles"
                )
            }
            .padding(18)
        }
    }

    private var runningCount: Int {
        store.snapshot.appBundles.filter(\.isRunning).count
    }

    private var nativeCount: Int {
        store.snapshot.appBundles.filter { $0.kind == "NATIVE APP" }.count
    }
}

struct AppBundleListBlock: View {
    @Bindable var store: TerminalStore
    let theme: TerminalTheme
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title, right: detail, color: theme.cyan, theme: theme)
            if store.snapshot.appBundles.isEmpty {
                EmptyState("No .app bundles found in configured projects or ~/Applications.", theme: theme)
            } else {
                ForEach(store.snapshot.appBundles) { app in
                    AppBundleCard(
                        app: app,
                        theme: theme,
                        isOpening: store.runningAppID == app.id,
                        run: {
                            Task { await store.runAppBundle(app) }
                        }
                    )
                }
            }
        }
    }
}

struct StartupServicesBlock: View {
    let snapshot: StartupServicesSnapshot
    let theme: TerminalTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Startup Services", right: snapshot.status, color: statusColor(snapshot.status), theme: theme)
            ForEach(snapshot.services) { service in
                HStack(alignment: .top, spacing: 10) {
                    Text(service.state.rawValue)
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(color(for: service.state))
                        .frame(width: 86, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(service.kind.displayName)
                            .foregroundStyle(theme.text)
                            .fontWeight(.bold)
                        Text(service.detail)
                            .foregroundStyle(theme.muted)
                            .textSelection(.enabled)
                        if !service.command.isEmpty {
                            Text(service.command)
                                .foregroundStyle(theme.dim)
                                .textSelection(.enabled)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                }
                .padding(10)
                .background(theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
            }
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "RUNNING": theme.green
        case "FAILED": theme.red
        case "DISABLED": theme.muted
        default: theme.cyan
        }
    }

    private func color(for state: StartupServiceState) -> Color {
        switch state {
        case .running: theme.green
        case .failed: theme.red
        case .disabled: theme.muted
        case .waiting: theme.cyan
        }
    }
}

struct AppBundleCard: View {
    let app: AppBundleSnapshot
    let theme: TerminalTheme
    let isOpening: Bool
    let run: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Text(app.isRunning ? "RUNNING" : "IDLE")
                    .foregroundStyle(app.isRunning ? theme.green : theme.muted)
                    .fontWeight(.black)
                    .frame(width: 82, alignment: .leading)
                Text(app.name)
                    .foregroundStyle(theme.text)
                    .fontWeight(.bold)
                Text(app.kind)
                    .foregroundStyle(theme.cyan)
                Spacer()
                Button {
                    run()
                } label: {
                    Label(isOpening ? "Opening" : "Run", systemImage: "play.fill")
                }
                .disabled(isOpening)
                .help(app.displayCommand)
            }
            .buttonStyle(.bordered)

            DetailGrid(rows: [
                ("Path", app.path),
                ("Bundle ID", app.bundleIdentifier),
                ("Executable", app.executablePath),
                ("Modified", app.modifiedAt?.formatted(date: .abbreviated, time: .shortened) ?? "unknown"),
                ("Command", app.displayCommand)
            ], theme: theme)
        }
        .padding(12)
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
    }
}

struct AutomationListBlock: View {
    @Bindable var store: TerminalStore
    let theme: TerminalTheme
    let title: String
    let detail: String
    let showRunReport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title, right: detail, color: theme.cyan, theme: theme)
            if store.snapshot.automations.isEmpty {
                EmptyState("No automation scripts found at \(detail).", theme: theme)
            } else {
                ForEach(store.snapshot.automations) { automation in
                    AutomationCard(
                        automation: automation,
                        theme: theme,
                        isRunning: store.runningAutomationID == automation.id,
                        run: {
                            Task {
                                await store.runAutomation(automation)
                                if store.automationRunResult?.automationID == automation.id {
                                    showRunReport()
                                }
                            }
                        }
                    )
                }
            }
        }
    }
}

struct AutomationCard: View {
    let automation: AutomationSnapshot
    let theme: TerminalTheme
    let isRunning: Bool
    let run: () -> Void

    private var running: Bool {
        automation.isRunning || isRunning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Text(running ? "RUNNING" : "IDLE")
                    .foregroundStyle(running ? theme.green : theme.muted)
                    .fontWeight(.black)
                    .frame(width: 82, alignment: .leading)
                Text(automation.name)
                    .foregroundStyle(theme.text)
                    .fontWeight(.bold)
                Text(automation.scriptType)
                    .foregroundStyle(theme.cyan)
                Spacer()
                Button {
                    run()
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .disabled(!automation.canRun || running)
                .help(runHelp)
            }
            .buttonStyle(.bordered)

            Text(automation.purpose)
                .foregroundStyle(theme.accent)
                .textSelection(.enabled)

            DetailGrid(rows: [
                ("Script", automation.path),
                ("Purpose", automation.purpose),
                ("Log path", automation.logPath),
                ("Last run", formatDate(automation.lastRunAt)),
                ("Modified", formatDate(automation.modifiedAt)),
                ("Run mode", automation.canRun ? "manual button" : runHelp)
            ], theme: theme)
        }
        .padding(12)
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
    }

    private var runHelp: String {
        if !automation.isExecutable {
            return "Script is not executable."
        }
        if !automation.runRequirement.isEmpty {
            return automation.runRequirement
        }
        return "Run \(automation.name) now."
    }

    private func formatDate(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .shortened) ?? "unknown"
    }
}

struct LogsCenterView: View {
    let snapshot: DashboardSnapshot
    let theme: TerminalTheme
    @State private var query = ""
    @State private var level = "ACTIONABLE"
    @State private var category = "ALL"
    @State private var projectID = "ALL"
    @State private var timeFilter = "24H"

    private let levels = ["ACTIONABLE", "INCIDENT", "ERROR", "WARN", "INFO", "ALL"]
    private let categories = ["ALL"] + LogCategory.allCases.map(\.rawValue)
    private let timeFilters = ["1H", "24H", "ALL"]

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(title: "Logs Center", detail: "Searchable actionable log view", theme: theme)
            HStack(spacing: 10) {
                TextField("Search logs", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 260)
                Picker("Severity", selection: $level) {
                    ForEach(levels, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 170)
                Picker("Category", selection: $category) {
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 150)
                Picker("Project", selection: $projectID) {
                    Text("ALL").tag("ALL")
                    ForEach(snapshot.projects) { project in
                        Text(project.shortName).tag(project.id)
                    }
                }
                .frame(width: 150)
                Picker("Time", selection: $timeFilter) {
                    ForEach(timeFilters, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 120)
                Spacer()
                Text("\(filteredLogs.count) shown")
                    .foregroundStyle(theme.muted)
            }
            .padding(12)
            .background(theme.panel)

            if filteredLogs.isEmpty {
                EmptyState("No logs match the current filters.", theme: theme)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredLogs) { log in
                    LogEntryRow(log: log, theme: theme)
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var filteredLogs: [LogEntry] {
        let cutoff: Date? = {
            switch timeFilter {
            case "1H": Date().addingTimeInterval(-3600)
            case "24H": Date().addingTimeInterval(-86400)
            default: nil
            }
        }()

        return snapshot.logs.filter { log in
            if let cutoff, log.timestamp < cutoff { return false }
            if level == "ACTIONABLE", !["INCIDENT", "ERROR", "WARN"].contains(log.level) { return false }
            if level != "ALL", level != "ACTIONABLE", log.level != level { return false }
            if category != "ALL", log.category.rawValue != category { return false }
            if projectID != "ALL", log.projectID != projectID { return false }
            if !query.isEmpty {
                let haystack = "\(log.source) \(log.message) \(log.level)".lowercased()
                if !haystack.contains(query.lowercased()) { return false }
            }
            return true
        }
    }
}

struct ActionCenterView: View {
    @Bindable var store: TerminalStore
    let theme: TerminalTheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ModuleHeader(title: "Action Center", detail: "Prioritized manual operations", theme: theme)
                if store.openActions.isEmpty {
                    EmptyState("No open operational actions.", theme: theme)
                } else {
                    ForEach(store.openActions) { action in
                        ActionCard(
                            action: action,
                            theme: theme,
                            markDone: { store.markDone(action) },
                            ignore: { store.ignore(action) }
                        )
                    }
                }
            }
            .padding(18)
        }
    }
}

struct FixQueueView: View {
    @Bindable var store: TerminalStore
    let theme: TerminalTheme
    let showCheckReport: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ModuleHeader(title: "Fix Queue", detail: "Manual command cards and read-only checks", theme: theme)
                if store.openActions.isEmpty {
                    EmptyState("Queue is empty.", theme: theme)
                } else {
                    ForEach(store.openActions) { action in
                        FixQueueCard(
                            action: action,
                            theme: theme,
                            isRunningCheck: store.runningCheckActionID == action.id,
                            runCheck: {
                                Task {
                                    await store.runReadOnlyCheck(action)
                                    showCheckReport()
                                }
                            },
                            markDone: { store.markDone(action) },
                            ignore: { store.ignore(action) }
                        )
                    }
                }
            }
            .padding(18)
        }
    }
}

struct DailyReportView: View {
    let store: TerminalStore
    let theme: TerminalTheme
    @State private var format: ReportFormat = .markdown

    private var report: String {
        store.dailyOpsReport(format: format)
    }

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(title: "Daily Ops Report", detail: "Markdown, plain text, clipboard", theme: theme)
            HStack {
                Picker("Format", selection: $format) {
                    ForEach(ReportFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
                Spacer()
                Button {
                    copyText(report)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            .buttonStyle(.bordered)
            .padding(12)
            .background(theme.panel)
            ScrollView {
                Text(report)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(theme.background)
        }
    }
}

struct SidebarSectionRow: View {
    let section: CommandCenterSection
    let status: String
    let help: String
    let theme: TerminalTheme

    var body: some View {
        HStack(spacing: 8) {
            Label(section.rawValue, systemImage: section.symbol)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(status)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.border, lineWidth: 1))
        }
        .help(help)
    }

    private var statusColor: Color {
        if status == "WAIT" || status == "0/3" { return theme.muted }
        if status == "READY" || status == "COLLECTING" { return theme.green }
        if status == "ERROR" { return theme.red }
        if let value = Int(status) {
            switch section {
            case .dashboard:
                return value >= 85 ? theme.green : value >= 65 ? theme.accent : theme.red
            case .actions, .fixQueue, .logs:
                return value == 0 ? theme.green : theme.accent
            default:
                return theme.cyan
            }
        }
        return theme.cyan
    }
}

struct ActionCard: View {
    let action: OperationalAction
    let theme: TerminalTheme
    let markDone: () -> Void
    let ignore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(action.severity.rawValue)
                    .foregroundStyle(severityColor(action.severity, theme: theme))
                    .fontWeight(.black)
                    .frame(width: 90, alignment: .leading)
                Text(action.scope)
                    .foregroundStyle(theme.cyan)
                    .fontWeight(.bold)
                Text(action.title)
                    .foregroundStyle(theme.text)
                    .fontWeight(.bold)
                Spacer()
                Button("Done", action: markDone)
                Button("Ignore", action: ignore)
            }
            .buttonStyle(.bordered)
            Text(action.evidence)
                .foregroundStyle(theme.muted)
                .textSelection(.enabled)
            Text(action.nextStep)
                .foregroundStyle(theme.accent)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
    }
}

struct FixQueueCard: View {
    let action: OperationalAction
    let theme: TerminalTheme
    let isRunningCheck: Bool
    let runCheck: () -> Void
    let markDone: () -> Void
    let ignore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(action.severity.rawValue)
                    .foregroundStyle(severityColor(action.severity, theme: theme))
                    .fontWeight(.black)
                Text(action.scope)
                    .foregroundStyle(theme.cyan)
                    .fontWeight(.bold)
                Text(action.title)
                    .foregroundStyle(theme.text)
                    .fontWeight(.bold)
                Spacer()
                Button(isRunningCheck ? "Checking" : "Run Check", action: runCheck)
                    .disabled(action.check == nil || isRunningCheck)
                Button("Done", action: markDone)
                Button("Ignore", action: ignore)
            }
            .buttonStyle(.bordered)

            Text(action.nextStep)
                .foregroundStyle(theme.muted)
                .textSelection(.enabled)

            ForEach(action.manualCommands) { command in
                ManualCommandRow(command: command, theme: theme)
            }
        }
        .padding(12)
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
    }
}

struct ManualCommandRow: View {
    let command: ManualCommand
    let theme: TerminalTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(command.title)
                    .foregroundStyle(theme.accent)
                    .fontWeight(.bold)
                Text(command.intent)
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
                Spacer()
                Button {
                    copyText(command.displayCommand)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
            }
            .buttonStyle(.bordered)
            Text(command.displayCommand)
                .foregroundStyle(theme.dim)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(8)
        .background(theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.border, lineWidth: 1))
    }
}

struct ProjectCompactRow: View {
    let project: ProjectStatus
    let theme: TerminalTheme

    var body: some View {
        HStack(spacing: 10) {
            Text(project.shortName)
                .foregroundStyle(healthColor(project.health, theme: theme))
                .fontWeight(.black)
                .frame(width: 70, alignment: .leading)
            Text("\(project.healthScore)")
                .foregroundStyle(project.healthScore >= 85 ? theme.green : project.healthScore >= 65 ? theme.accent : theme.red)
                .frame(width: 45, alignment: .leading)
            Text(project.reason)
                .foregroundStyle(theme.text)
            Spacer()
            Text(project.branch)
                .foregroundStyle(theme.cyan)
        }
        .padding(8)
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct LogEntryRow: View {
    let log: LogEntry
    let theme: TerminalTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(log.level)
                    .foregroundStyle(levelColor)
                    .fontWeight(.black)
                    .frame(width: 88, alignment: .leading)
                Text(log.category.rawValue)
                    .foregroundStyle(theme.cyan)
                    .frame(width: 82, alignment: .leading)
                Text(log.source)
                    .foregroundStyle(theme.muted)
                Spacer()
                Text(log.timestamp.formatted(date: .omitted, time: .standard))
                    .foregroundStyle(theme.dim)
            }
            Text(log.message)
                .foregroundStyle(theme.text)
                .textSelection(.enabled)
                .lineLimit(4)
        }
        .padding(.vertical, 5)
    }

    private var levelColor: Color {
        switch log.level {
        case "INCIDENT": theme.red
        case "ERROR": theme.red
        case "WARN": theme.accent
        default: theme.muted
        }
    }
}

struct IncidentRow: View {
    let incident: Incident
    let theme: TerminalTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(incident.severity.rawValue)
                    .foregroundStyle(severityColor(incident.severity, theme: theme))
                    .fontWeight(.black)
                Text(incident.scope)
                    .foregroundStyle(theme.cyan)
                Spacer()
            }
            Text(incident.title)
                .foregroundStyle(theme.text)
                .fontWeight(.bold)
            Text(incident.evidence)
                .foregroundStyle(theme.muted)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
    }
}

struct DetailGrid: View {
    let rows: [(String, String)]
    let theme: TerminalTheme

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
            ForEach(rows, id: \.0) { label, value in
                GridRow {
                    Text(label)
                        .foregroundStyle(theme.muted)
                        .frame(width: 120, alignment: .leading)
                    Text(value)
                        .foregroundStyle(theme.text)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let detail: String
    let color: Color
    let comment: String
    let theme: TerminalTheme

    init(
        title: String,
        value: String,
        detail: String,
        color: Color,
        comment: String? = nil,
        theme: TerminalTheme
    ) {
        self.title = title
        self.value = value
        self.detail = detail
        self.color = color
        self.comment = comment ?? detail
        self.theme = theme
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .foregroundStyle(theme.muted)
                .help(comment)
            Text(value)
                .foregroundStyle(color)
                .font(.system(size: 22, weight: .black, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .foregroundStyle(theme.dim)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
        .help(comment)
    }
}

struct ScorePill: View {
    let label: String
    let score: Int
    let theme: TerminalTheme

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .foregroundStyle(theme.muted)
            Text("\(score)")
                .foregroundStyle(score >= 85 ? theme.green : score >= 65 ? theme.accent : theme.red)
                .fontWeight(.black)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
    }
}

struct ModuleHeader: View {
    let title: String
    let detail: String
    let theme: TerminalTheme

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased())
                    .foregroundStyle(theme.accent)
                    .fontWeight(.black)
                    .tracking(1.2)
                Text(detail)
                    .foregroundStyle(theme.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(theme.header)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.border, lineWidth: 1))
    }
}

struct SectionHeader: View {
    let title: String
    let right: String?
    let color: Color
    let theme: TerminalTheme

    init(_ title: String, right: String? = nil, color: Color, theme: TerminalTheme) {
        self.title = title
        self.right = right
        self.color = color
        self.theme = theme
    }

    var body: some View {
        HStack {
            Text(title.uppercased())
                .foregroundStyle(color)
                .fontWeight(.black)
            Spacer()
            if let right {
                Text(right)
                    .foregroundStyle(theme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(theme.header)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct EmptyState: View {
    let text: String
    let theme: TerminalTheme

    init(_ text: String, theme: TerminalTheme) {
        self.text = text
        self.theme = theme
    }

    var body: some View {
        Text(text)
            .foregroundStyle(theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct CheckReportView: View {
    let result: ReadOnlyCheckResult?
    let theme: TerminalTheme
    @Environment(\.dismiss) private var dismiss

    private var reportText: String {
        guard let result else {
            return "No read-only check result is available."
        }

        return [
            "READ-ONLY CHECK",
            "Title: \(result.title)",
            "Command: \(result.command)",
            "Exit: \(result.exitCode)",
            "Timed out: \(result.timedOut ? "yes" : "no")",
            "Ran at: \(result.ranAt.formatted(date: .abbreviated, time: .standard))",
            "",
            result.combinedOutput
        ].joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("READ-ONLY CHECK")
                    .foregroundStyle(theme.accent)
                    .fontWeight(.black)
                Text(resultSummary)
                    .foregroundStyle(theme.muted)
                Spacer()
                Button("Copy") { copyText(reportText) }
                Button("Close") { dismiss() }
            }
            .buttonStyle(.bordered)
            .padding(12)
            .background(theme.topBackground)
            ScrollView {
                Text(reportText)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(resultColor)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(theme.background)
        }
        .background(theme.background)
    }

    private var resultSummary: String {
        guard let result else { return "NO RESULT" }
        return "exit \(result.exitCode) | \(result.timedOut ? "TIMEOUT" : "COMPLETE")"
    }

    private var resultColor: Color {
        guard let result else { return theme.muted }
        return result.timedOut || result.exitCode != 0 ? theme.accent : theme.green
    }
}

struct AutomationReportView: View {
    let result: AutomationRunResult?
    let theme: TerminalTheme
    @Environment(\.dismiss) private var dismiss

    private var reportText: String {
        guard let result else {
            return "No automation run result is available."
        }

        return [
            "AUTOMATION RUN",
            "Name: \(result.name)",
            "Command: \(result.command)",
            "Exit: \(result.exitCode)",
            "Timed out: \(result.timedOut ? "yes" : "no")",
            "Ran at: \(result.ranAt.formatted(date: .abbreviated, time: .standard))",
            "",
            result.combinedOutput
        ].joined(separator: "\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("AUTOMATION RUN")
                    .foregroundStyle(theme.accent)
                    .fontWeight(.black)
                Text(resultSummary)
                    .foregroundStyle(theme.muted)
                Spacer()
                Button("Copy") { copyText(reportText) }
                Button("Close") { dismiss() }
            }
            .buttonStyle(.bordered)
            .padding(12)
            .background(theme.topBackground)
            ScrollView {
                Text(reportText)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(resultColor)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(theme.background)
        }
        .background(theme.background)
    }

    private var resultSummary: String {
        guard let result else { return "NO RESULT" }
        return "exit \(result.exitCode) | \(result.timedOut ? "TIMEOUT" : "COMPLETE")"
    }

    private var resultColor: Color {
        guard let result else { return theme.muted }
        return result.timedOut || result.exitCode != 0 ? theme.accent : theme.green
    }
}

struct AIReportView: View {
    let analysis: LocalAIAnalysis
    let theme: TerminalTheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("AI REPORT")
                    .foregroundStyle(theme.accent)
                    .fontWeight(.black)
                Text("\(analysis.provider) | \(analysis.model) | \(analysis.status.rawValue)")
                    .foregroundStyle(theme.muted)
                Spacer()
                Button("Copy") { copyText(analysis.text) }
                Button("Close") { dismiss() }
            }
            .buttonStyle(.bordered)
            .padding(12)
            .background(theme.topBackground)
            ScrollView {
                Text(analysis.text)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(color(for: analysis.status))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .background(theme.background)
        }
        .background(theme.background)
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
    case graphite = "GRAPHITE"
    case amber = "AMBER"

    var id: String { rawValue }

    var background: Color {
        switch self {
        case .graphite: Color(red: 0.055, green: 0.060, blue: 0.065)
        case .amber: Color(red: 0.0, green: 0.0, blue: 0.0)
        }
    }

    var panel: Color {
        switch self {
        case .graphite: Color(red: 0.085, green: 0.095, blue: 0.105)
        case .amber: Color(red: 0.02, green: 0.02, blue: 0.02)
        }
    }

    var header: Color {
        switch self {
        case .graphite: Color(red: 0.105, green: 0.120, blue: 0.130)
        case .amber: Color(red: 0.04, green: 0.04, blue: 0.04)
        }
    }

    var topBackground: Color {
        switch self {
        case .graphite: Color(red: 0.075, green: 0.085, blue: 0.095)
        case .amber: Color(red: 0.08, green: 0.055, blue: 0.0)
        }
    }

    var accent: Color {
        switch self {
        case .graphite: Color(red: 0.95, green: 0.58, blue: 0.18)
        case .amber: Color(red: 0.96, green: 0.62, blue: 0.04)
        }
    }

    var green: Color { Color(red: 0.52, green: 0.86, blue: 0.36) }
    var cyan: Color { Color(red: 0.18, green: 0.72, blue: 0.90) }
    var red: Color { Color(red: 0.95, green: 0.24, blue: 0.22) }
    var text: Color { Color(red: 0.82, green: 0.83, blue: 0.82) }
    var muted: Color { Color(red: 0.58, green: 0.60, blue: 0.61) }
    var dim: Color { Color(red: 0.42, green: 0.44, blue: 0.45) }
    var border: Color { Color.white.opacity(0.10) }
}

private func copyText(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

private func healthColor(_ health: ProjectStatus.Health, theme: TerminalTheme) -> Color {
    switch health {
    case .clean: theme.green
    case .dirty: theme.accent
    case .unpushed: theme.cyan
    case .missing: theme.red
    case .notGit: theme.accent
    case .unknown: theme.accent
    }
}

private func severityColor(_ severity: OperationalAction.Severity, theme: TerminalTheme) -> Color {
    switch severity {
    case .critical: theme.red
    case .warning: theme.accent
    case .info: theme.cyan
    }
}
