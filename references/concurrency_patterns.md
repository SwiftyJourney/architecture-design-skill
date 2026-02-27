# Swift Concurrency Patterns

Reference implementations from the Essential Developer Feed Case Study (Swift 6).

---

## Why async/await Over Completion Handlers

Completion-handler callbacks have several drawbacks:
- Pyramid of doom when chaining calls
- Easy to forget to call the callback on all paths
- No compiler-enforced structured cancellation
- Thread-safety violations (calling back on wrong thread) are silent

Swift's `async/await` with `@MainActor` isolation solves all of these at compile time:
- The compiler enforces that you `await` results and handle errors
- Structured concurrency (`Task`) provides automatic cancellation propagation
- `@MainActor` isolation replaces `DispatchQueue.main.async` with a compile-time guarantee

---

## Async Protocol Boundaries

### HTTPClient — async throws

Network calls are naturally async. The protocol uses `async throws` directly:

```swift
public protocol HTTPClient {
    func get(from url: URL) async throws -> (Data, HTTPURLResponse)
}
```

Callers simply `try await client.get(from: url)`. No callbacks, no thread-marshalling.

### FeedStore — sync throws (not async)

The cache store is **synchronous**, not async:

```swift
public typealias CachedFeed = (feed: [LocalFeedImage], timestamp: Date)

public protocol FeedStore {
    func deleteCachedFeed() throws
    func insert(_ feed: [LocalFeedImage], timestamp: Date) throws
    func retrieve() throws -> CachedFeed?
}
```

Why sync? CoreData and in-memory stores perform their work on a specific queue. Making the protocol synchronous keeps the contract simple. The **Scheduler** protocol (below) bridges sync store operations into async contexts safely.

---

## @MainActor Isolation

### ResourceView and LoadResourcePresenter

Presentation layer types are isolated to the main actor. This means UI-update calls are always on the main thread — without `DispatchQueue.main.async`:

```swift
@MainActor
public protocol ResourceView {
    associatedtype ResourceViewModel
    func display(_ viewModel: ResourceViewModel)
}

@MainActor
public final class LoadResourcePresenter<Resource, View: ResourceView> { ... }
```

Any type conforming to `ResourceView` is implicitly `@MainActor`. The presenter's methods (`didStartLoading`, `didFinishLoading`) can be called freely from `async` contexts and the compiler guarantees they run on the main actor.

---

## Sendable Value Types

Value types that cross concurrency boundaries must be `Sendable`. In the domain:

```swift
public struct FeedImage: Hashable, Sendable {
    public let id: UUID
    public let description: String?
    public let location: String?
    public let url: URL
}
```

All stored properties are `Sendable` (`UUID`, `String?`, `URL`), so `FeedImage` satisfies `Sendable` automatically. `Hashable` is needed for diffable data sources.

`Paginated<Item: Sendable>` similarly propagates `Sendable` through the generic constraint.

---

## Generic LoadResourcePresenter

The full implementation that replaces per-feature presenters:

```swift
import Foundation

@MainActor
public protocol ResourceView {
    associatedtype ResourceViewModel
    func display(_ viewModel: ResourceViewModel)
}

@MainActor
public final class LoadResourcePresenter<Resource, View: ResourceView> {
    public typealias Mapper = (Resource) throws -> View.ResourceViewModel

    private let resourceView: View
    private let loadingView: ResourceLoadingView
    private let errorView: ResourceErrorView
    private let mapper: Mapper

    public static var loadError: String {
        NSLocalizedString("GENERIC_CONNECTION_ERROR",
                          tableName: "Shared",
                          bundle: Bundle(for: Self.self),
                          comment: "Error message displayed when we can't load the resource from the server")
    }

    // Use when Resource needs mapping to ViewModel
    public init(resourceView: View, loadingView: ResourceLoadingView,
                errorView: ResourceErrorView, mapper: @escaping Mapper) {
        self.resourceView = resourceView
        self.loadingView = loadingView
        self.errorView = errorView
        self.mapper = mapper
    }

    // Use when Resource == ResourceViewModel (no mapping needed)
    public init(resourceView: View, loadingView: ResourceLoadingView,
                errorView: ResourceErrorView) where Resource == View.ResourceViewModel {
        self.resourceView = resourceView
        self.loadingView = loadingView
        self.errorView = errorView
        self.mapper = { $0 }
    }

    public func didStartLoading() {
        errorView.display(.noError)
        loadingView.display(ResourceLoadingViewModel(isLoading: true))
    }

    public func didFinishLoading(with resource: Resource) {
        do {
            resourceView.display(try mapper(resource))
            loadingView.display(ResourceLoadingViewModel(isLoading: false))
        } catch {
            didFinishLoading(with: error)
        }
    }

    public func didFinishLoading(with error: Error) {
        errorView.display(.error(message: Self.loadError))
        loadingView.display(ResourceLoadingViewModel(isLoading: false))
    }
}
```

