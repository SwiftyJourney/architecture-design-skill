# Clean Architecture Reference

Comprehensive guide to implementing Clean Architecture principles in your projects.

---

## Overview

Clean Architecture is a software design philosophy that separates the elements of a design into ring levels. The main rule of Clean Architecture is the **Dependency Rule**:

> **Source code dependencies must point only inward, toward higher-level policies.**

Nothing in an inner circle can know anything about something in an outer circle.

---

## The Dependency Rule

```
┌──────────────────────────────────────────────────┐
│                   Frameworks                     │  ← External
│                  UI, Database                    │     (Details)
└────────────────────┬─────────────────────────────┘
                     │
┌────────────────────▼─────────────────────────────┐
│              Interface Adapters                  │  ← Adapters
│         Controllers, Presenters, Gateways        │     (Convert data)
└────────────────────┬─────────────────────────────┘
                     │
┌────────────────────▼─────────────────────────────┐
│              Application Business Rules          │  ← Use Cases
│                  Use Cases                       │     (App-specific)
└────────────────────┬─────────────────────────────┘
                     │
┌────────────────────▼─────────────────────────────┐
│            Enterprise Business Rules             │  ← Entities
│                   Entities                       │     (Core business)
└──────────────────────────────────────────────────┘
```

**Key Point**: Dependencies point **inward only**. Outer layers depend on inner layers, never the reverse.

---

## The Four Layers

### 1. Entities (Enterprise Business Rules)

**What**: Core business objects and rules that are universal to the enterprise.

**Characteristics**:
- Pure business logic
- No framework dependencies
- Highest level of abstraction
- Least likely to change

**Examples**:
```swift
struct FeedItem: Equatable {
    let id: UUID
    let description: String?
    let location: String?
    let imageURL: URL
}

struct ImageComment: Equatable {
    let id: UUID
    let message: String
    let createdAt: Date
    let author: CommentAuthor
}

struct CommentAuthor: Equatable {
    let username: String
}
```

**Rules**:
- No dependencies on any other layer
- Can be shared across multiple applications
- Contains critical business rules
- Framework-agnostic

---

### 2. Use Cases (Application Business Rules)

**What**: Application-specific business rules that orchestrate the flow of data.

**Characteristics**:
- Implements application logic
- Coordinates entity interactions
- Independent of UI and database
- Defines input/output boundaries

**Example Use Case**:
```swift
protocol FeedLoader {
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void)
}

class RemoteFeedLoader: FeedLoader {
    private let client: HTTPClient
    private let url: URL
    
    init(client: HTTPClient, url: URL) {
        self.client = client
        self.url = url
    }
    
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        client.get(from: url) { [weak self] result in
            guard self != nil else { return }
            
            switch result {
            case let .success((data, response)):
                completion(FeedItemsMapper.map(data, from: response))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }
}
```

**Use Case Structure**:
1. Define boundary interface (protocol)
2. Implement business logic
3. Coordinate data flow
4. Return results through boundary

**Rules**:
- Depends only on entities
- Independent of UI framework
- Independent of database
- Orchestrates business logic

---

### 3. Interface Adapters (Controllers, Presenters, Gateways)

**What**: Convert data between use cases and external systems (UI, database, web).

**Characteristics**:
- Adapts data formats
- Implements use case boundaries
- Converts between domain and infrastructure
- Handles framework-specific code

**Example Presenter**:
```swift
protocol FeedView {
    func display(_ viewModel: FeedViewModel)
}

struct FeedViewModel {
    let feed: [FeedItemViewModel]
}

struct FeedItemViewModel {
    let description: String?
    let location: String?
    let imageURL: URL
}

class FeedPresenter {
    private let view: FeedView
    private let loader: FeedLoader
    
    init(view: FeedView, loader: FeedLoader) {
        self.view = view
        self.loader = loader
    }
    
    func didRequestFeedRefresh() {
        loader.load { [weak self] result in
            switch result {
            case let .success(feed):
                self?.view.display(self?.map(feed) ?? FeedViewModel(feed: []))
            case .failure:
                // Handle error
                break
            }
        }
    }
    
    private func map(_ feed: [FeedItem]) -> FeedViewModel {
        let items = feed.map { item in
            FeedItemViewModel(
                description: item.description,
                location: item.location,
                imageURL: item.imageURL
            )
        }
        return FeedViewModel(feed: items)
    }
}
```

