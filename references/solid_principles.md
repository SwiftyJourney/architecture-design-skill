# SOLID Principles Reference

Detailed guide to applying SOLID principles in software design, with examples and anti-patterns.

---

## S - Single Responsibility Principle (SRP)

> "A class should have one, and only one, reason to change"

### Definition

Each module, class, or function should have responsibility over a single part of the functionality, and that responsibility should be entirely encapsulated.

### Why It Matters

- Makes code easier to understand
- Reduces the impact of changes
- Improves testability
- Reduces coupling

### How to Identify SRP Violations

Ask: **"How many reasons does this class have to change?"**

If the answer is more than one, you're violating SRP.

### Common Violations ❌

#### Violation 1: Mixing Business Logic and Infrastructure

```swift
class FeedViewController: UIViewController {
    func loadFeed() {
        // ❌ View controller making network requests
        let url = URL(string: "https://api.example.com/feed")!
        URLSession.shared.dataTask(with: url) { data, response, error in
            // ❌ View controller parsing JSON
            let items = try? JSONDecoder().decode([FeedItem].self, from: data!)
            // ❌ View controller updating UI
            self.display(items!)
        }.resume()
    }
}
```

**Problems**:
- Controller has 3 reasons to change: UI, networking, parsing
- Cannot test business logic without UI framework
- Hard to reuse networking logic

#### Violation 2: God Classes

```swift
class UserManager {
    func login(username: String, password: String) { ... }
    func logout() { ... }
    func updateProfile(_ profile: UserProfile) { ... }
    func uploadAvatar(_ image: UIImage) { ... }
    func validateEmail(_ email: String) -> Bool { ... }
    func hashPassword(_ password: String) -> String { ... }
    func sendPasswordResetEmail(to email: String) { ... }
}
```

**Problems**:
- Too many responsibilities
- Many reasons to change
- Hard to test individual behaviors

### Solutions ✅

#### Solution 1: Separate Concerns

```swift
// Business logic
protocol FeedLoader {
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void)
}

// Infrastructure
class RemoteFeedLoader: FeedLoader {
    private let client: HTTPClient
    
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        client.get(from: url) { result in
            // Handle networking
        }
    }
}

// Presentation
class FeedViewController: UIViewController {
    private let loader: FeedLoader
    
    func loadFeed() {
        loader.load { [weak self] result in
            // Only handle UI updates
            self?.display(result)
        }
    }
}
```

#### Solution 2: Split God Class

```swift
// Authentication
class AuthenticationService {
    func login(username: String, password: String) { ... }
    func logout() { ... }
}

// Profile Management
class ProfileService {
    func update(_ profile: UserProfile) { ... }
    func uploadAvatar(_ image: UIImage) { ... }
}

// Validation
class EmailValidator {
    func validate(_ email: String) -> Bool { ... }
}

// Security
class PasswordHasher {
    func hash(_ password: String) -> String { ... }
}
```

### SRP Checklist

- [ ] Each class has a single, well-defined responsibility
- [ ] Class name clearly describes its purpose
- [ ] Methods are cohesive (work together toward same goal)
- [ ] Changes to one feature don't require modifying this class
- [ ] Class can be described in one sentence without "and" or "or"

---

## O - Open/Closed Principle (OCP)

> "Software entities should be open for extension, but closed for modification"

### Definition

You should be able to extend a class's behavior without modifying its source code.

### Why It Matters

- Reduces risk when adding features
- Minimizes regression bugs
- Promotes code reuse
- Enables plugin architectures

### Common Violations ❌

#### Violation: Modifying Existing Code for New Features

```swift
class FeedLoader {
    func load(from source: String) {
        if source == "remote" {
            // Load from network
        } else if source == "local" {
            // Load from cache
        }
        // ❌ Adding new source requires modifying this class
    }
}
```

**Problems**:
- Need to modify existing code for new sources
- Growing if/else statements
- Violates SRP too

### Solutions ✅

#### Solution: Use Abstraction and Composition

