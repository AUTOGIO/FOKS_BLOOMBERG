import SwiftUI

@main
struct FOKSTerminalApp: App {
    var body: some Scene {
        WindowGroup {
            TerminalView()
                .frame(minWidth: 1280, minHeight: 820)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
    }
}
