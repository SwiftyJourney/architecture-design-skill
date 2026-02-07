# Command-Query Separation (CQS) Principle

A design principle that separates operations into two distinct categories: Commands (modify state) and Queries (return data).

---

## The Principle

> "A method should either change state of an object (Command), or return a result (Query), but not both."
> — Bertrand Meyer

> "A Query should only return a result and should not have side-effects (does not change the observable state of the system). A Command changes the state of a system (side-effects) but does not return a value."
> — Essential Developer

### Commands
- **Modify state** (create, update, delete)
- **Return void** (or acknowledgment of success/failure)
- **Have side effects**

### Queries
- **Return data** (read)
- **Don't modify state**
- **No side effects** (idempotent - calling multiple times produces same result)

---

## The Problem (Without CQS)

```swift
// ❌ Violates CQS - method both returns data AND modifies state
class FeedCache {
    private var cache: [FeedItem]?
    
    func getAndRefresh() -> [FeedItem]? {
        let items = cache  // Query - reading
        cache = nil        // Command - modifying state
        return items       // Query - returning
    }
}
```

**Problems**:
- Confusing - does it modify state or not?
- Calling it multiple times has different results
- Hard to test - side effects hidden
- Violates Single Responsibility Principle

---

## The Solution (With CQS)

```swift
// ✅ Follows CQS - separate commands and queries
class FeedCache {
    private var cache: [FeedItem]?
    
    // Query - returns data, no side effects
    func retrieve() -> [FeedItem]? {
        return cache
    }
    
    // Command - modifies state, returns void
    func delete() {
        cache = nil
    }
    
    // Command - modifies state, returns void
    func save(_ items: [FeedItem]) {
        cache = items
    }
}

// Usage - intent is clear
let items = cache.retrieve()  // Read
cache.delete()                // Modify
cache.save(newItems)          // Modify
```

**Benefits**:
- Clear intent - reading vs modifying
- Predictable - queries always return same result
- Easy to test - no hidden side effects
- Composable - can chain queries safely

---

## Essential Feed's Cache Implementation

### FeedStore Protocol (Following CQS)

```swift
protocol FeedStore {
    typealias DeletionResult = Result<Void, Error>
    typealias InsertionResult = Result<Void, Error>
    typealias RetrievalResult = Result<CachedFeed?, Error>
    
    // Command - deletes cached feed
    func deleteCachedFeed(completion: @escaping (DeletionResult) -> Void)
    
    // Command - inserts feed into cache
    func insert(_ feed: [LocalFeedImage], timestamp: Date, completion: @escaping (InsertionResult) -> Void)
    
    // Query - retrieves cached feed
    func retrieve(completion: @escaping (RetrievalResult) -> Void)
}
```

**Key Points**:
- `deleteCachedFeed` - **Command** (returns `Void`)
- `insert` - **Command** (returns `Void`)
- `retrieve` - **Query** (returns `CachedFeed?`)
- Commands use completion handlers for async operations
- Queries never modify state

### LocalFeedLoader Using CQS

```swift
public final class LocalFeedLoader {
    private let store: FeedStore
    private let currentDate: () -> Date
    
    public init(store: FeedStore, currentDate: @escaping () -> Date) {
        self.store = store
        self.currentDate = currentDate
    }
}

// MARK: - FeedCache (Commands)

extension LocalFeedLoader: FeedCache {
    public typealias SaveResult = Result<Void, Error>
    
    // Command - saves feed (modifies state)
    public func save(_ feed: [FeedImage], completion: @escaping (SaveResult) -> Void) {
        store.deleteCachedFeed { [weak self] deletionResult in
            guard let self = self else { return }
            
            switch deletionResult {
            case .success:
                self.cache(feed, with: completion)
                
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }
    
    private func cache(_ feed: [FeedImage], with completion: @escaping (SaveResult) -> Void) {
        store.insert(feed.toLocal(), timestamp: self.currentDate()) { [weak self] insertionResult in
            guard self != nil else { return }
            completion(insertionResult)
        }
    }
}

// MARK: - FeedLoader (Query)

extension LocalFeedLoader: FeedLoader {
    public typealias LoadResult = Result<[FeedImage], Error>
    
    // Query - loads feed (doesn't modify state)
    public func load(completion: @escaping (LoadResult) -> Void) {
        store.retrieve { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case let .failure(error):
                completion(.failure(error))
                
            case let .success(.some(cache)) where FeedCachePolicy.validate(cache.timestamp, against: self.currentDate()):
                completion(.success(cache.feed.toModels()))
                
            case .success:
                completion(.success([]))
            }
        }
    }
}
```

