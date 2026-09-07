import Foundation

struct MacroPlaybackProgress: Sendable {
    var eventIndex: Int
    var eventCount: Int
    var loopIndex: Int
    var loopCount: Int?
}

actor MacroPlayer {
    private let mouseEvents: any MouseEventPosting
    private var runTask: Task<Void, Never>?
    private var delayTask: Task<Void, Never>?
    private var runID: UUID?
    private var isPaused = false
    private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
    private var pressedButtons: Set<MouseButton> = []
    private var suspendedButtons: Set<MouseButton> = []
    private var lastPosition: ScreenPoint?

    init(mouseEvents: any MouseEventPosting = MouseEventService()) {
        self.mouseEvents = mouseEvents
    }

    func start(
        macro: MouseMacro,
        progress: @escaping @Sendable (MacroPlaybackProgress) -> Void,
        completion: @escaping @Sendable (String?) -> Void
    ) {
        guard runTask == nil else { return }
        let currentRunID = UUID()
        runID = currentRunID
        runTask = Task { [weak self] in
            guard let self else { return }
            let error = await self.run(macro: macro, progress: progress)
            await self.cleanupAllPressedButtons()
            await self.finish(id: currentRunID)
            completion(error)
        }
        AppLogger.automation.notice("Macro playback started: \(macro.name, privacy: .public)")
    }

    func stop() async {
        let task = runTask
        task?.cancel()
        delayTask?.cancel()
        isPaused = false
        resumePauseWaiters()
        await task?.value
        if task == nil {
            cleanupAllPressedButtons()
        }
        AppLogger.automation.notice("Macro playback stopped")
    }

    func isRunning() -> Bool { runTask != nil }

    func togglePause() -> Bool? {
        guard runTask != nil else { return nil }
        if isPaused {
            isPaused = false
            resumePauseWaiters()
            AppLogger.automation.notice("Macro playback resumed")
        } else {
            isPaused = true
            delayTask?.cancel()
            suspendedButtons = pressedButtons
            releaseActiveButtons()
            AppLogger.automation.notice("Macro playback paused")
        }
        return isPaused
    }

    private func finish(id: UUID) {
        guard runID == id else { return }
        delayTask = nil
        isPaused = false
        resumePauseWaiters()
        runTask = nil
        runID = nil
    }

    private func run(
        macro: MouseMacro,
        progress: @escaping @Sendable (MacroPlaybackProgress) -> Void
    ) async -> String? {
        let totalLoops = macro.repeatMode.resolvedLoopCount(configuredCount: macro.repeatCount)
        var loopIndex = 0

        do {
            while !Task.isCancelled {
                if let totalLoops, loopIndex >= totalLoops { break }
                loopIndex += 1
                var priorTimestamp = 0.0
                for (index, event) in macro.events.enumerated() {
                    try Task.checkCancellation()
                    let eventDelay = max(0, event.timestampMilliseconds - priorTimestamp)
                    try await pauseAwareSleep(milliseconds: PlaybackTiming.scaledMilliseconds(
                        eventDelay,
                        speed: macro.playbackSpeed
                    ))
                    if isPaused {
                        try await waitUntilResumed()
                    } else {
                        try restoreSuspendedButtons()
                    }
                    try post(event)
                    priorTimestamp = max(priorTimestamp, event.timestampMilliseconds)
                    progress(
                        MacroPlaybackProgress(
                            eventIndex: index + 1,
                            eventCount: macro.events.count,
                            loopIndex: loopIndex,
                            loopCount: totalLoops
                        )
                    )
                }

                if totalLoops.map({ loopIndex < $0 }) ?? true {
                    if macro.repeatDelayMilliseconds > 0 {
                        try await pauseAwareSleep(milliseconds: macro.repeatDelayMilliseconds)
                    } else {
                        await Task.yield()
                        try Task.checkCancellation()
                        if isPaused { try await waitUntilResumed() }
                    }
                }
            }
            return nil
        } catch is CancellationError {
            return nil
        } catch {
            AppLogger.automation.error("Macro playback failed: \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
    }

    private func post(_ event: MacroEvent) throws {
        if let position = event.position {
            lastPosition = position
        }
        let position = event.position ?? lastPosition ?? mouseEvents.currentPosition()
        switch event.kind {
        case .mouseMove:
            try mouseEvents.postMove(to: position, dragging: pressedButtons.first)
        case .mouseDown:
            guard let button = event.button else { return }
            try mouseEvents.postButton(button, down: true, at: position)
            pressedButtons.insert(button)
        case .mouseUp:
            guard let button = event.button else { return }
            try mouseEvents.postButton(button, down: false, at: position)
            pressedButtons.remove(button)
        case .scroll:
            try mouseEvents.postScroll(
                deltaX: event.scrollDeltaX ?? 0,
                deltaY: event.scrollDeltaY ?? 0,
                at: position
            )
        }
    }

    private func pauseAwareSleep(milliseconds: Double) async throws {
        var remaining = duration(milliseconds: milliseconds)
        let clock = ContinuousClock()

        while remaining > .zero {
            try await waitUntilResumed()
            let startedAt = clock.now
            let sleepDuration = remaining
            let sleeper = Task<Void, Never> { @Sendable [sleepDuration] in
                try? await ContinuousClock().sleep(for: sleepDuration)
            }
            delayTask = sleeper
            await sleeper.value
            delayTask = nil
            let elapsed = startedAt.duration(to: clock.now)
            remaining = elapsed < remaining ? remaining - elapsed : .zero
            try Task.checkCancellation()
            if !isPaused { return }
        }
    }

    private func waitUntilResumed() async throws {
        if isPaused {
            await withCheckedContinuation { continuation in
                pauseWaiters.append(continuation)
            }
        }
        try Task.checkCancellation()
        try restoreSuspendedButtons()
    }

    private func resumePauseWaiters() {
        let waiters = pauseWaiters
        pauseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func restoreSuspendedButtons() throws {
        guard !isPaused, !suspendedButtons.isEmpty else { return }
        let position = lastPosition ?? mouseEvents.currentPosition()
        for button in suspendedButtons {
            try mouseEvents.postButton(button, down: true, at: position)
            pressedButtons.insert(button)
        }
        suspendedButtons.removeAll()
    }

    private func releaseActiveButtons() {
        let position = lastPosition ?? mouseEvents.currentPosition()
        for button in pressedButtons {
            try? mouseEvents.postButton(button, down: false, at: position)
        }
        pressedButtons.removeAll()
    }

    private func cleanupAllPressedButtons() {
        releaseActiveButtons()
        suspendedButtons.removeAll()
    }

    private func duration(milliseconds: Double) -> Duration {
        .nanoseconds(Int64(max(0, milliseconds) * 1_000_000))
    }
}
