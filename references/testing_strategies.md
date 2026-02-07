# Testing Strategies Reference

Comprehensive guide to testing in Clean Architecture, covering unit tests, integration tests, test doubles, and best practices.

---

## Testing Philosophy

> "If it's hard to test, it's poorly designed"

Good architecture makes testing easy. If testing is difficult, it's a signal that the design needs improvement.

---

## The Testing Pyramid

```
        ┌───────────┐
        │  UI/E2E   │ ← 10% - Slow, Expensive, Brittle
        ├───────────┤
        │Integration│ ← 20% - Medium Speed, Some Setup
        ├───────────┤
        │   Unit    │ ← 70% - Fast, Cheap, Isolated
        └───────────┘
```

### Unit Tests (70%)
- Test one component in isolation
- Mock all dependencies
- Fast (milliseconds)
- No external dependencies
- Run frequently

### Integration Tests (20%)
- Test component integration
- May use real dependencies
- Slower than unit tests
- Test boundaries between layers
- Run before commits

### UI/E2E Tests (10%)
- Test complete user flows
- Full system integration
- Slowest tests
- Most brittle
- Run before releases

---

## Test Doubles

### Types of Test Doubles

#### 1. Stub
Provides canned answers to calls.

```swift
class HTTPClientStub: HTTPClient {
    private let result: HTTPClient.Result
    
    init(result: HTTPClient.Result) {
        self.result = result
    }
    
    func get(from url: URL, completion: @escaping (HTTPClient.Result) -> Void) {
        completion(result)
    }
}

// Usage
let stub = HTTPClientStub(result: .success((Data(), HTTPURLResponse())))
let sut = RemoteFeedLoader(client: stub)
```

**When to use**: Need predetermined responses.

#### 2. Spy
Records calls for later verification.

```swift
class HTTPClientSpy: HTTPClient {
    private(set) var requestedURLs = [URL]()
    private(set) var completions = [(HTTPClient.Result) -> Void]()
    
    func get(from url: URL, completion: @escaping (HTTPClient.Result) -> Void) {
        requestedURLs.append(url)
        completions.append(completion)
    }
    
    func complete(with result: HTTPClient.Result, at index: Int = 0) {
        completions[index](result)
    }
}

// Usage in tests
func test_load_requestsDataFromURL() {
    let url = URL(string: "https://a-url.com")!
    let (sut, client) = makeSUT(url: url)
    
    sut.load { _ in }
    
    XCTAssertEqual(client.requestedURLs, [url])
}
```

**When to use**: Need to verify interactions.

#### 3. Mock
Verifies behavior expectations.

```swift
class FeedCacheMock: FeedCache {
    enum Message: Equatable {
        case save([FeedItem])
        case deleteCacheFeed
    }
    
    private(set) var messages = [Message]()
    
    func save(_ feed: [FeedItem], completion: @escaping (Error?) -> Void) {
        messages.append(.save(feed))
        completion(nil)
    }
    
    func deleteCacheFeed(completion: @escaping (Error?) -> Void) {
        messages.append(.deleteCacheFeed)
        completion(nil)
    }
}

// Usage
func test_save_requestsCacheDeletion() {
    let (sut, cache) = makeSUT()
    
    sut.save(uniqueFeed().models) { _ in }
    
    XCTAssertEqual(cache.messages, [.deleteCacheFeed])
}
```

**When to use**: Need to verify specific calls were made.

#### 4. Fake
Working implementation for testing.

```swift
class InMemoryFeedStore: FeedStore {
    private var feedCache: CachedFeed?
    
    func deleteCacheFeed(completion: @escaping (Error?) -> Void) {
        feedCache = nil
        completion(nil)
    }
    
    func insert(_ feed: [LocalFeedItem], timestamp: Date, completion: @escaping (Error?) -> Void) {
        feedCache = CachedFeed(feed: feed, timestamp: timestamp)
        completion(nil)
    }
    
    func retrieve(completion: @escaping (Result<CachedFeed?, Error>) -> Void) {
        completion(.success(feedCache))
    }
}
```

**When to use**: Need lightweight, working implementation for tests.

---

## Unit Testing Patterns

### Pattern 1: Arrange, Act, Assert (AAA)

