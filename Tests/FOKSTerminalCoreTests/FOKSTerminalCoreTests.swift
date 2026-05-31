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

    func testCommandTimeout() async {
        let runner = CommandRunner()
        let result = await runner.run("/bin/sleep", ["2"], timeout: 0.05)

        XCTAssertTrue(result.timedOut)
        XCTAssertEqual(result.exitCode, -1)
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
        XCTAssertTrue(actions.first?.command.contains("tail -80 '/tmp/personallifeos.err'") == true)
        XCTAssertTrue(actions.contains { $0.id == "project-dirty-gmc" })
    }
}