**Key Observations**:
1. **`save()` is a Command** - Modifies cache state, returns `Void`
2. **`load()` is a Query** - Reads cache, doesn't modify it
3. **Separate protocols** - `FeedCache` for commands, `FeedLoader` for queries
4. **Clear separation** - Easy to understand what each method does

---

## Cache Validation (Identifying CQS Violation)

### The Problem - Hidden Side Effect in Query

In the Essential Feed case study, the initial implementation of cache loading included validation as a side effect:

```swift
// ❌ Violates CQS - Query with side effects
public func load(completion: @escaping (LoadResult) -> Void) {
    store.retrieve { [weak self] result in
        guard let self = self else { return }
        
        switch result {
        case let .success(.some(cache)) where FeedCachePolicy.validate(cache.timestamp, against: self.currentDate()):
            completion(.success(cache.feed.toModels()))
            
        case let .success(.some(cache)):
            // ❌ Side effect - deleting cache as part of loading!
            self.store.deleteCachedFeed { _ in }
            completion(.success([]))
            
        case .success:
            completion(.success([]))
            
        case let .failure(error):
            self.store.deleteCachedFeed { _ in }
            completion(.failure(error))
        }
    }
}
```

**Problem Identified**:
- `load()` looks like a **Query** (it returns data)
- But it has **side effects** (deletes cache) - making it also a **Command**
- Violates CQS - does too much
- Side effect is hidden - not obvious from method signature

### The Solution - Separate Use Cases

As explained by Essential Developer:

> "By following the principle, we identified that the action of loading the feed from cache is a Query, and ideally should have no side-effects. However, deleting the cache as part of the load alters the state of the system (which is a side-effect!). Thus, we separate loading and validation into two use cases, implemented in distinct methods: load() and validateCache()."

```swift
// ✅ Query - no side effects
public func load(completion: @escaping (LoadResult) -> Void) {
    store.retrieve { [weak self] result in
        guard let self = self else { return }
        
        switch result {
        case let .success(.some(cache)) where FeedCachePolicy.validate(cache.timestamp, against: self.currentDate()):
            completion(.success(cache.feed.toModels()))
            
        case .success:
            completion(.success([]))
            
        case let .failure(error):
            completion(.failure(error))
        }
    }
}

// ✅ Command - modifies state (deletes invalid cache)
public func validateCache() {
    store.retrieve { [weak self] result in
        guard let self = self else { return }
        
        switch result {
        case .failure:
            self.store.deleteCachedFeed { _ in }
            
        case let .success(.some(cache)) where !FeedCachePolicy.validate(cache.timestamp, against: self.currentDate()):
            self.store.deleteCachedFeed { _ in }
            
        case .success:
            break
        }
    }
}
```

### Benefits of Separation

> "A great benefit of separating the functionality is that now we can [re]use both actions in distinct contexts. For example, we can schedule cache validation every 10 minutes or every time the app goes to (or gets back from) the background (instead of only performing it when the user requests to see the feed)."

**Reusability**:
```swift
// Different contexts can now use each operation independently

// Context 1: User requests to see feed
func viewDidLoad() {
    loader.load { result in
        self.display(result)
    }
}

// Context 2: App enters background - validate cache
func sceneDidEnterBackground() {
    loader.validateCache()
}

// Context 3: Scheduled validation every 10 minutes
Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
    loader.validateCache()
}
```

### Should We Keep Old Tests After Separation?

From Essential Developer:

> "If a new functionality makes the old one irrelevant, we don't have to keep old tests (or even the old functionality!). However, in our case, the load method is still relevant to the application. What we did instead was to replace the old load method tests, regarding deletion side-effects, with new assertions to guarantee there are no side-effects."

**Before Separation**:
```swift
func test_load_deletesInvalidCacheOnRetrievalError() {
    // Test that load deletes cache on error
}
```

