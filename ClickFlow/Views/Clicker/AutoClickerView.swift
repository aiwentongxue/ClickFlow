import AppKit
import SwiftUI

struct AutoClickerView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("clicker.status") {
                LabeledContent("common.state") {
                    Text(appState.isClickerRunning ? "status.running" : "status.stopped")
                }
                LabeledContent("clicker.count") {
                    if appState.clickerConfiguration.countMode == .finite {
                        Text("\(appState.clickCount) / \(appState.clickerConfiguration.finiteClickCount)")
                    } else {
                        Text(appState.clickCount.formatted())
                    }
                }
                if appState.isClickerRunning {
                    LabeledContent("clicker.cps") {
                        Text("\(appState.clickerConfiguration.clicksPerSecond.formatted(.number.precision(.fractionLength(0...2)))) CPS")
                    }
                }
            }

            Section("clicker.configuration") {
                Picker("clicker.inputKind", selection: $appState.clickerConfiguration.inputKind) {
                    Text("clicker.input.mouse").tag(ClickerInputKind.mouse)
                    Text("clicker.input.keyboard").tag(ClickerInputKind.keyboard)
                }
                if appState.clickerConfiguration.inputKind == .mouse {
                    Picker("clicker.button", selection: $appState.clickerConfiguration.button) {
                        ForEach(MouseButton.allCases) { button in
                            Text(button.localizedName).tag(button)
                        }
                    }
                } else {
                    LabeledContent("clicker.keyboardKey") {
                        KeyboardKeyRecorderButton(key: $appState.clickerConfiguration.keyboardKey)
                            .frame(width: 150)
                    }
                }
                Picker("clicker.gesture", selection: $appState.clickerConfiguration.gesture) {
                    ForEach(ClickGesture.allCases) { gesture in
                        Text(gesture.localizedName).tag(gesture)
                    }
                }
                LabeledContent("clicker.interval") {
                    TextField("", value: intervalBinding, format: .number.precision(.fractionLength(0...2)))
                        .frame(width: 100)
                    Text("ms")
                }
                LabeledContent("clicker.cps") {
                    TextField("", value: cpsBinding, format: .number.precision(.fractionLength(0...3)))
                        .frame(width: 100)
                    Text("CPS")
                }
            }

            if appState.clickerConfiguration.inputKind == .mouse {
              Section("clicker.position") {
                Picker("clicker.position.mode", selection: $appState.clickerConfiguration.positionMode) {
                    Text("clicker.position.current").tag(ClickPositionMode.current)
                    Text("clicker.position.fixed").tag(ClickPositionMode.fixed)
                }
                if appState.clickerConfiguration.positionMode == .fixed {
                    HStack {
                        TextField("X", value: $appState.clickerConfiguration.fixedPosition.x, format: .number)
                        TextField("Y", value: $appState.clickerConfiguration.fixedPosition.y, format: .number)
                        Button("clicker.position.capture") { appState.captureCurrentPosition() }
                    }
                    Text("clicker.position.shortcutHint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
              }
            }

            Section("clicker.repeat") {
                Picker("clicker.count.mode", selection: $appState.clickerConfiguration.countMode) {
                    Text("clicker.unlimited").tag(ClickCountMode.unlimited)
                    Text("clicker.finite").tag(ClickCountMode.finite)
                }
                if appState.clickerConfiguration.countMode == .finite {
                    Stepper(value: $appState.clickerConfiguration.finiteClickCount, in: 1...1_000_000) {
                        Text(appState.clickerConfiguration.finiteClickCount.formatted())
                    }
                }
            }

            Button(appState.isClickerRunning ? "clicker.stop" : "clicker.start") {
                appState.toggleClicker()
            }
                .buttonStyle(.borderedProminent)
        }
        .formStyle(.grouped)
        .navigationTitle("sidebar.clicker")
        .onChange(of: appState.clickerConfiguration) { _, configuration in
            appState.settingsStore.saveClickerConfiguration(configuration)
        }
    }

    private var intervalBinding: Binding<Double> {
        Binding(
            get: { appState.clickerConfiguration.intervalMilliseconds },
            set: { appState.clickerConfiguration.setInterval(milliseconds: $0) }
        )
    }

    private var cpsBinding: Binding<Double> {
        Binding(
            get: { appState.clickerConfiguration.clicksPerSecond },
            set: { appState.clickerConfiguration.clicksPerSecond = $0 }
        )
    }
}

private struct KeyboardKeyRecorderButton: NSViewRepresentable {
    @Binding var key: KeyboardKey

    func makeNSView(context: Context) -> SingleKeyCaptureButton {
        let button = SingleKeyCaptureButton()
        button.bezelStyle = .rounded
        button.key = key
        button.onChange = { key = $0 }
        button.updateTitle()
        return button
    }

    func updateNSView(_ button: SingleKeyCaptureButton, context: Context) {
        button.key = key
        button.onChange = { key = $0 }
        button.updateTitle()
    }
}

private final class SingleKeyCaptureButton: NSButton {
    var key: KeyboardKey = .defaultKey
    var onChange: ((KeyboardKey) -> Void)?
    private var isCapturing = false

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        isCapturing = true
        title = String(localized: "clicker.keyboardKey.pressNow")
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isCapturing else {
            super.keyDown(with: event)
            return
        }
        let code = UInt16(event.keyCode)
        let known = HotkeyConfiguration.keyNames[UInt32(code)]
        let characters = event.charactersIgnoringModifiers?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let name = known ?? ((characters?.isEmpty == false) ? characters : nil) ?? "Key \(code)"
        let captured = KeyboardKey(keyCode: code, displayName: name)
        key = captured
        isCapturing = false
        updateTitle()
        window?.makeFirstResponder(nil)
        onChange?(captured)
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        isCapturing = false
        updateTitle()
        return result
    }

    func updateTitle() {
        guard !isCapturing else { return }
        title = key.displayName
    }
}
