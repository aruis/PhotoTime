import Testing
@testable import PhotoTime

struct TimelineEngineTests {
    @Test
    func timelineProducesCrossfadeLayers() {
        let timeline = TimelineEngine(itemCount: 3, imageDuration: 3.0, transitionDuration: 0.6)

        let snapshot = timeline.snapshot(at: 2.7)

        #expect(snapshot.layers.count == 2)
        #expect(snapshot.layers[0].clipIndex == 0)
        #expect(snapshot.layers[1].clipIndex == 1)
        #expect(snapshot.layers[1].opacity > 0)
    }
}
