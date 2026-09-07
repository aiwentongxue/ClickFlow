@preconcurrency import Carbon
import CoreGraphics
import XCTest
@testable import ClickFlow

final class ClickFlowTests: XCTestCase {
    private func waitUntilStopped(
        _ service: AutoClickerService,
        timeout: Duration = .seconds(20)
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while await service.isRunning() {
            if clock.now >= deadline {
                XCTFail("Auto clicker did not stop before the timeout")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func waitUntilStopped(
        _ player: MacroPlayer,
        timeout: Duration = .seconds(20)
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while await player.isRunning() {
            if clock.now >= deadline {
                XCTFail("Macro player did not stop before the timeout")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private func waitUntilStopped(
        _ player: CombinedMacroPlayer,
        timeout: Duration = .seconds(20)
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while await player.isRunning() {
            if clock.now >= deadline {
                XCTFail("Combined macro player did not stop before the timeout")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    func testIntervalAndCPSConversion() {
        var configuration = ClickerConfiguration()
        configuration.setInterval(milliseconds: 1_000)
        XCTAssertEqual(configuration.clicksPerSecond, 1, accuracy: 0.000_1)
        configuration.setInterval(milliseconds: 100)
        XCTAssertEqual(configuration.clicksPerSecond, 10, accuracy: 0.000_1)
        configuration.clicksPerSecond = 100
        XCTAssertEqual(configuration.intervalMilliseconds, 10, accuracy: 0.000_1)
    }

    func testUnsafeClickerConfigurationIsClampedBeforeExecution() {
        var configuration = ClickerConfiguration()
        configuration.intervalMilliseconds = -1
        configuration.finiteClickCount = 0
        let safe = configuration.sanitizedForExecution()
        XCTAssertEqual(safe.intervalMilliseconds, 10)
        XCTAssertEqual(safe.finiteClickCount, 1)

        configuration.intervalMilliseconds = .infinity
        XCTAssertEqual(configuration.sanitizedForExecution().intervalMilliseconds, 60_000)
        XCTAssertEqual(ClickerConfiguration.clampedInterval(forCPS: 0), 60_000)
    }

    @MainActor
    func testSettingsPersistAndDamagedSettingsFallBackSafely() throws {
        let suiteName = "ClickFlowTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        var configuration = ClickerConfiguration()
        configuration.button = .middle
        configuration.countMode = .finite
        configuration.finiteClickCount = 10
        configuration.intervalMilliseconds = 100
        store.saveClickerConfiguration(configuration)
        XCTAssertEqual(SettingsStore(defaults: defaults).loadClickerConfiguration(), configuration)

        defaults.set(Data("damaged".utf8), forKey: "clickerConfiguration")
        XCTAssertEqual(SettingsStore(defaults: defaults).loadClickerConfiguration(), ClickerConfiguration())
    }

    func testMacroStorageSavesReloadsAndDeletesEditedSteps() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = MacroStorage(directoryURL: root)
        var macro = MouseMacro(name: "Saved", events: [.init(timestampMilliseconds: 0, kind: .mouseMove, position: .init(x: 1, y: 2))])
        try await storage.save(macro)
        macro.events.append(.init(timestampMilliseconds: 100, kind: .mouseDown, button: .right))
        try await storage.save(macro)
        let loaded = await storage.loadAll()
        XCTAssertEqual(loaded.macros.count, 1)
        XCTAssertEqual(loaded.macros.first?.id, macro.id)
        XCTAssertEqual(loaded.macros.first?.name, macro.name)
        XCTAssertEqual(loaded.macros.first?.events, macro.events)
        try await storage.delete(id: macro.id)
        let afterDeletion = await storage.loadAll()
        XCTAssertTrue(afterDeletion.macros.isEmpty)
    }

    func testClickerPostsExactFiniteCountsForEveryMouseButton() async throws {
        for button in MouseButton.allCases {
            for count in [1, 10, 100, 1_000] {
                let recorder = RecordedMouseEvents()
                let clicker = AutoClickerService(mouseEvents: recorder)
                var configuration = ClickerConfiguration()
                configuration.button = button
                configuration.countMode = .finite
                configuration.finiteClickCount = count
                configuration.intervalMilliseconds = 10
                await clicker.start(configuration: configuration, progress: { _ in }, completion: { _ in })
                try await waitUntilStopped(clicker)
                let posted = recorder.snapshot()
                XCTAssertEqual(posted.count, count * 2, "\(button) \(count)")
                XCTAssertTrue(posted.allSatisfy { $0.button == button })
                XCTAssertEqual(posted.filter(\.isDown).count, count)
            }
        }
    }

    func testClickerUsesCurrentAndFixedPositionsAndRejectsDuplicateStarts() async throws {
        let recorder = RecordedMouseEvents(currentPosition: .init(x: 12, y: 34))
        let clicker = AutoClickerService(mouseEvents: recorder)
        var configuration = ClickerConfiguration()
        configuration.countMode = .unlimited
        configuration.intervalMilliseconds = 10
        configuration.positionMode = .current
        await clicker.start(configuration: configuration, progress: { _ in }, completion: { _ in })
        await clicker.start(configuration: configuration, progress: { _ in }, completion: { _ in })
        try await Task.sleep(for: .milliseconds(80))
        await clicker.stop()
        let current = recorder.snapshot()
        XCTAssertGreaterThan(current.count, 0)
        XCTAssertLessThan(current.count, 30, "duplicate start must not create a second loop")
        XCTAssertTrue(current.allSatisfy { $0.position == .init(x: 12, y: 34) })

        recorder.reset()
        configuration.positionMode = .fixed
        configuration.fixedPosition = .init(x: -500, y: 250)
        configuration.countMode = .finite
        configuration.finiteClickCount = 1
        await clicker.start(configuration: configuration, progress: { _ in }, completion: { _ in })
        try await waitUntilStopped(clicker)
        XCTAssertTrue(recorder.snapshot().allSatisfy { $0.position == .init(x: -500, y: 250) })
    }

    func testClickerRapidStartStopAndTenMillisecondSixtySecondStress() async throws {
        let recorder = RecordedMouseEvents()
        let clicker = AutoClickerService(mouseEvents: recorder)
        var configuration = ClickerConfiguration()
        configuration.intervalMilliseconds = 10
        configuration.countMode = .unlimited
        for _ in 0..<100 {
            await clicker.start(configuration: configuration, progress: { _ in }, completion: { _ in })
            await clicker.stop()
            let isRunning = await clicker.isRunning()
            XCTAssertFalse(isRunning)
        }
        await clicker.start(configuration: configuration, progress: { _ in }, completion: { _ in })
        try await Task.sleep(for: .seconds(60))
        await clicker.stop()
        let isRunning = await clicker.isRunning()
        XCTAssertFalse(isRunning)
        XCTAssertGreaterThan(recorder.snapshot().count, 10_000)
    }

    func testMacroOrderTimingLoopsAndStopReleasesPressedButton() async throws {
        let recorder = RecordedMouseEvents()
        let player = MacroPlayer(mouseEvents: recorder)
        let macro = MouseMacro(name: "Playback", events: [
            .init(timestampMilliseconds: 0, kind: .mouseMove, position: .init(x: 10, y: 20)),
            .init(timestampMilliseconds: 200, kind: .mouseDown, position: .init(x: 10, y: 20), button: .left),
            .init(timestampMilliseconds: 210, kind: .mouseUp, position: .init(x: 10, y: 20), button: .left),
            .init(timestampMilliseconds: 310, kind: .mouseMove, position: .init(x: -50, y: 40)),
            .init(timestampMilliseconds: 320, kind: .mouseDown, position: .init(x: -50, y: 40), button: .right),
            .init(timestampMilliseconds: 330, kind: .mouseUp, position: .init(x: -50, y: 40), button: .right)
        ])
        await player.start(macro: macro, progress: { _ in }, completion: { _ in })
        try await waitUntilStopped(player)
        let events = recorder.snapshot()
        XCTAssertEqual(events.map(\.kind), [.move, .button, .button, .move, .button, .button])
        XCTAssertEqual(events.map(\.position), [.init(x: 10, y: 20), .init(x: 10, y: 20), .init(x: 10, y: 20), .init(x: -50, y: 40), .init(x: -50, y: 40), .init(x: -50, y: 40)])
        XCTAssertEqual(events.map(\.button), [.left, .left, .left, .left, .right, .right])
        XCTAssertGreaterThanOrEqual(events[1].time - events[0].time, 0.17)
        XCTAssertGreaterThanOrEqual(events[3].time - events[1].time, 0.09)

        recorder.reset()
        let held = MouseMacro(name: "Held", events: [
            .init(timestampMilliseconds: 0, kind: .mouseDown, position: .init(x: 1, y: 2), button: .middle),
            .init(timestampMilliseconds: 2_000, kind: .mouseUp, position: .init(x: 1, y: 2), button: .middle)
        ])
        await player.start(macro: held, progress: { _ in }, completion: { _ in })
        try await Task.sleep(for: .milliseconds(30))
        await player.stop()
        let stopped = recorder.snapshot()
        XCTAssertEqual(stopped.map(\.isDown), [true, false])
        XCTAssertEqual(stopped.last?.button, .middle)

        recorder.reset()
        var looping = macro
        looping.repeatMode = .count
        looping.repeatCount = 1_000
        looping.events = [
            .init(timestampMilliseconds: 0, kind: .mouseDown, position: .init(x: 4, y: 5), button: .left),
            .init(timestampMilliseconds: 0, kind: .mouseUp, position: .init(x: 4, y: 5), button: .left)
        ]
        await player.start(macro: looping, progress: { _ in }, completion: { _ in })
        await player.start(macro: looping, progress: { _ in }, completion: { _ in })
        try await waitUntilStopped(player)
        XCTAssertEqual(recorder.snapshot().count, 2_000)
    }

    func testMouseMacroPauseFreezesTimelineAndRestoresHeldButton() async throws {
        let recorder = RecordedMouseEvents()
        let player = MacroPlayer(mouseEvents: recorder)
        let macro = MouseMacro(name: "Pause", events: [
            .init(timestampMilliseconds: 0, kind: .mouseDown, position: .init(x: 10, y: 20), button: .left),
            .init(timestampMilliseconds: 300, kind: .mouseUp, position: .init(x: 10, y: 20), button: .left)
        ])

        await player.start(macro: macro, progress: { _ in }, completion: { _ in })
        try await Task.sleep(for: .milliseconds(40))
        let mousePaused = await player.togglePause()
        XCTAssertEqual(mousePaused, true)
        XCTAssertEqual(recorder.snapshot().map(\.isDown), [true, false])

        try await Task.sleep(for: .milliseconds(140))
        XCTAssertEqual(recorder.snapshot().map(\.isDown), [true, false])

        let mouseResumed = await player.togglePause()
        XCTAssertEqual(mouseResumed, false)
        try await waitUntilStopped(player)
        let posted = recorder.snapshot()
        XCTAssertEqual(posted.map(\.isDown), [true, false, true, false])
        XCTAssertGreaterThanOrEqual(posted[3].time - posted[2].time, 0.22)
    }

    func testCombinedMacroPauseFreezesTimelineAndRestoresHeldKey() async throws {
        let recorder = RecordedMouseEvents()
        let player = CombinedMacroPlayer(events: recorder)
        let macro = CombinedMacro(name: "Pause", events: [
            .init(timestampMilliseconds: 0, kind: .keyDown, keyCode: 3, keyDisplayName: "F"),
            .init(timestampMilliseconds: 300, kind: .keyUp, keyCode: 3, keyDisplayName: "F")
        ])

        await player.start(macro: macro, progress: { _ in }, completion: { _ in })
        try await Task.sleep(for: .milliseconds(40))
        let combinedPaused = await player.togglePause()
        XCTAssertEqual(combinedPaused, true)
        XCTAssertEqual(recorder.snapshot().map(\.isDown), [true, false])

        try await Task.sleep(for: .milliseconds(140))
        XCTAssertEqual(recorder.snapshot().map(\.isDown), [true, false])

        let combinedResumed = await player.togglePause()
        XCTAssertEqual(combinedResumed, false)
        try await waitUntilStopped(player)
        let posted = recorder.snapshot()
        XCTAssertEqual(posted.map(\.kind), [.key, .key, .key, .key])
        XCTAssertEqual(posted.map(\.isDown), [true, false, true, false])
        XCTAssertGreaterThanOrEqual(posted[3].time - posted[2].time, 0.22)
    }

    func testMacroCodableRoundTrip() throws {
        let macro = MouseMacro(
            name: "Test",
            events: [MacroEvent(timestampMilliseconds: 100, kind: .mouseMove, position: .init(x: 10, y: 20))]
        )
        let data = try JSONEncoder().encode(macro)
        let decoded = try JSONDecoder().decode(MouseMacro.self, from: data)
        XCTAssertEqual(decoded, macro)
    }

    func testPlaybackSpeedScaling() {
        XCTAssertEqual(PlaybackTiming.scaledMilliseconds(100, speed: 2), 50, accuracy: 0.000_1)
        XCTAssertEqual(PlaybackTiming.scaledMilliseconds(100, speed: 0.5), 200, accuracy: 0.000_1)
    }

    func testLoopCounts() {
        XCTAssertEqual(MacroRepeatMode.once.resolvedLoopCount(configuredCount: 99), 1)
        XCTAssertEqual(MacroRepeatMode.count.resolvedLoopCount(configuredCount: 5), 5)
        XCTAssertNil(MacroRepeatMode.unlimited.resolvedLoopCount(configuredCount: 5))
    }

    func testDoubleClickOddRemainder() {
        XCTAssertEqual(ClickExecutionPlanner.clicksThisRound(gesture: .double, remaining: 10), 2)
        XCTAssertEqual(ClickExecutionPlanner.clicksThisRound(gesture: .double, remaining: 1), 1)
    }

    func testCoordinateVisibilityAcrossDisplays() {
        let bounds = [
            CGRect(x: 0, y: 0, width: 1_440, height: 900),
            CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080)
        ]
        XCTAssertTrue(ScreenCoordinateConverter.isVisible(.init(x: -100, y: 500), in: bounds))
        XCTAssertFalse(ScreenCoordinateConverter.isVisible(.init(x: 2_000, y: 500), in: bounds))
    }

    func testMoveSamplerFlushesFinalPoint() {
        var sampler = MouseMoveSampler()
        let first = MacroEvent(timestampMilliseconds: 0, kind: .mouseMove, position: .init(x: 0, y: 0))
        let pending = MacroEvent(timestampMilliseconds: 5, kind: .mouseMove, position: .init(x: 1, y: 1))
        XCTAssertNotNil(sampler.consider(first))
        XCTAssertNil(sampler.consider(pending))
        XCTAssertEqual(sampler.flush()?.position, pending.position)
    }

    func testTimelineDelayShiftsFollowingEvents() {
        let first = MacroEvent(timestampMilliseconds: 0, kind: .mouseMove)
        let second = MacroEvent(timestampMilliseconds: 100, kind: .mouseDown, button: .left)
        let third = MacroEvent(timestampMilliseconds: 150, kind: .mouseUp, button: .left)
        var events = [first, second, third]
        MacroTimeline.setDelay(200, for: second.id, in: &events)
        XCTAssertEqual(events[1].timestampMilliseconds, 200)
        XCTAssertEqual(events[2].timestampMilliseconds, 250)
    }

    func testHotkeyDuplicateDetectionInput() {
        let chord = HotkeyConfiguration(keyCode: 0, modifiers: 0, keyDisplayName: "A")
        XCTAssertFalse(HotkeyConflictValidator.hasConflict([
            .startClicker: chord,
            .stopClicker: chord
        ]))
        XCTAssertFalse(HotkeyConflictValidator.hasConflict([
            .playRecentMacro: chord,
            .stopMacro: chord
        ]))
        XCTAssertFalse(HotkeyConflictValidator.hasConflict([
            .startMouseRecording: chord,
            .stopMouseRecording: chord
        ]))
        XCTAssertFalse(HotkeyConflictValidator.hasConflict([
            .playRecentCombinedMacro: chord,
            .stopCombinedMacro: chord
        ]))
        XCTAssertFalse(HotkeyConflictValidator.hasConflict([
            .startCombinedRecording: chord,
            .stopCombinedRecording: chord
        ]))
        XCTAssertTrue(HotkeyConflictValidator.hasConflict([
            .startClicker: chord,
            .playRecentMacro: chord
        ]))
        XCTAssertTrue(HotkeyConflictValidator.hasConflict([
            .pauseResumeMacro: chord,
            .pauseResumeCombinedMacro: chord
        ]))
        XCTAssertEqual(HotkeyAction.clickerCases, [.startClicker, .stopClicker])
        XCTAssertTrue(HotkeyAction.mouseMacroCases.contains(.pauseResumeMacro))
        XCTAssertTrue(HotkeyAction.combinedMacroCases.contains(.pauseResumeCombinedMacro))
    }

    func testFreshInstallHasNoGlobalHotkeys() {
        XCTAssertTrue(HotkeyConfiguration.defaults.isEmpty)
    }

    func testStorageSkipsDamagedMacroWithoutDeletingIt() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let damagedURL = root.appendingPathComponent("damaged.json")
        try Data("not json".utf8).write(to: damagedURL)

        let storage = MacroStorage(directoryURL: root)
        let result = await storage.loadAll()
        XCTAssertTrue(result.macros.isEmpty)
        XCTAssertEqual(result.damagedFileNames, ["damaged.json"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: damagedURL.path))
    }

    func testAccessibilityPermissionAcceptsEitherTrustedSignal() {
        XCTAssertTrue(PermissionDecision.canPostEvents(accessibilityTrusted: true, postEventTrusted: false))
        XCTAssertTrue(PermissionDecision.canPostEvents(accessibilityTrusted: false, postEventTrusted: true))
        XCTAssertFalse(PermissionDecision.canPostEvents(accessibilityTrusted: false, postEventTrusted: false))
    }

    func testLegacyClickerConfigurationDecodesAsMouseInput() throws {
        let data = Data(#"{"button":"right","gesture":"single","intervalMilliseconds":100,"positionMode":"current","fixedPosition":{"x":0,"y":0},"countMode":"unlimited","finiteClickCount":100}"#.utf8)
        let configuration = try JSONDecoder().decode(ClickerConfiguration.self, from: data)
        XCTAssertEqual(configuration.inputKind, .mouse)
        XCTAssertEqual(configuration.button, .right)
        XCTAssertEqual(configuration.keyboardKey, .defaultKey)
    }

    func testClickPositionOnlyModeFiltersMovement() {
        XCTAssertFalse(MouseRecordingMode.clickPositionsOnly.records(.mouseMove))
        XCTAssertTrue(MouseRecordingMode.clickPositionsOnly.records(.mouseDown))
        XCTAssertTrue(MouseRecordingMode.clickPositionsOnly.records(.mouseUp))
        XCTAssertTrue(MouseRecordingMode.clickPositionsOnly.records(.scroll))
    }

    func testCombinedMacroCodableRoundTrip() throws {
        let macro = CombinedMacro(name: "Combined", events: [
            CombinedMacroEvent(
                timestampMilliseconds: 10,
                kind: .keyDown,
                keyCode: 3,
                keyDisplayName: "F"
            ),
            CombinedMacroEvent(
                timestampMilliseconds: 20,
                kind: .controller,
                controllerName: "Controller",
                controlName: "buttonA",
                controlValue: 1
            )
        ])
        let decoded = try JSONDecoder().decode(CombinedMacro.self, from: JSONEncoder().encode(macro))
        XCTAssertEqual(decoded, macro)
        XCTAssertTrue(decoded.containsControllerEvents)
    }

    func testContinuationAppendsAfterExistingTimeline() {
        let existing = [MacroEvent(timestampMilliseconds: 100, kind: .mouseMove)]
        let newEvents = [
            MacroEvent(timestampMilliseconds: 0, kind: .mouseDown, button: .left),
            MacroEvent(timestampMilliseconds: 50, kind: .mouseUp, button: .left)
        ]
        let result = RecordingTimeline.appending(newEvents, to: existing)
        XCTAssertEqual(result.map(\.timestampMilliseconds), [100, 101, 151])
    }

    func testCombinedTimelineDelayAndReordering() {
        let first = CombinedMacroEvent(timestampMilliseconds: 0, kind: .keyDown, keyCode: 3)
        let second = CombinedMacroEvent(timestampMilliseconds: 100, kind: .keyUp, keyCode: 3)
        let third = CombinedMacroEvent(timestampMilliseconds: 200, kind: .controller)
        var events = [first, second, third]

        MacroTimeline.setDelay(250, for: second.id, in: &events)
        XCTAssertEqual(events.map(\.timestampMilliseconds), [0, 250, 350])

        MacroTimeline.move([third.id], direction: -1, in: &events)
        XCTAssertEqual(events.map(\.id), [first.id, third.id, second.id])
        XCTAssertEqual(events.map(\.timestampMilliseconds), [0, 250, 350])
    }

    func testTerminalStopButtonClickIsRemoved() {
        let intended = MacroEvent(timestampMilliseconds: 0, kind: .mouseMove)
        let stopDown = MacroEvent(timestampMilliseconds: 100, kind: .mouseDown, button: .left)
        let stopUp = MacroEvent(timestampMilliseconds: 140, kind: .mouseUp, button: .left)
        let result = RecordingTimeline.removingTerminalControlClick(
            from: [intended, stopDown, stopUp]
        )
        XCTAssertEqual(result, [intended])
    }

    func testTerminalStopButtonDownIsRemovedIfMouseUpRacesStop() {
        let intendedDown = MacroEvent(timestampMilliseconds: 0, kind: .mouseDown, button: .right)
        let intendedUp = MacroEvent(timestampMilliseconds: 50, kind: .mouseUp, button: .right)
        let stopDown = MacroEvent(timestampMilliseconds: 100, kind: .mouseDown, button: .left)
        XCTAssertEqual(
            RecordingTimeline.removingTerminalControlClick(from: [intendedDown, intendedUp, stopDown]),
            [intendedDown, intendedUp]
        )
    }

    func testCombinedTerminalStopButtonClickIsRemoved() {
        let intended = CombinedMacroEvent(
            timestampMilliseconds: 0,
            kind: .keyDown,
            keyCode: 3,
            keyDisplayName: "F"
        )
        let stopDown = CombinedMacroEvent(
            timestampMilliseconds: 100,
            kind: .mouseDown,
            button: .left
        )
        let stopUp = CombinedMacroEvent(
            timestampMilliseconds: 130,
            kind: .mouseUp,
            button: .left
        )
        XCTAssertEqual(
            RecordingTimeline.removingTerminalControlClick(from: [intended, stopDown, stopUp]),
            [intended]
        )
    }

    func testCombinedTerminalStopHotkeyIsRemovedWithoutDeletingPriorInput() {
        let priorDown = CombinedMacroEvent(
            timestampMilliseconds: 0,
            kind: .keyDown,
            keyCode: 3,
            keyDisplayName: "F"
        )
        let priorUp = CombinedMacroEvent(
            timestampMilliseconds: 20,
            kind: .keyUp,
            keyCode: 3,
            keyDisplayName: "F"
        )
        let priorCommandDown = CombinedMacroEvent(
            timestampMilliseconds: 40,
            kind: .keyDown,
            keyCode: 55,
            keyDisplayName: "Command",
            keyboardModifiers: CGEventFlags.maskCommand.rawValue
        )
        let priorCommandUp = CombinedMacroEvent(
            timestampMilliseconds: 60,
            kind: .keyUp,
            keyCode: 55,
            keyDisplayName: "Command",
            keyboardModifiers: 0
        )
        let commandDown = CombinedMacroEvent(
            timestampMilliseconds: 100,
            kind: .keyDown,
            keyCode: 55,
            keyDisplayName: "Command",
            keyboardModifiers: CGEventFlags.maskCommand.rawValue
        )
        let optionDown = CombinedMacroEvent(
            timestampMilliseconds: 110,
            kind: .keyDown,
            keyCode: 58,
            keyDisplayName: "Option",
            keyboardModifiers: (CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue)
        )
        let stopKeyDown = CombinedMacroEvent(
            timestampMilliseconds: 120,
            kind: .keyDown,
            keyCode: 7,
            keyDisplayName: "X",
            keyboardModifiers: (CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue)
        )
        let configuration = HotkeyConfiguration(
            keyCode: 7,
            modifiers: UInt32(cmdKey | optionKey),
            keyDisplayName: "X"
        )

        XCTAssertEqual(
            RecordingTimeline.removingTerminalHotkey(
                from: [
                    priorDown, priorUp, priorCommandDown, priorCommandUp,
                    commandDown, optionDown, stopKeyDown
                ],
                configuration: configuration
            ),
            [priorDown, priorUp, priorCommandDown, priorCommandUp]
        )
    }
}

private final class RecordedMouseEvents: MouseEventPosting, @unchecked Sendable {
    enum Kind: Equatable {
        case move
        case button
        case scroll
        case key
    }

    struct Event: Equatable {
        let kind: Kind
        let button: MouseButton
        let isDown: Bool
        let position: ScreenPoint
        let time: TimeInterval
    }

    private let lock = NSLock()
    private let configuredCurrentPosition: ScreenPoint
    private var events: [Event] = []

    init(currentPosition: ScreenPoint = .init(x: 0, y: 0)) {
        configuredCurrentPosition = currentPosition
    }

    func currentPosition() -> ScreenPoint { configuredCurrentPosition }

    func postClick(button: MouseButton, at position: ScreenPoint, clickState: Int64) throws {
        try postButton(button, down: true, at: position, clickState: clickState)
        try postButton(button, down: false, at: position, clickState: clickState)
    }

    func postKeyPress(_ key: KeyboardKey) throws {
        try postKey(key, down: true, flags: [])
        try postKey(key, down: false, flags: [])
    }

    func postKey(_ key: KeyboardKey, down: Bool, flags: CGEventFlags) throws {
        append(.init(kind: .key, button: .left, isDown: down, position: configuredCurrentPosition, time: Date.timeIntervalSinceReferenceDate))
    }

    func postButton(_ button: MouseButton, down: Bool, at position: ScreenPoint, clickState: Int64) throws {
        append(.init(kind: .button, button: button, isDown: down, position: position, time: Date.timeIntervalSinceReferenceDate))
    }

    func postMove(to position: ScreenPoint, dragging button: MouseButton?) throws {
        append(.init(kind: .move, button: button ?? .left, isDown: false, position: position, time: Date.timeIntervalSinceReferenceDate))
    }

    func postScroll(deltaX: Int32, deltaY: Int32, at position: ScreenPoint?) throws {
        append(.init(kind: .scroll, button: .left, isDown: false, position: position ?? configuredCurrentPosition, time: Date.timeIntervalSinceReferenceDate))
    }

    func snapshot() -> [Event] {
        lock.withLock { events }
    }

    func reset() {
        lock.withLock { events.removeAll() }
    }

    private func append(_ event: Event) {
        lock.withLock { events.append(event) }
    }
}