**After Separation**:
```swift
func test_load_hasNoSideEffectsOnRetrievalError() {
    let (sut, store) = makeSUT()
    
    sut.load { _ in }
    store.completeRetrieval(with: anyNSError())
    
    // ✅ Verify NO deletion happens
    XCTAssertEqual(store.receivedMessages, [.retrieve])
}

func test_validateCache_deletesCacheOnRetrievalError() {
    let (sut, store) = makeSUT()
    
    sut.validateCache()
    store.completeRetrieval(with: anyNSError())
    
    XCTAssertEqual(store.receivedMessages, [.retrieve, .deleteCachedFeed])
}
```

> "In our opinion, it still makes sense to keep the tests, as it also serves as documentation about the intention: there should never be side effects in the load method."

---

## CQS in Testing

### Commands Should Be Tested for Side Effects

```swift
func test_save_requestsCacheDeletion() {
    let (sut, store) = makeSUT()
    
    sut.save(uniqueImageFeed().models) { _ in }
    
    // Verify side effect - cache deletion was called
    XCTAssertEqual(store.receivedMessages, [.deleteCachedFeed])
}

func test_save_requestsNewCacheInsertionWithTimestampOnSuccessfulDeletion() {
    let timestamp = Date()
    let feed = uniqueImageFeed()
    let (sut, store) = makeSUT(currentDate: { timestamp })
    
    sut.save(feed.models) { _ in }
    store.completeDeletion(with: .success(()))
    
    // Verify side effect - insertion was called
    XCTAssertEqual(store.receivedMessages, [.deleteCachedFeed, .insert(feed.local, timestamp)])
}
```

### Queries Should Be Tested for Return Values

```swift
func test_load_deliversCachedImagesOnLessThanSevenDaysOldCache() {
    let feed = uniqueImageFeed()
    let fixedCurrentDate = Date()
    let lessThanSevenDaysOldTimestamp = fixedCurrentDate.adding(days: -7).adding(seconds: 1)
    let (sut, store) = makeSUT(currentDate: { fixedCurrentDate })
    
    expect(sut, toCompleteWith: .success(feed.models), when: {
        store.completeRetrieval(with: feed.local, timestamp: lessThanSevenDaysOldTimestamp)
    })
}

func test_load_deliversNoImagesOnSevenDaysOldCache() {
    let feed = uniqueImageFeed()
    let fixedCurrentDate = Date()
    let sevenDaysOldTimestamp = fixedCurrentDate.adding(days: -7)
    let (sut, store) = makeSUT(currentDate: { fixedCurrentDate })
    
    expect(sut, toCompleteWith: .success([]), when: {
        store.completeRetrieval(with: feed.local, timestamp: sevenDaysOldTimestamp)
    })
}
```

**Key Points**:
- Commands tested by verifying **side effects** (what changed)
- Queries tested by verifying **return values** (what was returned)
- No overlap - clear separation

---

## Benefits of CQS

### 1. Predictability

```swift
// Query - always returns same result for same state
let items1 = cache.retrieve()
let items2 = cache.retrieve()
assert(items1 == items2)  // ✅ Always true

// Command - modifies state
cache.save(newItems)
let items3 = cache.retrieve()
assert(items3 == newItems)  // ✅ State changed
```

### 2. Composability

```swift
// Can chain queries safely
let cachedItems = cache.retrieve()
let validItems = cachedItems?.filter { isValid($0) }
let sortedItems = validItems?.sorted()

// Still no side effects - cache unchanged
let sameItems = cache.retrieve()
assert(cachedItems == sameItems)  // ✅ Still the same
```

### 3. Testability

```swift
// Test queries - verify return values
func test_retrieve_deliversCachedItems() {
    let items = [makeItem()]
    cache.save(items)
    
    let retrieved = cache.retrieve()
    
    XCTAssertEqual(retrieved, items)
}

// Test commands - verify side effects
func test_delete_emptiesCache() {
    cache.save([makeItem()])
    
    cache.delete()
    
    XCTAssertNil(cache.retrieve())
}
```

### 4. Thread Safety