**Gateway Example**:
```swift
// Adapter between use case and database
protocol FeedStore {
    func save(_ feed: [LocalFeedItem], timestamp: Date, completion: @escaping (Error?) -> Void)
    func retrieve(completion: @escaping (Result<CachedFeed?, Error>) -> Void)
}

class CoreDataFeedStore: FeedStore {
    private let container: NSPersistentContainer
    
    func save(_ feed: [LocalFeedItem], timestamp: Date, completion: @escaping (Error?) -> Void) {
        // CoreData-specific implementation
    }
    
    func retrieve(completion: @escaping (Result<CachedFeed?, Error>) -> Void) {
        // CoreData-specific implementation
    }
}
```

**Rules**:
- Depends on use cases
- Implements boundary interfaces
- Converts data formats
- Isolates framework code

---

### 4. Frameworks & Drivers (External Layer)

**What**: External tools, frameworks, and details (database, UI, web, devices).

**Characteristics**:
- Framework-specific code
- Database implementations
- UI implementations
- External service integrations

**Example UI**:
```swift
class FeedViewController: UIViewController, FeedView {
    private let presenter: FeedPresenter
    private var tableModel = [FeedItemViewModel]()
    
    init(presenter: FeedPresenter) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        presenter.didRequestFeedRefresh()
    }
    
    func display(_ viewModel: FeedViewModel) {
        tableModel = viewModel.feed
        tableView.reloadData()
    }
}
```

**Example HTTP Client**:
```swift
class URLSessionHTTPClient: HTTPClient {
    private let session: URLSession
    
    func get(from url: URL, completion: @escaping (HTTPClient.Result) -> Void) {
        session.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
            } else if let data = data, let response = response as? HTTPURLResponse {
                completion(.success((data, response)))
            }
        }.resume()
    }
}
```

**Rules**:
- Contains framework-specific code
- Implements adapter interfaces
- Most volatile layer
- Details, not policies

---

## Crossing Boundaries

Data crosses boundaries through well-defined interfaces using the **Dependency Inversion Principle**.

### Example: Loading Feed Data

```
┌──────────────┐     ┌───────────────┐     ┌──────────────┐
│ViewController│────▶│  FeedPresenter│────▶│  FeedLoader  │
│   (UI Layer) │     │ (Adapter Layer)     │ (Use Case)   │
└──────────────┘     └───────────────┘     └──────────────┘
        │                    │                      │
        │                    │                      │
        ▼                    ▼                      ▼
   UIKit/SwiftUI         Protocol              Protocol
    (Framework)         (Boundary)            (Boundary)
```

**Data Flow**:
1. ViewController calls Presenter method
2. Presenter calls FeedLoader (use case)
3. FeedLoader executes business logic
4. FeedLoader returns domain models (FeedItem)
5. Presenter converts to view models
6. ViewController displays view models

**Key**: Each boundary is defined by a protocol/interface.

---

## Dependency Inversion at Boundaries

### The Problem (Without DI)

```swift
// ❌ Use case depends on concrete implementation
class LoadFeedUseCase {
    private let client = URLSessionHTTPClient()  // Concrete dependency
    
    func load() {
        client.get(from: url) { ... }
    }
}
```

**Issues**:
- Use case depends on infrastructure detail
- Cannot test without real network
- Tight coupling
- Violates dependency rule

### The Solution (With DI)

```swift
// ✅ Use case depends on abstraction
protocol HTTPClient {
    func get(from url: URL, completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void)
}

class LoadFeedUseCase {
    private let client: HTTPClient  // Depends on abstraction
    
    init(client: HTTPClient) {
        self.client = client
    }
    
    func load() {
        client.get(from: url) { ... }
    }
}

// Infrastructure implements abstraction
class URLSessionHTTPClient: HTTPClient {
    func get(from url: URL, completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void) {
        // URLSession implementation
    }
}
```

