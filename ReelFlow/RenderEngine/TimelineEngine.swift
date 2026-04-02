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
    let transitionDipDuration: TimeInterval
    let totalDuration: TimeInterval

    nonisolated init(
        itemCount: Int,
        imageDuration: TimeInterval,
        transitionDuration: TimeInterval,
        transitionDipDuration: TimeInterval = 0.18
    ) {
        precondition(itemCount > 0, "Timeline requires at least one item")
        precondition(imageDuration > 0)
        precondition(transitionDuration >= 0 && transitionDuration < imageDuration)

        self.transitionDuration = transitionDuration
        self.transitionDipDuration = max(0, transitionDipDuration)

        let stride = imageDuration + self.transitionDipDuration
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
        let halfFadeDuration = transitionDuration / 2
        let active = clips.compactMap { clip -> TimelineLayer? in
            guard time >= clip.start, time < clip.end else { return nil }

            var opacity = 1.0
            if halfFadeDuration > 0 {
                if clip.index > 0, time < clip.start + halfFadeDuration {
                    let phase = (time - clip.start) / halfFadeDuration
                    opacity = min(opacity, min(max(phase, 0), 1))
                }
                if clip.index < lastClip, time > clip.end - halfFadeDuration {
                    let phase = (time - (clip.end - halfFadeDuration)) / halfFadeDuration
                    opacity = min(opacity, min(max(1 - phase, 0), 1))
                }
            }

            guard opacity > 0 else { return nil }
            let progress = min(max((time - clip.start) / clip.duration, 0), 1)
            return TimelineLayer(clipIndex: clip.index, opacity: Float(opacity), progress: progress)
        }

        return TimelineSnapshot(layers: active.sorted { $0.clipIndex < $1.clipIndex })
    }
}
