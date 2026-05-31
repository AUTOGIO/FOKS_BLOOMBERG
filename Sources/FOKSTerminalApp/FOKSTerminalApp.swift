import SwiftUI
import FOKSTerminalCore

@main
struct FOKSTerminalApp: App {
    var body: some Scene {
        WindowGroup {
            TerminalView()
                .frame(minWidth: 1200, minHeight: 760)
        }
        .windowStyle(.titleBar)
    }
}
