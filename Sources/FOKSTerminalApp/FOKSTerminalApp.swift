import SwiftUI

@main
struct FOKSTerminalApp: App {
    init() {
        let telemetry = MetricKitTelemetryCollector.shared
        _ = telemetry.start()
        telemetry.beginLaunchMeasurement()
        telemetry.recordEvent(.appLaunch)
    }

    var body: some Scene {
        WindowGroup {
            TerminalView()
                .frame(minWidth: 1280, minHeight: 820)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
    }
}
