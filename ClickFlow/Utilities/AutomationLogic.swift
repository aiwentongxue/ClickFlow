import Foundation

enum PlaybackTiming {
    static func scaledMilliseconds(_ milliseconds: Double, speed: Double) -> Double {
        milliseconds / max(0.25, min(4, speed))
    }
}

enum ClickExecutionPlanner {
    static func clicksThisRound(gesture: ClickGesture, remaining: Int?) -> Int {
        let planned = gesture == .double ? 2 : 1
        return min(planned, remaining ?? planned)
    }
}

enum MacroTimeline {
    static func setDelay(_ delay: Double, for id: UUID, in events: inout [MacroEvent]) {
        guard let index = events.firstIndex(where: { $0.id == id }) else { return }
        let previous = index == 0 ? 0 : events[index - 1].timestampMilliseconds
        let target = previous + max(0, delay)
        let shift = target - events[index].timestampMilliseconds
        for eventIndex in index..<events.count {
            events[eventIndex].timestampMilliseconds += shift
        }
    }

    static func move(_ selectedIDs: Set<UUID>, direction: Int, in events: inout [MacroEvent]) {
        guard direction == -1 || direction == 1, !selectedIDs.isEmpty else { return }
        let sourceIndex: Int?
        if direction < 0 {
            sourceIndex = events.firstIndex { selectedIDs.contains($0.id) }
        } else {
            sourceIndex = events.lastIndex { selectedIDs.contains($0.id) }
        }
        guard let sourceIndex else { return }
        let destinationIndex = sourceIndex + direction
        guard events.indices.contains(destinationIndex) else { return }
        let times = events.map(\.timestampMilliseconds).sorted()
        events.swapAt(sourceIndex, destinationIndex)
        for index in events.indices { events[index].timestampMilliseconds = times[index] }
    }

    static func setDelay(_ delay: Double, for id: UUID, in events: inout [CombinedMacroEvent]) {
        guard let index = events.firstIndex(where: { $0.id == id }) else { return }
        let previous = index == 0 ? 0 : events[index - 1].timestampMilliseconds
        let target = previous + max(0, delay)
        let shift = target - events[index].timestampMilliseconds
        for eventIndex in index..<events.count {
            events[eventIndex].timestampMilliseconds += shift
        }
    }

    static func move(
        _ selectedIDs: Set<UUID>,
        direction: Int,
        in events: inout [CombinedMacroEvent]
    ) {
        guard direction == -1 || direction == 1, !selectedIDs.isEmpty else { return }
        let sourceIndex = direction < 0
            ? events.firstIndex { selectedIDs.contains($0.id) }
            : events.lastIndex { selectedIDs.contains($0.id) }
        guard let sourceIndex else { return }
        let destinationIndex = sourceIndex + direction
        guard events.indices.contains(destinationIndex) else { return }
        let times = events.map(\.timestampMilliseconds).sorted()
        events.swapAt(sourceIndex, destinationIndex)
        for index in events.indices { events[index].timestampMilliseconds = times[index] }
    }
}

extension MacroRepeatMode {
    func resolvedLoopCount(configuredCount: Int) -> Int? {
        switch self {
        case .once: 1
        case .count: max(1, configuredCount)
        case .unlimited: nil
        }
    }
}