**Benefits**:
- Use case independent of infrastructure
- Easy to test with mocks
- Loose coupling
- Follows dependency rule

---

## Module Organization

### Recommended Project Structure

```
MyApp/
├── Domain/                      # Entities + Use Cases
│   ├── Entities/
│   │   ├── FeedItem.swift
│   │   └── ImageComment.swift
│   ├── UseCases/
│   │   ├── LoadFeed.swift
│   │   └── LoadComments.swift
│   └── Boundaries/             # Protocols defining boundaries
│       ├── FeedLoader.swift
│       ├── FeedCache.swift
│       └── HTTPClient.swift
│
├── Infrastructure/              # Framework & External Details
│   ├── Network/
│   │   ├── URLSessionHTTPClient.swift
│   │   └── FeedItemsMapper.swift
│   ├── Persistence/
│   │   ├── CoreDataFeedStore.swift
│   │   └── CoreDataHelpers.swift
│   └── API/
│       └── RemoteFeedLoader.swift
│
├── Presentation/                # Adapters (Presenters, ViewModels)
│   ├── FeedPresentation/
│   │   ├── FeedPresenter.swift
│   │   ├── FeedViewModel.swift
│   │   └── FeedView.swift (protocol)
│   └── CommentsPresentation/
│       ├── CommentsPresenter.swift
│       └── CommentsViewModel.swift
│
├── UI/                          # Frameworks (UIKit/SwiftUI)
│   ├── Feed/
│   │   ├── FeedViewController.swift
│   │   └── FeedCell.swift
│   └── Comments/
│       └── CommentsViewController.swift
│
└── Main/                        # Composition Root
    ├── SceneDelegate.swift
    ├── AppDelegate.swift
    └── CompositionRoot.swift
```

### Dependency Direction

```
UI ───────────────▶ Presentation
                          │
                          ▼
Infrastructure ────▶ Domain (Entities + Use Cases)
```

---

## The Composition Root

**What**: The place where all dependencies are wired together.

**Purpose**: 
- Create concrete implementations
- Inject dependencies
- Configure object graph
- Keep business logic clean

### Example Composition Root

```swift
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = (scene as? UIWindowScene) else { return }
        
        window = UIWindow(windowScene: scene)
        window?.rootViewController = makeFeedViewController()
        window?.makeKeyAndVisible()
    }
    
    // MARK: - Composition Root
    
    private func makeFeedViewController() -> UIViewController {
        let url = URL(string: "https://api.example.com/feed")!
        
        // Infrastructure Layer
        let httpClient = URLSessionHTTPClient()
        let store = try! CoreDataFeedStore(storeURL: storeURL)
        
        // Use Case Layer
        let remoteFeedLoader = RemoteFeedLoader(url: url, client: httpClient)
        let localFeedLoader = LocalFeedLoader(store: store, currentDate: Date.init)
        let combinedLoader = FeedLoaderWithFallback(
            primary: remoteFeedLoader,
            fallback: localFeedLoader
        )
        
        // Presentation Layer
        let viewController = FeedViewController()
        let presenter = FeedPresenter(view: viewController, loader: combinedLoader)
        viewController.presenter = presenter
        
        return UINavigationController(rootViewController: viewController)
    }
    
    private var storeURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("feed-store.sqlite")
    }
}
```

**Benefits**:
- All dependency creation in one place
- Easy to change implementations
- Business logic stays clean
- Testable architecture

---

## Testing Strategy in Clean Architecture

### Test Pyramid

```
        ┌──────────┐
        │  UI/E2E  │ ← Few, Slow, Expensive
        ├──────────┤
        │Integration│ ← Some, Medium Speed
        ├──────────┤
        │   Unit   │ ← Many, Fast, Cheap
        └──────────┘
```

### Testing Each Layer

#### 1. Domain Layer Testing (Unit Tests)

