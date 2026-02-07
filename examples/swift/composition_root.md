# Composition Root Pattern (Swift)

How to wire dependencies together in one place.

---

## SceneDelegate as Composition Root

```swift
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    private lazy var httpClient: HTTPClient = {
        URLSessionHTTPClient(session: URLSession(configuration: .ephemeral))
    }()
    
    private lazy var store: FeedStore & FeedImageDataStore = {
        try! CoreDataFeedStore(
            storeURL: NSPersistentContainer
                .defaultDirectoryURL()
                .appendingPathComponent("feed-store.sqlite")
        )
    }()
    
    convenience init(httpClient: HTTPClient, store: FeedStore & FeedImageDataStore) {
        self.init()
        self.httpClient = httpClient
        self.store = store
    }
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
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
    
    // MARK: - Feed Composition
    
    private func makeFeedViewController() -> FeedViewController {
        let url = URL(string: "https://ile-api.essentialdeveloper.com/essential-feed/v1/feed")!
        let remoteLoader = makeRemoteFeedLoader(url: url)
        let localLoader = makeLocalFeedLoader()
        
        let feedViewController = FeedUIComposer.feedComposedWith(
            feedLoader: makeCompositeLoader(remote: remoteLoader, local: localLoader),
            imageLoader: makeLocalImageLoaderWithRemoteFallback(url: url)
        )
        
        return feedViewController
    }
    
    private func makeRemoteFeedLoader(url: URL) -> RemoteFeedLoader {
        return RemoteFeedLoader(url: url, client: httpClient)
    }
    
    private func makeLocalFeedLoader() -> LocalFeedLoader {
        return LocalFeedLoader(store: store, currentDate: Date.init)
    }
    
    private func makeCompositeLoader(remote: RemoteFeedLoader, local: LocalFeedLoader) -> FeedLoader {
        return FeedLoaderWithFallbackComposite(
            primary: FeedLoaderCacheDecorator(
                decoratee: remote,
                cache: local
            ),
            fallback: local
        )
    }
    
    private func makeLocalImageLoaderWithRemoteFallback(url: URL) -> FeedImageDataLoader {
        let remoteImageLoader = RemoteFeedImageDataLoader(client: httpClient)
        let localImageLoader = LocalFeedImageDataLoader(store: store)
        
        return FeedImageDataLoaderWithFallbackComposite(
            primary: localImageLoader,
            fallback: FeedImageDataLoaderCacheDecorator(
                decoratee: remoteImageLoader,
                cache: localImageLoader
            )
        )
    }
}

// MARK: - Feed UI Composer

public final class FeedUIComposer {
    private init() {}
    
    public static func feedComposedWith(
        feedLoader: FeedLoader,
        imageLoader: FeedImageDataLoader
    ) -> FeedViewController {
        let presentationAdapter = FeedLoaderPresentationAdapter(
            feedLoader: MainQueueDispatchDecorator(decoratee: feedLoader)
        )
        
        let feedController = makeFeedViewController(
            delegate: presentationAdapter,
            title: FeedPresenter.title
        )
        
        presentationAdapter.presenter = FeedPresenter(
            feedView: FeedViewAdapter(
                controller: feedController,
                imageLoader: MainQueueDispatchDecorator(decoratee: imageLoader)
            ),
            loadingView: WeakRefVirtualProxy(feedController),
            errorView: WeakRefVirtualProxy(feedController)
        )
        
        return feedController
    }
    
    private static func makeFeedViewController(
        delegate: FeedViewControllerDelegate,
        title: String
    ) -> FeedViewController {
        let bundle = Bundle(for: FeedViewController.self)
        let storyboard = UIStoryboard(name: "Feed", bundle: bundle)
        let feedController = storyboard.instantiateInitialViewController() as! FeedViewController
        feedController.delegate = delegate
        feedController.title = title
        return feedController
    }
}
```

---

## Main Thread Decorator

```swift
public final class MainQueueDispatchDecorator<T> {
    private let decoratee: T
    
    public init(decoratee: T) {
        self.decoratee = decoratee
    }
    
    public func dispatch(completion: @escaping () -> Void) {
        guard Thread.isMainThread else {
            return DispatchQueue.main.async(execute: completion)
        }
        
        completion()
    }
}

extension MainQueueDispatchDecorator: FeedLoader where T == FeedLoader {
    public func load(completion: @escaping (FeedLoader.Result) -> Void) {
        decoratee.load { [weak self] result in
            self?.dispatch { completion(result) }
        }
    }
}

extension MainQueueDispatchDecorator: FeedImageDataLoader where T == FeedImageDataLoader {
    public func loadImageData(from url: URL, completion: @escaping (FeedImageDataLoader.Result) -> Void) -> FeedImageDataLoaderTask {
        decoratee.loadImageData(from: url) { [weak self] result in
            self?.dispatch { completion(result) }
        }
    }
}
```

---

## Weak Reference Virtual Proxy

```swift
public final class WeakRefVirtualProxy<T: AnyObject> {
    private weak var object: T?
    
    public init(_ object: T) {
        self.object = object
    }
}

extension WeakRefVirtualProxy: FeedLoadingView where T: FeedLoadingView {
    public func display(_ viewModel: FeedLoadingViewModel) {
        object?.display(viewModel)
    }
}

extension WeakRefVirtualProxy: FeedErrorView where T: FeedErrorView {
    public func display(_ viewModel: FeedErrorViewModel) {
        object?.display(viewModel)
    }
}
```

---

## Benefits

1. **Single responsibility** - One place for wiring
2. **Easy testing** - Inject test doubles
3. **Flexibility** - Swap implementations easily
4. **Clear dependencies** - Everything explicit
5. **No singletons** - Proper dependency injection

---

## Testing the Composition

```swift
class SceneDelegateTests: XCTestCase {
    func test_configureWindow_setsWindowAsKeyAndVisible() {
        let window = UIWindowSpy()
        let sut = SceneDelegate()
        sut.window = window
        
        sut.configureWindow()
        
        XCTAssertEqual(window.makeKeyAndVisibleCallCount, 1, "Expected to make window key and visible")
    }
    
    func test_configureWindow_configuresRootViewController() {
        let sut = SceneDelegate()
        sut.window = UIWindow()
        
        sut.configureWindow()
        
        let root = sut.window?.rootViewController
        let rootNavigation = root as? UINavigationController
        let topController = rootNavigation?.topViewController
        
        XCTAssertNotNil(rootNavigation, "Expected a navigation controller as root")
        XCTAssertTrue(topController is FeedViewController, "Expected a feed controller as top view controller")
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

- Essential Feed Case Study: https://github.com/essentialdevelopercom/essential-feed-case-study
- Essential Developer: https://www.essentialdeveloper.com/
