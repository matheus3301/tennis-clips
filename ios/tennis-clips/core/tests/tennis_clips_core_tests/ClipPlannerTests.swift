import Testing
@testable import TennisClipsCore

@Test func mergesEventsFromTheSameRally() {
    let planner = ClipPlanner(preRoll: 1.2, postRoll: 2.6, mergeGap: 0.35)
    let events = [
        ImpactEvent(time: 4, score: 1, amplitude: 1, midEnergyRatio: 0.2, highEnergyRatio: 0.1),
        ImpactEvent(time: 6, score: 1, amplitude: 1, midEnergyRatio: 0.2, highEnergyRatio: 0.1),
    ]

    let ranges = planner.ranges(for: events, assetDuration: 20)

    #expect(ranges.count == 1)
    #expect(ranges[0].start == 2.8)
    #expect(ranges[0].end == 8.6)
}

@Test func clampsRangesToTheVideoDuration() {
    let planner = ClipPlanner(preRoll: 1.2, postRoll: 2.6)
    let events = [
        ImpactEvent(time: 0.3, score: 1, amplitude: 1, midEnergyRatio: 0.2, highEnergyRatio: 0.1),
        ImpactEvent(time: 9.5, score: 1, amplitude: 1, midEnergyRatio: 0.2, highEnergyRatio: 0.1),
    ]

    let ranges = planner.ranges(for: events, assetDuration: 10)

    #expect(ranges.first?.start == 0)
    #expect(ranges.last?.end == 10)
}
