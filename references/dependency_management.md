# Dependency Management & Injection

Guide to managing dependencies and applying Dependency Inversion Principle in Clean Architecture.

---

## Dependency Injection Fundamentals

### What is Dependency Injection?

Dependency Injection is a technique where an object receives its dependencies from external sources rather than creating them itself.

**Without DI**:
```swift
class FeedViewController {
    // ❌ Creates its own dependencies
    private let loader = RemoteFeedLoader()
}
```

**With DI**:
```swift
class FeedViewController {
    private let loader: FeedLoader  // ✅ Receives dependency
    
    init(loader: FeedLoader) {
        self.loader = loader
    }
}
```

---

## Types of Dependency Injection

### 1. Constructor Injection (Recommended)

**Definition**: Dependencies passed through initializer.

```swift
class LoadFeedUseCase {
    private let loader: FeedLoader
    private let cache: FeedCache
    
    init(loader: FeedLoader, cache: FeedCache) {
        self.loader = loader
        self.cache = cache
    }
    
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        loader.load { [weak self] result in
            if case let .success(feed) = result {
                self?.cache.save(feed) { _ in }
            }
            completion(result)
        }
    }
}
```

**Pros**:
- Dependencies explicit and required
- Immutable dependencies
- Easy to test
- Clear contracts

**Cons**:
- Many dependencies = long initializer
- Can be verbose

**When to use**: Default choice for most cases.

---

### 2. Property Injection

**Definition**: Dependencies set after initialization.

```swift
class FeedViewController: UIViewController {
    var loader: FeedLoader!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        loader.load { [weak self] result in
            self?.display(result)
        }
    }
}

// Usage
let viewController = FeedViewController()
viewController.loader = RemoteFeedLoader()
```

**Pros**:
- Useful for optional dependencies
- Works with Interface Builder

**Cons**:
- Dependencies mutable
- Can be nil (!)
- Less explicit

**When to use**: Only for optional dependencies or framework constraints.

---

### 3. Method Injection

**Definition**: Dependencies passed to specific methods.

```swift
class FeedPresenter {
    func didRequestFeed(loader: FeedLoader) {
        loader.load { result in
            // Handle result
        }
    }
}
```

**Pros**:
- Flexible for different dependencies
- Clear method requirements

**Cons**:
- Repetitive for commonly used dependencies
- Can make API unclear

**When to use**: When dependency varies per method call.

---

## Dependency Inversion Principle (DIP)

### The Problem: Direct Dependencies

```swift
// ❌ High-level module depends on low-level concrete class
class FeedViewController {
    private let loader = RemoteFeedLoader()  // Concrete dependency
    private let httpClient = URLSessionHTTPClient()
    private let imageDataLoader = RemoteImageDataLoader()
}
```

**Issues**:
- Cannot test without real network
- Cannot swap implementations
- Tight coupling
- Violates DIP

---

### The Solution: Depend on Abstractions

```swift
// ✅ Define abstractions
protocol FeedLoader {
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void)
}

protocol ImageDataLoader {
    func loadImageData(from url: URL, completion: @escaping (Result<Data, Error>) -> Void)
}

// High-level module depends on abstractions
class FeedViewController {
    private let feedLoader: FeedLoader
    private let imageDataLoader: ImageDataLoader
    
    init(feedLoader: FeedLoader, imageDataLoader: ImageDataLoader) {
        self.feedLoader = feedLoader
        self.imageDataLoader = imageDataLoader
    }
}

// Low-level modules implement abstractions
class RemoteFeedLoader: FeedLoader {
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        // Implementation
    }
}

class RemoteImageDataLoader: ImageDataLoader {
    func loadImageData(from url: URL, completion: @escaping (Result<Data, Error>) -> Void) {
        // Implementation
    }
}
```

---

## Composition Root Pattern

### What is a Composition Root?

The single place in the application where all dependencies are wired together.

### Example: SceneDelegate as Composition Root

