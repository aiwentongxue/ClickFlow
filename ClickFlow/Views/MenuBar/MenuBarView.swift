import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("ClickFlow")
        Divider()
        Text(appState.isClickerRunning ? "menu.clicker.running" : "menu.clicker.stopped")
        Text(appState.isMouseMacroPaused ? "menu.macro.paused" : (appState.isPlayingMacro ? "menu.macro.running" : "menu.macro.stopped"))
        Text(appState.isCombinedMacroPaused ? "menu.combined.paused" : (appState.isPlayingCombinedMacro ? "menu.combined.running" : "menu.combined.stopped"))
        Divider()
        Button(appState.isClickerRunning ? "clicker.stop" : "clicker.start") {
            appState.toggleClicker()
        }
        Button("menu.playRecentMouse") { appState.playRecentMacro() }
        Button(appState.isMouseMacroPaused ? "macros.resumePlayback" : "macros.pause") {
            appState.toggleMouseMacroPause()
        }
        .disabled(!appState.isPlayingMacro)
        Button("menu.stopMacro") { appState.stopPlayback() }
            .disabled(!appState.isPlayingMacro)
        Button("menu.playRecentCombined") { appState.playRecentCombinedMacro() }
        Button(appState.isCombinedMacroPaused ? "macros.resumePlayback" : "macros.pause") {
            appState.toggleCombinedMacroPause()
        }
        .disabled(!appState.isPlayingCombinedMacro)
        Button("menu.stopCombined") { appState.stopCombinedPlayback() }
            .disabled(!appState.isPlayingCombinedMacro)
        Button("menu.emergency") { appState.emergencyStop() }
        Divider()
        Button("menu.open") {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        Button("menu.quit") {
            appState.shutdown()
            NSApplication.shared.terminate(nil)
        }
    }
}

struct MenuBarGlyph: View {
    var body: some View {
        ZStack {
            Image(systemName: "arrow.triangle.2.circlepath")
            Image(systemName: "cursorarrow")
                .font(.system(size: 8, weight: .bold))
                .offset(x: 1, y: 1)
        }
        .symbolRenderingMode(.monochrome)
    }
}
