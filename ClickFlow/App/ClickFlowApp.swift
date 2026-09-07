import SwiftUI

@main
struct ClickFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environmentObject(appState)
                .onAppear {
                    appDelegate.shutdownHandler = { appState.shutdown() }
                }
        }
        .defaultSize(width: 900, height: 620)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            MenuBarGlyph()
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var shutdownHandler: (() -> Void)?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        shutdownHandler?()
    }
}
