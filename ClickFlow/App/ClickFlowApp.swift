import SwiftUI

@main
struct ClickFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appSession = AppSession()

    var body: some Scene {
        WindowGroup(id: "main") {
            Group {
                if let appState = appSession.appState {
                    RootView()
                        .environmentObject(appState)
                        .onAppear {
                            appDelegate.shutdownHandler = { appState.shutdown() }
                        }
                } else {
                    DisclaimerView(
                        onAccept: appSession.acceptDisclaimer,
                        onDecline: { NSApplication.shared.terminate(nil) }
                    )
                }
            }
        }
        .defaultSize(width: 900, height: 620)

        MenuBarExtra {
            if let appState = appSession.appState {
                MenuBarView()
                    .environmentObject(appState)
            } else {
                DisclaimerMenuBarView()
            }
        } label: {
            MenuBarGlyph()
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct DisclaimerMenuBarView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("disclaimer.menu.required")
        Divider()
        Button("menu.open") {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        Button("menu.quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}

@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var appState: AppState?

    private let disclaimerStore: DisclaimerAcceptanceStore

    init(disclaimerStore: DisclaimerAcceptanceStore = DisclaimerAcceptanceStore()) {
        self.disclaimerStore = disclaimerStore
        appState = disclaimerStore.hasAcceptedCurrentDisclaimer ? AppState() : nil
    }

    func acceptDisclaimer() {
        guard appState == nil else { return }
        disclaimerStore.acceptCurrentDisclaimer()
        appState = AppState()
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
