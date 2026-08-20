import Foundation

public struct ClipPlanner: Sendable {
    public let preRoll: TimeInterval
    public let postRoll: TimeInterval
    public let mergeGap: TimeInterval

    public init(
        preRoll: TimeInterval = 1.2,
        postRoll: TimeInterval = 2.6,
        mergeGap: TimeInterval = 0.35
    ) {
        self.preRoll = preRoll
        self.postRoll = postRoll
        self.mergeGap = mergeGap
    }

    public func ranges(for events: [ImpactEvent], assetDuration: TimeInterval) -> [ClipRange] {
        var result: [ClipRange] = []
        for event in events.sorted(by: { $0.time < $1.time }) {
            let start = max(0, event.time - preRoll)
            let end = min(assetDuration, event.time + postRoll)
            guard end > start else { continue }

            if let previous = result.last, start <= previous.end + mergeGap {
                result[result.count - 1] = ClipRange(
                    id: previous.id,
                    start: previous.start,
                    end: max(previous.end, end)
                )
            } else {
                result.append(ClipRange(start: start, end: end))
            }
        }
        return result
    }
}
