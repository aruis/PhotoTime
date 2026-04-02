import Testing
@testable import ReelFlow

struct TimelineEngineTests {
    @Test
    func timelineProducesCrossfadeLayersWhenGapIsDisabled() {
        let timeline = TimelineEngine(itemCount: 3, imageDuration: 3.0, transitionDuration: 0.6, transitionDipDuration: 0)

        let outgoing = timeline.snapshot(at: 2.8)
        let incoming = timeline.snapshot(at: 3.1)

        #expect(outgoing.layers.count == 1)
        #expect(outgoing.layers[0].clipIndex == 0)
        #expect(outgoing.layers[0].opacity < 1)
        #expect(incoming.layers.count == 1)
        #expect(incoming.layers[0].clipIndex == 1)
        #expect(incoming.layers[0].opacity > 0)
    }

    @Test
    func timelineLeavesBackgroundGapWhenGapDurationIsSet() {
        let timeline = TimelineEngine(itemCount: 3, imageDuration: 3.0, transitionDuration: 0.6, transitionDipDuration: 0.18)

        let snapshot = timeline.snapshot(at: 3.09)

        #expect(snapshot.layers.isEmpty)
    }

    @Test
    func timelineGapOnlyAffectsMidpointWindow() {
        let timeline = TimelineEngine(itemCount: 3, imageDuration: 3.0, transitionDuration: 0.6, transitionDipDuration: 0.12)

        let beforeGap = timeline.snapshot(at: 2.85)
        let nearMidpoint = timeline.snapshot(at: 3.06)
        let afterGap = timeline.snapshot(at: 3.18)

        #expect(beforeGap.layers.count == 1)
        #expect(beforeGap.layers[0].clipIndex == 0)
        #expect(nearMidpoint.layers.isEmpty)
        #expect(afterGap.layers.count == 1)
        #expect(afterGap.layers[0].clipIndex == 1)
    }
}
