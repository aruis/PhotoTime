import Foundation
import CoreGraphics

enum MobileResolutionPreset: String, CaseIterable, Sendable, Identifiable {
    case hd720
    case fullHD1080
    case uhd4K

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hd720: return "720p"
        case .fullHD1080: return "1080p"
        case .uhd4K: return "4K"
        }
    }

    var size: CGSize {
        switch self {
        case .hd720: return CGSize(width: 1280, height: 720)
        case .fullHD1080: return CGSize(width: 1920, height: 1080)
        case .uhd4K: return CGSize(width: 3840, height: 2160)
        }
    }
}

enum MobileDurationPreset: String, CaseIterable, Sendable, Identifiable {
    case quick
    case standard
    case relaxed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quick: return "快节奏"
        case .standard: return "标准"
        case .relaxed: return "舒缓"
        }
    }

    var imageDuration: TimeInterval {
        switch self {
        case .quick: return 1.5
        case .standard: return 2.5
        case .relaxed: return 4.0
        }
    }
}

enum MobileTransitionPreset: String, CaseIterable, Sendable, Identifiable {
    case off
    case soft
    case standard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "关闭"
        case .soft: return "柔和"
        case .standard: return "标准"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .off: return 0
        case .soft: return 0.4
        case .standard: return 0.8
        }
    }
}

enum MobileKenBurnsPreset: String, CaseIterable, Sendable, Identifiable {
    case off
    case subtle
    case standard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "关闭"
        case .subtle: return "轻微"
        case .standard: return "标准"
        }
    }
}

struct MobileRenderConfiguration: Sendable {
    var resolution: MobileResolutionPreset = .fullHD1080
    var fps: Int = 30
    var duration: MobileDurationPreset = .standard
    var transition: MobileTransitionPreset = .soft
    var kenBurns: MobileKenBurnsPreset = .subtle
    var shutterSoundEnabled = true
    var shutterSoundPreset: ShutterSoundPreset = .canonEOS
    var shutterSoundVolume: Double = 0.72

    func makeRenderSettings(bundle: Bundle = .main) -> RenderSettings {
        let shutterTrack: ShutterSoundTrackSettings?
        if shutterSoundEnabled, let url = ShutterSoundCatalog.bundledURL(for: shutterSoundPreset, bundle: bundle) {
            shutterTrack = ShutterSoundTrackSettings(sourceURL: url, volume: shutterSoundVolume)
        } else {
            shutterTrack = nil
        }

        return RenderSettings(
            outputSize: resolution.size,
            fps: Int32(fps),
            imageDuration: duration.imageDuration,
            transitionDuration: transition.duration,
            transitionEnabled: transition != .off,
            transitionStyle: .crossfade,
            transitionDipDuration: transition == .off ? 0 : 0.18,
            orientationStrategy: .followAsset,
            enableKenBurns: kenBurns != .off,
            kenBurnsIntensity: {
                switch kenBurns {
                case .off: return .small
                case .subtle: return .small
                case .standard: return .medium
                }
            }(),
            layout: .default,
            plate: .default,
            canvas: CanvasSettings(
                backgroundGray: 0.09,
                paperWhite: 0.98,
                strokeGray: 0.82,
                textGray: 0.15
            ),
            audioTrack: nil,
            shutterSoundTrack: shutterTrack
        )
    }
}
