# Command-Query Separation in Essential Feed

Real-world implementation of CQS principle in Essential Developer's Feed Case Study.

---

## FeedStore Protocol (Perfect CQS)

```swift
public protocol FeedStore {
    typealias DeletionResult = Result<Void, Error>
    typealias InsertionResult = Result<Void, Error>  
    typealias RetrievalResult = Result<CachedFeed?, Error>
    
    /// Command - Deletes cached feed
    func deleteCachedFeed(completion: @escaping (DeletionResult) -> Void)
    
    /// Command - Inserts feed with timestamp
    func insert(_ feed: [LocalFeedImage], timestamp: Date, completion: @escaping (InsertionResult) -> Void)
    
    /// Query - Retrieves cached feed
    func retrieve(completion: @escaping (RetrievalResult) -> Void)
}

public struct CachedFeed: Equatable {
    public let feed: [LocalFeedImage]
    public let timestamp: Date
    
    public init(feed: [LocalFeedImage], timestamp: Date) {
        self.feed = feed
        self.timestamp = timestamp
    }
}
```

**CQS Compliance**:
- ✅ `deleteCachedFeed` - **Command** (returns `Void`)
- ✅ `insert` - **Command** (returns `Void`)
- ✅ `retrieve` - **Query** (returns data, no side effects)

---

## LocalFeedLoader - Implementing CQS

### Save Operation (Command)

```swift
public final class LocalFeedLoader {
    private let store: FeedStore
    private let currentDate: () -> Date
    
    public init(store: FeedStore, currentDate: @escaping () -> Date) {
        self.store = store
        self.currentDate = currentDate
    }
}

extension LocalFeedLoader: FeedCache {
    public typealias SaveResult = Result<Void, Error>
    
    // Command - saves feed to cache
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
```

**Testing Commands**:
```swift
func test_save_requestsCacheDeletion() {
    let (sut, store) = makeSUT()
    
    sut.save(uniqueImageFeed().models) { _ in }
    
    XCTAssertEqual(store.receivedMessages, [.deleteCachedFeed])
}

func test_save_requestsNewCacheInsertionOnSuccessfulDeletion() {
    let timestamp = Date()
    let feed = uniqueImageFeed()
    let (sut, store) = makeSUT(currentDate: { timestamp })
    
    sut.save(feed.models) { _ in }
    store.completeDeletion(with: .success(()))
    
    XCTAssertEqual(store.receivedMessages, [
        .deleteCachedFeed,
        .insert(feed.local, timestamp)
    ])
}

func test_save_failsOnDeletionError() {
    let (sut, store) = makeSUT()
    let deletionError = anyNSError()
    
    expect(sut, toCompleteWithError: deletionError, when: {
        store.completeDeletion(with: .failure(deletionError))
    })
}
```

---

### Load Operation (Query)

```swift
extension LocalFeedLoader: FeedLoader {
    public typealias LoadResult = Result<[FeedImage], Error>
    
    // Query - loads feed from cache
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

**Testing Queries**:
```swift
func test_load_requestsCacheRetrieval() {
    let (sut, store) = makeSUT()
    
    sut.load { _ in }
    
    XCTAssertEqual(store.receivedMessages, [.retrieve])
}

func test_load_deliversCachedImagesOnLessThanSevenDaysOldCache() {
    let feed = uniqueImageFeed()
    let fixedCurrentDate = Date()
    let lessThanSevenDaysOldTimestamp = add(seconds: 1, to: add(days: -7, to: fixedCurrentDate))
    let (sut, store) = makeSUT(currentDate: { fixedCurrentDate })
    
    expect(sut, toCompleteWith: .success(feed.models), when: {
        store.completeRetrieval(with: feed.local, timestamp: lessThanSevenDaysOldTimestamp)
    })
}

func test_load_deliversNoImagesOnSevenDaysOldCache() {
    let feed = uniqueImageFeed()
    let fixedCurrentDate = Date()
    let sevenDaysOldTimestamp = add(days: -7, to: fixedCurrentDate)
    let (sut, store) = makeSUT(currentDate: { fixedCurrentDate })
    
    expect(sut, toCompleteWith: .success([]), when: {
        store.completeRetrieval(with: feed.local, timestamp: sevenDaysOldTimestamp)
    })
}
```

---

## CoreDataFeedStore Implementation

### Commands

```swift
public final class CoreDataFeedStore: FeedStore {
    private let container: NSPersistentContainer
    
