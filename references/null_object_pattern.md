# Null Object Pattern

A behavioral design pattern that provides a default "do-nothing" behavior, eliminating the need for null checks and making tests cleaner.

---

## What is the Null Object Pattern?

The Null Object Pattern replaces `null` references with an object that implements the expected interface but does nothing. This avoids `if (object != null)` checks throughout the code.

### The Problem

```swift
// ❌ Without Null Object Pattern
class FeedViewController {
    var loader: FeedLoader?
    
    func loadFeed() {
        if let loader = loader {  // Null check required
            loader.load { result in
                // Handle result
            }
        } else {
            // Handle missing loader
        }
    }
}
```

**Issues**:
- Null checks scattered everywhere
- Easy to forget checks → crashes
- Test code needs to handle nil cases
- Verbose and error-prone

### The Solution

```swift
// ✅ With Null Object Pattern
protocol FeedLoader {
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void)
}

// Null Object - does nothing safely
class NullFeedLoader: FeedLoader {
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        // Do nothing - no completion call
    }
}

class FeedViewController {
    var loader: FeedLoader  // Never nil
    
    init(loader: FeedLoader = NullFeedLoader()) {
        self.loader = loader
    }
    
    func loadFeed() {
        loader.load { result in  // No null check needed
            // Handle result
        }
    }
}
```

**Benefits**:
- No null checks needed
- Type-safe - loader is never nil
- Tests can use NullFeedLoader as default
- Clean, predictable behavior

---

## Essential Developer's Usage

### 1. Null Object for Analytics (Optional Dependencies)

```swift
protocol FeedLoadingAnalytics {
    func didStartLoadingFeed()
    func didFinishLoadingFeed(with result: FeedLoader.Result)
}

// Real implementation
class FeedLoadingAnalyticsTracker: FeedLoadingAnalytics {
    func didStartLoadingFeed() {
        // Track analytics event
        analytics.track("feed_loading_started")
    }
    
    func didFinishLoadingFeed(with result: FeedLoader.Result) {
        switch result {
        case .success:
            analytics.track("feed_loading_success")
        case .failure:
            analytics.track("feed_loading_failure")
        }
    }
}

// Null Object - does nothing
class NullFeedLoadingAnalytics: FeedLoadingAnalytics {
    func didStartLoadingFeed() {
        // Do nothing
    }
    
    func didFinishLoadingFeed(with result: FeedLoader.Result) {
        // Do nothing
    }
}

// Use case with optional analytics
class LoadFeedUseCase {
    private let loader: FeedLoader
    private let analytics: FeedLoadingAnalytics
    
    // Analytics defaults to Null Object
    init(loader: FeedLoader, analytics: FeedLoadingAnalytics = NullFeedLoadingAnalytics()) {
        self.loader = loader
        self.analytics = analytics
    }
    
    func load(completion: @escaping (FeedLoader.Result) -> Void) {
        analytics.didStartLoadingFeed()
        
        loader.load { [weak self] result in
            self?.analytics.didFinishLoadingFeed(with: result)
            completion(result)
        }
    }
}
```

### 2. Null Object for Logging

```swift
protocol Logger {
    func log(_ message: String)
}

class ConsoleLogger: Logger {
    func log(_ message: String) {
        print("[LOG]: \(message)")
    }
}

class NullLogger: Logger {
    func log(_ message: String) {
        // Do nothing - silent logger
    }
}

// Production: uses ConsoleLogger
let productionLoader = RemoteFeedLoader(
    client: httpClient,
    logger: ConsoleLogger()
)

// Tests: uses NullLogger (no console spam)
let testLoader = RemoteFeedLoader(
    client: httpClient,
    logger: NullLogger()
)
```

### 3. Null Object for Caching (Optional Behavior)

```swift
protocol FeedCache {
    func save(_ feed: [FeedItem], completion: @escaping (Error?) -> Void)
}

class LocalFeedCache: FeedCache {
    func save(_ feed: [FeedItem], completion: @escaping (Error?) -> Void) {
        // Save to disk
        store.insert(feed, completion: completion)
    }
}

class NullFeedCache: FeedCache {
    func save(_ feed: [FeedItem], completion: @escaping (Error?) -> Void) {
        // Do nothing - no caching
        completion(nil)
    }
}

// Loader with optional caching
class FeedLoaderCacheDecorator: FeedLoader {
    private let decoratee: FeedLoader
    private let cache: FeedCache
    
    init(decoratee: FeedLoader, cache: FeedCache = NullFeedCache()) {
        self.decoratee = decoratee
        self.cache = cache
    }
    
    func load(completion: @escaping (FeedLoader.Result) -> Void) {
        decoratee.load { [weak self] result in
            if case let .success(feed) = result {
                self?.cache.save(feed) { _ in }  // Safe - never nil
            }
            completion(result)
        }
    }
}
```

