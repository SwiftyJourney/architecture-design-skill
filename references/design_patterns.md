# Design Patterns for Clean Architecture

Common design patterns used in Clean Architecture implementations.

---

## Creational Patterns

### 1. Factory Pattern

Creates objects without exposing creation logic.

```swift
protocol FeedLoaderFactory {
    func makeFeedLoader() -> FeedLoader
}

class ProductionFeedLoaderFactory: FeedLoaderFactory {
    func makeFeedLoader() -> FeedLoader {
        let client = URLSessionHTTPClient()
        return RemoteFeedLoader(client: client, url: feedURL)
    }
}
```

---

## Structural Patterns

### 2. Adapter Pattern

Convert interface to match client expectations.

```swift
protocol FeedLoader {
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void)
}

class RemoteFeedLoaderAdapter: FeedLoader {
    private let client: HTTPClient
    
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        client.get(from: url) { result in
            // Adapt HTTP response to FeedItem
        }
    }
}
```

### 3. Decorator Pattern

Add behavior without modifying existing code.

```swift
class FeedLoaderCacheDecorator: FeedLoader {
    private let decoratee: FeedLoader
    private let cache: FeedCache
    
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        decoratee.load { [weak self] result in
            if case let .success(feed) = result {
                self?.cache.save(feed) { _ in }
            }
            completion(result)
        }
    }
}
```

### 4. Composite Pattern

Treat individual objects and compositions uniformly.

```swift
class FeedLoaderWithFallback: FeedLoader {
    private let primary: FeedLoader
    private let fallback: FeedLoader
    
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        primary.load { [weak self] result in
            switch result {
            case .success:
                completion(result)
            case .failure:
                self?.fallback.load(completion: completion)
            }
        }
    }
}
```

---

## Behavioral Patterns

### 5. Null Object Pattern

Provides default "do-nothing" behavior, eliminating null checks.

```swift
protocol Logger {
    func log(_ message: String)
}

class ConsoleLogger: Logger {
    func log(_ message: String) {
        print("[LOG]: \(message)")
    }
}

// Null Object - does nothing
class NullLogger: Logger {
    func log(_ message: String) {
        // Do nothing - silent
    }
}

// Use case - no null checks needed
class FeedLoader {
    private let logger: Logger
    
    // Defaults to NullLogger - optional dependency
    init(client: HTTPClient, logger: Logger = NullLogger()) {
        self.logger = logger
    }
    
    func load() {
        logger.log("Loading feed")  // Safe - never nil
        // Load logic
    }
}
```

**When to use**: Optional dependencies (analytics, logging, metrics).

**Benefits**:
- No null checks
- Simplifies testing
- Type-safe
- Clean code

### 6. Strategy Pattern

Define family of algorithms.

```swift
protocol CachePolicy {
    func validate(_ timestamp: Date) -> Bool
}

class SevenDaysCachePolicy: CachePolicy {
    func validate(_ timestamp: Date) -> Bool {
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        return timestamp > sevenDaysAgo
    }
}

class LocalFeedLoader {
    private let policy: CachePolicy
    
    init(store: FeedStore, policy: CachePolicy) {
        self.policy = policy
    }
}
```

### 7. Template Method Pattern

Define skeleton of algorithm in base class.

```swift
protocol FeedLoader {
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void)
}

// Base template
class BaseFeedLoader: FeedLoader {
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        performLoad { [weak self] result in
            let mappedResult = self?.mapResult(result) ?? .failure(anyError())
            completion(mappedResult)
        }
    }
    
    // Subclasses override these
    func performLoad(completion: @escaping (RawResult) -> Void) {
        fatalError("Must override")
    }
    
    func mapResult(_ result: RawResult) -> Result<[FeedItem], Error> {
        fatalError("Must override")
    }
}
```

### 8. Observer Pattern

Define one-to-many dependency.

```swift
protocol FeedLoadingObserver {
    func didStartLoading()
    func didFinishLoading(_ result: Result<[FeedItem], Error>)
}

class FeedLoader {
    private var observers: [FeedLoadingObserver] = []
    
    func addObserver(_ observer: FeedLoadingObserver) {
        observers.append(observer)
    }
    
    func load() {
        observers.forEach { $0.didStartLoading() }
        // Load logic
        observers.forEach { $0.didFinishLoading(result) }
    }
}
```

---

## Essential Developer Patterns

### Main-Thread Decorator

```swift
class MainQueueDispatchDecorator<T> {
    private let decoratee: T
    
    init(decoratee: T) {
        self.decoratee = decoratee
    }
}

extension MainQueueDispatchDecorator: FeedLoader where T == FeedLoader {
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        decoratee.load { result in
            if Thread.isMainThread {
                completion(result)
            } else {
                DispatchQueue.main.async {
                    completion(result)
                }
            }
        }
    }
}
```

### Resource Loader Pattern

```swift
protocol ResourceLoader {
    typealias Result = Swift.Result<Resource, Error>
    associatedtype Resource
    
    func load(completion: @escaping (Result) -> Void)
}
```

---

## Further Reading
- Design Patterns by Gang of Four
- Essential Developer: https://www.essentialdeveloper.com/
