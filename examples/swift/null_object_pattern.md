# Null Object Pattern in Essential Feed

Real-world examples of Null Object Pattern from the Essential Developer's Feed Case Study.

---

## Overview

The Null Object Pattern is used extensively in Essential Feed to:
1. Eliminate null checks in production code
2. Simplify test setup by providing safe default dependencies
3. Make optional dependencies truly optional

---

## Example 1: Task Cancellation

### The Problem

```swift
class ImageCell {
    private var task: URLSessionDataTask?
    
    func display(_ model: FeedImage) {
        // ❌ Need to check for nil
        if let task = task {
            task.cancel()
        }
        
        task = loader.loadImageData(from: model.url) { [weak self] result in
            self?.display(result)
        }
    }
}
```

### The Solution with Null Object

```swift
protocol FeedImageDataLoaderTask {
    func cancel()
}

// Real task
private final class LoadImageDataTask: FeedImageDataLoaderTask {
    private let task: URLSessionDataTask
    
    init(_ task: URLSessionDataTask) {
        self.task = task
    }
    
    func cancel() {
        task.cancel()
    }
}

// Null Object - does nothing
private struct NullTask: FeedImageDataLoaderTask {
    func cancel() {
        // Do nothing - already complete or cancelled
    }
}

// Loader
class RemoteFeedImageDataLoader {
    func loadImageData(from url: URL, completion: @escaping (Result<Data, Error>) -> Void) -> FeedImageDataLoaderTask {
        guard let data = try? Data(contentsOf: url) else {
            return NullTask()  // Return null object instead of nil
        }
        
        let task = session.dataTask(with: url) { data, response, error in
            completion(.success(data!))
        }
        task.resume()
        return LoadImageDataTask(task)
    }
}

// Usage - no null checks!
class ImageCell {
    private var task: FeedImageDataLoaderTask = NullTask()  // Never nil
    
    func display(_ model: FeedImage) {
        task.cancel()  // ✅ Always safe - no if let needed
        
        task = loader.loadImageData(from: model.url) { [weak self] result in
            self?.display(result)
        }
    }
}
```

**Benefits**:
- No nil checks in ImageCell
- Type-safe - task is never nil
- Clean, simple code

---

## Example 2: Analytics (Optional Dependency)

### Real Implementation

```swift
protocol FeedLoadingAnalytics {
    func didStartLoadingFeed()
    func didFinishLoadingFeed(itemCount: Int)
}

// Production analytics
class FeedLoadingAnalyticsTracker: FeedLoadingAnalytics {
    private let tracker: AnalyticsTracker
    
    init(tracker: AnalyticsTracker) {
        self.tracker = tracker
    }
    
    func didStartLoadingFeed() {
        tracker.track(event: "feed_loading_started")
    }
    
    func didFinishLoadingFeed(itemCount: Int) {
        tracker.track(event: "feed_loading_finished", properties: [
            "item_count": itemCount
        ])
    }
}

// Null Object for testing
class NullFeedLoadingAnalytics: FeedLoadingAnalytics {
    func didStartLoadingFeed() {
        // Do nothing
    }
    
    func didFinishLoadingFeed(itemCount: Int) {
        // Do nothing
    }
}

// Use Case
class RemoteFeedLoader {
    private let client: HTTPClient
    private let analytics: FeedLoadingAnalytics
    
    // Defaults to NullFeedLoadingAnalytics
    init(client: HTTPClient, analytics: FeedLoadingAnalytics = NullFeedLoadingAnalytics()) {
        self.client = client
        self.analytics = analytics
    }
    
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        analytics.didStartLoadingFeed()
        
        client.get(from: url) { [weak self] result in
            switch result {
            case let .success(data):
                let items = Self.map(data)
                self?.analytics.didFinishLoadingFeed(itemCount: items.count)
                completion(.success(items))
                
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }
}

// Test - no need to mock analytics
func test_load_requestsDataFromURL() {
    let client = HTTPClientSpy()
    let sut = RemoteFeedLoader(client: client)  // Uses NullFeedLoadingAnalytics
    
    sut.load { _ in }
    
    XCTAssertEqual(client.requestedURLs, [expectedURL])
}

// Production - uses real analytics
let productionLoader = RemoteFeedLoader(
    client: URLSessionHTTPClient(),
    analytics: FeedLoadingAnalyticsTracker(tracker: analyticsService)
)
```

---

## Example 3: Logger