**Key design decisions**:
- `Mapper` typealias: transforms `Resource` (e.g. `[FeedImage]`) into the view's `ResourceViewModel`
- Two `init` overloads: the second (identity mapper) removes boilerplate when types match
- All methods are `@MainActor` (inherited from the class) — no dispatch needed at call sites

---

## WeakRefVirtualProxy

Prevents retain cycles between the presenter (which holds a strong reference to its views) and view controllers (which typically hold strong references to their presenters):

```swift
import UIKit
import EssentialFeed

final class WeakRefVirtualProxy<T: AnyObject> {
    private weak var object: T?

    init(_ object: T) {
        self.object = object
    }
}

extension WeakRefVirtualProxy: ResourceErrorView where T: ResourceErrorView {
    func display(_ viewModel: ResourceErrorViewModel) {
        object?.display(viewModel)
    }
}

extension WeakRefVirtualProxy: ResourceLoadingView where T: ResourceLoadingView {
    func display(_ viewModel: ResourceLoadingViewModel) {
        object?.display(viewModel)
    }
}

extension WeakRefVirtualProxy: ResourceView where T: ResourceView, T.ResourceViewModel == UIImage {
    func display(_ model: UIImage) {
        object?.display(model)
    }
}
```

**Key design decisions**:
- Generic `T: AnyObject` keeps one implementation for all view types
- Conditional extensions (`where T: ResourceErrorView`) mean the proxy automatically conforms to whatever its wrapped type conforms to
- The `weak var object` ensures the proxy never extends the lifetime of the view controller

---

## LoadResourcePresentationAdapter

Bridges a `() async throws -> Resource` loader closure to the presenter's synchronous interface. Manages the active `Task` to prevent duplicate in-flight loads and ensure cancellation on deallocation:

```swift
import EssentialFeed
import EssentialFeediOS

@MainActor
final class LoadResourcePresentationAdapter<Resource, View: ResourceView> {
    private let loader: () async throws -> Resource
    private var cancellable: Task<Void, Never>?
    private var isLoading = false

    var presenter: LoadResourcePresenter<Resource, View>?

    init(loader: @escaping () async throws -> Resource) {
        self.loader = loader
    }

    func loadResource() {
        guard !isLoading else { return }

        presenter?.didStartLoading()
        isLoading = true

        cancellable = Task.immediate { @MainActor [weak self] in
            defer { self?.isLoading = false }

            do {
                if let resource = try await self?.loader() {
                    if Task.isCancelled { return }
                    self?.presenter?.didFinishLoading(with: resource)
                }
            } catch {
                if Task.isCancelled { return }
                self?.presenter?.didFinishLoading(with: error)
            }
        }
    }

    deinit {
        cancellable?.cancel()
    }
}

extension LoadResourcePresentationAdapter: FeedImageCellControllerDelegate {
    func didRequestImage() { loadResource() }
    func didCancelImageRequest() {
        cancellable?.cancel()
        cancellable = nil
        isLoading = false
    }
}
```

**Key design decisions**:
- `Task.immediate` starts the task on the current executor (main actor) immediately
- `isLoading` guard prevents duplicate loads from rapid user interaction
- `deinit { cancellable?.cancel() }` ensures in-flight network requests are cancelled when the adapter is deallocated (e.g. when navigating away)
- `weak self` inside the Task avoids retain cycles

---

## Scheduler Protocol