```swift
class LoadFeedUseCaseTests: XCTestCase {
    func test_init_doesNotRequestDataFromURL() {
        let (_, client) = makeSUT()
        
        XCTAssertTrue(client.requestedURLs.isEmpty)
    }
    
    func test_load_requestsDataFromURL() {
        let url = URL(string: "https://a-url.com")!
        let (sut, client) = makeSUT(url: url)
        
        sut.load { _ in }
        
        XCTAssertEqual(client.requestedURLs, [url])
    }
    
    func test_loadTwice_requestsDataFromURLTwice() {
        let url = URL(string: "https://a-url.com")!
        let (sut, client) = makeSUT(url: url)
        
        sut.load { _ in }
        sut.load { _ in }
        
        XCTAssertEqual(client.requestedURLs, [url, url])
    }
    
    // MARK: - Helpers
    
    private func makeSUT(url: URL = URL(string: "https://a-url.com")!) -> (sut: RemoteFeedLoader, client: HTTPClientSpy) {
        let client = HTTPClientSpy()
        let sut = RemoteFeedLoader(url: url, client: client)
        return (sut, client)
    }
    
    private class HTTPClientSpy: HTTPClient {
        private(set) var requestedURLs = [URL]()
        
        func get(from url: URL, completion: @escaping (HTTPClient.Result) -> Void) {
            requestedURLs.append(url)
        }
    }
}
```

**Characteristics**:
- Fast (milliseconds)
- No external dependencies
- Mock all boundaries
- Test business logic only

#### 2. Infrastructure Layer Testing (Integration Tests)

```swift
class CoreDataFeedStoreTests: XCTestCase {
    func test_retrieve_deliversEmptyOnEmptyCache() {
        let sut = makeSUT()
        
        expect(sut, toRetrieve: .success(.none))
    }
    
    func test_retrieve_hasNoSideEffectsOnEmptyCache() {
        let sut = makeSUT()
        
        expect(sut, toRetrieveTwice: .success(.none))
    }
    
    func test_save_deliversNoErrorOnEmptyCache() {
        let sut = makeSUT()
        
        let saveError = save(uniqueFeed().local, to: sut)
        
        XCTAssertNil(saveError)
    }
    
    // MARK: - Helpers
    
    private func makeSUT() -> FeedStore {
        let storeURL = URL(fileURLWithPath: "/dev/null")
        let sut = try! CoreDataFeedStore(storeURL: storeURL)
        return sut
    }
}
```

**Characteristics**:
- Slower than unit tests
- May use real database/filesystem
- Test adapter implementations
- Verify integration with frameworks

#### 3. Presentation Layer Testing (Unit Tests)

```swift
class FeedPresenterTests: XCTestCase {
    func test_init_doesNotMessageView() {
        let (_, view) = makeSUT()
        
        XCTAssertTrue(view.messages.isEmpty)
    }
    
    func test_didStartLoading_displaysNoErrorAndStartsLoading() {
        let (sut, view) = makeSUT()
        
        sut.didStartLoading()
        
        XCTAssertEqual(view.messages, [
            .display(errorMessage: .none),
            .display(isLoading: true)
        ])
    }
    
    // MARK: - Helpers
    
    private func makeSUT() -> (sut: FeedPresenter, view: ViewSpy) {
        let view = ViewSpy()
        let sut = FeedPresenter(view: view)
        return (sut, view)
    }
    
    private class ViewSpy: FeedView {
        enum Message: Equatable {
            case display(errorMessage: String?)
            case display(isLoading: Bool)
            case display(feed: [FeedItemViewModel])
        }
        
        private(set) var messages = [Message]()
        
        func display(_ viewModel: FeedErrorViewModel) {
            messages.append(.display(errorMessage: viewModel.message))
        }
        
        func display(_ viewModel: FeedLoadingViewModel) {
            messages.append(.display(isLoading: viewModel.isLoading))
        }
        
        func display(_ viewModel: FeedViewModel) {
            messages.append(.display(feed: viewModel.feed))
        }
    }
}
```

**Characteristics**:
- Fast unit tests
- Mock use cases and views
- Test presentation logic
- No UI framework code

---

## Common Patterns

### 1. Adapter Pattern

Convert interface to match what client expects.