```swift
protocol FeedLoaderLogger {
    func log(_ message: String, level: LogLevel)
}

enum LogLevel {
    case debug, info, warning, error
}

// Production logger
class ConsoleFeedLoaderLogger: FeedLoaderLogger {
    func log(_ message: String, level: LogLevel) {
        print("[\(level)] \(message)")
    }
}

// Null logger - silent
class NullFeedLoaderLogger: FeedLoaderLogger {
    func log(_ message: String, level: LogLevel) {
        // Silent - do nothing
    }
}

// Usage
class RemoteFeedLoader {
    private let client: HTTPClient
    private let logger: FeedLoaderLogger
    
    init(client: HTTPClient, logger: FeedLoaderLogger = NullFeedLoaderLogger()) {
        self.client = client
        self.logger = logger
    }
    
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        logger.log("Starting feed load from \(url)", level: .info)
        
        client.get(from: url) { [weak self] result in
            switch result {
            case .success:
                self?.logger.log("Feed load successful", level: .info)
            case let .failure(error):
                self?.logger.log("Feed load failed: \(error)", level: .error)
            }
            completion(result)
        }
    }
}
```

---

## Example 4: Cache (Optional Behavior)

```swift
protocol FeedCache {
    func save(_ feed: [FeedItem], completion: @escaping (Error?) -> Void)
}

// Real cache
class LocalFeedCache: FeedCache {
    private let store: FeedStore
    
    func save(_ feed: [FeedItem], completion: @escaping (Error?) -> Void) {
        store.deleteCachedFeed { [weak self] deletionResult in
            switch deletionResult {
            case .success:
                self?.insert(feed, completion: completion)
            case let .failure(error):
                completion(error)
            }
        }
    }
}

// Null cache - no caching
class NullFeedCache: FeedCache {
    func save(_ feed: [FeedItem], completion: @escaping (Error?) -> Void) {
        completion(nil)  // Success - no error
    }
}

// Decorator with optional caching
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
                self?.cache.save(feed) { _ in }
            }
            completion(result)
        }
    }
}

// Test - no caching
func test_load_doesNotCacheOnFailure() {
    let cache = FeedCacheSpy()
    let sut = FeedLoaderCacheDecorator(
        decoratee: loader,
        cache: NullFeedCache()  // No caching in this test
    )
    
    sut.load { _ in }
    
    // Test other behavior
}
```

---

## Testing Benefits

### Before (Without Null Object)

```swift
class RemoteFeedLoaderTests: XCTestCase {
    func test_load_requestsDataFromURL() {
        let client = HTTPClientSpy()
        let logger: FeedLoaderLogger? = nil
        let analytics: FeedLoadingAnalytics? = nil
        
        // ❌ Need to handle optionals
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
class RemoteFeedLoaderTests: XCTestCase {
    func test_load_requestsDataFromURL() {
        let client = HTTPClientSpy()
        
        // ✅ Clean - defaults to null objects
        let sut = RemoteFeedLoader(client: client)
        
        sut.load { _ in }
        
        XCTAssertEqual(client.requestedURLs, [url])
    }
    
    func test_load_logsStartAndFinish() {
        let client = HTTPClientSpy()
        let logger = LoggerSpy()  // Only mock when testing logging
        let sut = RemoteFeedLoader(client: client, logger: logger)
        
        sut.load { _ in }
        client.complete(withStatusCode: 200, data: validData)
        
        XCTAssertEqual(logger.messages, [
            "Starting feed load",
            "Feed load successful"
        ])
    }
}
```

---

## Singleton Null Objects

```swift
// Make null objects singletons - they're stateless
class NullFeedLoadingAnalytics: FeedLoadingAnalytics {
    static let shared = NullFeedLoadingAnalytics()
    private init() {}
    
    func didStartLoadingFeed() {}
    func didFinishLoadingFeed(itemCount: Int) {}
}

class NullFeedLoaderLogger: FeedLoaderLogger {
    static let shared = NullFeedLoaderLogger()
    private init() {}
    
    func log(_ message: String, level: LogLevel) {}
}

// Usage
let loader = RemoteFeedLoader(
    client: httpClient,
    logger: NullFeedLoaderLogger.shared,
    analytics: NullFeedLoadingAnalytics.shared
)
```

---

## Key Takeaways

1. **Null Object eliminates null checks** - Code is cleaner and safer
2. **Perfect for optional dependencies** - Analytics, logging, metrics
3. **Simplifies testing** - Default to null objects, only mock what you test
4. **Type-safe** - No optionals, no force unwrapping
5. **Make them singletons** - Stateless objects can be shared
6. **Essential Developer uses it extensively** - Check Essential Feed for more examples

---

## Further Reading

- Essential Feed Case Study: https://github.com/essentialdevelopercom/essential-feed-case-study
- Essential Developer Articles: https://www.essentialdeveloper.com/articles
- Design Patterns: Elements of Reusable Object-Oriented Software
