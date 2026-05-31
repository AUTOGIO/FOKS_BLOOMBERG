import Foundation

public struct ShellResult: Sendable, Equatable {
    public let command: String
    public let exitCode: Int32
    public let output: String
    public let error: String

    public var combinedOutput: String {
        [output, error].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

public enum ShellError: Error, LocalizedError {
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return message
        }
    }
}

public struct Shell: Sendable {
    public init() {}

    public func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval = 6) throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw ShellError.launchFailed("Failed to launch \(launchPath): \(error.localizedDescription)")
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
        }

        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()

        return ShellResult(
            command: ([launchPath] + arguments).joined(separator: " "),
            exitCode: process.terminationStatus,
            output: String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            error: String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }

    public func zsh(_ command: String, timeout: TimeInterval = 6) throws -> ShellResult {
        try run("/bin/zsh", ["-lc", command], timeout: timeout)
    }
}