    // Command - deletes cached feed
    public func deleteCachedFeed(completion: @escaping (DeletionResult) -> Void) {
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
    
    // Command - inserts new feed
    public func insert(_ feed: [LocalFeedImage], timestamp: Date, completion: @escaping (InsertionResult) -> Void) {
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

### Queries

```swift
extension CoreDataFeedStore {
    // Query - retrieves cached feed
    public func retrieve(completion: @escaping (RetrievalResult) -> Void) {
        performAsync { context in
            do {
                if let cache = try ManagedCache.find(in: context) {
                    completion(.success(CachedFeed(
                        feed: cache.localFeed,
                        timestamp: cache.timestamp
                    )))
                } else {
                    completion(.success(nil))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }
}
```

---

## Testing CQS in CoreDataFeedStore

### Testing Commands (Side Effects)

```swift
func test_retrieve_deliversEmptyOnEmptyCache() {
    let sut = makeSUT()
    
    expect(sut, toRetrieve: .success(nil))
}

func test_retrieve_hasNoSideEffectsOnEmptyCache() {
    let sut = makeSUT()
    
    expect(sut, toRetrieveTwice: .success(nil))
}

func test_retrieve_deliversFoundValuesOnNonEmptyCache() {
    let sut = makeSUT()
    let feed = uniqueImageFeed().local
    let timestamp = Date()
    
    insert((feed, timestamp), to: sut)
    
    expect(sut, toRetrieve: .success(CachedFeed(feed: feed, timestamp: timestamp)))
}

func test_retrieve_hasNoSideEffectsOnNonEmptyCache() {
    let sut = makeSUT()
    let feed = uniqueImageFeed().local
    let timestamp = Date()
    
    insert((feed, timestamp), to: sut)
    
    expect(sut, toRetrieveTwice: .success(CachedFeed(feed: feed, timestamp: timestamp)))
}
```

### Testing Queries (Return Values)

```swift
func test_insert_deliversNoErrorOnEmptyCache() {
    let sut = makeSUT()
    
    let insertionError = insert((uniqueImageFeed().local, Date()), to: sut)
    
    XCTAssertNil(insertionError, "Expected to insert cache successfully")
}

func test_insert_deliversNoErrorOnNonEmptyCache() {
    let sut = makeSUT()
    insert((uniqueImageFeed().local, Date()), to: sut)
    
    let insertionError = insert((uniqueImageFeed().local, Date()), to: sut)
    
    XCTAssertNil(insertionError, "Expected to override cache successfully")
}

func test_insert_overridesPreviouslyInsertedCacheValues() {
    let sut = makeSUT()
    insert((uniqueImageFeed().local, Date()), to: sut)
    
    let latestFeed = uniqueImageFeed().local
    let latestTimestamp = Date()
    insert((latestFeed, latestTimestamp), to: sut)
    
    expect(sut, toRetrieve: .success(CachedFeed(feed: latestFeed, timestamp: latestTimestamp)))
}
```

---

## Separation of Concerns

### Different Protocols for Different Responsibilities

```swift
// Command protocol
public protocol FeedCache {
    func save(_ feed: [FeedImage], completion: @escaping (Result<Void, Error>) -> Void)
}

// Query protocol
public protocol FeedLoader {
    func load(completion: @escaping (Result<[FeedImage], Error>) -> Void)
}

// LocalFeedLoader implements both
extension LocalFeedLoader: FeedCache { }
extension LocalFeedLoader: FeedLoader { }
```

**Benefits**:
- Clear separation of read/write concerns
- Clients only depend on what they need
- Easy to create read-only or write-only implementations

---

## Cache Validation

### Original Implementation

```swift
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

**Analysis**: This violates CQS!
- Method name suggests "Query" (validate)
- But it's actually a "Command" (deletes cache)

### Better Implementation

```swift
// Command - clear naming indicates side effect
public func removeInvalidCache(completion: @escaping (DeletionResult) -> Void) {
    store.retrieve { [weak self] result in
        guard let self = self else { return }
        
        switch result {
        case .failure:
            self.store.deleteCachedFeed(completion: completion)
            
        case let .success(.some(cache)) where !FeedCachePolicy.validate(cache.timestamp, against: self.currentDate()):
            self.store.deleteCachedFeed(completion: completion)
            
        case .success:
            completion(.success(()))
        }
    }
}
```

---

## Image Data Cache (Another Example)

### Commands

```swift
public protocol FeedImageDataStore {
    typealias InsertionResult = Result<Void, Error>
    
    func insert(_ data: Data, for url: URL, completion: @escaping (InsertionResult) -> Void)
}
```

### Queries

```swift
extension FeedImageDataStore {
    typealias RetrievalResult = Result<Data?, Error>
    
    func retrieve(dataForURL url: URL, completion: @escaping (RetrievalResult) -> Void)
}
```

### Implementation

```swift
extension CoreDataFeedStore: FeedImageDataStore {
    // Command - inserts image data
    public func insert(_ data: Data, for url: URL, completion: @escaping (InsertionResult) -> Void) {
        performAsync { context in
            do {
                let managedImage = try ManagedFeedImage.first(with: url, in: context)
                managedImage?.data = data
                
                try context.save()
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    // Query - retrieves image data
    public func retrieve(dataForURL url: URL, completion: @escaping (RetrievalResult) -> Void) {
        performAsync { context in
            do {
                if let data = try ManagedFeedImage.first(with: url, in: context)?.data {
                    completion(.success(data))
                } else {
                    completion(.success(nil))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }
}
```

---

## Key Takeaways

1. **Separate Commands and Queries** - Different methods for different purposes
2. **Commands modify state** - `save()`, `delete()`, `insert()`
3. **Queries return data** - `load()`, `retrieve()`
4. **Test Commands for side effects** - Verify state changes
5. **Test Queries for return values** - Verify correct data returned
6. **Use protocols to enforce separation** - `FeedCache` vs `FeedLoader`
7. **Name methods clearly** - `validateCache()` vs `removeInvalidCache()`
8. **Essential Feed follows CQS religiously** - Clean, testable caching layer

---

## Benefits in Essential Feed

1. **Predictable Cache Behavior**
   - `retrieve()` always returns same result for same state
   - `save()` clearly modifies cache
   
2. **Easy Testing**
   - Commands tested by verifying messages sent to store
   - Queries tested by verifying returned data
   
3. **Composability**
   - Can chain queries safely
   - Commands executed sequentially
   
4. **Clear Intent**
   - Code reads like English
   - No confusion about what methods do

---

## Further Reading

- Essential Feed Case Study: https://github.com/essentialdevelopercom/essential-feed-case-study
- Essential Developer Articles: https://www.essentialdeveloper.com/articles
- Object-Oriented Software Construction by Bertrand Meyer
