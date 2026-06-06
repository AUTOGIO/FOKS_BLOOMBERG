import XCTest
@testable import FOKSTerminalCore

final class FOKSTerminalCoreTests: XCTestCase {
    func testProjectConfigDecodingFiltersEnabledProjects() throws {
        let json = """
        {
          "projects": [
            {
              "id": "foks",
              "shortName": "FOKS",
              "displayName": "FOKS Bloomberg Terminal",
              "path": "/tmp/foks",
              "group": "OPS",
              "enabled": true
            },
            {
              "id": "old",
              "shortName": "OLD",
              "displayName": "Old Project",
              "path": "/tmp/old",
              "group": "ARCHIVE",
              "enabled": false
            }
          ]
        }
        """

        let decoded = try ProjectConfigLoader.decode(Data(json.utf8))

        XCTAssertEqual(decoded.projects.count, 2)
        XCTAssertEqual(decoded.projects.first?.id, "foks")
        XCTAssertFalse(decoded.projects[1].enabled)
    }

    func testProjectConfigLoaderDoesNotInventFallbackProjects() {
        let missingURL = URL(fileURLWithPath: "/tmp/foks-terminal-missing-projects-\(UUID().uuidString).json")

        XCTAssertEqual(ProjectConfigLoader.load(from: missingURL), [])
    }

    func testProjectConfigManagerSyncAddAndRemove() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("foks-project-sync-\(UUID().uuidString)")
        let configURL = root.appendingPathComponent("projects.json")
        let existing = root.appendingPathComponent("ExistingRepo")
        let discovered = root.appendingPathComponent("NewRepo")
        let missing = root.appendingPathComponent("MissingRepo")
        try FileManager.default.createDirectory(at: existing.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: discovered.appendingPathComponent(".git"), withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        try ProjectConfigManager.save([
            ProjectConfig(
                id: "existing",
                shortName: "EX",
                displayName: "Existing Repo",
                path: existing.path,
                group: "TEST",
                enabled: true
            ),
            ProjectConfig(
                id: "missing",
                shortName: "MISS",
                displayName: "Missing Repo",
                path: missing.path,
                group: "TEST",
                enabled: true
            )
        ], to: configURL)

        let result = try ProjectConfigManager.syncDiscoveredProjects(
            configURL: configURL,
            discoveryRoots: [root.path]
        )
        let next = try ProjectConfigManager.loadAll(from: configURL)

        XCTAssertEqual(result.added.map { normalizedPath($0.path) }, [normalizedPath(discovered.path)])
        XCTAssertEqual(result.removed.map(\.id), ["missing"])
        XCTAssertEqual(next.map { normalizedPath($0.path) }.sorted(), [normalizedPath(discovered.path), normalizedPath(existing.path)].sorted())
    }

    func testProjectConfigManagerManualAddAndRemove() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("foks-project-manual-\(UUID().uuidString)")
        let configURL = root.appendingPathComponent("projects.json")
        let project = root.appendingPathComponent("ManualRepo")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        let added = try ProjectConfigManager.addProject(
            path: project.path,
            shortName: "MAN",
            displayName: "Manual Repo",
            group: "OPS",
            configURL: configURL
        )
        XCTAssertEqual(added.added.first?.shortName, "MAN")

