import Foundation

public struct CommandResult: Sendable, Equatable {
    public let executable: String
    public let arguments: [String]
    public let exitCode: Int32
    public let output: String
    public let error: String
    public let timedOut: Bool

    public var combinedOutput: String {
        [output, error].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    public init(
        executable: String,
        arguments: [String],
        exitCode: Int32,
        output: String,
        error: String,
        timedOut: Bool = false
    ) {
        self.executable = executable
        self.arguments = arguments
        self.exitCode = exitCode
        self.output = output
        self.error = error
        self.timedOut = timedOut
    }
}

public struct CommandRunner: Sendable {
    public init() {}

    public func run(
        _ executable: String,
        _ arguments: [String] = [],
        timeout: TimeInterval = 5
    ) async -> CommandResult {
        await Task.detached(priority: .utility) {
            Self.runBlocking(executable: executable, arguments: arguments, timeout: timeout)
        }.value
    }

    private static func runBlocking(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return CommandResult(
                executable: executable,
                arguments: arguments,
                exitCode: -1,
                output: "",
                error: "launch failed: \(error.localizedDescription)"
            )
        }

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false

        while process.isRunning {
            if Date() >= deadline {
                timedOut = true
                process.terminate()
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }

        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()

        return CommandResult(
            executable: executable,
            arguments: arguments,
            exitCode: timedOut ? -1 : process.terminationStatus,
            output: String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            error: String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            timedOut: timedOut
        )
    }
}
