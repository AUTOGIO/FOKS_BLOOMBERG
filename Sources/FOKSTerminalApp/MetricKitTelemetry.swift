import Foundation
import MetricKit
import os

struct MetricKitTelemetrySnapshot: Sendable, Equatable {
    let isRuntimeAvailable: Bool
    let isRegistered: Bool
    let storagePath: String
    let signpostCategory: String
    let deliveredMetricPayloads: Int
    let deliveredDiagnosticPayloads: Int
    let pastMetricPayloads: Int
    let pastDiagnosticPayloads: Int
    let storedMetricPayloads: Int
    let storedDiagnosticPayloads: Int
    let latestMetricPayloadPath: String?
    let latestDiagnosticPayloadPath: String?
    let lastMetricPayloadAt: Date?
    let lastDiagnosticPayloadAt: Date?
    let lastWriteAt: Date?
    let lastError: String?
    let launchMeasurementState: String
    let launchMeasurementError: String?

    var status: String {
        if let lastError, !lastError.isEmpty {
            return "ERROR"
        }
        guard isRuntimeAvailable else {
            return "UNAVAILABLE"
        }
        guard isRegistered else {
            return "NOT REGISTERED"
        }
        if deliveredMetricPayloads + deliveredDiagnosticPayloads + storedMetricPayloads + storedDiagnosticPayloads == 0 {
            return "WAITING"
        }
        return "COLLECTING"
    }

    static let empty = MetricKitTelemetrySnapshot(
        isRuntimeAvailable: false,
        isRegistered: false,
        storagePath: "-",
        signpostCategory: "foks.runtime",
        deliveredMetricPayloads: 0,
        deliveredDiagnosticPayloads: 0,
        pastMetricPayloads: 0,
        pastDiagnosticPayloads: 0,
        storedMetricPayloads: 0,
        storedDiagnosticPayloads: 0,
        latestMetricPayloadPath: nil,
        latestDiagnosticPayloadPath: nil,
        lastMetricPayloadAt: nil,
        lastDiagnosticPayloadAt: nil,
        lastWriteAt: nil,
        lastError: nil,
        launchMeasurementState: "not started",
        launchMeasurementError: nil
    )
}

enum MetricKitTelemetryInterval {
    case dashboardRefresh
    case localAIAnalysis
    case readOnlyCheck
    case automationRun
    case appBundleOpen
    case projectSync

    var name: StaticString {
        switch self {
        case .dashboardRefresh: "DashboardRefresh"
        case .localAIAnalysis: "LocalAIAnalysis"
        case .readOnlyCheck: "ReadOnlyCheck"
        case .automationRun: "AutomationRun"
        case .appBundleOpen: "AppBundleOpen"
        case .projectSync: "ProjectSync"
        }
    }
}

enum MetricKitTelemetryEvent {
    case appLaunch

    var name: StaticString {
        switch self {
        case .appLaunch: "AppLaunch"
        }
    }
}

