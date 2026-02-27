# Use Case Pattern (Swift Examples)

Real examples from Essential Developer's Feed Case Study — Swift 6, async/await.

---

## Domain Entity

```swift
public struct FeedImage: Hashable, Sendable {
    public let id: UUID
    public let description: String?
    public let location: String?
    public let url: URL
}
```

`Hashable` is required for diffable data sources. `Sendable` allows safe crossing of actor boundaries.

---

## Load Feed Use Case

### Boundary Protocol (Infrastructure)

```swift
public protocol HTTPClient {
    func get(from url: URL) async throws -> (Data, HTTPURLResponse)
}
```

### Remote Feed Loader (Infrastructure)

```swift
public final class RemoteFeedLoader {
    private let url: URL
    private let client: HTTPClient

    public enum Error: Swift.Error {
        case connectivity
        case invalidData
    }

    public init(url: URL, client: HTTPClient) {
        self.url = url
        self.client = client
    }

    public func load() async throws -> [FeedImage] {
        let (data, response) = try await client.get(from: url)
        return try FeedItemsMapper.map(data, from: response)
    }
}

// Internal Mapper
internal final class FeedItemsMapper {
    private struct Root: Decodable {
        let items: [RemoteFeedImage]
        var feed: [FeedImage] { items.map { $0.image } }
    }

    private struct RemoteFeedImage: Decodable {
        let id: UUID
        let description: String?
        let location: String?
        let image: URL

        var image: FeedImage {
            FeedImage(id: id, description: description, location: location, url: image)
        }
    }

    static func map(_ data: Data, from response: HTTPURLResponse) throws -> [FeedImage] {
        guard response.statusCode == 200,
              let root = try? JSONDecoder().decode(Root.self, from: data) else {
            throw RemoteFeedLoader.Error.invalidData
        }
        return root.feed
    }
}
```

---

## Cache Feed Use Case

### Cache Store Protocol (Infrastructure boundary)

```swift
public typealias CachedFeed = (feed: [LocalFeedImage], timestamp: Date)

public protocol FeedStore {
    func deleteCachedFeed() throws
    func insert(_ feed: [LocalFeedImage], timestamp: Date) throws
    func retrieve() throws -> CachedFeed?
}
```

`FeedStore` is **synchronous** (`throws`, not `async throws`). Store operations run on a specific queue managed by the infrastructure layer via the `Scheduler` protocol. See `references/concurrency_patterns.md` for details.

### Local Feed Loader (Infrastructure)

```swift
public final class LocalFeedLoader {
    private let store: FeedStore
    private let currentDate: () -> Date

    public init(store: FeedStore, currentDate: @escaping () -> Date) {
        self.store = store
        self.currentDate = currentDate
    }

    public func load() throws -> [FeedImage] {
        guard let cache = try store.retrieve(),
              FeedCachePolicy.validate(cache.timestamp, against: currentDate()) else {
            return []
        }
        return cache.feed.toModels()
    }
}
```

### Cache Protocol

```swift
public protocol FeedCache {
    func save(_ feed: [FeedImage]) throws
}

extension LocalFeedLoader: FeedCache {
    public func save(_ feed: [FeedImage]) throws {
        try store.deleteCachedFeed()
        try store.insert(feed.toLocal(), timestamp: currentDate())
    }
}
```

---

## Composite Pattern for Fallback

```swift
func loadRemoteFeedWithLocalFallback() async throws -> [FeedImage] {
    do {
        return try await loadRemoteFeed()
    } catch {
        return try loadLocalFeed()   // sync throws, scheduled via Scheduler
    }
}
```

In the actual `FeedService`, this pattern is orchestrated using the `Scheduler` protocol so that local store access happens on the correct queue:

```swift
private func loadRemoteFeedWithLocalFallback() async throws -> Paginated<FeedImage> {
    do {
        let feed = try await loadRemoteFeed()
        await store.schedule { [store] in try? LocalFeedLoader(store: store, currentDate: Date.init).save(feed) }
        return makeFirstPage(items: feed)
    } catch {
        let feed = try await store.schedule { [store] in
            try LocalFeedLoader(store: store, currentDate: Date.init).load()
        }
        return makeFirstPage(items: feed)
    }
}
```

---

## Decorator Pattern for Caching

The decorator wraps a loader and fire-and-forgets cache writes to avoid blocking the caller:

```swift
func loadAndCacheRemoteFeed() async throws -> [FeedImage] {
    let feed = try await loadRemoteFeed()
    // Fire-and-forget: don't let cache failure affect the caller
    Task { try? await cache.save(feed) }
    return feed
}
```

---

## Generic Presenter Integration

`LoadResourcePresenter<Resource, View>` wires any loader result to any view without a custom presenter per feature.

### Setup in Composition Root

```swift
// 1. Create the adapter that bridges async loader → presenter
let adapter = LoadResourcePresentationAdapter<[FeedImage], FeedView>(
    loader: feedService.loadRemoteFeedWithLocalFallback
)

// 2. Create the presenter, providing view + loading + error views
adapter.presenter = LoadResourcePresenter(
    resourceView: feedView,
    loadingView: WeakRefVirtualProxy(feedController),
    errorView: WeakRefVirtualProxy(feedController),
    mapper: FeedImagePresenter.map  // [FeedImage] -> [FeedImageViewModel]
)

// 3. Wire the trigger (e.g. pull-to-refresh)
feedController.onRefresh = adapter.loadResource
```

### Identity Mapper Overload (when no mapping needed)

```swift
// Resource == View.ResourceViewModel — use the simpler init
adapter.presenter = LoadResourcePresenter(
    resourceView: commentsView,
    loadingView: WeakRefVirtualProxy(commentsController),
    errorView: WeakRefVirtualProxy(commentsController)
    // no mapper: [ImageComment] is directly the ViewModel
)
```

---

## Key Takeaways

1. **async throws** at network boundaries — `HTTPClient` protocol and remote loaders
2. **sync throws** at cache boundaries — `FeedStore` protocol; queue management via `Scheduler`
3. **`FeedImage` is `Sendable`** — safe to pass across actor boundaries
4. **`LoadResourcePresenter<Resource, View>`** replaces per-feature presenters
5. **Composite/Decorator via closures** — no protocol indirection required for composition
6. **Fire-and-forget cache writes** — `Task { try? await cache.save(...) }`

---

## Further Reading

- `references/concurrency_patterns.md` — Full async/await patterns and Scheduler protocol
- Essential Feed Case Study: https://github.com/essentialdevelopercom/essential-feed-case-study
- Essential Developer: https://www.essentialdeveloper.com/