```swift
// Target interface
protocol FeedLoader {
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void)
}

// Adaptee (existing interface)
protocol HTTPClient {
    func get(from url: URL, completion: @escaping (HTTPClient.Result) -> Void)
}

// Adapter
class RemoteFeedLoader: FeedLoader {
    private let client: HTTPClient
    private let url: URL
    
    init(client: HTTPClient, url: URL) {
        self.client = client
        self.url = url
    }
    
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        client.get(from: url) { result in
            switch result {
            case let .success((data, response)):
                completion(FeedItemsMapper.map(data, from: response))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }
}
```

### 2. Decorator Pattern

Add behavior without modifying existing code.

```swift
// Base component
protocol FeedLoader {
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void)
}

// Decorator - adds caching behavior
class FeedLoaderCacheDecorator: FeedLoader {
    private let decoratee: FeedLoader
    private let cache: FeedCache
    
    init(decoratee: FeedLoader, cache: FeedCache) {
        self.decoratee = decoratee
        self.cache = cache
    }
    
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

### 3. Composite Pattern

Combine multiple strategies.

```swift
class FeedLoaderWithFallback: FeedLoader {
    private let primary: FeedLoader
    private let fallback: FeedLoader
    
    init(primary: FeedLoader, fallback: FeedLoader) {
        self.primary = primary
        self.fallback = fallback
    }
    
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

### 4. Strategy Pattern

Define family of algorithms.

```swift
protocol CachePolicy {
    func validate(_ timestamp: Date) -> Bool
}

class SevenDaysCachePolicy: CachePolicy {
    private let calendar: Calendar
    
    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }
    
    func validate(_ timestamp: Date) -> Bool {
        guard let maxAge = calendar.date(byAdding: .day, value: 7, to: timestamp) else {
            return false
        }
        return Date() < maxAge
    }
}

class LocalFeedLoader {
    private let store: FeedStore
    private let policy: CachePolicy
    
    init(store: FeedStore, policy: CachePolicy) {
        self.store = store
        self.policy = policy
    }
    
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        store.retrieve { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case let .success(.some(cache)) where self.policy.validate(cache.timestamp):
                completion(.success(cache.feed))
            case .success:
                completion(.success([]))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }
}
```

---

## Benefits of Clean Architecture

### 1. Framework Independence
Business rules can be tested without UI, database, or external services.

### 2. Testability
Business logic is completely testable without UI, database, or web server.

### 3. UI Independence
UI can change without affecting business rules. Swap UIKit for SwiftUI easily.

### 4. Database Independence
Business rules don't know about database. Swap Core Data for Realm easily.

### 5. External Agency Independence
Business rules don't depend on external services.

### 6. Maintainability
Clear separation makes it easier to understand, modify, and extend.

---

## Common Mistakes

### 1. Skipping the Abstraction Layer

```swift
// ❌ View Controller directly using concrete loader
class FeedViewController {
    let loader = RemoteFeedLoader()
}
```

**Fix**: Always depend on abstractions.

### 2. Letting Domain Depend on Infrastructure

```swift
// ❌ Entity depending on UI framework
struct FeedItem {
    let image: UIImage  // UI framework in domain!
}
```

**Fix**: Keep domain pure, convert in adapter layer.

### 3. Mixing Layers

```swift
// ❌ View controller with business logic
class FeedViewController {
    func loadFeed() {
        let url = URL(string: "https://api.com")!
        URLSession.shared.dataTask(with: url) { ... }
    }
}
```

**Fix**: Separate into layers with clear boundaries.

### 4. Not Inverting Dependencies

```swift
// ❌ Use case depends on concrete implementation
class LoadFeedUseCase {
    let client = URLSessionHTTPClient()
}
```

**Fix**: Inject abstractions through initializer.

---

## Clean Architecture Checklist

- [ ] Dependencies point inward only
- [ ] Entities have no framework dependencies
- [ ] Use cases orchestrate business logic
- [ ] Boundaries defined with protocols/interfaces
- [ ] Adapters convert between layers
- [ ] Composition root wires dependencies
- [ ] Business logic is testable in isolation
- [ ] UI is independent of business logic
- [ ] Database is swappable

---

## Further Reading

- Clean Architecture by Robert C. Martin
- Essential Developer Resources: https://www.essentialdeveloper.com/
- iOS Lead Essentials: https://iosacademy.essentialdeveloper.com/