```swift
func test_load_deliversItemsOnSuccessfulHTTPResponse() {
    // Arrange
    let (sut, client) = makeSUT()
    let item1 = makeItem(id: UUID(), imageURL: URL(string: "http://a-url.com")!)
    let item2 = makeItem(id: UUID(), imageURL: URL(string: "http://another-url.com")!)
    let items = [item1.model, item2.model]
    
    // Act
    expect(sut, toCompleteWith: .success(items), when: {
        let json = makeItemsJSON([item1.json, item2.json])
        client.complete(withStatusCode: 200, data: json)
    })
    
    // Assert happens in expect helper
}
```

### Pattern 2: Given, When, Then (BDD Style)

```swift
func test_load_deliversItemsOnSuccessfulHTTPResponse() {
    // Given a feed loader and expected items
    let (sut, client) = makeSUT()
    let expectedItems = [makeItem(), makeItem()]
    
    // When loader completes successfully
    var receivedResult: Result<[FeedItem], Error>?
    sut.load { receivedResult = $0 }
    client.complete(with: expectedItems)
    
    // Then it delivers the items
    switch receivedResult {
    case let .success(items)?:
        XCTAssertEqual(items, expectedItems)
    default:
        XCTFail("Expected success, got \(String(describing: receivedResult)) instead")
    }
}
```

### Pattern 3: Descriptive Test Names

```swift
// ❌ Bad - unclear what's being tested
func testLoad() { }
func testLoadError() { }

// ✅ Good - clear behavior description
func test_load_deliversNoItemsOn200HTTPResponseWithEmptyJSONList() { }
func test_load_deliversErrorOnNon200HTTPResponse() { }
func test_load_deliversErrorOnInvalidData() { }
```

**Format**: `test_[unitOfWork]_[stateUnderTest]_[expectedBehavior]`

### Pattern 4: One Assertion Per Test (Guideline)

```swift
// ✅ Good - tests one behavior
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
```

### Pattern 5: Extract Helper Methods

```swift
class LoadFeedFromRemoteUseCaseTests: XCTestCase {
    
    func test_load_deliversItemsOn200HTTPResponseWithJSONItems() {
        let (sut, client) = makeSUT()
        let item1 = makeItem(id: UUID(), imageURL: URL(string: "http://a-url.com")!)
        let item2 = makeItem(id: UUID(), imageURL: URL(string: "http://another-url.com")!)
        let items = [item1.model, item2.model]
        
        expect(sut, toCompleteWith: .success(items), when: {
            let json = makeItemsJSON([item1.json, item2.json])
            client.complete(withStatusCode: 200, data: json)
        })
    }
    
    // MARK: - Helpers
    
    private func makeSUT(url: URL = URL(string: "https://a-url.com")!, file: StaticString = #filePath, line: UInt = #line) -> (sut: RemoteFeedLoader, client: HTTPClientSpy) {
        let client = HTTPClientSpy()
        let sut = RemoteFeedLoader(url: url, client: client)
        trackForMemoryLeaks(sut, file: file, line: line)
        trackForMemoryLeaks(client, file: file, line: line)
        return (sut, client)
    }
    
    private func expect(_ sut: RemoteFeedLoader, toCompleteWith expectedResult: Result<[FeedItem], Error>, when action: () -> Void, file: StaticString = #filePath, line: UInt = #line) {
        let exp = expectation(description: "Wait for load completion")
        
        sut.load { receivedResult in
            switch (receivedResult, expectedResult) {
            case let (.success(receivedItems), .success(expectedItems)):
                XCTAssertEqual(receivedItems, expectedItems, file: file, line: line)
                
            case let (.failure(receivedError as RemoteFeedLoader.Error), .failure(expectedError as RemoteFeedLoader.Error)):
                XCTAssertEqual(receivedError, expectedError, file: file, line: line)
                
            default:
                XCTFail("Expected result \(expectedResult) got \(receivedResult) instead", file: file, line: line)
            }
            
            exp.fulfill()
        }
        
        action()
        
        wait(for: [exp], timeout: 1.0)
    }
    
    private func makeItem(id: UUID, description: String? = nil, location: String? = nil, imageURL: URL) -> (model: FeedItem, json: [String: Any]) {
        let item = FeedItem(id: id, description: description, location: location, imageURL: imageURL)
        
        let json = [
            "id": id.uuidString,
            "description": description,
            "location": location,
            "image": imageURL.absoluteString
        ].compactMapValues { $0 }
        
        return (item, json)
    }
    
    private func makeItemsJSON(_ items: [[String: Any]]) -> Data {
        let json = ["items": items]
        return try! JSONSerialization.data(withJSONObject: json)
    }
}
```

