@preconcurrency import Carbon
import Foundation

enum HotkeyRegistrationError: LocalizedError, Sendable {
    case duplicate
    case registrationFailed(HotkeyAction, OSStatus)
    case handlerInstallationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .duplicate:
            String(localized: "error.hotkeyDuplicate")
        case let .registrationFailed(action, status):
            String(localized: "error.hotkeyRegistration \(action.displayName) \(status)")
        case let .handlerInstallationFailed(status):
            String(localized: "error.hotkeyHandler \(status)")
        }
    }
}

@MainActor
final class GlobalHotkeyManager {
    typealias Handler = @MainActor @Sendable ([HotkeyAction]) -> Void

    private static let signature: OSType = 0x43464C57 // CFLW
    private var eventHandler: EventHandlerRef?
    private var registered: [EventHotKeyRef] = []
    private var actionsByIdentifier: [UInt32: [HotkeyAction]] = [:]
    private(set) var configurations: [HotkeyAction: HotkeyConfiguration] = [:]
    var onAction: Handler?

    init() throws {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            clickFlowHotkeyCallback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard status == noErr else {
            throw HotkeyRegistrationError.handlerInstallationFailed(status)
        }
    }

    func register(_ newConfigurations: [HotkeyAction: HotkeyConfiguration]) throws {
        let effectiveConfigurations = newConfigurations.merging(Self.builtInConfigurations) { current, _ in current }
        guard !HotkeyConflictValidator.hasConflict(effectiveConfigurations) else {
            throw HotkeyRegistrationError.duplicate
        }

        let oldConfigurations = configurations
        unregisterAll()
        do {
            try registerWithoutRollback(effectiveConfigurations)
            configurations = newConfigurations
        } catch {
            unregisterAll()
            let oldEffective = oldConfigurations.merging(Self.builtInConfigurations) { current, _ in current }
            try? registerWithoutRollback(oldEffective)
            configurations = oldConfigurations
            throw error
        }
    }

    private static let builtInConfigurations: [HotkeyAction: HotkeyConfiguration] = [
        .captureFixedPosition: HotkeyConfiguration(
            keyCode: 7,
            modifiers: UInt32(cmdKey | optionKey),
            keyDisplayName: "X"
        )
    ]

    func shutdown() {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    func suspendForCapture() {
        unregisterAll()
    }

    fileprivate func receive(id: UInt32) {
        guard let actions = actionsByIdentifier[id] else { return }
        onAction?(actions)
    }

    private func registerWithoutRollback(_ configurations: [HotkeyAction: HotkeyConfiguration]) throws {
        let grouped = Dictionary(grouping: HotkeyAction.allCases.filter { configurations[$0] != nil }) {
            configurations[$0]?.chord
        }
        let groups = grouped.compactMap { chord, actions -> (HotkeyChord, [HotkeyAction])? in
            guard let chord else { return nil }
            return (chord, actions)
        }.sorted { lhs, rhs in
            let leftIndex = lhs.1.compactMap(HotkeyAction.allCases.firstIndex).min() ?? 0
            let rightIndex = rhs.1.compactMap(HotkeyAction.allCases.firstIndex).min() ?? 0
            return leftIndex < rightIndex
        }

        for (index, group) in groups.enumerated() {
            let identifierValue = UInt32(index + 1)
            var reference: EventHotKeyRef?
            let identifier = EventHotKeyID(signature: Self.signature, id: identifierValue)
            let status = RegisterEventHotKey(
                group.0.keyCode,
                group.0.modifiers,
                identifier,
                GetApplicationEventTarget(),
                OptionBits(kEventHotKeyExclusive),
                &reference
            )
            guard status == noErr, let reference else {
                throw HotkeyRegistrationError.registrationFailed(group.1[0], status)
            }
            registered.append(reference)
            actionsByIdentifier[identifierValue] = group.1
        }
    }

    private func unregisterAll() {
        for reference in registered {
            UnregisterEventHotKey(reference)
        }
        registered.removeAll()
        actionsByIdentifier.removeAll()
    }
}

private let clickFlowHotkeyCallback: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard status == noErr else { return status }
    let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
        manager.receive(id: identifier.id)
    }
    return noErr
}

extension HotkeyAction {
    var displayName: String {
        switch self {
        case .startClicker: String(localized: "hotkey.startClicker")
        case .stopClicker: String(localized: "hotkey.stopClicker")
        case .startMouseRecording: String(localized: "hotkey.startMouseRecording")
        case .stopMouseRecording: String(localized: "hotkey.stopMouseRecording")
        case .playRecentMacro: String(localized: "hotkey.playback")
        case .pauseResumeMacro: String(localized: "hotkey.pauseResumeMacro")
        case .stopMacro: String(localized: "hotkey.stopMacro")
        case .startCombinedRecording: String(localized: "hotkey.startCombinedRecording")
        case .stopCombinedRecording: String(localized: "hotkey.stopCombinedRecording")
        case .playRecentCombinedMacro: String(localized: "hotkey.playCombinedMacro")
        case .pauseResumeCombinedMacro: String(localized: "hotkey.pauseResumeCombinedMacro")
        case .stopCombinedMacro: String(localized: "hotkey.stopCombinedMacro")
        case .captureFixedPosition: String(localized: "hotkey.captureFixedPosition")
        }
    }
}

extension HotkeyConfiguration {
    var displayString: String {
        let modifierText = [
            modifiers & UInt32(cmdKey) != 0 ? "⌘" : "",
            modifiers & UInt32(optionKey) != 0 ? "⌥" : "",
            modifiers & UInt32(controlKey) != 0 ? "⌃" : "",
            modifiers & UInt32(shiftKey) != 0 ? "⇧" : ""
        ].joined()
        return modifierText + (keyDisplayName ?? Self.keyNames[keyCode, default: "Key \(keyCode)"])
    }

    static let keyNames: [UInt32: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        53: "Esc", 36: "Return", 48: "Tab", 49: "Space", 51: "Delete",
        117: "Forward Delete", 123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "Home", 119: "End", 116: "Page Up", 121: "Page Down"
    ]
}

enum HotkeyConflictValidator {
    static func hasConflict(_ configurations: [HotkeyAction: HotkeyConfiguration]) -> Bool {
        let groups = Dictionary(grouping: configurations.keys) { configurations[$0]?.chord }
        return groups.values.contains { actions in
            guard actions.count > 1 else { return false }
            let actionSet = Set(actions)
            return actionSet != Set([.startClicker, .stopClicker])
                && actionSet != Set([.startMouseRecording, .stopMouseRecording])
                && actionSet != Set([.playRecentMacro, .stopMacro])
                && actionSet != Set([.startCombinedRecording, .stopCombinedRecording])
                && actionSet != Set([.playRecentCombinedMacro, .stopCombinedMacro])
        }
    }
}
