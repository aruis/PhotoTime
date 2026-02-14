import CoreGraphics
import CoreImage
import Foundation

enum TransitionStyle: String, Codable, Sendable {
    case crossfade
}

enum PhotoOrientationStrategy: String, Codable, Sendable {
    case followAsset
    case forceLandscape
    case forcePortrait
}

enum PlatePlacement: String, Codable, Sendable {
    case frame
    case canvasBottom
}

struct LayoutSettings: Codable, Sendable {
    let horizontalMargin: Double
    let topMargin: Double
    let bottomMargin: Double
    let innerPadding: Double

    nonisolated static let `default` = LayoutSettings(
        horizontalMargin: 180,
        topMargin: 72,
        bottomMargin: 96,
        innerPadding: 24
    )
}

struct PlateSettings: Codable, Sendable {
    let enabled: Bool
    let height: Double
    let baselineOffset: Double
    let fontSize: Double
    let placement: PlatePlacement

    nonisolated static let `default` = PlateSettings(
        enabled: true,
        height: 96,
        baselineOffset: 18,
        fontSize: 26,
        placement: .frame
    )
}

struct CanvasSettings: Codable, Sendable {
    let backgroundGray: Double
    let paperWhite: Double
    let strokeGray: Double
    let textGray: Double

    nonisolated static let `default` = CanvasSettings(
        backgroundGray: 0.09,
        paperWhite: 0.98,
        strokeGray: 0.82,
        textGray: 0.15
    )
}

struct AudioTrackSettings: Sendable {
    let sourceURL: URL
    let volume: Double
    let loopEnabled: Bool

    nonisolated init(sourceURL: URL, volume: Double = 1, loopEnabled: Bool = false) {
        self.sourceURL = sourceURL
        self.volume = max(0, min(volume, 1))
        self.loopEnabled = loopEnabled
    }
}

struct RenderSettings {
    let outputSize: CGSize
    let fps: Int32
    let imageDuration: TimeInterval
    let transitionDuration: TimeInterval
    let transitionEnabled: Bool
    let transitionStyle: TransitionStyle
    let orientationStrategy: PhotoOrientationStrategy
    let enableKenBurns: Bool
    let prefetchRadius: Int
    let prefetchMaxConcurrent: Int
    let layout: LayoutSettings
    let plate: PlateSettings
    let canvas: CanvasSettings
    let audioTrack: AudioTrackSettings?

    nonisolated init(
        outputSize: CGSize,
        fps: Int32,
        imageDuration: TimeInterval,
        transitionDuration: TimeInterval,
        transitionEnabled: Bool = true,
        transitionStyle: TransitionStyle = .crossfade,
        orientationStrategy: PhotoOrientationStrategy = .followAsset,
        enableKenBurns: Bool,
        prefetchRadius: Int = 1,
        prefetchMaxConcurrent: Int = 2,
        layout: LayoutSettings = .default,
        plate: PlateSettings = .default,
        canvas: CanvasSettings = .default,
        audioTrack: AudioTrackSettings? = nil
    ) {
        self.outputSize = outputSize
        self.fps = fps
        self.imageDuration = imageDuration
        self.transitionDuration = transitionDuration
        self.transitionEnabled = transitionEnabled
        self.transitionStyle = transitionStyle
        self.orientationStrategy = orientationStrategy
        self.enableKenBurns = enableKenBurns
        self.prefetchRadius = max(0, prefetchRadius)
        self.prefetchMaxConcurrent = max(1, prefetchMaxConcurrent)
        self.layout = layout
        self.plate = plate
        self.canvas = canvas
        self.audioTrack = audioTrack
    }

    nonisolated static let mvp = RenderSettings(
        outputSize: CGSize(width: 1920, height: 1080),
        fps: 30,
        imageDuration: 3.0,
        transitionDuration: 0.6,
        transitionEnabled: true,
        transitionStyle: .crossfade,
        orientationStrategy: .followAsset,
        enableKenBurns: true,
        prefetchRadius: 1,
        prefetchMaxConcurrent: 2,
        layout: .default,
        plate: .default,
        canvas: .default
    )