---

## Testing Each Architecture Layer

### Testing Domain Layer (Entities + Use Cases)

#### Test Use Case Business Logic

```swift
class RemoteFeedLoaderTests: XCTestCase {
    
    func test_init_doesNotRequestDataFromURL() {
        let (_, client) = makeSUT()
        
        XCTAssertTrue(client.requestedURLs.isEmpty)
    }
    
    func test_load_requestsDataFromURL() {
        let url = URL(string: "https://a-given-url.com")!
        let (sut, client) = makeSUT(url: url)
        
        sut.load { _ in }
        
        XCTAssertEqual(client.requestedURLs, [url])
    }
    
    func test_loadTwice_requestsDataFromURLTwice() {
        let url = URL(string: "https://a-given-url.com")!
        let (sut, client) = makeSUT(url: url)
        
        sut.load { _ in }
        sut.load { _ in }
        
        XCTAssertEqual(client.requestedURLs, [url, url])
    }
    
    func test_load_deliversErrorOnClientError() {
        let (sut, client) = makeSUT()
        
        expect(sut, toCompleteWith: failure(.connectivity), when: {
            let clientError = NSError(domain: "Test", code: 0)
            client.complete(with: clientError)
        })
    }
    
    func test_load_deliversErrorOnNon200HTTPResponse() {
        let (sut, client) = makeSUT()
        
        let samples = [199, 201, 300, 400, 500]
        
        samples.enumerated().forEach { index, code in
            expect(sut, toCompleteWith: failure(.invalidData), when: {
                let json = makeItemsJSON([])
                client.complete(withStatusCode: code, data: json, at: index)
            })
        }
    }
    
    func test_load_deliversErrorOn200HTTPResponseWithInvalidJSON() {
        let (sut, client) = makeSUT()
        
        expect(sut, toCompleteWith: failure(.invalidData), when: {
            let invalidJSON = Data("invalid json".utf8)
            client.complete(withStatusCode: 200, data: invalidJSON)
        })
    }
    
    func test_load_deliversNoItemsOn200HTTPResponseWithEmptyJSONList() {
        let (sut, client) = makeSUT()
        
        expect(sut, toCompleteWith: .success([]), when: {
            let emptyListJSON = makeItemsJSON([])
            client.complete(withStatusCode: 200, data: emptyListJSON)
        })
    }
    
    func test_load_deliversItemsOn200HTTPResponseWithJSONItems() {
        let (sut, client) = makeSUT()
        
        let item1 = makeItem(
            id: UUID(),
            imageURL: URL(string: "http://a-url.com")!)
        
        let item2 = makeItem(
            id: UUID(),
            description: "a description",
            location: "a location",
            imageURL: URL(string: "http://another-url.com")!)
        
        let items = [item1.model, item2.model]
        
        expect(sut, toCompleteWith: .success(items), when: {
            let json = makeItemsJSON([item1.json, item2.json])
            client.complete(withStatusCode: 200, data: json)
        })
    }
    
    func test_load_doesNotDeliverResultAfterSUTInstanceHasBeenDeallocated() {
        let url = URL(string: "http://any-url.com")!
        let client = HTTPClientSpy()
        var sut: RemoteFeedLoader? = RemoteFeedLoader(url: url, client: client)
        
        var capturedResults = [RemoteFeedLoader.Result]()
        sut?.load { capturedResults.append($0) }
        
        sut = nil
        client.complete(withStatusCode: 200, data: makeItemsJSON([]))
        
        XCTAssertTrue(capturedResults.isEmpty)
    }
    
    // MARK: - Helpers
    
    private func makeSUT(url: URL = URL(string: "https://a-url.com")!, file: StaticString = #filePath, line: UInt = #line) -> (sut: RemoteFeedLoader, client: HTTPClientSpy) {
        let client = HTTPClientSpy()
        let sut = RemoteFeedLoader(url: url, client: client)
        trackForMemoryLeaks(sut, file: file, line: line)
        trackForMemoryLeaks(client, file: file, line: line)
        return (sut, client)
    }
    
    private func failure(_ error: RemoteFeedLoader.Error) -> Result<[FeedItem], Error> {
        return .failure(error)
    }
}
```

