# Composition Root Pattern (Swift)

How to wire dependencies together in one place — Swift 6, async/await, @MainActor.

---

## FeedService — Business Logic Intermediary

`FeedService` is a `@MainActor` class that owns the concrete dependencies and exposes `async throws` closures to the UI layer. It replaces the old `SceneDelegate` factory methods and `MainQueueDispatchDecorator`.

```swift
import os
import CoreData
import EssentialFeed

@MainActor
final class FeedService {

    private lazy var httpClient: HTTPClient = {
        URLSessionHTTPClient(session: URLSession(configuration: .ephemeral))
    }()

    private lazy var logger = Logger(
        subsystem: "com.essentialdeveloper.EssentialAppCaseStudy",
        category: "main"
    )

    private lazy var store: FeedStore & FeedImageDataStore & Scheduler & Sendable = {
        do {
            return try CoreDataFeedStore(
                storeURL: NSPersistentContainer
                    .defaultDirectoryURL()
                    .appendingPathComponent("feed-store.sqlite"))
        } catch {
            assertionFailure("Failed to instantiate CoreData store: \(error)")
            logger.fault("Failed to instantiate CoreData store: \(error)")
            return InMemoryFeedStore()
        }
    }()

    // Convenience init for testing — inject doubles
    convenience init(httpClient: HTTPClient,
                     store: FeedStore & FeedImageDataStore & Scheduler & Sendable) {
        self.init()
        self.httpClient = httpClient
        self.store = store
    }

    func loadRemoteFeedWithLocalFallback() async throws -> Paginated<FeedImage> {
        do {
            let feed = try await loadRemoteFeed()
            await store.schedule { [store] in
                try? LocalFeedLoader(store: store, currentDate: Date.init).save(feed)
            }
            return makeFirstPage(items: feed)
        } catch {
            let feed = try await store.schedule { [store] in
                try LocalFeedLoader(store: store, currentDate: Date.init).load()
            }
            return makeFirstPage(items: feed)
        }
    }

    func loadLocalImageWithRemoteFallback(url: URL) async throws -> Data {
        do {
            return try await store.schedule { [store] in
                try LocalFeedImageDataLoader(store: store).loadImageData(from: url)
            }
        } catch {
            let (data, response) = try await httpClient.get(from: url)
            let imageData = try FeedImageDataMapper.map(data, from: response)
            await store.schedule { [store] in
                try? LocalFeedImageDataLoader(store: store).save(imageData, for: url)
            }
            return imageData
        }
    }

    private func loadRemoteFeed(after: FeedImage? = nil) async throws -> [FeedImage] {
        let url = FeedEndpoint.get(after: after).url(baseURL: baseURL)
        let (data, response) = try await httpClient.get(from: url)
        return try FeedItemsMapper.map(data, from: response)
    }

    private func makeFirstPage(items: [FeedImage]) -> Paginated<FeedImage> {
        makePage(items: items, last: items.last)
    }

    private func makePage(items: [FeedImage], last: FeedImage?) -> Paginated<FeedImage> {
        Paginated(items: items, loadMore: last.map { last in
            { @MainActor @Sendable in try await self.loadMoreRemoteFeed(last: last) }
        })
    }
}
```

---

## Scheduler Protocol

Bridges synchronous `FeedStore` operations into async contexts. Replaces `MainQueueDispatchDecorator`:

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
        try action()
    }
}
```

`Scheduler` is defined alongside `FeedService` (infrastructure/composition layer), keeping `FeedStore` in the domain layer clean.

---

## Feed UI Composer

`FeedUIComposer` accepts `@MainActor` async closures instead of protocol instances. This lets the composition root inject any implementation (including decorated composites) without extra types:

```swift
import UIKit
import EssentialFeed
import EssentialFeediOS

@MainActor
public final class FeedUIComposer {
    private init() {}

    private typealias FeedPresentationAdapter =
        LoadResourcePresentationAdapter<Paginated<FeedImage>, FeedViewAdapter>