```swift
// Open for extension via protocol
protocol FeedLoader {
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void)
}

// Closed for modification - each implementation is separate
class RemoteFeedLoader: FeedLoader {
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        // Remote loading logic
    }
}

class LocalFeedLoader: FeedLoader {
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        // Local loading logic
    }
}

class FallbackFeedLoader: FeedLoader {
    private let primary: FeedLoader
    private let fallback: FeedLoader
    
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        primary.load { result in
            switch result {
            case .success:
                completion(result)
            case .failure:
                self.fallback.load(completion: completion)
            }
        }
    }
}
```

**Benefits**:
- Add new loaders without modifying existing code
- Compose behaviors (FallbackFeedLoader)
- Each implementation is closed for modification

### Strategy Pattern Example

```swift
// Strategy interface
protocol ValidationStrategy {
    func validate(_ text: String) -> Bool
}

// Concrete strategies (closed for modification)
class EmailValidationStrategy: ValidationStrategy {
    func validate(_ text: String) -> Bool {
        // Email validation logic
    }
}

class PhoneValidationStrategy: ValidationStrategy {
    func validate(_ text: String) -> Bool {
        // Phone validation logic
    }
}

// Context (open for extension)
class FormValidator {
    private let strategy: ValidationStrategy
    
    init(strategy: ValidationStrategy) {
        self.strategy = strategy
    }
    
    func validate(_ input: String) -> Bool {
        return strategy.validate(input)
    }
}
```

### OCP Checklist

- [ ] New features added through new classes, not modification
- [ ] Abstraction (protocol/interface) defines extension points
- [ ] Existing code doesn't need changes when extending
- [ ] Use composition and dependency injection
- [ ] Follow "Program to interfaces, not implementations"

---

## L - Liskov Substitution Principle (LSP)

> "Derived classes must be substitutable for their base classes"

### Definition

If S is a subtype of T, then objects of type T may be replaced with objects of type S without altering the correctness of the program.

### Why It Matters

- Ensures polymorphism works correctly
- Prevents unexpected behavior
- Maintains contracts
- Enables reliable abstractions

### Common Violations ❌

#### Violation 1: Strengthening Preconditions

```swift
protocol FeedCache {
    func save(_ items: [FeedItem]) throws
}

class LocalFeedCache: FeedCache {
    func save(_ items: [FeedItem]) throws {
        // ❌ Strengthening precondition - base doesn't require this
        guard !items.isEmpty else {
            throw CacheError.emptyItems
        }
        // Save logic
    }
}
```

**Problem**: Client expects to save empty arrays based on protocol, but implementation throws error.

#### Violation 2: Weakening Postconditions

```swift
protocol FeedLoader {
    // Promise: always delivers result (success or failure)
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void)
}

class BrokenFeedLoader: FeedLoader {
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        // ❌ Weakening postcondition - might not call completion
        if someCondition {
            completion(.success([]))
        }
        // Missing completion call in else case
    }
}
```

**Problem**: Violates contract by not always delivering result.

### Solutions ✅

#### Solution 1: Honor Preconditions

```swift
protocol FeedCache {
    func save(_ items: [FeedItem]) throws
}

class LocalFeedCache: FeedCache {
    func save(_ items: [FeedItem]) throws {
        // ✅ Accept any items array, including empty
        let encoder = JSONEncoder()
        let data = try encoder.encode(items)
        try data.write(to: storeURL)
    }
}
```

#### Solution 2: Honor Postconditions

```swift
class ReliableFeedLoader: FeedLoader {
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        // ✅ Always calls completion
        httpClient.get(from: url) { result in
            switch result {
            case let .success(data):
                do {
                    let items = try self.decode(data)
                    completion(.success(items))
                } catch {
                    completion(.failure(error))
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }
}
```

### LSP Checklist

- [ ] Subtypes don't strengthen preconditions
- [ ] Subtypes don't weaken postconditions
- [ ] Subtypes maintain invariants of base type
- [ ] No surprising behavior when substituting
- [ ] All protocol requirements fully implemented

---

## I - Interface Segregation Principle (ISP)

> "Clients should not be forced to depend on interfaces they don't use"

### Definition

Split large interfaces into smaller, more specific ones so clients only need to know about methods relevant to them.

### Why It Matters

- Reduces coupling
- Improves code clarity
- Easier to test
- Avoids unnecessary dependencies

### Common Violations ❌