final class MetricKitTelemetryCollector: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = MetricKitTelemetryCollector()

    private let lock = NSLock()
    private let storageURL: URL
    private let signpostLog: OSLog
    private var state: State

    private override init() {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("FOKSTerminal", isDirectory: true)
            .appendingPathComponent("MetricKit", isDirectory: true)

        storageURL = root
        signpostLog = MXMetricManager.makeLogHandle(category: "foks.runtime")
        state = State(storagePath: root.path)
        super.init()
    }

    func start() -> MetricKitTelemetrySnapshot {
        guard #available(macOS 12.0, *) else {
            updateState { state in
                state.isRuntimeAvailable = false
                state.lastError = "MetricKit requires macOS 12 or later."
            }
            return snapshot()
        }

        do {
            try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        } catch {
            updateState { state in
                state.isRuntimeAvailable = true
                state.lastError = "MetricKit storage unavailable: \(error.localizedDescription)"
            }
            return snapshot()
        }

        let shouldRegister = lock.locked {
            if state.isRegistered {
                return false
            }
            state.isRuntimeAvailable = true
            state.isRegistered = true
            state.lastError = nil
            return true
        }

        if shouldRegister {
            MXMetricManager.shared.add(self)
        }

        capturePastPayloads()
        refreshStoredCounts()
        return snapshot()
    }

    func beginLaunchMeasurement() {
        guard #available(macOS 13.0, *) else {
            updateState { state in
                state.launchMeasurementState = "unavailable"
                state.launchMeasurementError = "Extended launch measurement requires macOS 13 or later."
            }
            return
        }

        let taskID = MXLaunchTaskID(rawValue: "FOKSTerminalInitialRefresh")
        do {
            try MXMetricManager.extendLaunchMeasurement(forTaskID: taskID)
            updateState { state in
                state.launchMeasurementState = "active"
                state.launchMeasurementError = nil
            }
        } catch {
            updateState { state in
                state.launchMeasurementState = "failed"
                state.launchMeasurementError = error.localizedDescription
            }
        }
    }

    func finishLaunchMeasurement() {
        guard #available(macOS 13.0, *) else { return }
        let taskID = MXLaunchTaskID(rawValue: "FOKSTerminalInitialRefresh")
        do {
            try MXMetricManager.finishExtendedLaunchMeasurement(forTaskID: taskID)
            updateState { state in
                state.launchMeasurementState = "finished"
                state.launchMeasurementError = nil
            }
        } catch {
            updateState { state in
                state.launchMeasurementState = "finish failed"
                state.launchMeasurementError = error.localizedDescription
            }
        }
    }

    func recordEvent(_ event: MetricKitTelemetryEvent) {
        guard snapshot().isRegistered else { return }
        let signpostID = OSSignpostID(log: signpostLog)
        mxSignpost(.event, log: signpostLog, name: event.name, signpostID: signpostID)
    }

    func beginInterval(_ interval: MetricKitTelemetryInterval) -> OSSignpostID? {
        guard snapshot().isRegistered else { return nil }
        let signpostID = OSSignpostID(log: signpostLog)
        mxSignpost(.begin, log: signpostLog, name: interval.name, signpostID: signpostID)
        return signpostID
    }

    func endInterval(_ interval: MetricKitTelemetryInterval, signpostID: OSSignpostID?) {
        guard let signpostID else { return }
        mxSignpost(.end, log: signpostLog, name: interval.name, signpostID: signpostID)
    }

    func snapshot() -> MetricKitTelemetrySnapshot {
        lock.locked {
            state.snapshot()
        }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        guard !payloads.isEmpty else { return }
        let storedPaths = storePayloads(
            payloads.enumerated().map { index, payload in
                PayloadWrite(
                    kind: .metric,
                    source: "delivered",
                    index: index,
                    timestamp: payload.timeStampEnd,
                    data: payload.jsonRepresentation()
                )
            }
        )

        updateState { state in
            state.deliveredMetricPayloads += payloads.count
            state.latestMetricPayloadPath = storedPaths.last?.path
            state.lastMetricPayloadAt = payloads.last?.timeStampEnd
            state.lastWriteAt = Date()
            state.lastError = nil
        }
        refreshStoredCounts()
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        guard !payloads.isEmpty else { return }
        let storedPaths = storePayloads(
            payloads.enumerated().map { index, payload in
                PayloadWrite(
                    kind: .diagnostic,
                    source: "delivered",
                    index: index,
                    timestamp: payload.timeStampEnd,
                    data: payload.jsonRepresentation()
                )
            }
        )

        updateState { state in
            state.deliveredDiagnosticPayloads += payloads.count
            state.latestDiagnosticPayloadPath = storedPaths.last?.path
            state.lastDiagnosticPayloadAt = payloads.last?.timeStampEnd
            state.lastWriteAt = Date()
            state.lastError = nil
        }
        refreshStoredCounts()
    }

    private func capturePastPayloads() {
        guard #available(macOS 12.0, *) else { return }
        let metrics = MXMetricManager.shared.pastPayloads
        let diagnostics = MXMetricManager.shared.pastDiagnosticPayloads

        let metricPaths = storePayloads(
            metrics.enumerated().map { index, payload in
                PayloadWrite(
                    kind: .metric,
                    source: "past",
                    index: index,
                    timestamp: payload.timeStampEnd,
                    data: payload.jsonRepresentation()
                )
            }
        )
        let diagnosticPaths = storePayloads(
            diagnostics.enumerated().map { index, payload in
                PayloadWrite(
                    kind: .diagnostic,
                    source: "past",
                    index: index,
                    timestamp: payload.timeStampEnd,
                    data: payload.jsonRepresentation()
                )
            }
        )

        updateState { state in
            state.pastMetricPayloads = metrics.count
            state.pastDiagnosticPayloads = diagnostics.count
            state.latestMetricPayloadPath = metricPaths.last?.path ?? state.latestMetricPayloadPath
            state.latestDiagnosticPayloadPath = diagnosticPaths.last?.path ?? state.latestDiagnosticPayloadPath
            state.lastMetricPayloadAt = metrics.last?.timeStampEnd ?? state.lastMetricPayloadAt
            state.lastDiagnosticPayloadAt = diagnostics.last?.timeStampEnd ?? state.lastDiagnosticPayloadAt
            if !metricPaths.isEmpty || !diagnosticPaths.isEmpty {
                state.lastWriteAt = Date()
            }
        }
    }

    private func storePayloads(_ writes: [PayloadWrite]) -> [URL] {
        guard !writes.isEmpty else { return [] }

        do {
            try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        } catch {
            updateState { state in
                state.lastError = "MetricKit storage unavailable: \(error.localizedDescription)"
            }
            return []
        }

        var stored: [URL] = []
        for write in writes {
            let url = storageURL.appendingPathComponent(write.fileName)
            do {
                try write.data.write(to: url, options: .atomic)
                stored.append(url)
            } catch {
                updateState { state in
                    state.lastError = "MetricKit payload write failed: \(error.localizedDescription)"
                }
            }
        }
        return stored
    }

    private func refreshStoredCounts() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: storageURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let metricFiles = files.filter { $0.lastPathComponent.hasPrefix("metric-") && $0.pathExtension == "json" }
        let diagnosticFiles = files.filter { $0.lastPathComponent.hasPrefix("diagnostic-") && $0.pathExtension == "json" }
        let latestMetric = latestFile(metricFiles)
        let latestDiagnostic = latestFile(diagnosticFiles)

        updateState { state in
            state.storedMetricPayloads = metricFiles.count
            state.storedDiagnosticPayloads = diagnosticFiles.count
            state.latestMetricPayloadPath = latestMetric?.path ?? state.latestMetricPayloadPath
            state.latestDiagnosticPayloadPath = latestDiagnostic?.path ?? state.latestDiagnosticPayloadPath
            state.lastWriteAt = [latestMetric, latestDiagnostic].compactMap(fileModificationDate).max() ?? state.lastWriteAt
        }
    }

    private func latestFile(_ urls: [URL]) -> URL? {
        urls.max {
            (fileModificationDate($0) ?? .distantPast) < (fileModificationDate($1) ?? .distantPast)
        }
    }

    private func fileModificationDate(_ url: URL?) -> Date? {
        guard let url,
              let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        else {
            return nil
        }
        return values.contentModificationDate
    }

    private func updateState(_ mutate: (inout State) -> Void) {
        lock.locked {
            mutate(&state)
        }
    }
}