```swift
// Queries are thread-safe (read-only)
DispatchQueue.concurrentPerform(iterations: 100) { _ in
    let items = cache.retrieve()  // Safe - no race conditions
}

// Commands need synchronization
let queue = DispatchQueue(label: "cache")
queue.async {
    cache.save(items)  // Synchronized writes
}
```

---

## Common Violations

### ❌ Violation 1: Query with Side Effects

```swift
// Bad - query modifies state
func pop() -> FeedItem? {
    guard let item = items.first else { return nil }
    items.removeFirst()  // ❌ Side effect in query
    return item
}

// Good - separate query and command
func peek() -> FeedItem? {
    return items.first  // ✅ Query - no side effects
}

func removeFirst() {
    items.removeFirst()  // ✅ Command - modifies state
}
```

### ❌ Violation 2: Command Returning Data

```swift
// Bad - command returns data
func save(_ items: [FeedItem]) -> [FeedItem] {
    cache = items       // Command - modifies state
    return cache        // ❌ Also returns data
}

// Good - separate operations
func save(_ items: [FeedItem]) {
    cache = items       // ✅ Command only
}

func retrieve() -> [FeedItem]? {
    return cache        // ✅ Query only
}
```

### ❌ Violation 3: Confusing Naming

```swift
// Bad - looks like query but is command
func getItems() -> [FeedItem] {
    let items = cache
    cache = []          // ❌ Side effect!
    return items
}

// Good - clear naming
func retrieveAndClear() -> [FeedItem] {  // Name indicates side effect
    let items = retrieve()
    clear()
    return items
}

// Better - separate completely
func retrieve() -> [FeedItem] { ... }  // Query
func clear() { ... }                   // Command
```

---

## CQS in CoreData Implementation

```swift
final class CoreDataFeedStore: FeedStore {
    private let container: NSPersistentContainer
    
    // Query - reads data (no side effects)
    func retrieve(completion: @escaping (RetrievalResult) -> Void) {
        performAsync { context in
            do {
                if let cache = try ManagedCache.find(in: context) {
                    completion(.success(CachedFeed(feed: cache.localFeed, timestamp: cache.timestamp)))
                } else {
                    completion(.success(nil))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    // Command - deletes data (modifies state)
    func deleteCachedFeed(completion: @escaping (DeletionResult) -> Void) {
        performAsync { context in
            do {
                try ManagedCache.find(in: context).map(context.delete)
                try context.save()
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    // Command - inserts data (modifies state)
    func insert(_ feed: [LocalFeedImage], timestamp: Date, completion: @escaping (InsertionResult) -> Void) {
        performAsync { context in
            do {
                let managedCache = try ManagedCache.newUniqueInstance(in: context)
                managedCache.timestamp = timestamp
                managedCache.feed = ManagedFeedImage.images(from: feed, in: context)
                
                try context.save()
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
```

**Key Points**:
- `retrieve()` only reads from CoreData
- `deleteCachedFeed()` and `insert()` modify CoreData
- Clear separation makes code easy to understand and test

---

## CQRS (Command Query Responsibility Segregation)

CQS taken to architectural level - separate models for read and write:

```swift
// Write model (Commands)
protocol FeedCache {
    func save(_ feed: [FeedItem], completion: @escaping (Error?) -> Void)
    func delete(completion: @escaping (Error?) -> Void)
}

// Read model (Queries)
protocol FeedLoader {
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void)
}

// Different implementations possible
class WriteFeedStore: FeedCache { ... }   // Optimized for writes
class ReadFeedStore: FeedLoader { ... }   // Optimized for reads

// Or same implementation with different protocols
class LocalFeedStore: FeedCache, FeedLoader { ... }
```

---

## Application-Specific vs Application-Agnostic Logic

### Two Types of Business Logic

From Essential Developer:

> "Use Cases describe application-specific logic. But Use Cases derive from business requirements, so they inherently describe business logic. Thus, Use Cases describe application-specific business logic!"

**1. Application-Specific Business Logic (Use Cases)**:
- Implemented by Controllers (Interactors/Service types)
- Coordinates domain models and infrastructure
- Handles application interactions (async operations, boundaries)
- Example: `LocalFeedLoader`, `RemoteFeedLoader`