#### Violation: Fat Interface

```swift
protocol FeedDataStore {
    func save(_ items: [FeedItem]) throws
    func load() throws -> [FeedItem]
    func delete(_ item: FeedItem) throws
    func deleteAll() throws
    func update(_ item: FeedItem) throws
    func search(query: String) throws -> [FeedItem]
    func migrate(from version: Int) throws
    func backup() throws
    func restore(from backup: URL) throws
}

// ❌ Simple cache only needs save/load but must implement everything
class SimpleFeedCache: FeedDataStore {
    func save(_ items: [FeedItem]) throws { ... }
    func load() throws -> [FeedItem] { ... }
    
    // ❌ Forced to implement unused methods
    func delete(_ item: FeedItem) throws { fatalError("Not supported") }
    func deleteAll() throws { fatalError("Not supported") }
    func update(_ item: FeedItem) throws { fatalError("Not supported") }
    func search(query: String) throws -> [FeedItem] { fatalError("Not supported") }
    func migrate(from version: Int) throws { fatalError("Not supported") }
    func backup() throws { fatalError("Not supported") }
    func restore(from backup: URL) throws { fatalError("Not supported") }
}
```

**Problems**:
- Clients forced to implement methods they don't need
- Unclear what interface actually provides
- High coupling

### Solutions ✅

#### Solution: Split into Focused Interfaces

```swift
// ✅ Focused interfaces
protocol FeedStore {
    func save(_ items: [FeedItem]) throws
    func load() throws -> [FeedItem]
}

protocol FeedDeleter {
    func delete(_ item: FeedItem) throws
    func deleteAll() throws
}

protocol FeedUpdater {
    func update(_ item: FeedItem) throws
}

protocol FeedSearcher {
    func search(query: String) throws -> [FeedItem]
}

// Clients only depend on what they need
class SimpleFeedCache: FeedStore {
    func save(_ items: [FeedItem]) throws { ... }
    func load() throws -> [FeedItem] { ... }
}

// Advanced cache implements multiple interfaces
class AdvancedFeedCache: FeedStore, FeedDeleter, FeedUpdater {
    func save(_ items: [FeedItem]) throws { ... }
    func load() throws -> [FeedItem] { ... }
    func delete(_ item: FeedItem) throws { ... }
    func deleteAll() throws { ... }
    func update(_ item: FeedItem) throws { ... }
}
```

### Role Interfaces Pattern

```swift
// Different clients need different capabilities
protocol FeedCacheReader {
    func load() throws -> [FeedItem]
}

protocol FeedCacheWriter {
    func save(_ items: [FeedItem]) throws
}

// Implementation provides both
class FeedCache: FeedCacheReader, FeedCacheWriter {
    func load() throws -> [FeedItem] { ... }
    func save(_ items: [FeedItem]) throws { ... }
}

// Use case only needs reading
class LoadFeedUseCase {
    private let cache: FeedCacheReader  // Only depends on reading
    
    init(cache: FeedCacheReader) {
        self.cache = cache
    }
}

// Different use case only needs writing
class CacheFeedUseCase {
    private let cache: FeedCacheWriter  // Only depends on writing
    
    init(cache: FeedCacheWriter) {
        self.cache = cache
    }
}
```

### ISP Checklist

- [ ] Interfaces are focused and cohesive
- [ ] Clients only depend on methods they use
- [ ] No "Not Implemented" or "Not Supported" methods
- [ ] Interface names clearly describe purpose
- [ ] Prefer multiple small interfaces over one large interface

---

## D - Dependency Inversion Principle (DIP)

> "Depend on abstractions, not concretions"

### Definition

1. High-level modules should not depend on low-level modules. Both should depend on abstractions.
2. Abstractions should not depend on details. Details should depend on abstractions.

### Why It Matters

- Reduces coupling
- Enables testability
- Allows flexibility
- Supports parallel development

### Common Violations ❌

#### Violation 1: Direct Dependency on Concrete Class

```swift
// ❌ High-level module depends on low-level concrete class
class FeedViewController: UIViewController {
    private let loader = RemoteFeedLoader()  // Concrete dependency
    
    func loadFeed() {
        loader.load { result in
            // Handle result
        }
    }
}
```

