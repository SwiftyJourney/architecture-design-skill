# Layered Architecture (Language-Agnostic)

Generic examples applicable to any programming language.

---

## The Four Layers

### 1. Domain Layer (Core Business Logic)

**Entities:**
```
// Pseudocode
class FeedItem {
    id: UUID
    description: String?
    location: String?
    imageURL: URL
}

class ImageComment {
    id: UUID
    message: String
    createdAt: DateTime
    author: CommentAuthor
}
```

**Use Cases:**
```
interface FeedLoader {
    function load(completion: Callback<Result<List<FeedItem>, Error>>)
}

class LoadFeedUseCase implements FeedLoader {
    private httpClient: HTTPClient
    
    function load(completion: Callback<Result<List<FeedItem>, Error>>) {
        httpClient.get(url) { response ->
            if (response.isSuccess) {
                items = parse(response.data)
                completion(Success(items))
            } else {
                completion(Failure(error))
            }
        }
    }
}
```

---

### 2. Infrastructure Layer (External Details)

**Network Adapter:**
```
interface HTTPClient {
    function get(url: URL, completion: Callback<Result<HTTPResponse, Error>>)
}

class URLSessionHTTPClient implements HTTPClient {
    function get(url: URL, completion: Callback<Result<HTTPResponse, Error>>) {
        // Platform-specific HTTP implementation
        networkLibrary.request(url) { response ->
            completion(response)
        }
    }
}
```

**Database Adapter:**
```
interface FeedStore {
    function save(items: List<FeedItem>)
    function load(): List<FeedItem>?
}

class SQLiteFeedStore implements FeedStore {
    function save(items: List<FeedItem>) {
        database.transaction {
            database.deleteAll("feed_items")
            items.forEach { item ->
                database.insert("feed_items", item)
            }
        }
    }
    
    function load(): List<FeedItem>? {
        return database.query("SELECT * FROM feed_items")
    }
}
```

---

### 3. Presentation Layer (View Logic)

**Presenter:**
```
interface FeedView {
    function display(viewModel: FeedViewModel)
    function displayLoading(isLoading: Boolean)
    function displayError(message: String)
}

class FeedPresenter {
    private view: FeedView
    private loader: FeedLoader
    
    function didRequestFeed() {
        view.displayLoading(true)
        
        loader.load { result ->
            view.displayLoading(false)
            
            if (result.isSuccess) {
                viewModel = map(result.value)
                view.display(viewModel)
            } else {
                view.displayError("Failed to load feed")
            }
        }
    }
    
    private function map(items: List<FeedItem>): FeedViewModel {
        return FeedViewModel(
            items: items.map { item ->
                FeedItemViewModel(
                    description: item.description,
                    location: item.location,
                    imageURL: item.imageURL
                )
            }
        )
    }
}
```

**View Model:**
```
class FeedViewModel {
    items: List<FeedItemViewModel>
}

class FeedItemViewModel {
    description: String?
    location: String?
    imageURL: URL
}
```

---

### 4. UI Layer (Framework-Specific)

**View:**
```
class FeedViewController implements FeedView {
    private presenter: FeedPresenter
    private items: List<FeedItemViewModel> = []
    
    function viewDidLoad() {
        presenter.didRequestFeed()
    }
    
    function display(viewModel: FeedViewModel) {
        items = viewModel.items
        tableView.reload()
    }
    
    function displayLoading(isLoading: Boolean) {
        loadingIndicator.visible = isLoading
    }
    
    function displayError(message: String) {
        alertView.show(message)
    }
}
```

---

## Dependency Flow

```
UI Layer
   ↓ depends on
Presentation Layer
   ↓ depends on
Domain Layer
   ↑ implements
Infrastructure Layer
```

**Key Rule**: Dependencies point inward only!

---

## Composition Root

```
class AppCompositionRoot {
    function makeMainViewController(): ViewController {
        // Infrastructure
        httpClient = URLSessionHTTPClient()
        feedStore = SQLiteFeedStore()
        
        // Use Cases
        remoteLoader = RemoteFeedLoader(httpClient)
        localLoader = LocalFeedLoader(feedStore)
        compositeLoader = FeedLoaderWithFallback(remoteLoader, localLoader)
        
        // Presentation
        viewController = FeedViewController()
        presenter = FeedPresenter(viewController, compositeLoader)
        viewController.presenter = presenter
        
        return viewController
    }
}
```

---

## Testing Each Layer

### Domain Layer Tests

```
test "load delivers items on successful HTTP response" {
    // Arrange
    sut = RemoteFeedLoader(httpClientSpy)
    expectedItems = [makeItem(), makeItem()]
    
    // Act
    sut.load { result -> }
    httpClientSpy.complete(with: expectedItems)
    
    // Assert
    assert(result == Success(expectedItems))
}

test "load delivers error on HTTP failure" {
    // Arrange
    sut = RemoteFeedLoader(httpClientSpy)
    
    // Act
    sut.load { result -> }
    httpClientSpy.complete(with: Error())
    
    // Assert
    assert(result.isFailure)
}
```

### Presentation Layer Tests

```
test "didRequestFeed displays loading" {
    // Arrange
    (presenter, view) = makeSUT()
    
    // Act
    presenter.didRequestFeed()
    
    // Assert
    assert(view.displayedLoading == true)
}

test "didRequestFeed displays items on success" {
    // Arrange
    (presenter, view, loader) = makeSUT()
    items = [makeItem(), makeItem()]
    
    // Act
    presenter.didRequestFeed()
    loader.complete(with: items)
    
    // Assert
    assert(view.displayedViewModel.items.count == 2)
}
```

---

## Benefits

1. **Testability** - Each layer testable in isolation
2. **Flexibility** - Easy to swap implementations
3. **Maintainability** - Clear responsibilities
4. **Scalability** - Easy to add features
5. **Framework Independence** - Business logic pure

---

## Common Patterns

### Decorator Pattern
```
class CachingFeedLoader implements FeedLoader {
    private decoratee: FeedLoader
    private cache: FeedCache
    
    function load(completion: Callback) {
        decoratee.load { result ->
            if (result.isSuccess) {
                cache.save(result.value)
            }
            completion(result)
        }
    }
}
```

### Composite Pattern
```
class FallbackFeedLoader implements FeedLoader {
    private primary: FeedLoader
    private fallback: FeedLoader
    
    function load(completion: Callback) {
        primary.load { result ->
            if (result.isSuccess) {
                completion(result)
            } else {
                fallback.load(completion)
            }
        }
    }
}
```

---

## Further Reading
- Clean Architecture by Robert C. Martin
- Essential Developer: https://www.essentialdeveloper.com/