**Key Points**:
- Test one behavior per test
- Use descriptive test names
- Mock all dependencies
- Test happy and sad paths
- Test memory management

---

### Testing Infrastructure Layer

#### Integration Tests for Database/Network

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
    
    func test_delete_deliversNoErrorOnEmptyCache() {
        let sut = makeSUT()
        
        let deletionError = deleteCache(from: sut)
        
        XCTAssertNil(deletionError, "Expected empty cache deletion to succeed")
    }
    
    func test_delete_hasNoSideEffectsOnEmptyCache() {
        let sut = makeSUT()
        
        deleteCache(from: sut)
        
        expect(sut, toRetrieve: .success(.none))
    }
    
    func test_delete_deliversNoErrorOnNonEmptyCache() {
        let sut = makeSUT()
        insert((uniqueImageFeed().local, Date()), to: sut)
        
        let deletionError = deleteCache(from: sut)
        
        XCTAssertNil(deletionError, "Expected non-empty cache deletion to succeed")
    }
    
    func test_delete_emptiesPreviouslyInsertedCache() {
        let sut = makeSUT()
        insert((uniqueImageFeed().local, Date()), to: sut)
        
        deleteCache(from: sut)
        
        expect(sut, toRetrieve: .success(.none))
    }
    
    func test_storeSideEffects_runSerially() {
        let sut = makeSUT()
        var completedOperationsInOrder = [XCTestExpectation]()
        
        let op1 = expectation(description: "Operation 1")
        sut.insert(uniqueImageFeed().local, timestamp: Date()) { _ in
            completedOperationsInOrder.append(op1)
            op1.fulfill()
        }
        
        let op2 = expectation(description: "Operation 2")
        sut.deleteCachedFeed { _ in
            completedOperationsInOrder.append(op2)
            op2.fulfill()
        }
        
        let op3 = expectation(description: "Operation 3")
        sut.insert(uniqueImageFeed().local, timestamp: Date()) { _ in
            completedOperationsInOrder.append(op3)
            op3.fulfill()
        }
        
        waitForExpectations(timeout: 5.0)
        
        XCTAssertEqual(completedOperationsInOrder, [op1, op2, op3], "Expected side-effects to run serially but operations finished in the wrong order")
    }
    
    // MARK: - Helpers
    
    private func makeSUT(file: StaticString = #filePath, line: UInt = #line) -> FeedStore {
        let storeBundle = Bundle(for: CoreDataFeedStore.self)
        let storeURL = URL(fileURLWithPath: "/dev/null")
        let sut = try! CoreDataFeedStore(storeURL: storeURL, bundle: storeBundle)
        trackForMemoryLeaks(sut, file: file, line: line)
        return sut
    }
    
    @discardableResult
    private func insert(_ cache: (feed: [LocalFeedImage], timestamp: Date), to sut: FeedStore) -> Error? {
        let exp = expectation(description: "Wait for cache insertion")
        var insertionError: Error?
        sut.insert(cache.feed, timestamp: cache.timestamp) { result in
            if case let Result.failure(error) = result { insertionError = error }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
        return insertionError
    }
    
    @discardableResult
    private func deleteCache(from sut: FeedStore) -> Error? {
        let exp = expectation(description: "Wait for cache deletion")
        var deletionError: Error?
        sut.deleteCachedFeed { result in
            if case let Result.failure(error) = result { deletionError = error }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
        return deletionError
    }
    
    private func expect(_ sut: FeedStore, toRetrieve expectedResult: Result<CachedFeed?, Error>, file: StaticString = #filePath, line: UInt = #line) {
        let exp = expectation(description: "Wait for cache retrieval")
        
        sut.retrieve { retrievedResult in
            switch (expectedResult, retrievedResult) {
            case (.success(.none), .success(.none)),
                 (.failure, .failure):
                break
                
            case let (.success(.some(expected)), .success(.some(retrieved))):
                XCTAssertEqual(retrieved.feed, expected.feed, file: file, line: line)
                XCTAssertEqual(retrieved.timestamp, expected.timestamp, file: file, line: line)
                
            default:
                XCTFail("Expected to retrieve \(expectedResult), got \(retrievedResult) instead", file: file, line: line)
            }
            
            exp.fulfill()
        }
        
        wait(for: [exp], timeout: 1.0)
    }
    
    private func expect(_ sut: FeedStore, toRetrieveTwice expectedResult: Result<CachedFeed?, Error>, file: StaticString = #filePath, line: UInt = #line) {
        expect(sut, toRetrieve: expectedResult, file: file, line: line)
        expect(sut, toRetrieve: expectedResult, file: file, line: line)
    }
}
```

**Key Points**:
- Test with real infrastructure (database, filesystem)
- Test CRUD operations
- Test edge cases (empty, non-empty)
- Test side effects
- Test thread safety if applicable

---

### Testing Presentation Layer

```swift
class FeedPresenterTests: XCTestCase {
    
    func test_init_doesNotSendMessagesToView() {
        let (_, view) = makeSUT()
        
        XCTAssertTrue(view.messages.isEmpty, "Expected no view messages")
    }
    
    func test_didStartLoadingFeed_displaysNoErrorMessageAndStartsLoading() {
        let (sut, view) = makeSUT()
        
        sut.didStartLoadingFeed()
        
        XCTAssertEqual(view.messages, [
            .display(errorMessage: .none),
            .display(isLoading: true)
        ])
    }
    
    func test_didFinishLoadingFeed_displaysFeedAndStopsLoading() {
        let (sut, view) = makeSUT()
        let feed = uniqueImageFeed().models
        
        sut.didFinishLoadingFeed(with: feed)
        
        XCTAssertEqual(view.messages, [
            .display(feed: feed),
            .display(isLoading: false)
        ])
    }
    
    func test_didFinishLoadingFeedWithError_displaysLocalizedErrorMessageAndStopsLoading() {
        let (sut, view) = makeSUT()
        
        sut.didFinishLoadingFeed(with: anyNSError())
        
        XCTAssertEqual(view.messages, [
            .display(errorMessage: localized("FEED_VIEW_CONNECTION_ERROR")),
            .display(isLoading: false)
        ])
    }
    
    // MARK: - Helpers
    
    private func makeSUT(file: StaticString = #filePath, line: UInt = #line) -> (sut: FeedPresenter, view: ViewSpy) {
        let view = ViewSpy()
        let sut = FeedPresenter(view: view, loadingView: view, errorView: view)
        trackForMemoryLeaks(sut, file: file, line: line)
        trackForMemoryLeaks(view, file: file, line: line)
        return (sut, view)
    }
    
    private func localized(_ key: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        let table = "Feed"
        let bundle = Bundle(for: FeedPresenter.self)
        let value = bundle.localizedString(forKey: key, value: nil, table: table)
        if value == key {
            XCTFail("Missing localized string for key: \(key) in table: \(table)", file: file, line: line)
        }
        return value
    }
    
    private class ViewSpy: FeedView, FeedLoadingView, FeedErrorView {
        enum Message: Hashable {
            case display(errorMessage: String?)
            case display(isLoading: Bool)
            case display(feed: [FeedImage])
        }
        
        private(set) var messages = Set<Message>()
        
        func display(_ viewModel: FeedErrorViewModel) {
            messages.insert(.display(errorMessage: viewModel.message))
        }
        
        func display(_ viewModel: FeedLoadingViewModel) {
            messages.insert(.display(isLoading: viewModel.isLoading))
        }
        
        func display(_ viewModel: FeedViewModel) {
            messages.insert(.display(feed: viewModel.feed))
        }
    }
}
```

**Key Points**:
- Test presenter logic, not UI
- Mock views and use cases
- Test view model mapping
- Test error handling
- Test localization

---

## Testing Best Practices

### 1. Test Behavior, Not Implementation

```swift
// ❌ Bad - tests implementation details
func test_load_usesURLSession() {
    let sut = makeSUT()
    XCTAssertNotNil(sut.session)
}

// ✅ Good - tests behavior
func test_load_deliversItemsOnSuccessfulHTTPResponse() {
    let (sut, client) = makeSUT()
    
    expect(sut, toCompleteWith: .success([item1, item2]), when: {
        client.complete(with: [item1, item2])
    })
}
```

### 2. Make Tests Readable

```swift
// ❌ Bad - hard to understand
func test1() {
    let s = makeSUT()
    let c = s.1
    s.0.load { _ in }
    XCTAssertEqual(c.urls.count, 1)
}

// ✅ Good - clear and readable
func test_load_requestsDataFromURL() {
    let (sut, client) = makeSUT()
    
    sut.load { _ in }
    
    XCTAssertEqual(client.requestedURLs.count, 1)
}
```

### 3. Don't Test Third-Party Code

```swift
// ❌ Bad - testing URLSession
func test_urlSession_createsDataTask() {
    let session = URLSession.shared
    let task = session.dataTask(with: URL(string: "http://a-url.com")!)
    XCTAssertNotNil(task)
}

// ✅ Good - test your adapter
func test_getFromURL_performsGETRequestWithURL() {
    let url = URL(string: "http://any-url.com")!
    let (sut, session) = makeSUT()
    
    sut.get(from: url) { _ in }
    
    XCTAssertEqual(session.receivedURLs, [url])
}
```

### 4. Test Edge Cases

```swift
func test_load_deliversNoItemsOnEmptyJSONList() { ... }
func test_load_deliversItemsOnNonEmptyJSONList() { ... }
func test_load_deliversErrorOnInvalidJSON() { ... }
func test_load_deliversErrorOnNon200Response() { ... }
func test_load_deliversErrorOnConnectionError() { ... }
```

### 5. Avoid Test Interdependence

```swift
// ❌ Bad - tests depend on each other
var sharedState: [FeedItem]?

func test_A() {
    sharedState = [item1]
}

func test_B() {
    XCTAssertEqual(sharedState, [item1])  // Depends on test_A
}

// ✅ Good - each test is independent
func test_A() {
    let state = [item1]
    XCTAssertEqual(state, [item1])
}

func test_B() {
    let state = [item1]
    XCTAssertEqual(state, [item1])
}
```

---

## Memory Leak Testing

```swift
extension XCTestCase {
    func trackForMemoryLeaks(_ instance: AnyObject, file: StaticString = #filePath, line: UInt = #line) {
        addTeardownBlock { [weak instance] in
            XCTAssertNil(instance, "Instance should have been deallocated. Potential memory leak.", file: file, line: line)
        }
    }
}

// Usage
func makeSUT() -> (sut: RemoteFeedLoader, client: HTTPClientSpy) {
    let client = HTTPClientSpy()
    let sut = RemoteFeedLoader(client: client)
    trackForMemoryLeaks(sut)
    trackForMemoryLeaks(client)
    return (sut, client)
}
```

---

## Testing Checklist

### Unit Tests
- [ ] Test one behavior per test
- [ ] Use descriptive test names
- [ ] Follow AAA or Given-When-Then
- [ ] Mock all dependencies
- [ ] Test happy and sad paths
- [ ] Test edge cases
- [ ] Track memory leaks
- [ ] Tests are fast (<1s each)
- [ ] Tests are independent
- [ ] Tests are repeatable

### Integration Tests
- [ ] Test real integrations
- [ ] Test database operations
- [ ] Test network operations
- [ ] Test thread safety
- [ ] Test error handling
- [ ] Clean up test data

### General
- [ ] Tests are readable
- [ ] Tests are maintainable
- [ ] Extract helper methods
- [ ] Use fixtures for test data
- [ ] Test behavior, not implementation
- [ ] Don't test third-party code

---

## Common Testing Anti-Patterns

### 1. The Liar
Test passes but functionality is broken.

```swift
// ❌ Test says it works but doesn't verify
func test_save_succeeds() {
    sut.save(items) { _ in }
    // No assertion!
}
```

### 2. The Giant
Test is too large and tests too much.

```swift
// ❌ Tests everything in one test
func test_feedFeature() {
    // Test loading
    // Test caching
    // Test displaying
    // Test error handling
    // ... hundreds of lines
}
```

### 3. The Mockery
Overuse of mocks leads to brittle tests.

```swift
// ❌ Too many mocks
mock1.verify()
mock2.verify()
mock3.verify()
// Tests implementation, not behavior
```

### 4. The Inspector
Tests internal state instead of behavior.

```swift
// ❌ Inspecting private state
func test_load_setsIsLoadingFlag() {
    sut.load { _ in }
    XCTAssertTrue(sut.isLoading)  // Private state
}
```

### 5. The Generous Leftovers
Test leaves data around.

```swift
// ❌ Doesn't clean up
func test_save() {
    sut.save(items)
    // Leaves test data in database
}
```

---

## Further Reading

- Test-Driven Development by Kent Beck
- Growing Object-Oriented Software, Guided by Tests by Steve Freeman
- xUnit Test Patterns by Gerard Meszaros
- Essential Developer Testing Guide: https://www.essentialdeveloper.com/