```swift
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = (scene as? UIWindowScene) else { return }
        
        window = UIWindow(windowScene: scene)
        window?.rootViewController = makeRootViewController()
        window?.makeKeyAndVisible()
    }
    
    // MARK: - Composition Root
    
    private func makeRootViewController() -> UIViewController {
        let navigationController = UINavigationController(
            rootViewController: makeFeedViewController()
        )
        return navigationController
    }
    
    private func makeFeedViewController() -> FeedViewController {
        let feedViewController = FeedViewController(
            feedLoader: makeRemoteFeedLoader(),
            imageDataLoader: makeRemoteImageDataLoader()
        )
        return feedViewController
    }
    
    private func makeRemoteFeedLoader() -> FeedLoader {
        let httpClient = makeHTTPClient()
        let url = URL(string: "https://api.example.com/feed")!
        return RemoteFeedLoader(url: url, client: httpClient)
    }
    
    private func makeRemoteImageDataLoader() -> ImageDataLoader {
        let httpClient = makeHTTPClient()
        return RemoteImageDataLoader(client: httpClient)
    }
    
    private func makeHTTPClient() -> HTTPClient {
        return URLSessionHTTPClient(session: URLSession(configuration: .ephemeral))
    }
}
```

### Composition Root Benefits

- All dependency creation in one place
- Easy to change implementations
- Business logic stays clean
- Clear dependency graph
- Testable architecture

---

## Advanced Composition Patterns

### 1. Decorator Pattern for Composition

```swift
// Base loader
let remoteLoader = RemoteFeedLoader(client: httpClient, url: feedURL)

// Add caching behavior via decorator
let cachingLoader = FeedLoaderCacheDecorator(
    decoratee: remoteLoader,
    cache: localFeedStore
)

// Add logging behavior via another decorator
let loggingLoader = FeedLoaderLoggingDecorator(
    decoratee: cachingLoader,
    logger: logger
)

// Use decorated loader
let viewController = FeedViewController(loader: loggingLoader)
```

### 2. Composite Pattern for Fallback

```swift
let primaryLoader = RemoteFeedLoader(client: httpClient, url: feedURL)
let fallbackLoader = LocalFeedLoader(store: feedStore)

let compositeLoader = FeedLoaderWithFallback(
    primary: primaryLoader,
    fallback: fallbackLoader
)

let viewController = FeedViewController(loader: compositeLoader)
```

### 3. Adapter Pattern for Integration

```swift
// Existing third-party service
class ThirdPartyFeedService {
    func fetchFeed() -> [ThirdPartyFeedItem] { ... }
}

// Adapter to our interface
class ThirdPartyFeedLoaderAdapter: FeedLoader {
    private let service: ThirdPartyFeedService
    
    init(service: ThirdPartyFeedService) {
        self.service = service
    }
    
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        let thirdPartyItems = service.fetchFeed()
        let feedItems = thirdPartyItems.map { item in
            FeedItem(
                id: item.identifier,
                description: item.text,
                location: item.place,
                imageURL: item.imageLink
            )
        }
        completion(.success(feedItems))
    }
}
```

---

## Managing Multiple Dependencies

### Factory Pattern

```swift
protocol FeedViewControllerFactory {
    func makeFeedViewController() -> FeedViewController
}

class FeedViewControllerFactoryImpl: FeedViewControllerFactory {
    private let httpClient: HTTPClient
    private let feedStore: FeedStore
    
    init(httpClient: HTTPClient, feedStore: FeedStore) {
        self.httpClient = httpClient
        self.feedStore = feedStore
    }
    
    func makeFeedViewController() -> FeedViewController {
        let feedLoader = makeFeedLoader()
        let imageDataLoader = makeImageDataLoader()
        return FeedViewController(
            feedLoader: feedLoader,
            imageDataLoader: imageDataLoader
        )
    }
    
    private func makeFeedLoader() -> FeedLoader {
        let remoteLoader = RemoteFeedLoader(client: httpClient, url: feedURL)
        let localLoader = LocalFeedLoader(store: feedStore)
        return FeedLoaderWithFallback(primary: remoteLoader, fallback: localLoader)
    }
    
    private func makeImageDataLoader() -> ImageDataLoader {
        return RemoteImageDataLoader(client: httpClient)
    }
}
```

---

## Dependency Injection Containers (Use Sparingly)

### Simple DI Container