    public static func feedComposedWith(
        feedLoader: @MainActor @escaping () async throws -> Paginated<FeedImage>,
        imageLoader: @MainActor @escaping (URL) async throws -> Data,
        selection: @MainActor @escaping (FeedImage) -> Void = { _ in }
    ) -> ListViewController {
        let presentationAdapter = FeedPresentationAdapter(loader: feedLoader)

        let feedController = makeFeedViewController(title: FeedPresenter.title)
        feedController.onRefresh = presentationAdapter.loadResource

        presentationAdapter.presenter = LoadResourcePresenter(
            resourceView: FeedViewAdapter(
                controller: feedController,
                imageLoader: imageLoader,
                selection: selection),
            loadingView: WeakRefVirtualProxy(feedController),
            errorView: WeakRefVirtualProxy(feedController))

        return feedController
    }

    private static func makeFeedViewController(title: String) -> ListViewController {
        let bundle = Bundle(for: ListViewController.self)
        let storyboard = UIStoryboard(name: "Feed", bundle: bundle)
        let feedController = storyboard.instantiateInitialViewController() as! ListViewController
        feedController.title = title
        return feedController
    }
}
```

---

## Weak Reference Virtual Proxy

Prevents retain cycles. The `WeakRefVirtualProxy<T>` wraps a view controller with a weak reference and conditionally conforms to the same view protocols:

```swift
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

---

## SceneDelegate as Composition Root

The `SceneDelegate` creates a `FeedService` and passes its async methods as closures to `FeedUIComposer`:

```swift
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    private lazy var feedService = FeedService()

    // Convenience init for testing — inject doubles
    convenience init(httpClient: HTTPClient,
                     store: FeedStore & FeedImageDataStore & Scheduler & Sendable) {
        self.init()
        self.feedService = FeedService(httpClient: httpClient, store: store)
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        window = UIWindow(windowScene: scene)
        configureWindow()
    }

    func configureWindow() {
        window?.rootViewController = UINavigationController(
            rootViewController: makeFeedViewController()
        )
        window?.makeKeyAndVisible()
    }

    private func makeFeedViewController() -> ListViewController {
        FeedUIComposer.feedComposedWith(
            feedLoader: feedService.loadRemoteFeedWithLocalFallback,
            imageLoader: feedService.loadLocalImageWithRemoteFallback
        )
    }
}
```

The `convenience init` is for testing only — production always uses `lazy var feedService = FeedService()`.

---

## Benefits

1. **Single responsibility** — one place for wiring; `FeedService` owns infrastructure, `FeedUIComposer` owns presentation assembly
2. **Easy testing** — inject doubles via `convenience init`
3. **No thread dispatching** — `@MainActor` on closures and classes replaces `DispatchQueue.main.async`
4. **Clear dependencies** — all explicit, no singletons
5. **Cancellation** — `LoadResourcePresentationAdapter.deinit` cancels in-flight tasks automatically

---

## Testing the Composition

```swift
class SceneDelegateTests: XCTestCase {
    func test_configureWindow_setsWindowAsKeyAndVisible() {
        let window = UIWindowSpy()
        let sut = SceneDelegate()
        sut.window = window

        sut.configureWindow()

        XCTAssertEqual(window.makeKeyAndVisibleCallCount, 1,
                       "Expected to make window key and visible")
    }

    func test_configureWindow_configuresRootViewController() {
        let sut = SceneDelegate()
        sut.window = UIWindow()

        sut.configureWindow()

        let root = sut.window?.rootViewController
        let rootNavigation = root as? UINavigationController
        let topController = rootNavigation?.topViewController

        XCTAssertNotNil(rootNavigation, "Expected a navigation controller as root")
        XCTAssertTrue(topController is ListViewController,
                      "Expected a list controller as top view controller")
    }

    // MARK: - Helpers

    private class UIWindowSpy: UIWindow {
        var makeKeyAndVisibleCallCount = 0

        override func makeKeyAndVisible() {
            makeKeyAndVisibleCallCount += 1
        }
    }
}
```

---

## Further Reading

- `references/concurrency_patterns.md` — Scheduler, WeakRefVirtualProxy, LoadResourcePresentationAdapter in depth
- Essential Feed Case Study: https://github.com/essentialdevelopercom/essential-feed-case-study
- Essential Developer: https://www.essentialdeveloper.com/