**Problems**:
- Cannot test without making real network requests
- Cannot swap implementations
- Tight coupling to RemoteFeedLoader

#### Violation 2: Business Logic Depending on Framework

```swift
// ❌ Business logic depends on UIKit
class FeedImageLoader {
    func load(from url: URL) -> UIImage? {
        let data = try? Data(contentsOf: url)
        return data.flatMap { UIImage(data: $0) }
    }
}
```

**Problems**:
- Business logic coupled to UI framework
- Cannot test on non-iOS platforms
- Cannot reuse in different contexts

### Solutions ✅

#### Solution 1: Depend on Abstraction

```swift
// ✅ Define abstraction
protocol FeedLoader {
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void)
}

// High-level module depends on abstraction
class FeedViewController: UIViewController {
    private let loader: FeedLoader  // Dependency on abstraction
    
    init(loader: FeedLoader) {
        self.loader = loader
        super.init(nibName: nil, bundle: nil)
    }
    
    func loadFeed() {
        loader.load { result in
            // Handle result
        }
    }
}

// Low-level module implements abstraction
class RemoteFeedLoader: FeedLoader {
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        // Network loading logic
    }
}

// Composition root wires them together
let loader = RemoteFeedLoader()
let viewController = FeedViewController(loader: loader)
```

#### Solution 2: Framework-Independent Business Logic

```swift
// ✅ Framework-independent abstraction
protocol ImageDataLoader {
    func load(from url: URL, completion: @escaping (Result<Data, Error>) -> Void)
}

// Business logic depends on abstraction
class FeedImageDataLoader {
    private let client: HTTPClient
    
    func load(from url: URL, completion: @escaping (Result<Data, Error>) -> Void) {
        client.get(from: url) { result in
            completion(result.mapError { $0 as Error })
        }
    }
}

// Adapter handles framework-specific conversion
class ImageDataToUIImageAdapter {
    private let loader: ImageDataLoader
    
    func loadImage(from url: URL, completion: @escaping (UIImage?) -> Void) {
        loader.load(from: url) { result in
            let image = try? result.get().flatMap(UIImage.init)
            completion(image)
        }
    }
}
```

### Dependency Injection Patterns

#### Constructor Injection (Recommended)

```swift
class LoadFeedUseCase {
    private let loader: FeedLoader
    private let cache: FeedCache
    
    // ✅ Dependencies injected through initializer
    init(loader: FeedLoader, cache: FeedCache) {
        self.loader = loader
        self.cache = cache
    }
}
```

#### Property Injection (Use Sparingly)

```swift
class FeedViewController {
    var loader: FeedLoader!  // Set after initialization
    
    func viewDidLoad() {
        super.viewDidLoad()
        loader.load { ... }
    }
}
```

**⚠️ Warning**: Makes dependencies optional and less explicit.

### DIP Checklist

- [ ] High-level modules depend on abstractions
- [ ] Low-level modules implement abstractions
- [ ] Abstractions don't depend on implementation details
- [ ] Dependencies injected, not instantiated
- [ ] Business logic is framework-independent
- [ ] Composition root wires dependencies

---

## Applying SOLID Together

All SOLID principles work together to create maintainable architecture:

### Example: Feed Loading Feature