Bridges synchronous `FeedStore` operations into async contexts without making the store protocol async. This lets the same store implementations work on any queue (CoreData's private queue or main queue):

```swift
protocol Scheduler {
    @MainActor
    func schedule<T>(_ action: @escaping @Sendable () throws -> T) async rethrows -> T
}

extension CoreDataFeedStore: Scheduler {
    @MainActor
    func schedule<T>(_ action: @escaping @Sendable () throws -> T) async rethrows -> T {
        if contextQueue == .main {
            return try action()
        } else {
            return try await perform(action)
        }
    }
}

extension InMemoryFeedStore: Scheduler {
    @MainActor
    func schedule<T>(_ action: @escaping @Sendable () throws -> T) async rethrows -> T {
        try action()   // in-memory: always synchronous
    }
}
```

**Why Scheduler instead of making FeedStore async?**
- `FeedStore` stays simple (sync `throws`) — easy to test and implement
- `Scheduler` is an infrastructure concern, defined where it's needed (composition layer)
- `CoreDataFeedStore` can check `contextQueue` at runtime to avoid unnecessary hops

**Usage in FeedService**:
```swift
private func loadLocalFeed() async throws -> [FeedImage] {
    try await store.schedule { [store] in
        let localFeedLoader = LocalFeedLoader(store: store, currentDate: Date.init)
        return try localFeedLoader.load()
    }
}
```

---

## Composition with @MainActor Closures

`FeedUIComposer` accepts closures instead of protocols. This is deliberate: closures are composable without needing extra types, and `@MainActor` on the closure types ensures calls arrive on the main actor:

```swift
@MainActor
public final class FeedUIComposer {
    public static func feedComposedWith(
        feedLoader: @MainActor @escaping () async throws -> Paginated<FeedImage>,
        imageLoader: @MainActor @escaping (URL) async throws -> Data,
        selection: @MainActor @escaping (FeedImage) -> Void = { _ in }
    ) -> ListViewController
}
```

In the composition root (`FeedService`):
```swift
FeedUIComposer.feedComposedWith(
    feedLoader: feedService.loadRemoteFeedWithLocalFallback,
    imageLoader: feedService.loadLocalImageWithRemoteFallback
)
```

The closures capture the concrete `FeedService` while the UI layer only sees `() async throws -> Paginated<FeedImage>`. No additional protocol needed.

---

## Testing with async/await

`async/await` eliminates `XCTestExpectation` boilerplate for most async tests:

```swift
final class LoadFeedFromRemoteUseCaseTests: XCTestCase {
    func test_load_deliversItemsOnHTTPClientSuccess() async throws {
        let (sut, client) = makeSUT()
        let feed = [makeImage(), makeImage()]

        client.stub(data: makeItemsJSON(feed), response: HTTPURLResponse(statusCode: 200))

        let received = try await sut.load()
        XCTAssertEqual(received, feed)
    }

    func test_load_deliversErrorOnHTTPClientError() async {
        let (sut, client) = makeSUT()
        client.stub(error: anyNSError())

        do {
            _ = try await sut.load()
            XCTFail("Expected error, got success")
        } catch {
            XCTAssertNotNil(error)
        }
    }
}
```

For `@MainActor` types, use `MainActor.run` in tests when needed:
```swift
func test_display_rendersLoadingState() async {
    let sut = await MainActor.run { makeSUT() }
    await MainActor.run { sut.presenter.didStartLoading() }
    // assert...
}
```

---

## Migration Guide: Closures to async/await

### Before (completion handlers)

```swift
protocol FeedLoader {
    func load(completion: @escaping (Result<[FeedImage], Error>) -> Void)
}

class RemoteFeedLoader: FeedLoader {
    func load(completion: @escaping (Result<[FeedImage], Error>) -> Void) {
        client.get(from: url) { result in
            DispatchQueue.main.async {
                completion(result.map { ... })
            }
        }
    }
}
```

### After (async/await)

```swift
// No FeedLoader protocol needed — use () async throws -> [FeedImage] closure
// or define a protocol if you need multiple conformances

public protocol HTTPClient {
    func get(from url: URL) async throws -> (Data, HTTPURLResponse)
}

// RemoteFeedLoader becomes a pure function or a struct with async load()
func loadRemoteFeed() async throws -> [FeedImage] {
    let (data, response) = try await httpClient.get(from: url)
    return try FeedItemsMapper.map(data, from: response)
}
```

Callers use `try await` and `@MainActor` ensures UI updates happen on the right thread automatically.