---

## Null Object in Testing

### Simplifying Test Setup

```swift
class FeedViewControllerTests: XCTestCase {
    
    // ✅ No need to create mocks for optional dependencies
    func test_viewDidLoad_doesNotCrashWithNullDependencies() {
        let sut = FeedViewController(
            loader: NullFeedLoader(),
            analytics: NullFeedLoadingAnalytics(),
            logger: NullLogger()
        )
        
        sut.loadViewIfNeeded()
        
        // Test passes - no null pointer exceptions
    }
    
    // ✅ Only mock what you're testing
    func test_load_requestsDataFromLoader() {
        let loader = FeedLoaderSpy()
        let sut = FeedViewController(
            loader: loader,
            analytics: NullFeedLoadingAnalytics(),  // Not under test
            logger: NullLogger()                     // Not under test
        )
        
        sut.loadFeed()
        
        XCTAssertEqual(loader.loadCallCount, 1)
    }
}
```

### Null Object as Default Parameter

```swift
class RemoteFeedLoader: FeedLoader {
    private let client: HTTPClient
    private let logger: Logger
    
    // Null object as default - tests don't need to provide logger
    init(client: HTTPClient, logger: Logger = NullLogger()) {
        self.client = client
        self.logger = logger
    }
    
    func load(completion: @escaping (FeedLoader.Result) -> Void) {
        logger.log("Starting feed load")
        
        client.get(from: url) { result in
            // Handle result
        }
    }
}

// Test - no need to provide logger
func test_load_requestsDataFromURL() {
    let client = HTTPClientSpy()
    let sut = RemoteFeedLoader(client: client)  // Uses NullLogger
    
    sut.load { _ in }
    
    XCTAssertEqual(client.requestedURLs, [expectedURL])
}
```

---

## When to Use Null Object Pattern

### ✅ Use When:

1. **Optional dependencies** that aren't critical to core functionality
   - Analytics
   - Logging
   - Metrics

2. **Testing** to avoid creating unnecessary mocks
   - Default parameters in tests
   - Simplify test setup

3. **Default behavior** is well-defined and safe
   - "Do nothing" is a valid response
   - No side effects expected

### ❌ Don't Use When:

1. **Critical dependencies** that are required
   - Network client
   - Database store
   - Core business logic

2. **Null has special meaning** in your domain
   - User might not exist
   - Data might be unavailable
   - Use Optional<T> instead

3. **Different failure modes** need different handling
   - Use Result<Success, Error> type
   - Explicit error handling needed

---

## Null Object vs Optional

### Optional<T> (Swift)

```swift
// Use Optional when absence is meaningful
class UserRepository {
    func findUser(id: UUID) -> User? {
        // nil means "user not found"
        return database.query(id)
    }
}

// Caller must handle nil case explicitly
if let user = repository.findUser(id: userId) {
    display(user)
} else {
    showError("User not found")
}
```

### Null Object Pattern

```swift
// Use Null Object when absence should be transparent
protocol Logger {
    func log(_ message: String)
}

// NullLogger is a valid logger that does nothing
class NullLogger: Logger {
    func log(_ message: String) {}
}

// Caller doesn't need to check
let logger: Logger = NullLogger()
logger.log("Something happened")  // Safe, does nothing
```

**Key Difference**: Optional forces caller to handle absence. Null Object makes absence transparent.

---

## Implementation Guidelines

### 1. Implement the Same Interface

```swift
// ✅ Null object implements full interface
protocol FeedCache {
    func save(_ feed: [FeedItem], completion: @escaping (Error?) -> Void)
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void)
}

class NullFeedCache: FeedCache {
    func save(_ feed: [FeedItem], completion: @escaping (Error?) -> Void) {
        completion(nil)  // Success - no error
    }
    
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        completion(.success([]))  // Empty feed
    }
}
```

### 2. Provide Sensible Default Behavior

```swift
// ❌ Bad - throwing errors defeats the purpose
class BadNullCache: FeedCache {
    func save(_ feed: [FeedItem], completion: @escaping (Error?) -> Void) {
        completion(NSError(domain: "NullCache", code: 1))  // Don't do this!
    }
}

// ✅ Good - returns neutral/empty values
class GoodNullCache: FeedCache {
    func save(_ feed: [FeedItem], completion: @escaping (Error?) -> Void) {
        completion(nil)  // No error
    }
    
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        completion(.success([]))  // Empty is valid
    }
}
```

### 3. Make it a Singleton (Optional)

```swift
// Null objects are stateless - one instance is enough
class NullLogger: Logger {
    static let shared = NullLogger()
    private init() {}
    
    func log(_ message: String) {
        // Do nothing
    }
}

// Usage
let loader = RemoteFeedLoader(
    client: httpClient,
    logger: NullLogger.shared
)
```

### 4. Name it Clearly

