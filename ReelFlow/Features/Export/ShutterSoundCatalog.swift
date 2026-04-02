import Foundation

enum ShutterSoundCatalog {
    nonisolated private static let subdirectory = "ShutterSounds"
    nonisolated private static let fileExtension = "m4a"

    nonisolated static func bundledURL(for preset: ShutterSoundPreset, bundle: Bundle = .main) -> URL? {
        if let subdirectoryURL = bundle.url(
            forResource: preset.resourceName,
            withExtension: fileExtension,
            subdirectory: subdirectory
        ) {
            return subdirectoryURL
        }

        // Xcode's synchronized groups may flatten files into Resources/.
        return bundle.url(
            forResource: preset.resourceName,
            withExtension: fileExtension
        )
    }
}