**2. Application-Agnostic Business Logic (Domain Models)**:
- Core business rules and policies
- Application-independent
- Reusable across Use Cases and applications
- Example: `FeedCachePolicy`, `FeedItem`

### Identifying Core Business Logic

> "Inside Use Case requirements, you can also find application-agnostic logic. This kind of logic is application-independent, also known as core business logic. Core business logic is often reused across Use Cases within the same application and even across other applications."

**Example - Cache Validation**:

**Before (Mixed in Use Case)**:
```swift
// ❌ Application-specific logic mixed with core business rules
class LocalFeedLoader {
    func load(completion: @escaping (LoadResult) -> Void) {
        store.retrieve { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case let .success(.some(cache)):
                // ❌ Cache validation logic buried in Use Case
                let sevenDaysInSeconds: TimeInterval = 7 * 24 * 60 * 60
                let cacheAge = self.currentDate().timeIntervalSince(cache.timestamp)
                
                if cacheAge < sevenDaysInSeconds {
                    completion(.success(cache.feed))
                } else {
                    completion(.success([]))
                }
            // ...
            }
        }
    }
}
```

**After (Separated into Domain Model)**:
```swift
// ✅ Core business rule extracted to Domain Model
final class FeedCachePolicy {
    private static let calendar = Calendar(identifier: .gregorian)
    private static var maxCacheAgeInDays: Int { 7 }
    
    static func validate(_ timestamp: Date, against date: Date) -> Bool {
        guard let maxCacheAge = calendar.date(byAdding: .day, value: maxCacheAgeInDays, to: timestamp) else {
            return false
        }
        return date < maxCacheAge
    }
}

// ✅ Use Case uses Domain Model for validation
class LocalFeedLoader {
    func load(completion: @escaping (LoadResult) -> Void) {
        store.retrieve { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case let .success(.some(cache)) where FeedCachePolicy.validate(cache.timestamp, against: self.currentDate()):
                completion(.success(cache.feed.toModels()))
            // ...
            }
        }
    }
}
```

### Controllers vs Domain Models

From Essential Developer:

> "The LocalFeedLoader collaborates with other types to solve Use Case requirements. It is a Controller type (aka Interactor/Model Controller) and should encapsulate application-specific logic only. When needed, it communicates with Domain Models to perform core business logic."

**Controllers (Application-Specific)**:
- `LocalFeedLoader` - Coordinates cache operations
- `RemoteFeedLoader` - Coordinates network operations
- Handle async operations
- Depend on abstractions (protocols)

**Domain Models (Application-Agnostic)**:
- `FeedCachePolicy` - Validation rules
- `FeedItem` - Core entity
- Pure logic, no side effects
- No dependencies on frameworks

### Side-Effect Free Core Business Rules

From Essential Developer:

> "Side-effect free logic seems more popular now with FP getting more attention, but such a concept has been around for a long time in OO land too. Keeping our core domain free from side-effects makes it extremely easy to build, maintain and test."

**Before (Impure - with side effects)**:
```swift
// ❌ Impure - depends on closure that yields non-deterministic Date
class FeedCachePolicy {
    private let currentDate: () -> Date  // Side effect!
    
    init(currentDate: @escaping () -> Date) {
        self.currentDate = currentDate
    }
    
    func validate(_ timestamp: Date) -> Bool {
        let date = currentDate()  // Different result each call!
        // Validation logic
    }
}
```

**After (Pure - no side effects)**:
```swift
// ✅ Pure function - deterministic
class FeedCachePolicy {
    static func validate(_ timestamp: Date, against date: Date) -> Bool {
        // Same input always produces same output
        guard let maxCacheAge = calendar.date(byAdding: .day, value: 7, to: timestamp) else {
            return false
        }
        return date < maxCacheAge
    }
}
```

**Benefits**:
- Deterministic - same input = same output
- Easy to test - no mocking needed
- No hidden dependencies
- Fully reusable

> "To remove side-effects in this case, we passed an actual Date value (immutable data), instead of passing an impure function that yields a non-deterministic Date. We shifted from initializer injection init(currentDate: () -> Date) to method injection with func validate(_ timestamp: Date, against date: Date) -> Bool where we pass a date value that can never change (immutable)."