    nonisolated init(template: RenderTemplate) {
        self.init(
            outputSize: CGSize(width: template.output.width, height: template.output.height),
            fps: template.output.fps,
            imageDuration: template.timeline.imageDuration,
            transitionDuration: template.timeline.transitionDuration,
            transitionEnabled: template.transition.enabled,
            transitionStyle: template.transition.style,
            orientationStrategy: template.motion.orientationStrategy,
            enableKenBurns: template.motion.enableKenBurns,
            prefetchRadius: template.performance.prefetchRadius,
            prefetchMaxConcurrent: template.performance.prefetchMaxConcurrent,
            layout: .init(
                horizontalMargin: template.layout.horizontalMargin,
                topMargin: template.layout.topMargin,
                bottomMargin: template.layout.bottomMargin,
                innerPadding: template.layout.innerPadding
            ),
            plate: .init(
                enabled: template.plate.enabled,
                height: template.plate.height,
                baselineOffset: template.plate.baselineOffset,
                fontSize: template.plate.fontSize,
                placement: template.plate.placement
            ),
            canvas: .init(
                backgroundGray: template.canvas.backgroundGray,
                paperWhite: template.canvas.paperWhite,
                strokeGray: template.canvas.strokeGray,
                textGray: template.canvas.textGray
            ),
            audioTrack: template.audio.enabled ? .init(
                sourceURL: URL(fileURLWithPath: template.audio.filePath),
                volume: template.audio.volume,
                loopEnabled: template.audio.loopEnabled
            ) : nil
        )
    }

    nonisolated var template: RenderTemplate {
        RenderTemplate(
            output: .init(
                width: Int(outputSize.width.rounded()),
                height: Int(outputSize.height.rounded()),
                fps: fps
            ),
            timeline: .init(
                imageDuration: imageDuration,
                transitionDuration: transitionDuration
            ),
            transition: .init(style: transitionStyle, enabled: transitionEnabled),
            motion: .init(enableKenBurns: enableKenBurns, orientationStrategy: orientationStrategy),
            performance: .init(
                prefetchRadius: prefetchRadius,
                prefetchMaxConcurrent: prefetchMaxConcurrent
            ),
            layout: .init(
                horizontalMargin: layout.horizontalMargin,
                topMargin: layout.topMargin,
                bottomMargin: layout.bottomMargin,
                innerPadding: layout.innerPadding
            ),
            plate: .init(
                enabled: plate.enabled,
                height: plate.height,
                baselineOffset: plate.baselineOffset,
                fontSize: plate.fontSize,
                placement: plate.placement
            ),
            canvas: .init(
                backgroundGray: canvas.backgroundGray,
                paperWhite: canvas.paperWhite,
                strokeGray: canvas.strokeGray,
                textGray: canvas.textGray
            ),
            audio: .init(
                enabled: audioTrack != nil,
                filePath: audioTrack?.sourceURL.path ?? "",
                volume: audioTrack?.volume ?? 1,
                loopEnabled: audioTrack?.loopEnabled ?? false
            )
        )
    }

    nonisolated var effectiveTransitionDuration: TimeInterval {
        transitionEnabled ? transitionDuration : 0
    }
}

struct RenderTemplate: Codable, Sendable {
    nonisolated static let currentSchemaVersion = 3

    let schemaVersion: Int
    let output: Output
    let timeline: Timeline
    let transition: Transition
    let motion: Motion
    let performance: Performance
    let layout: Layout
    let plate: Plate
    let canvas: Canvas
    let audio: Audio

    nonisolated init(
        schemaVersion: Int = RenderTemplate.currentSchemaVersion,
        output: Output,
        timeline: Timeline,
        transition: Transition,
        motion: Motion,
        performance: Performance,
        layout: Layout,
        plate: Plate,
        canvas: Canvas,
        audio: Audio = .default
    ) {
        self.schemaVersion = schemaVersion
        self.output = output
        self.timeline = timeline
        self.transition = transition
        self.motion = motion
        self.performance = performance
        self.layout = layout
        self.plate = plate
        self.canvas = canvas
        self.audio = audio
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case output
        case timeline
        case transition
        case motion
        case performance
        case layout
        case plate
        case canvas
        case audio
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        output = try container.decode(Output.self, forKey: .output)
        timeline = try container.decode(Timeline.self, forKey: .timeline)
        transition = try container.decodeIfPresent(Transition.self, forKey: .transition) ?? .default
        motion = try container.decode(Motion.self, forKey: .motion)
        performance = try container.decode(Performance.self, forKey: .performance)
        layout = try container.decodeIfPresent(Layout.self, forKey: .layout) ?? .default
        plate = try container.decodeIfPresent(Plate.self, forKey: .plate) ?? .default
        canvas = try container.decodeIfPresent(Canvas.self, forKey: .canvas) ?? .default
        audio = try container.decodeIfPresent(Audio.self, forKey: .audio) ?? .default
    }

    struct Output: Codable, Sendable {
        let width: Int
        let height: Int
        let fps: Int32
    }

    struct Timeline: Codable, Sendable {
        let imageDuration: TimeInterval
        let transitionDuration: TimeInterval
    }

    struct Transition: Codable, Sendable {
        let style: TransitionStyle
        let enabled: Bool

        nonisolated static let `default` = Transition(style: .crossfade, enabled: true)