```swift
// S - Single Responsibility
// Each class has one reason to change

// Domain - Business Rules
protocol FeedLoader {
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void)
}

struct FeedItem: Equatable {
    let id: UUID
    let description: String?
    let location: String?
    let imageURL: URL
}

// O - Open/Closed
// Can add new loaders without modifying existing code

class RemoteFeedLoader: FeedLoader {
    private let client: HTTPClient
    private let url: URL
    
    init(client: HTTPClient, url: URL) {
        self.client = client
        self.url = url
    }
    
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        client.get(from: url) { result in
            completion(result
                .flatMap { FeedItemsMapper.map($0.data, from: $0.response) }
                .mapError { $0 as Error }
            )
        }
    }
}

class LocalFeedLoader: FeedLoader {
    private let store: FeedStore
    
    init(store: FeedStore) {
        self.store = store
    }
    
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        store.retrieve { result in
            completion(result
                .map { $0?.feed ?? [] }
                .mapError { $0 as Error }
            )
        }
    }
}

// L - Liskov Substitution
// Both loaders can be substituted without breaking behavior

class FeedViewController {
    private let loader: FeedLoader  // Works with any FeedLoader
    
    func loadFeed() {
        loader.load { result in
            // Works correctly with RemoteFeedLoader or LocalFeedLoader
        }
    }
}

// I - Interface Segregation
// Focused interfaces for different concerns

protocol FeedStore {
    func retrieve(completion: @escaping (Result<CachedFeed?, Error>) -> Void)
}

protocol FeedCache {
    func save(_ items: [FeedItem], completion: @escaping (Error?) -> Void)
}

// Implementation can provide both if needed
class CoreDataFeedStore: FeedStore, FeedCache {
    func retrieve(completion: @escaping (Result<CachedFeed?, Error>) -> Void) { ... }
    func save(_ items: [FeedItem], completion: @escaping (Error?) -> Void) { ... }
}

// D - Dependency Inversion
// High-level (ViewController) depends on abstraction (FeedLoader)
// Low-level (RemoteFeedLoader) implements abstraction

// Composition Root
let client = URLSessionHTTPClient()
let remoteLoader = RemoteFeedLoader(client: client, url: feedURL)
let viewController = FeedViewController(loader: remoteLoader)

// Can easily swap to local loader for testing
let store = CoreDataFeedStore()
let localLoader = LocalFeedLoader(store: store)
let testViewController = FeedViewController(loader: localLoader)
```

---

## Anti-Patterns to Avoid

### 1. The God Object

```swift
// ❌ Violates SRP, OCP, ISP
class ApplicationManager {
    func handleNetworking() { ... }
    func manageDatabase() { ... }
    func updateUI() { ... }
    func processBusinessLogic() { ... }
    func handleAuthentication() { ... }
    func manageCache() { ... }
}
```

### 2. Tight Coupling

```swift
// ❌ Violates DIP
class ViewController {
    let networkManager = NetworkManager()
    let databaseManager = DatabaseManager()
    let cacheManager = CacheManager()
}
```

### 3. Leaky Abstractions

```swift
// ❌ Abstraction exposes implementation details
protocol DataStore {
    func saveToCoreData(_ entity: NSManagedObject)  // Leaks CoreData
    func fetchWithPredicate(_ predicate: NSPredicate) -> [NSManagedObject]
}
```

### 4. Interface Pollution

```swift
// ❌ Violates ISP
protocol MegaInterface {
    func method1()
    func method2()
    // ... 50 more methods
}
```

---

## SOLID in Testing

SOLID principles make code testable:

```swift
// SRP - Easy to test one thing
class LoadFeedUseCaseTests: XCTestCase {
    func test_load_deliversItemsOnSuccess() {
        let (sut, loader) = makeSUT()
        
        expect(sut, toCompleteWith: .success([]), when: {
            loader.complete(with: [])
        })
    }
}

// OCP - Easy to extend with test doubles
class LoaderSpy: FeedLoader {
    private(set) var messages = [Message]()
    
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void) {
        messages.append(.load(completion))
    }
    
    func complete(with items: [FeedItem], at index: Int = 0) {
        messages[index].completion(.success(items))
    }
}

// DIP - Easy to inject test doubles
func makeSUT() -> (sut: LoadFeedUseCase, loader: LoaderSpy) {
    let loader = LoaderSpy()
    let sut = LoadFeedUseCase(loader: loader)
    return (sut, loader)
}
```

---

## Quick Reference Card

| Principle | Question to Ask | Red Flag |
|-----------|----------------|----------|
| **SRP** | How many reasons to change? | Class with "and" in description |
| **OCP** | Can I add features without modifying? | if/else or switch for types |
| **LSP** | Can I substitute safely? | Type checking or casting |
| **ISP** | Am I forced to implement unused methods? | NotImplemented errors |
| **DIP** | Do I depend on abstractions? | new keyword in business logic |

---

## Further Reading

- Clean Code by Robert C. Martin
- Agile Software Development by Robert C. Martin
- Design Patterns by Gang of Four
- Essential Developer Resources: https://www.essentialdeveloper.com/