        let removed = try ProjectConfigManager.removeProject(
            id: try XCTUnwrap(added.added.first?.id),
            configURL: configURL
        )
        XCTAssertEqual(removed.removed.first?.displayName, "Manual Repo")
        XCTAssertEqual(try ProjectConfigManager.loadAll(from: configURL), [])
    }

    func testGitHealthClean() {
        let result = GitStatusParser.health(
            pathExists: true,
            isGitRepository: true,
            dirtyFiles: 0,
            ahead: 0,
            behind: 0,
            remoteURL: "https://github.com/example/repo.git",
            upstream: "origin/main"
        )

        XCTAssertEqual(result.0, .clean)
        XCTAssertEqual(result.1, "clean and synced")
    }

    func testGitHealthDirty() {
        let result = GitStatusParser.health(
            pathExists: true,
            isGitRepository: true,
            dirtyFiles: 2,
            ahead: 0,
            behind: 0,
            remoteURL: "https://github.com/example/repo.git",
            upstream: "origin/main"
        )

        XCTAssertEqual(result.0, .dirty)
        XCTAssertEqual(result.1, "2 dirty files")
    }

    func testGitHealthUnpushed() {
        let result = GitStatusParser.health(
            pathExists: true,
            isGitRepository: true,
            dirtyFiles: 0,
            ahead: 1,
            behind: 0,
            remoteURL: "https://github.com/example/repo.git",
            upstream: "origin/main"
        )

        XCTAssertEqual(result.0, .unpushed)
        XCTAssertEqual(result.1, "1 unpushed commit")
    }

    func testGitHealthMissingAndNotGit() {
        let missing = GitStatusParser.health(
            pathExists: false,
            isGitRepository: false,
            dirtyFiles: 0,
            ahead: 0,
            behind: 0,
            remoteURL: "",
            upstream: ""
        )
        let notGit = GitStatusParser.health(
            pathExists: true,
            isGitRepository: false,
            dirtyFiles: 0,
            ahead: 0,
            behind: 0,
            remoteURL: "",
            upstream: ""
        )

        XCTAssertEqual(missing.0, .missing)
        XCTAssertEqual(notGit.0, .notGit)
    }

    func testDirtyFileCountAndDivergenceParsing() {
        XCTAssertEqual(GitStatusParser.dirtyFileCount(from: " M README.md\n?? scratch.txt\n"), 2)
        XCTAssertEqual(GitStatusParser.dirtyItems(from: " M README.md\n?? scratch.txt\n"), ["M README.md", "?? scratch.txt"])

        let divergence = GitStatusParser.divergence(from: "3\t1")
        XCTAssertEqual(divergence.ahead, 3)
        XCTAssertEqual(divergence.behind, 1)
    }

    func testProcessLineParsing() {
        let parsed = ProcessParser.parsePSLine("1234  4.2  204800 /Applications/LM Studio.app/Contents/MacOS/LM Studio")

        XCTAssertEqual(parsed?.pid, "1234")
        XCTAssertEqual(parsed?.cpu, "4.2%")
        XCTAssertEqual(parsed?.memory, "200 MB")
        XCTAssertEqual(parsed?.command, "/Applications/LM Studio.app/Contents/MacOS/LM Studio")
    }

    func testLaunchAgentLineParsing() {
        let parsed = LaunchAgentParser.parseLaunchctlLine("123\t0\tcom.giovannini.foks")

        XCTAssertEqual(parsed?.pid, "123")
        XCTAssertEqual(parsed?.status, "0")
        XCTAssertEqual(parsed?.label, "com.giovannini.foks")
    }

    func testLaunchAgentAnalysisDetectsFailedExit() {
        let output = """
        gui/501/com.personallifeos = {
            path = /Users/test/Library/LaunchAgents/com.personallifeos.plist
            state = spawn scheduled
            stdout path = /tmp/personallifeos.log
            stderr path = /tmp/personallifeos.err
            runs = 3042
            last exit code = 1
        }
        """

        let analyzed = LaunchAgentParser.analyze(
            label: "com.personallifeos",
            listPID: "none",
            listStatus: "1",
            printOutput: output
        )

        XCTAssertEqual(analyzed.health, .failed)
        XCTAssertEqual(analyzed.state, "spawn scheduled")
        XCTAssertEqual(analyzed.reason, "last exit 1; runs 3042")
        XCTAssertEqual(analyzed.plistPath, "/Users/test/Library/LaunchAgents/com.personallifeos.plist")
        XCTAssertEqual(analyzed.stdoutPath, "/tmp/personallifeos.log")
        XCTAssertEqual(analyzed.stderrPath, "/tmp/personallifeos.err")
    }

    func testDiagnosticBundleIncludesDirtyAndLaunchAgentFailures() {
        let snapshot = DashboardSnapshot(
            projects: [
                ProjectStatus(
                    id: "life",
                    shortName: "LIFE",
                    displayName: "Personal Life OS",
                    path: "/tmp/life",
                    group: "LIFE",
                    health: .dirty,
                    reason: "2 dirty files",
                    branch: "main",
                    dirtyFiles: 2,
                    dirtyItems: ["M core/views.py", "?? .env"]
                )
            ],
            hardware: .empty,
            processes: [
                ProcessSnapshot(pid: "42", cpu: "1.0%", memory: "50 MB", command: "python manage.py runserver")
            ],
            launchAgents: [
                LaunchAgentSnapshot(
                    pid: "none",
                    status: "1",
                    label: "com.personallifeos",
                    state: "spawn scheduled",
                    health: .failed,
                    reason: "last exit 1; runs 10",
                    plistPath: "/Users/test/Library/LaunchAgents/com.personallifeos.plist"
                )
            ],
            logs: []
        )

        let bundle = DiagnosticBundleBuilder().build(snapshot: snapshot, selectedProjectID: "life")

        XCTAssertTrue(bundle.contains("M core/views.py"))
        XCTAssertTrue(bundle.contains("com.personallifeos"))
        XCTAssertTrue(bundle.contains("Use only these headings: NOW, NEXT, LATER"))
    }

    func testDiagnosticBundleCloudModeUsesExplicitCloudRules() {
        let bundle = DiagnosticBundleBuilder().build(snapshot: .empty, selectedProjectID: nil, provider: .cloud)

        XCTAssertTrue(bundle.contains("FOKS TERMINAL CLOUD DIAGNOSTIC BUNDLE"))
        XCTAssertTrue(bundle.contains("cloud-assisted advisory analysis was explicitly selected"))
        XCTAssertFalse(bundle.contains("local-only analysis; do not suggest cloud services"))
        XCTAssertTrue(bundle.contains("do not claim you can execute fixes"))
    }

    func testCloudAIConfigurationRequiresExplicitEnvironment() {
        let result = CloudAIConfiguration.fromEnvironment([:])

        guard case .failure(let error) = result else {
            XCTFail("Expected missing cloud AI environment to fail")
            return
        }
        XCTAssertTrue(error.localizedDescription.contains("FOKS_CLOUD_AI_ENDPOINT"))
        XCTAssertTrue(error.localizedDescription.contains("FOKS_CLOUD_AI_API_KEY"))
        XCTAssertTrue(error.localizedDescription.contains("FOKS_CLOUD_AI_MODEL"))
        XCTAssertTrue(error.localizedDescription.contains("No request was sent"))
    }

    func testCloudAIConfigurationRequiresHTTPSEndpoint() {
        let result = CloudAIConfiguration.fromEnvironment([
            "FOKS_CLOUD_AI_ENDPOINT": "http://example.com/v1/chat/completions",
            "FOKS_CLOUD_AI_API_KEY": "test-key",
            "FOKS_CLOUD_AI_MODEL": "test-model"
        ])

        guard case .failure(let error) = result else {
            XCTFail("Expected non-HTTPS cloud AI endpoint to fail")
            return
        }
        XCTAssertTrue(error.localizedDescription.contains("valid HTTPS URL"))
        XCTAssertTrue(error.localizedDescription.contains("No request was sent"))
    }

    func testCloudAIConfigurationAcceptsExplicitHTTPSConfiguration() throws {
        let result = CloudAIConfiguration.fromEnvironment([
            "FOKS_CLOUD_AI_ENDPOINT": "https://api.example.com/v1/chat/completions",
            "FOKS_CLOUD_AI_API_KEY": "test-key",
            "FOKS_CLOUD_AI_MODEL": "test-model"
        ])

        guard case .success(let configuration) = result else {
            XCTFail("Expected valid cloud AI environment to pass")
            return
        }
        XCTAssertEqual(configuration.endpoint.absoluteString, "https://api.example.com/v1/chat/completions")
        XCTAssertEqual(configuration.apiKey, "test-key")
        XCTAssertEqual(configuration.model, "test-model")
    }

    func testStartupServicesConfigLoadsLocalAIAndCloudflareTunnel() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("foks-startup-config-\(UUID().uuidString)")
        let configURL = root.appendingPathComponent("startup_services.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        try """
        {
          "startOnAppLaunch": true,
          "localAI": {
            "enabled": true,
            "binaryPath": "/opt/homebrew/bin/ollama",
            "healthURL": "http://127.0.0.1:11434/api/tags",
            "startupTimeoutSeconds": 3
          },
          "cloudflareTunnel": {
            "enabled": true,
            "binaryPath": "/opt/homebrew/bin/cloudflared",
            "tunnelName": "ollama",
            "configPath": "/Users/test/.cloudflared/config.yml"
          }
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let config = try StartupServicesConfig.load(from: configURL, environment: [:])

        XCTAssertTrue(config.startOnAppLaunch)
        XCTAssertTrue(config.localAI.enabled)
        XCTAssertEqual(config.localAI.launchArguments, ["serve"])
        XCTAssertEqual(config.cloudflareTunnel.launchArguments, [
            "tunnel",
            "--config",
            "/Users/test/.cloudflared/config.yml",
            "--no-autoupdate",
            "run",
            "ollama"
        ])
    }

    func testStartupServicesConfigEnvironmentOverrides() throws {
        let config = try StartupServicesConfig.load(
            from: URL(fileURLWithPath: "/tmp/foks-missing-startup-\(UUID().uuidString).json"),
            environment: [
                "FOKS_STARTUP_SERVICES_ENABLED": "false",
                "FOKS_OLLAMA_BIN": "/tmp/ollama",
                "FOKS_CLOUDFLARE_TUNNEL_ENABLED": "true",
                "FOKS_CLOUDFLARED_BIN": "/tmp/cloudflared",
                "FOKS_CLOUDFLARE_TUNNEL_NAME": "production"
            ]
        )

        XCTAssertFalse(config.startOnAppLaunch)
        XCTAssertEqual(config.localAI.binaryPath, "/tmp/ollama")
        XCTAssertTrue(config.cloudflareTunnel.enabled)
        XCTAssertEqual(config.cloudflareTunnel.binaryPath, "/tmp/cloudflared")
        XCTAssertEqual(config.cloudflareTunnel.tunnelName, "production")
    }

    func testCommandTimeout() async {
        let runner = CommandRunner()
        let result = await runner.run("/bin/sleep", ["2"], timeout: 0.05)

        XCTAssertTrue(result.timedOut)
        XCTAssertEqual(result.exitCode, -1)
    }

    func testAutomationMetadataParserExtractsPurposeAndUsage() {
        let python = """
        #!/usr/bin/env python3
        \"\"\"Organize Downloads root using local Ollama neural-chat model.\"\"\"
        import json
        """
        let shell = """
        #!/bin/zsh
        set -euo pipefail
        echo "usage: cursor-task /absolute/project/path 'task description'"
        """

        XCTAssertEqual(
            AutomationMetadataParser.purpose(from: python, fallbackName: "organize-downloads"),
            "Organize Downloads root using local Ollama neural-chat model."
        )
        XCTAssertEqual(
            AutomationMetadataParser.runRequirement(from: shell),
            "Requires arguments: usage: cursor-task /absolute/project/path 'task description'"
        )
    }

    func testReadAutomationsDiscoversScriptsAndLatestLogs() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("foks-automation-\(UUID().uuidString)")
        let bin = root.appendingPathComponent("bin")
        let logs = root.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        let organize = bin.appendingPathComponent("organize-downloads.py")
        try """
        #!/usr/bin/env python3
        \"\"\"Organize Downloads root using local Ollama neural-chat model.\"\"\"
        print("ok")
        """.write(to: organize, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: organize.path)

        let cursorTask = bin.appendingPathComponent("cursor-task")
        try """
        #!/bin/zsh
        echo "usage: cursor-task /absolute/project/path 'task description'"
        """.write(to: cursorTask, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cursorTask.path)

        let latestLog = logs.appendingPathComponent("organize-downloads-20260601.json")
        try "{}".write(to: latestLog, atomically: true, encoding: .utf8)
        let latestDate = Date(timeIntervalSince1970: 1_800_000_000)
        try FileManager.default.setAttributes([.modificationDate: latestDate], ofItemAtPath: latestLog.path)

        let reader = SystemReader(configURL: URL(fileURLWithPath: "/tmp/foks-missing-\(UUID().uuidString).json"))
        let automations = await reader.readAutomations(rootPath: root.path)
        let organizeSnapshot = try XCTUnwrap(automations.first { $0.name == "organize-downloads" })
        let cursorSnapshot = try XCTUnwrap(automations.first { $0.name == "cursor-task" })

        XCTAssertEqual(automations.count, 2)
        XCTAssertTrue(organizeSnapshot.canRun)
        XCTAssertEqual(
            URL(fileURLWithPath: organizeSnapshot.logPath).resolvingSymlinksInPath().path,
            latestLog.resolvingSymlinksInPath().path
        )
        XCTAssertEqual(organizeSnapshot.lastRunAt, latestDate)
        XCTAssertEqual(organizeSnapshot.purpose, "Organize Downloads root using local Ollama neural-chat model.")
        XCTAssertFalse(cursorSnapshot.canRun)
        XCTAssertTrue(cursorSnapshot.runRequirement.contains("cursor-task"))
    }

    func testReadAppBundlesDiscoversLocalApps() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("foks-apps-\(UUID().uuidString)")
        let dist = root.appendingPathComponent("dist")
        let app = dist.appendingPathComponent("DemoTool.app")
        let contents = app.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleExecutable</key>
            <string>DemoTool</string>
            <key>CFBundleIdentifier</key>
            <string>com.example.demotool</string>
        </dict>
        </plist>
        """.write(to: contents.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        try "#!/bin/sh\n".write(to: macOS.appendingPathComponent("DemoTool"), atomically: true, encoding: .utf8)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        let project = ProjectStatus(
            id: "demo",
            shortName: "DEMO",
            displayName: "Demo",
            path: root.path,
            group: "TEST",
            health: .clean,
            reason: "clean"
        )
        let apps = await SystemReader(configURL: URL(fileURLWithPath: "/tmp/foks-missing-\(UUID().uuidString).json"))
            .readAppBundles(projects: [project])
        let found = try XCTUnwrap(apps.first { $0.name == "DemoTool" })

        XCTAssertEqual(normalizedPath(found.path), normalizedPath(app.path))
        XCTAssertEqual(found.bundleIdentifier, "com.example.demotool")
        XCTAssertEqual(found.runExecutable, "/usr/bin/open")
        XCTAssertEqual(found.runArguments.map(normalizedPath), [normalizedPath(app.path)])
    }

    func testActionCenterPrioritizesFailedAgentsAndDirtyRepos() {
        let snapshot = DashboardSnapshot(
            projects: [
                ProjectStatus(
                    id: "gmc",
                    shortName: "GMC",
                    displayName: "GMC",
                    path: "/tmp/gmc",
                    group: "FINANCE",
                    health: .dirty,
                    reason: "3 dirty files",
                    dirtyFiles: 3,
                    dirtyItems: ["D launcher.command", "M src/App.jsx"]
                )
            ],
            hardware: .empty,
            processes: [],
            launchAgents: [
                LaunchAgentSnapshot(
                    pid: "none",
                    status: "1",
                    label: "com.personallifeos",
                    state: "spawn scheduled",
                    health: .failed,
                    reason: "last exit 1; runs 10",
                    plistPath: "/Users/test/Library/LaunchAgents/com.personallifeos.plist",
                    stdoutPath: "/tmp/personallifeos.log",
                    stderrPath: "/tmp/personallifeos.err"
                )
            ],
            logs: []
        )

        let actions = ActionCenterBuilder().build(snapshot: snapshot)

        XCTAssertEqual(actions.first?.id, "agent-com.personallifeos")
        XCTAssertEqual(actions.first?.severity, .critical)
        XCTAssertTrue(actions.first?.command.contains("/usr/bin/tail -80 /tmp/personallifeos.err") == true)
        XCTAssertEqual(actions.first?.manualCommands.first?.executable, "/bin/launchctl")
        XCTAssertEqual(actions.first?.check?.executable, "/usr/bin/tail")
        XCTAssertTrue(actions.contains { $0.id == "project-dirty-gmc" && $0.check?.executable == "/usr/bin/git" })
    }

    func testDailyOpsReportIncludesActionableSummary() {
        let snapshot = DashboardSnapshot(
            projects: [
                ProjectStatus(
                    id: "gmc",
                    shortName: "GMC",
                    displayName: "GMC",
                    path: "/tmp/gmc",
                    group: "FINANCE",
                    health: .dirty,
                    reason: "3 dirty files",
                    branch: "main",
                    dirtyFiles: 3,
                    dirtyItems: ["M src/App.jsx"]
                ),
                ProjectStatus(
                    id: "foks",
                    shortName: "FOKS",
                    displayName: "FOKS Bloomberg Terminal",
                    path: "/tmp/foks",
                    group: "OPS",
                    health: .unpushed,
                    reason: "2 unpushed commits",
                    branch: "main",
                    ahead: 2
                )
            ],
            hardware: .empty,
            processes: [],
            launchAgents: [
                LaunchAgentSnapshot(
                    pid: "none",
                    status: "1",
                    label: "com.personallifeos",
                    state: "spawn scheduled",
                    health: .failed,
                    reason: "last exit 1; runs 10",
                    stderrPath: "/tmp/personallifeos.err"
                )
            ],
            logs: []
        )

        let actions = ActionCenterBuilder().build(snapshot: snapshot)
        let report = DailyOpsReportBuilder().build(
            snapshot: snapshot,
            actions: actions,
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(report.contains("# FoKS Daily Ops Report"))
        XCTAssertTrue(report.contains("- Dirty repos: 1"))
        XCTAssertTrue(report.contains("- Unpushed repos: 1"))
        XCTAssertTrue(report.contains("- Failed LaunchAgents: 1"))
        XCTAssertTrue(report.contains("[CRITICAL] com.personallifeos: Inspect failing agent"))
        XCTAssertTrue(report.contains("GMC: 3 dirty files"))
        XCTAssertTrue(report.contains("FOKS: 2 ahead on main"))
    }

    func testResourceParsersAndLogClassifier() {
        XCTAssertEqual(ResourceParser.cpuPercent(fromPSOutput: "50.0\n25.0\n", logicalCores: 4), 18.75)

        let vm = """
        Mach Virtual Memory Statistics: (page size of 4096 bytes)
        Pages free:                               10.
        Pages active:                             20.
        Pages wired down:                         30.
        Pages occupied by compressor:             40.
        Pages speculative:                        5.
        """
        XCTAssertEqual(ResourceParser.memoryUsedBytes(fromVMStat: vm, totalBytes: 500_000), 368_640)

        let memoryPressure = """
        System-wide memory free percentage: 45%
        """
        XCTAssertEqual(
            ResourceParser.memoryUsedBytes(fromMemoryPressure: memoryPressure, totalBytes: 17_179_869_184),
            9_448_928_051
        )

        let df = """
        Filesystem 1024-blocks Used Available Capacity iused ifree %iused Mounted on
        /dev/disk3s1 100000 90000 10000 90% 1 2 1% /
        """
        let disk = ResourceParser.diskUsage(fromDFOutput: df)
        XCTAssertEqual(disk?.usedPercent, 90)
        XCTAssertEqual(disk?.freeBytes, 10_240_000)
        XCTAssertNil(ResourceParser.diskUsage(fromDFOutput: ""))

        XCTAssertEqual(LogClassifier.level(for: "fatal incident detected"), "INCIDENT")
        XCTAssertEqual(LogClassifier.level(for: "request failed with error"), "ERROR")
        XCTAssertEqual(LogClassifier.level(for: "warning: slow response"), "WARN")
    }

    func testUnavailableSystemMetricsDoNotReportHealthyScore() {
        XCTAssertEqual(SystemMetricsSnapshot.empty.healthScore, 0)
        XCTAssertFalse(SystemMetricsSnapshot.empty.cpuAvailable)
        XCTAssertFalse(SystemMetricsSnapshot.empty.memoryAvailable)
        XCTAssertFalse(SystemMetricsSnapshot.empty.diskAvailable)
    }

    func testActiveIssueCountUsesOnlyAvailableSnapshotSignals() {
        let unavailableSystem = SystemMetricsSnapshot(
            cpuPercent: 99,
            cpuAvailable: false,
            memoryUsedBytes: 99,
            memoryTotalBytes: 100,
            memoryAvailable: false,
            diskUsedPercent: 99,
            diskFreeBytes: 1,
            diskAvailable: false,
            networkReceivedBytes: 0,
            networkTransmittedBytes: 0,
            networkAvailable: false,
            uptime: "-",
            uptimeAvailable: false
        )
        let unavailableSnapshot = DashboardSnapshot(
            projects: [],
            hardware: .empty,
            system: unavailableSystem,
            processes: [],
            launchAgents: [],
            logs: []
        )

        XCTAssertEqual(unavailableSnapshot.activeIssueCount, 0)

        let availableSystem = SystemMetricsSnapshot(
            cpuPercent: 80,
            memoryUsedBytes: 85,
            memoryTotalBytes: 100,
            diskUsedPercent: 90,
            diskFreeBytes: 1,
            networkReceivedBytes: 0,
            networkTransmittedBytes: 0,
            uptime: "up 1 day"
        )
        let liveSnapshot = DashboardSnapshot(
            projects: [
                ProjectStatus(
                    id: "dirty",
                    shortName: "DIRTY",
                    displayName: "Dirty Project",
                    path: "/tmp/dirty",
                    group: "TEST",
                    health: .dirty,
                    reason: "1 dirty file",
                    dirtyFiles: 1
                )
            ],
            hardware: .empty,
            system: availableSystem,
            processes: [],
            launchAgents: [
                LaunchAgentSnapshot(
                    pid: "none",
                    status: "1",
                    label: "local.failed",
                    health: .failed,
                    reason: "last exit 1"
                )
            ],
            logs: [
                LogEntry(source: "test.log", message: "request failed", level: "ERROR")
            ]
        )

        XCTAssertEqual(liveSnapshot.activeIssueCount, 6)
    }

    func testCommandRunnerRejectsShellExecution() async {
        let runner = CommandRunner()
        let relative = await runner.run("git", ["status"], timeout: 1)
        let shell = await runner.run("/bin/zsh", ["-lc", "echo unsafe"], timeout: 1)

        XCTAssertEqual(relative.exitCode, -1)
        XCTAssertTrue(relative.error.contains("absolute path"))
        XCTAssertEqual(shell.exitCode, -1)
        XCTAssertTrue(shell.error.contains("shell execution"))
    }
}

private func normalizedPath(_ path: String) -> String {
    URL(fileURLWithPath: path).resolvingSymlinksInPath().path
}