### Functional Core, Imperative Shell

From Essential Developer:

> "Side-effects (e.g., I/O, database writes, UI updates…) do need to happen, but not at the core of the application. The side-effects can happen at the boundary of the system, in the Infrastructure implementations. This separation is also known as Functional Core, Imperative Shell."

```
┌─────────────────────────────────────────┐
│      Imperative Shell (Controllers)     │
│   - Async operations                    │
│   - Side effects (I/O, DB, Network)    │
│   - Coordinates infrastructure          │
│                                         │
│   ┌─────────────────────────────────┐  │
│   │   Functional Core (Domain)      │  │
│   │ - Pure functions                │  │
│   │ - No side effects               │  │
│   │ - Business rules                │  │
│   │ - Deterministic                 │  │
│   └─────────────────────────────────┘  │
│                                         │
└─────────────────────────────────────────┘
```

**Example**:
```swift
// Imperative Shell (Controller)
class LocalFeedLoader {
    private let store: FeedStore
    private let currentDate: () -> Date  // Side effect here is OK
    
    func load(completion: @escaping (LoadResult) -> Void) {
        // Side effects: async I/O
        store.retrieve { [weak self] result in
            guard let self = self else { return }
            
            let date = self.currentDate()  // Get current date (side effect)
            
            // Functional Core: pure validation
            switch result {
            case let .success(.some(cache)) where FeedCachePolicy.validate(cache.timestamp, against: date):
                completion(.success(cache.feed.toModels()))
            // ...
            }
        }
    }
}

// Functional Core (Domain)
final class FeedCachePolicy {
    // Pure function - no side effects
    static func validate(_ timestamp: Date, against date: Date) -> Bool {
        guard let maxCacheAge = calendar.date(byAdding: .day, value: 7, to: timestamp) else {
            return false
        }
        return date < maxCacheAge
    }
}
```

### Single Source of Truth

From Essential Developer:

> "To reduce the cost of change, duplication and risk of making mistakes, we strive to create reusable components while hiding implementation details (from production code and tests) as much as we can. This includes constant values such as 7 days max age in the cache policy."

**Problem - Duplication**:
```swift
// ❌ Magic number scattered everywhere
func test_load_deliversCachedImagesOnLessThanSevenDaysOldCache()
func test_load_deliversNoImagesOnSevenDaysOldCache()
func test_load_deliversNoImagesOnMoreThanSevenDaysOldCache()
```

**Solution - Centralized**:
```swift
// ✅ Single source of truth
private extension Date {
    func adding(days: Int) -> Date {
        return Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: self)!
    }
    
    var minusFeedCacheMaxAge: Date {
        return adding(days: -7)  // Only place where 7 is defined
    }
}

// Usage in tests
func test_load_deliversCachedImagesOnLessThanMaxCacheAge() {
    let lessThanMaxAge = fixedCurrentDate.minusFeedCacheMaxAge.adding(seconds: 1)
    // ...
}

func test_load_deliversNoImagesOnMaxCacheAge() {
    let maxAge = fixedCurrentDate.minusFeedCacheMaxAge
    // ...
}
```

> "By doing so, we are free to safely and easily change the max cache age value from a centralized point on the system without having to replace other parts (clients)."

---

## Entities vs Value Objects

From Essential Developer:

> "Entities are models with intrinsic identity. Value Objects are models with no intrinsic identity. Both can hold business rules."

### Value Objects (No Identity)

```swift
// Value Object - compared by value
struct FeedItem: Equatable {
    let id: UUID
    let description: String?
    let location: String?
    let imageURL: URL
}

// Two FeedItems are equal if all values match
let item1 = FeedItem(id: uuid, description: "A", location: "B", imageURL: url)
let item2 = FeedItem(id: uuid, description: "A", location: "B", imageURL: url)
assert(item1 == item2)  // ✅ Equal by value
```

### Entities (With Identity)

```swift
// Entity - compared by ID
struct Money: Equatable {
    let id: MoneyID  // Identity
    let amount: Decimal
    let currency: Currency
    
    static func ==(lhs: Money, rhs: Money) -> Bool {
        return lhs.id == rhs.id  // Compare by identity only
    }
}

// Two Money instances with same ID are identical, even if values differ
let money1 = Money(id: MoneyID("123"), amount: 100, currency: .USD)
let money2 = Money(id: MoneyID("123"), amount: 200, currency: .EUR)
assert(money1 == money2)  // ✅ Same identity
```