```swift
// ✅ Good names
class NullFeedLoader
class NullLogger
class NullAnalytics
class SilentLogger
class NoOpCache

// ❌ Confusing names
class EmptyFeedLoader  // Confusing with actual empty feed
class DefaultLogger    // Suggests it's the default, not null
```

---

## Real-World Example from Essential Feed

### Image Data Loader with Null Task

```swift
protocol FeedImageDataLoaderTask {
    func cancel()
}

class FeedImageDataLoader {
    func loadImageData(from url: URL, completion: @escaping (Result<Data, Error>) -> Void) -> FeedImageDataLoaderTask {
        let task = URLSessionTask()
        task.resume()
        return task
    }
}

// Null task - returned when operation is cancelled immediately
private struct NullTask: FeedImageDataLoaderTask {
    func cancel() {
        // Do nothing - already cancelled
    }
}

// Usage
class ImageCell {
    private var task: FeedImageDataLoaderTask?
    
    func loadImage(from url: URL, loader: FeedImageDataLoader) {
        task = loader.loadImageData(from: url) { [weak self] result in
            self?.display(result)
        }
    }
    
    func cancelLoad() {
        task?.cancel()  // Safe even if nil or NullTask
        task = nil
    }
}
```

---

## Testing with Null Object

### Before (Without Null Object)

```swift
class FeedLoaderTests: XCTestCase {
    func test_load_requestsData() {
        let client = HTTPClientSpy()
        let logger: Logger? = nil  // Need to handle optionals
        let analytics: Analytics? = nil
        let sut = RemoteFeedLoader(
            client: client,
            logger: logger,
            analytics: analytics
        )
        
        sut.load { _ in }
        
        XCTAssertEqual(client.requestedURLs, [url])
    }
}
```

### After (With Null Object)

```swift
class FeedLoaderTests: XCTestCase {
    func test_load_requestsData() {
        let client = HTTPClientSpy()
        // No need to provide logger or analytics - defaults to Null Objects
        let sut = RemoteFeedLoader(client: client)
        
        sut.load { _ in }
        
        XCTAssertEqual(client.requestedURLs, [url])
    }
}
```

---

## Combining with Other Patterns

### Null Object + Decorator

```swift
// Base loader
let remoteLoader = RemoteFeedLoader(client: httpClient)

// Add analytics with Decorator (using Null Object if analytics not needed)
let loaderWithAnalytics = FeedLoaderAnalyticsDecorator(
    decoratee: remoteLoader,
    analytics: NullFeedLoadingAnalytics()  // No analytics in tests
)

// Add caching with Decorator
let loaderWithCache = FeedLoaderCacheDecorator(
    decoratee: loaderWithAnalytics,
    cache: NullFeedCache()  // No caching in tests
)
```

### Null Object + Strategy

```swift
protocol CachePolicy {
    func validate(_ timestamp: Date, against date: Date) -> Bool
}

// Real policy
class SevenDaysCachePolicy: CachePolicy {
    func validate(_ timestamp: Date, against date: Date) -> Bool {
        // Validate age
    }
}

// Null policy - always valid
class NullCachePolicy: CachePolicy {
    func validate(_ timestamp: Date, against date: Date) -> Bool {
        return true  // Always accept
    }
}
```

---

## Checklist

- [ ] Null object implements full interface
- [ ] Provides sensible "do nothing" behavior
- [ ] No side effects or state changes
- [ ] Named clearly (Null*, Silent*, NoOp*)
- [ ] Used for optional, non-critical dependencies
- [ ] Simplifies test setup
- [ ] Returns neutral/empty values, not errors
- [ ] Consider making it a singleton

---

## Common Mistakes

### ❌ Mistake 1: Throwing Errors

```swift
class NullCache: FeedCache {
    func save(_ feed: [FeedItem], completion: @escaping (Error?) -> Void) {
        completion(NSError(...))  // Don't throw errors!
    }
}
```

**Fix**: Return success/neutral values.

### ❌ Mistake 2: Using for Critical Dependencies

```swift
// Bad - HTTP client is critical!
class NullHTTPClient: HTTPClient {
    func get(from url: URL, completion: @escaping (Result) -> Void) {
        // Do nothing
    }
}
```

**Fix**: Only use for optional dependencies.

### ❌ Mistake 3: Complex Logic in Null Object

```swift
class NullLogger: Logger {
    func log(_ message: String) {
        // ❌ Too much logic for null object
        if message.contains("ERROR") {
            logToFile(message)
        }
    }
}
```

**Fix**: Null objects should do nothing.

---

## Further Reading

- Design Patterns: Elements of Reusable Object-Oriented Software (Gang of Four)
- Refactoring: Improving the Design of Existing Code by Martin Fowler
- Essential Developer: https://www.essentialdeveloper.com/
- Essential Feed Case Study: https://github.com/essentialdevelopercom/essential-feed-case-study
