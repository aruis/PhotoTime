import Foundation

actor AssetProvider {
    private let urls: [URL]
    private let targetMaxDimension: Int
    private let logger: RenderLogger
    private let capacity: Int
    private let prefetchMaxConcurrent: Int

    private var storage: [Int: RenderAsset] = [:]
    private var order: [Int] = []
    private var inFlight: [Int: Task<RenderAsset, Error>] = [:]

    init(
        urls: [URL],
        targetMaxDimension: Int,
        logger: RenderLogger,
        capacity: Int = 4,
        prefetchMaxConcurrent: Int = 2
    ) {
        self.urls = urls
        self.targetMaxDimension = targetMaxDimension
        self.logger = logger
        self.capacity = max(1, capacity)
        self.prefetchMaxConcurrent = max(1, prefetchMaxConcurrent)
    }

    func asset(for index: Int) async throws -> RenderAsset {
        if let cached = storage[index] {
            touch(index)
            return cached
        }

        if let task = inFlight[index] {
            return try await task.value
        }

        let url = urls[index]
        let task = Task.detached(priority: .utility) { [targetMaxDimension] in
            try ImageLoader.load(url: url, targetMaxDimension: targetMaxDimension)
        }
        inFlight[index] = task

        do {
            let loaded = try await task.value
            inFlight[index] = nil

            if let cached = storage[index] {
                touch(index)
                return cached
            }

            storage[index] = loaded
            order.append(index)
            evictIfNeeded()
            return loaded
        } catch {
            inFlight[index] = nil
            await logger.log("asset load failed at index \(index): \(url.lastPathComponent), \(error.localizedDescription)")
            throw error
        }
    }

    func prefetch(around index: Int, radius: Int) async {
        guard radius > 0 else { return }
        let lower = max(0, index - radius)
        let upper = min(urls.count - 1, index + radius)
        guard lower <= upper else { return }

        let candidates = (lower...upper).filter { storage[$0] == nil && inFlight[$0] == nil }
        guard !candidates.isEmpty else { return }

        var next = 0
        let initialWorkers = min(prefetchMaxConcurrent, candidates.count)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<initialWorkers {
                let candidate = candidates[next]
                next += 1
                group.addTask {
                    _ = try? await self.asset(for: candidate)
                }
            }

            while await group.next() != nil {
                guard next < candidates.count else { continue }
                let candidate = candidates[next]
                next += 1
                group.addTask {
                    _ = try? await self.asset(for: candidate)
                }
            }
        }
    }

    var cachedCount: Int {
        storage.count
    }

    var inFlightCount: Int {
        inFlight.count
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