        private enum CodingKeys: String, CodingKey {
            case style
            case enabled
        }

        nonisolated init(style: TransitionStyle, enabled: Bool = true) {
            self.style = style
            self.enabled = enabled
        }

        nonisolated init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            style = try container.decodeIfPresent(TransitionStyle.self, forKey: .style) ?? .crossfade
            enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        }
    }

    struct Motion: Codable, Sendable {
        let enableKenBurns: Bool
        let orientationStrategy: PhotoOrientationStrategy

        private enum CodingKeys: String, CodingKey {
            case enableKenBurns
            case orientationStrategy
        }

        nonisolated init(enableKenBurns: Bool, orientationStrategy: PhotoOrientationStrategy = .followAsset) {
            self.enableKenBurns = enableKenBurns
            self.orientationStrategy = orientationStrategy
        }

        nonisolated init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enableKenBurns = try container.decode(Bool.self, forKey: .enableKenBurns)
            orientationStrategy = try container.decodeIfPresent(PhotoOrientationStrategy.self, forKey: .orientationStrategy) ?? .followAsset
        }
    }

    struct Performance: Codable, Sendable {
        let prefetchRadius: Int
        let prefetchMaxConcurrent: Int
    }

    struct Layout: Codable, Sendable {
        let horizontalMargin: Double
        let topMargin: Double
        let bottomMargin: Double
        let innerPadding: Double

        nonisolated static let `default` = Layout(
            horizontalMargin: 180,
            topMargin: 72,
            bottomMargin: 96,
            innerPadding: 24
        )
    }

    struct Plate: Codable, Sendable {
        let enabled: Bool
        let height: Double
        let baselineOffset: Double
        let fontSize: Double
        let placement: PlatePlacement

        nonisolated static let `default` = Plate(
            enabled: true,
            height: 96,
            baselineOffset: 18,
            fontSize: 26,
            placement: .frame
        )

        private enum CodingKeys: String, CodingKey {
            case enabled
            case height
            case baselineOffset
            case fontSize
            case placement
        }

        nonisolated init(
            enabled: Bool,
            height: Double,
            baselineOffset: Double,
            fontSize: Double,
            placement: PlatePlacement = .frame
        ) {
            self.enabled = enabled
            self.height = height
            self.baselineOffset = baselineOffset
            self.fontSize = fontSize
            self.placement = placement
        }

        nonisolated init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
            height = try container.decodeIfPresent(Double.self, forKey: .height) ?? 96
            baselineOffset = try container.decodeIfPresent(Double.self, forKey: .baselineOffset) ?? 18
            fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 26
            placement = try container.decodeIfPresent(PlatePlacement.self, forKey: .placement) ?? .frame
        }
    }

    struct Canvas: Codable, Sendable {
        let backgroundGray: Double
        let paperWhite: Double
        let strokeGray: Double
        let textGray: Double

        nonisolated static let `default` = Canvas(
            backgroundGray: 0.09,
            paperWhite: 0.98,
            strokeGray: 0.82,
            textGray: 0.15
        )
    }

    struct Audio: Codable, Sendable {
        let enabled: Bool
        let filePath: String
        let volume: Double
        let loopEnabled: Bool

        nonisolated static let `default` = Audio(enabled: false, filePath: "", volume: 1, loopEnabled: false)

        private enum CodingKeys: String, CodingKey {
            case enabled
            case filePath
            case volume
            case loopEnabled
        }

        nonisolated init(enabled: Bool, filePath: String, volume: Double = 1, loopEnabled: Bool = false) {
            self.enabled = enabled && !filePath.isEmpty
            self.filePath = filePath
            self.volume = max(0, min(volume, 1))
            self.loopEnabled = loopEnabled
        }

        nonisolated init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
            let filePath = try container.decodeIfPresent(String.self, forKey: .filePath) ?? ""
            let volume = try container.decodeIfPresent(Double.self, forKey: .volume) ?? 1
            let loopEnabled = try container.decodeIfPresent(Bool.self, forKey: .loopEnabled) ?? false
            self.init(enabled: enabled, filePath: filePath, volume: volume, loopEnabled: loopEnabled)
        }
    }
}

struct ExifInfo: Sendable {
    let shutter: String?
    let aperture: String?
    let iso: String?
    let focalLength: String?

    nonisolated var plateText: String {
        let shutterValue = shutter ?? "--"
        let apertureValue = aperture ?? "--"
        let isoValue = iso ?? "--"
        let focalValue = focalLength ?? "--"
        return "S \(shutterValue)   A \(apertureValue)   ISO \(isoValue)   F \(focalValue)"
    }
}

struct RenderAsset {
    let url: URL
    let image: CIImage
    let exif: ExifInfo
}