### Value Types in Swift

From Essential Developer:

> "In Swift, we don't need objects (class instances) to represent types. So Value Object is often called Value Type or 'just data' in Swift. Entities and Value Types can be represented by classes, structs or enums."

**Stateless Value Types**:
```swift
// If a Value Type holds no state, it can be replaced by static or free functions
final class FeedCachePolicy {
    private init() {}  // Can't instantiate
    
    static func validate(_ timestamp: Date, against date: Date) -> Bool {
        // Pure function - no instance needed
    }
}

// Or as free function
func validateFeedCache(_ timestamp: Date, against date: Date) -> Bool {
    // ...
}
```

### When Identity Matters

From Essential Developer:

> "If a model has an identity or not, it depends on your domain. For example, a Money model may be a Value Object in some systems, representing a simple monetary amount (data) with its respective currency (data)."

**Money as Value Object** (Most systems):
```swift
struct Money: Equatable {
    let amount: Decimal
    let currency: Currency
}
// Compared by value - $100 USD == $100 USD
```

**Money as Entity** (Money printing/tracking system):
```swift
struct Money: Equatable {
    let id: MoneyID  // Serial number on bill
    let amount: Decimal
    let currency: Currency
}
// Compared by ID - Bill #123 != Bill #456, even if both are $100
```

### Cross-System Communication

From Essential Developer:

> "If to perform business logic, you need to talk to external systems (which holds the business rules), then it's not suitable to add this cross-system communication logic into an Entity or a Value Object. Instead, create a Controller (aka Interactor/Service...) type to coordinate the communication with the external system."

**❌ Wrong - External communication in Entity**:
```swift
struct FeedItem {
    func validate() async throws -> Bool {
        // ❌ Talking to external validation service
        let result = try await validationService.validate(self)
        return result.isValid
    }
}
```

**✅ Right - Controller coordinates**:
```swift
// Value Object - pure data
struct FeedItem {
    let id: UUID
    let description: String?
}

// Controller - handles external communication
class FeedValidationService {
    func validate(_ item: FeedItem) async throws -> Bool {
        // ✅ Controller talks to external system
        let result = try await externalValidator.validate(item)
        return result.isValid
    }
}
```

---

## Checklist

- [ ] Commands modify state, return void (or Result<Void, Error>)
- [ ] Queries return data, don't modify state
- [ ] Method names reflect behavior (save vs retrieve, validate vs removeInvalid)
- [ ] No side effects in queries (verify with tests)
- [ ] Test commands for side effects (what changed)
- [ ] Test queries for return values (what was returned)
- [ ] Separate protocols for commands and queries (FeedCache vs FeedLoader)
- [ ] Extract application-agnostic logic into Domain Models
- [ ] Keep Domain Models pure (no side effects)
- [ ] Use value injection instead of closure injection for pure functions
- [ ] Single source of truth for business rules and constants
- [ ] Consider CQRS for complex domains

---

## Common Questions

### Q: Can a command return acknowledgment?

**A**: Yes, returning success/failure is acceptable:
```swift
func save(_ items: [FeedItem], completion: @escaping (Error?) -> Void)
```

### Q: What about methods that need to do both?

**A**: Split into two methods:
```swift
// Instead of:
func popAndReturn() -> Item?  // ❌ Does both

// Do:
func peek() -> Item?  // Query
func remove()         // Command

// Or compose:
let item = peek()
remove()
```

### Q: What about IDs from creation?

**A**: Acceptable to return generated ID:
```swift
func create(_ item: Item) -> UUID  // Returns generated ID
```

Or use completion:
```swift
func create(_ item: Item, completion: @escaping (UUID) -> Void)
```

---

## Further Reading

- Object-Oriented Software Construction by Bertrand Meyer
- CQRS Pattern by Martin Fowler
- Essential Developer: https://www.essentialdeveloper.com/
- Essential Feed Case Study: https://github.com/essentialdevelopercom/essential-feed-case-study
