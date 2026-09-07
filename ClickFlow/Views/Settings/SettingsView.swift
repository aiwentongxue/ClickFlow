import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("settings.permissions") {
                LabeledContent("settings.accessibility") {
                    permissionRow(
                        granted: appState.permissionManager.canPostEvents,
                        request: appState.permissionManager.requestEventPostingAccess,
                        openSettings: appState.permissionManager.openAccessibilitySettings
                    )
                }
                LabeledContent("settings.inputMonitoring") {
                    permissionRow(
                        granted: appState.permissionManager.canListenToEvents,
                        request: appState.permissionManager.requestEventListeningAccess,
                        openSettings: appState.permissionManager.openInputMonitoringSettings
                    )
                }
                Text("permission.inputMonitoring.restartHint")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("permission.refresh") {
                    appState.permissionManager.refresh()
                }
            }
            Section("settings.hotkeys") {
                HotkeySettingsView()
            }
        }
        .formStyle(.grouped)
        .navigationTitle("sidebar.settings")
        .onAppear { appState.permissionManager.refresh() }
    }

    @ViewBuilder
    private func permissionRow(
        granted: Bool,
        request: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(granted ? "permission.granted" : "permission.notGranted")
                .foregroundStyle(granted ? .green : .secondary)
            if !granted {
                Button("permission.request", action: request)
                Button("permission.openSettings", action: openSettings)
            }
        }
    }
}