```swift
class DependencyContainer {
    // Singletons
    lazy var httpClient: HTTPClient = URLSessionHTTPClient()
    lazy var feedStore: FeedStore = CoreDataFeedStore()
    
    // Factories
    func makeFeedLoader() -> FeedLoader {
        RemoteFeedLoader(client: httpClient, url: feedURL)
    }
    
    func makeImageDataLoader() -> ImageDataLoader {
        RemoteImageDataLoader(client: httpClient)
    }
    
    func makeFeedViewController() -> FeedViewController {
        FeedViewController(
            feedLoader: makeFeedLoader(),
            imageDataLoader: makeImageDataLoader()
        )
    }
}

// Usage in SceneDelegate
class SceneDelegate {
    private let container = DependencyContainer()
    
    func makeRootViewController() -> UIViewController {
        container.makeFeedViewController()
    }
}
```

**⚠️ Warning**: Use containers sparingly. Simple composition in Composition Root is often sufficient.

---

## Testing with Dependency Injection

### Easy Unit Testing

```swift
class FeedViewControllerTests: XCTestCase {
    func test_viewDidLoad_startsFeedLoading() {
        let (sut, loader) = makeSUT()
        
        sut.loadViewIfNeeded()
        
        XCTAssertEqual(loader.loadCallCount, 1)
    }
    
    // MARK: - Helpers
    
    private func makeSUT() -> (sut: FeedViewController, loader: FeedLoaderSpy) {
        let loader = FeedLoaderSpy()
        let imageLoader = ImageDataLoaderSpy()
        let sut = FeedViewController(
            feedLoader: loader,
            imageDataLoader: imageLoader
        )
        return (sut, loader)
    }
    
    private class FeedLoaderSpy: FeedLoader {
        private(set) var loadCallCount = 0
        
        func load(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
            loadCallCount += 1
        }
    }
}
```

### Test-Specific Implementations

```swift
// In-memory test double
class InMemoryFeedStore: FeedStore {
    private var cache: [FeedItem]?
    
    func save(_ items: [FeedItem]) {
        cache = items
    }
    
    func load() -> [FeedItem]? {
        cache
    }
}

// Use in tests
func test_save_storesFeedItems() {
    let store = InMemoryFeedStore()
    let items = [FeedItem(...)]
    
    store.save(items)
    
    XCTAssertEqual(store.load(), items)
}
```

---

## Best Practices

### DO ✅

- **Inject through initializers** for required dependencies
- **Depend on abstractions** (protocols/interfaces)
- **Keep composition root simple** and centralized
- **Use factories** for complex object creation
- **Make dependencies explicit** in signatures
- **Favor immutability** in dependencies

### DON'T ❌

- **Don't use singletons** for dependency management
- **Don't create dependencies** inside classes
- **Don't hide dependencies** with service locators
- **Don't overuse DI containers** - simple composition often better
- **Don't make everything injectable** - only what needs testing/swapping
- **Don't use property injection** as default

---

## Common Patterns

### 1. Optional Dependencies

```swift
protocol Analytics {
    func track(_ event: String)
}

class FeedViewController {
    private let loader: FeedLoader
    private let analytics: Analytics?  // Optional dependency
    
    init(loader: FeedLoader, analytics: Analytics? = nil) {
        self.loader = loader
        self.analytics = analytics
    }
    
    func loadFeed() {
        analytics?.track("feed_load_started")
        loader.load { [weak self] result in
            self?.analytics?.track("feed_load_completed")
        }
    }
}
```

### 2. Environment-Based Injection

```swift
class DependencyContainer {
    private let environment: Environment
    
    init(environment: Environment) {
        self.environment = environment
    }
    
    func makeFeedLoader() -> FeedLoader {
        switch environment {
        case .production:
            return RemoteFeedLoader(client: httpClient, url: productionURL)
        case .staging:
            return RemoteFeedLoader(client: httpClient, url: stagingURL)
        case .development:
            return MockFeedLoader()
        }
    }
}
```

---

## Dependency Injection Checklist

- [ ] Dependencies injected, not created
- [ ] Depend on abstractions, not concretions
- [ ] Use constructor injection as default
- [ ] Composition root centralizes wiring
- [ ] Business logic has no framework dependencies
- [ ] Easy to test with mocks/stubs
- [ ] Easy to swap implementations
- [ ] Dependencies are explicit

---

## Further Reading

- Dependency Injection Principles, Practices, and Patterns by Steven van Deursen and Mark Seemann
- Clean Architecture by Robert C. Martin
- Essential Developer Resources: https://www.essentialdeveloper.com/
