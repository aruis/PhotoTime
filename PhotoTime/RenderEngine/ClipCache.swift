import Foundation

actor ClipCache {
    private let provider: AssetProvider
    private let composer: FrameComposer
    private let capacity: Int

    private var storage: [Int: ComposedClip] = [:]
    private var order: [Int] = []

    init(provider: AssetProvider, composer: FrameComposer, capacity: Int = 3) {
        self.provider = provider
        self.composer = composer
        self.capacity = max(capacity, 1)
    }

    func clip(for index: Int) async throws -> ComposedClip {
        if let cached = storage[index] {
            touch(index)
            return cached
        }

        let asset = try await provider.asset(for: index)
        let clip = composer.makeClip(asset)
        storage[index] = clip
        order.append(index)
        evictIfNeeded()
        return clip
    }

    var cachedCount: Int {
        storage.count
    }

    private func touch(_ index: Int) {
        order.removeAll { $0 == index }
        order.append(index)
    }

    private func evictIfNeeded() {
        while order.count > capacity {
            let removed = order.removeFirst()
            storage.removeValue(forKey: removed)
        }
    }
}