private struct PayloadWrite {
    let kind: PayloadKind
    let source: String
    let index: Int
    let timestamp: Date
    let data: Data

    var fileName: String {
        "\(kind.rawValue)-\(source)-\(timestamp.metricKitFileStamp)-\(index).json"
    }
}

private enum PayloadKind: String {
    case metric
    case diagnostic
}

private struct State {
    var isRuntimeAvailable = false
    var isRegistered = false
    var storagePath: String
    var deliveredMetricPayloads = 0
    var deliveredDiagnosticPayloads = 0
    var pastMetricPayloads = 0
    var pastDiagnosticPayloads = 0
    var storedMetricPayloads = 0
    var storedDiagnosticPayloads = 0
    var latestMetricPayloadPath: String?
    var latestDiagnosticPayloadPath: String?
    var lastMetricPayloadAt: Date?
    var lastDiagnosticPayloadAt: Date?
    var lastWriteAt: Date?
    var lastError: String?
    var launchMeasurementState = "not started"
    var launchMeasurementError: String?

    func snapshot() -> MetricKitTelemetrySnapshot {
        MetricKitTelemetrySnapshot(
            isRuntimeAvailable: isRuntimeAvailable,
            isRegistered: isRegistered,
            storagePath: storagePath,
            signpostCategory: "foks.runtime",
            deliveredMetricPayloads: deliveredMetricPayloads,
            deliveredDiagnosticPayloads: deliveredDiagnosticPayloads,
            pastMetricPayloads: pastMetricPayloads,
            pastDiagnosticPayloads: pastDiagnosticPayloads,
            storedMetricPayloads: storedMetricPayloads,
            storedDiagnosticPayloads: storedDiagnosticPayloads,
            latestMetricPayloadPath: latestMetricPayloadPath,
            latestDiagnosticPayloadPath: latestDiagnosticPayloadPath,
            lastMetricPayloadAt: lastMetricPayloadAt,
            lastDiagnosticPayloadAt: lastDiagnosticPayloadAt,
            lastWriteAt: lastWriteAt,
            lastError: lastError,
            launchMeasurementState: launchMeasurementState,
            launchMeasurementError: launchMeasurementError
        )
    }
}

private extension Date {
    var metricKitFileStamp: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
            .string(from: self)
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }
}

private extension NSLock {
    func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
