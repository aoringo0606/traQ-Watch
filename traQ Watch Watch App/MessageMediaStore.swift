import Foundation
import Combine
import UIKit

@MainActor
final class MessageMediaStore: ObservableObject {
    enum Phase { case loading, ready, notImage, unicode(String), failed(String) }
    @Published private(set) var phases: [MessageMediaResource: Phase] = [:]
    private let cache = NSCache<NSString, UIImage>()
    private let auth: AuthManager
    private let client = ImageHTTPClient()
    private var catalog: Task<[String: TraQStamp], Error>?
    private var queue: [MessageMediaResource] = []
    private var generation = 0
    private var tasks: [MessageMediaResource: Task<Void, Never>] = [:]

    init(auth: AuthManager) {
        self.auth = auth
        cache.totalCostLimit = 8 * 1024 * 1024
        cache.countLimit = 64
    }

    func image(for resource: MessageMediaResource) -> UIImage? {
        cache.object(forKey: resource.cacheKey as NSString)
    }

    func stampImage(_ stamp: StampReference) -> UIImage? {
        guard let image = image(for: .stamp(stamp.name)), let cgImage = image.cgImage else { return nil }
        return UIImage(cgImage: cgImage, scale: Double(max(cgImage.width, cgImage.height)) / stamp.pointSize, orientation: .up)
    }

    func request(_ resource: MessageMediaResource) {
#if DEBUG
        if previewOnly { return }
#endif
        if image(for: resource) != nil { return }
        if let phase = phases[resource] {
            switch phase {
            case .loading, .failed, .notImage, .unicode: return
            case .ready: break // キャッシュから追い出された画像は必要時だけ再取得。
            }
        }
        if phases.count >= 256, let old = phases.first(where: { if case .loading = $0.value { return false }; return true })?.key {
            phases[old] = nil
        }
        guard queue.count < 64 else {
            phases[resource] = .failed("同時に表示できる画像数を超えました。手動更新で再試行できます")
            return
        }
        phases[resource] = .loading
        queue.append(resource)
        pump()
    }

    func retryFailures() {
        let failed = phases.compactMap { key, phase -> MessageMediaResource? in
            if case .failed = phase { return key }; return nil
        }
        if failed.contains(where: { if case .stamp = $0 { return true }; return false }) { catalog = nil }
        for key in failed { phases[key] = nil; request(key) }
    }

    func cancel() {
        queue.removeAll()
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        generation += 1
        catalog?.cancel()
        catalog = nil
        for (key, phase) in phases {
            if case .loading = phase { phases[key] = nil }
        }
    }

    private enum StampContent {
        case image(URLRequest)
        case unicode(String)
    }

    func unicodeEmoji(for stamp: StampReference) -> String? {
        if case .unicode(let emoji) = phases[.stamp(stamp.name)] { return emoji }
        return nil
    }

    private func stampContent(_ name: String) async throws -> StampContent {
        if name.hasPrefix("@") {
            let users = try await auth.fetchUsers()
            guard let user = users.values.first(where: { $0.name == name.dropFirst() }) else {
                throw ImageLoadError.unsupportedImage
            }
            return .image(try auth.stampImageRequest(id: user.id, userIcon: true))
        }
        if catalog == nil { catalog = Task { try await auth.fetchStamps() } }
        guard let catalog else { throw ImageLoadError.invalidResponse }
        let stamps: [String: TraQStamp]
        do { stamps = try await catalog.value }
        catch { self.catalog = nil; throw error }
        guard let info = stamps[name] else { throw ImageLoadError.unsupportedImage }
        if info.isUnicode, let emoji = try await auth.unicodeEmoji(for: info) { return .unicode(emoji) }
        return .image(try auth.stampImageRequest(id: info.id))
    }

    private func pump() {
        while tasks.count < 3 && !queue.isEmpty {
            let resource = queue.removeFirst()
            let startedGeneration = generation
            tasks[resource] = Task {
                defer {
                    if generation == startedGeneration { tasks[resource] = nil; pump() }
                }
                do {
                    let request: URLRequest
                    let isStamp: Bool
                    switch resource {
                    case .stamp(let name):
                        switch try await stampContent(name) {
                        case .image(let imageRequest): request = imageRequest
                        case .unicode(let emoji):
                            try Task.checkCancellation()
                            phases[resource] = .unicode(emoji)
                            return
                        }
                        isStamp = true
                    case .image(let url):
                        request = try auth.messageImageRequest(url)
                        isStamp = false
                    case .file(let url):
                        guard let imageRequest = try await auth.attachedImageRequest(url) else {
                            try Task.checkCancellation()
                            phases[resource] = .notImage
                            return
                        }
                        request = imageRequest
                        isStamp = false
                    }
                    let data = try await client.data(for: request)
                    let image = try await Task.detached(priority: .utility) {
                        try ImageDecoder.decode(data, maximumPixels: isStamp ? 120 : 480, pointSize: isStamp ? 24 : nil)
                    }.value
                    try Task.checkCancellation()
                    cache.setObject(image, forKey: resource.cacheKey as NSString, cost: Int(image.size.width * image.scale * image.size.height * image.scale) * 4)
                    phases[resource] = .ready
                } catch {
                    if generation == startedGeneration {
                        phases[resource] = Task.isCancelled ? nil : .failed(error.localizedDescription)
                    }
                }
            }
        }
    }

#if DEBUG
    private var previewOnly = false

    func installPreviewImage(_ image: UIImage, for resource: MessageMediaResource) {
        previewOnly = true
        cache.setObject(image, forKey: resource.cacheKey as NSString)
        phases[resource] = .ready
    }

    func installPreviewFailure(_ reason: String, for resource: MessageMediaResource) {
        previewOnly = true
        phases[resource] = .failed(reason)
    }

    func installPreviewLoading(for resource: MessageMediaResource) {
        previewOnly = true
        phases[resource] = .loading
    }
#endif

}
