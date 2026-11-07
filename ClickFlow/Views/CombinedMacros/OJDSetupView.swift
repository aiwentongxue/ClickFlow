import AppKit
import SwiftUI

@MainActor
final class OJDSetupModel: ObservableObject {
    @Published var busy = false
    @Published var message = ""
    @Published var connected = false
    @Published var permissions = OJDPermissionStatus.unknown
    @Published var sources: [ControllerSourceChoice] = []
    @Published var selectedSourceID = ""
    private let output: ControllerOutputRouter

    init(output: ControllerOutputRouter) { self.output = output }

    func refreshSources() {
        connected = output.isOJDConnected
        if !connected, output.hasOJDFeed, !busy {
            busy = true
            let output = output
            Task {
                await Task.detached { output.disconnectOJD() }.value
                message = String(localized: "ojd.error.disconnected")
                busy = false
                refreshSources()
            }
            return
        }
        let registry = ControllerDeviceRegistry.shared
        sources = registry.physicalControllers().enumerated().map {
            ControllerSourceChoice(id: registry.identifier($0.element), name: "\($0.element.vendorName ?? "Controller") #\($0.offset + 1)")
        }
        let selected = registry.selectedController(preferredName: nil)
        selectedSourceID = selected.map(registry.identifier) ?? ""
    }
    func selectSource(_ id: String) {
        ControllerDeviceRegistry.shared.select(id: id.isEmpty ? nil : id)
        selectedSourceID = id
    }
    func install() async {
        guard !busy else { return }
        busy = true; message = String(localized: "ojd.installing")
        do {
            try await Task.detached { try await OJDService().install() }.value
            message = String(localized: "ojd.installed")
        } catch { message = error.localizedDescription }
        busy = false; refreshSources(); await refreshPermissions()
    }
    func inspect() async {
        guard !busy else { return }
        busy = true
        do {
            let permissions = try await Task.detached {
                let service = OJDService()
                return try OJDPermissionStatus.decodeStatus(service.status())
            }.value
            self.permissions = permissions
            message = String(localized: "ojd.verified")
        } catch { message = error.localizedDescription }
        busy = false; refreshSources(); await refreshPermissions()
    }
    func connect() async {
        guard !busy else { return }
        busy = true; message = String(localized: "ojd.connecting")
        do {
            let output = output
            try await Task.detached { try output.connectOJD() }.value
            message = String(localized: "ojd.connected")
        } catch { message = error.localizedDescription }
        busy = false; refreshSources(); await refreshPermissions()
    }
    func openComponent() async {
        do {
            try await Task.detached { try OJDService().verify() }.value
            NSWorkspace.shared.open(OJDService.appURL)
        } catch { message = error.localizedDescription }
    }

    func refreshPermissions() async {
        guard !busy else { return }
        do {
            permissions = try await Task.detached {
                try OJDPermissionStatus.decodeStatus(OJDService().status())
            }.value
        } catch { permissions = .unknown }
    }

    func disconnect() async {
        guard !busy else { return }
        busy = true
        let output = output
        await Task.detached { output.disconnectOJD() }.value
        message = String(localized: "ojd.disconnected")
        busy = false; refreshSources(); await refreshPermissions()
    }
}

struct ControllerSourceChoice: Identifiable { var id: String; var name: String }

struct OJDSetupView: View {
    @ObservedObject var model: OJDSetupModel
    @EnvironmentObject private var appState: AppState
    private var activityRunning: Bool { appState.isPlayingCombinedMacro || appState.isRecordingCombinedMacro }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("ojd.title", systemImage: "gamecontroller.fill").font(.title2.bold())
                        Text("controller.backend.ojd.description")
                        Text("ojd.instructions").foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                GroupBox("ojd.source") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("ojd.source", selection: Binding(get: { model.selectedSourceID }, set: model.selectSource)) {
                            Text("ojd.source.none").tag("")
                            ForEach(model.sources) { Text($0.name).tag($0.id) }
                        }
                        Text("ojd.source.help").font(.footnote).foregroundStyle(.secondary)
                        Button("ojd.refreshSources") { model.refreshSources() }
                    }.padding(6)
                }.disabled(model.busy || activityRunning || model.connected)
                HStack {
                    Button("ojd.install") { Task { await model.install() } }
                    Button("ojd.check") { Task { await model.inspect() } }
                    Spacer()
                    if model.connected {
                        Button("ojd.disconnect") { Task { await model.disconnect() } }
                    } else {
                        Button("ojd.connect") { Task { await model.connect() } }.buttonStyle(.borderedProminent)
                    }
                    if model.busy { ProgressView().controlSize(.small) }
                }.disabled(model.busy || activityRunning)
                GroupBox("ojd.permissions.title") {
                    VStack(alignment: .leading, spacing: 10) {
                        permissionRow("ojd.permissions.input", state: model.permissions.inputRead) {
                            appState.permissionManager.openInputMonitoringSettings()
                        }
                        permissionRow("ojd.permissions.inject", state: model.permissions.inputInject) {
                            appState.permissionManager.openAccessibilitySettings()
                        }
                        Text("ojd.permissions.help").font(.footnote).foregroundStyle(.secondary)
                        HStack {
                            Button("ojd.permissions.copyPath") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(OJDService.appURL.path, forType: .string)
                            }
                            Button("ojd.permissions.open") { Task { await model.openComponent() } }
                            Button("ojd.permissions.recheck") { Task { await model.refreshPermissions() } }
                        }
                    }.padding(6)
                }
                Label(model.connected ? "ojd.feed.active" : "ojd.feed.inactive", systemImage: model.connected ? "checkmark.circle" : "circle")
                if !model.message.isEmpty {
                    Text(model.message).font(.callout).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                Text("ojd.dependency").font(.footnote).foregroundStyle(.secondary)
                Link("ojd.website", destination: URL(string: "https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.6.0-alpha.1")!)
            }.padding(24).frame(maxWidth: 900, alignment: .leading)
        }
        .navigationTitle("ojd.title")
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refreshPermissions() }
        }
        .task {
            model.refreshSources()
            await model.refreshPermissions()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled { model.refreshSources() }
            }
        }
    }
    private func permissionRow(_ key: LocalizedStringKey, state: String, open: @escaping () -> Void) -> some View {
        HStack {
            Label(key, systemImage: state == "Granted" ? "checkmark.circle.fill" : "circle")
            Spacer()
            Text(state == "Granted" ? "ojd.permissions.granted" : "ojd.permissions.unknown")
                .foregroundStyle(.secondary)
            Button("ojd.permissions.settings", action: open)
        }
    }

}
