import Foundation

struct TimelineLayer {
    let clipIndex: Int
    let opacity: Float
    let progress: Double
}

struct TimelineSnapshot {
    let layers: [TimelineLayer]
}

struct TimelineClip {
    let index: Int
    let start: TimeInterval
    let end: TimeInterval
    let duration: TimeInterval
}

struct TimelineEngine {
    let clips: [TimelineClip]
    let transitionDuration: TimeInterval
    let totalDuration: TimeInterval

    nonisolated init(itemCount: Int, imageDuration: TimeInterval, transitionDuration: TimeInterval) {
        precondition(itemCount > 0, "Timeline requires at least one item")
        precondition(imageDuration > 0)
        precondition(transitionDuration >= 0 && transitionDuration < imageDuration)

        self.transitionDuration = transitionDuration

        let stride = imageDuration - transitionDuration
        var built: [TimelineClip] = []
        built.reserveCapacity(itemCount)

        for index in 0..<itemCount {
            let start = TimeInterval(index) * stride
            built.append(TimelineClip(index: index, start: start, end: start + imageDuration, duration: imageDuration))
        }

        clips = built
        totalDuration = built.last?.end ?? imageDuration
    }

    nonisolated func snapshot(at time: TimeInterval) -> TimelineSnapshot {
        let lastClip = clips.count - 1
        let active = clips.compactMap { clip -> TimelineLayer? in
            guard time >= clip.start, time < clip.end else { return nil }

            var opacity = 1.0
            if transitionDuration > 0 {
                if clip.index > 0, time < clip.start + transitionDuration {
                    opacity = min(opacity, (time - clip.start) / transitionDuration)
                }
                if clip.index < lastClip, time > clip.end - transitionDuration {
                    opacity = min(opacity, (clip.end - time) / transitionDuration)
                }
            }

            guard opacity > 0 else { return nil }
            let progress = min(max((time - clip.start) / clip.duration, 0), 1)
            return TimelineLayer(clipIndex: clip.index, opacity: Float(opacity), progress: progress)
        }

        return TimelineSnapshot(layers: active.sorted { $0.clipIndex < $1.clipIndex })
    }
}
