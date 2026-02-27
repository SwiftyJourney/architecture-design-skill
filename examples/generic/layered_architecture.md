# Layered Architecture (Language-Agnostic)

Generic examples applicable to any project and any programming language. Entity names are intentionally neutral — substitute your own domain types.

---

## The Four Layers

```
Presentation Layer   →   Domain Layer   ←   Infrastructure Layer
(UI, ViewModels)         (Entities,          (Network, DB,
                          Use Cases)          Frameworks)
```

**Dependency Rule**: Dependencies point inward only. Infrastructure depends on Domain (via interfaces); Presentation depends on Domain. Nothing in Domain knows about Infrastructure or UI.

---

### 1. Domain Layer (Core Business Logic)

**Entities** — plain data, no framework dependencies:

```
// Pseudocode — replace Item/Comment with your own types
struct Item {
    id: UUID
    title: String
    description: String?
    createdAt: DateTime
}

struct Comment {
    id: UUID
    body: String
    author: String
    createdAt: DateTime
}
```

**Use Cases** — business rules, defined as interfaces:

```
// Async boundary: IO operations use async/await (or equivalent)
interface ItemLoader {
    function load() async throws -> List<Item>
}

interface ItemCache {
    function save(items: List<Item>) throws
    function loadCached() throws -> List<Item>?
}

// Concrete use case: remote load with optional caching
class RemoteItemLoader implements ItemLoader {
    private client: HTTPClient

    function load() async throws -> List<Item> {
        let (data, response) = try await client.get(url)
        return try ItemsMapper.map(data, response)
    }
}

class CachedItemLoader implements ItemLoader {
    private store: ItemStore

    function load() throws -> List<Item> {
        let cached = try store.retrieve()
        guard let cache = cached, CachePolicy.isValid(cache.timestamp) else {
            return []
        }
        return cache.items
    }
}
```

---

### 2. Infrastructure Layer (External Details)

**Network Adapter**:

```
// Interface (defined in Domain layer)
interface HTTPClient {
    function get(url: URL) async throws -> (Data, HTTPResponse)
}

// Concrete adapter (lives in Infrastructure layer)
class NetworkHTTPClient implements HTTPClient {
    function get(url: URL) async throws -> (Data, HTTPResponse) {
        // Platform-specific HTTP implementation
        return try await httpLibrary.request(url)
    }
}
```

**Database Adapter**:

```
// Interface (defined in Domain layer — sync throws)
interface ItemStore {
    function retrieve() throws -> CachedItems?
    function insert(items: List<LocalItem>, timestamp: DateTime) throws
    function delete() throws
}

// Concrete adapter (lives in Infrastructure)
class SQLiteItemStore implements ItemStore {
    function retrieve() throws -> CachedItems? {
        let rows = try database.query("SELECT * FROM items")
        return rows.isEmpty ? nil : CachedItems(items: rows.map(toLocal), timestamp: rows.first!.timestamp)
    }

    function insert(items: List<LocalItem>, timestamp: DateTime) throws {
        try database.transaction {
            try database.execute("DELETE FROM items")
            for item in items {
                try database.execute("INSERT INTO items ...", item)
            }
        }
    }

    function delete() throws {
        try database.execute("DELETE FROM items")
    }
}
```

> **Why sync for the store?** The store runs on a dedicated queue/thread managed by infrastructure (e.g., CoreData's private queue, SQLite's serial queue). Keeping the protocol synchronous keeps the domain contract simple. A `Scheduler`-style bridge (see `references/concurrency_patterns.md`) handles the thread hop in the infrastructure layer.

---

### 3. Presentation Layer (View Logic)

**Presenter / ViewModel** — transforms domain data into display data, no UI framework dependency:

```
// View protocol — implemented by the actual UI component
interface ResourceView<ViewModel> {
    function display(viewModel: ViewModel)
}

interface LoadingView {
    function displayLoading(isLoading: Boolean)
}

interface ErrorView {
    function displayError(message: String?)
}

// Generic presenter — maps Resource to ViewModel
class ResourcePresenter<Resource, ViewModel> {
    private resourceView: ResourceView<ViewModel>
    private loadingView: LoadingView
    private errorView: ErrorView
    private mapper: (Resource) throws -> ViewModel

    function didStartLoading() {
        errorView.displayError(nil)
        loadingView.displayLoading(true)
    }

    function didFinishLoading(resource: Resource) {
        try {
            resourceView.display(mapper(resource))
            loadingView.displayLoading(false)
        } catch {
            didFinishLoading(error: error)
        }
    }

    function didFinishLoading(error: Error) {
        errorView.displayError("Failed to load. Please try again.")
        loadingView.displayLoading(false)
    }
}
```

> **Note:** In Swift this pattern is `LoadResourcePresenter<Resource, View: ResourceView>` — see `references/concurrency_patterns.md` for the full implementation.

---

### 4. UI Layer (Framework-Specific)

The UI layer implements the view protocols defined in the Presentation layer:

```
class ItemListViewController implements ResourceView<List<ItemViewModel>>,
                                           LoadingView,
                                           ErrorView {

    function display(viewModel: List<ItemViewModel>) {
        items = viewModel
        listComponent.reload()
    }

    function displayLoading(isLoading: Boolean) {
        spinner.visible = isLoading
    }

    function displayError(message: String?) {
        errorBanner.text = message
        errorBanner.visible = message != nil
    }
}
```

The UI layer should contain NO business logic. All it does is render what the presenter tells it to display.

---

## Dependency Flow

```
UI Layer
   │ implements
Presentation Layer (interfaces: ResourceView, LoadingView, ErrorView)
   │ depends on
Domain Layer (interfaces: ItemLoader, ItemStore; entities: Item)
   │ implements
Infrastructure Layer (NetworkHTTPClient, SQLiteItemStore, ...)
```

**Key Rule**: The arrow always points from outer layers toward the Domain. Domain never imports Infrastructure.

---

## Composition Root

The one place where all concrete types are instantiated and wired together. The composition root is the only place that knows about all the implementations:

```
class AppCompositionRoot {
    function makeItemListScreen() -> UIComponent {
        // Infrastructure
        let httpClient = NetworkHTTPClient()
        let itemStore = SQLiteItemStore(path: "items.sqlite")

        // Use Cases
        let remoteLoader = RemoteItemLoader(client: httpClient)
        let cachedLoader = CachedItemLoader(store: itemStore)
        let fallbackLoader = FallbackLoader(primary: remoteLoader, fallback: cachedLoader)

        // Presentation
        let viewController = ItemListViewController()
        let presenter = ResourcePresenter(
            resourceView: viewController,
            loadingView: viewController,
            errorView: viewController,
            mapper: ItemViewModel.from
        )

        // Adapter: bridges async loader → presenter
        let adapter = LoadAdapter(loader: fallbackLoader.load)
        viewController.onRefresh = adapter.load
        adapter.presenter = presenter

        return viewController
    }
}
```

---

## Testing Each Layer

### Domain / Use Case Tests

```
// No async callbacks — use native async/await
test "load delivers items on successful HTTP response" {
    // Arrange
    let client = HTTPClientSpy()
    let sut = RemoteItemLoader(client: client)
    let expected = [makeItem(), makeItem()]
    client.stub(data: encode(expected), response: successResponse())

    // Act
    let received = try await sut.load()

    // Assert
    assert(received == expected)
}

test "load throws connectivity error on HTTP failure" {
    let client = HTTPClientSpy()
    let sut = RemoteItemLoader(client: client)
    client.stub(error: anyError())

    await assertThrows { try await sut.load() }
}
```

### Presentation Layer Tests

```
test "didStartLoading shows loading and clears error" {
    let (sut, view) = makeSUT()

    sut.didStartLoading()

    assert(view.isLoading == true)
    assert(view.errorMessage == nil)
}

test "didFinishLoading maps resource to view model" {
    let (sut, view) = makeSUT()
    let items = [makeItem(), makeItem()]

    sut.didFinishLoading(resource: items)

    assert(view.displayedItems.count == 2)
    assert(view.isLoading == false)
}

// Helper
function makeSUT() -> (ResourcePresenter, ViewSpy) {
    let view = ViewSpy()
    let sut = ResourcePresenter(resourceView: view, loadingView: view, errorView: view, mapper: identity)
    return (sut, view)
}
```

---

## Composition Patterns

### Decorator (add behavior without modifying)

```
class CachingItemLoader implements ItemLoader {
    private decoratee: ItemLoader
    private cache: ItemCache

    function load() async throws -> List<Item> {
        let items = try await decoratee.load()
        // Fire-and-forget: cache failure should not affect caller
        Task { try? cache.save(items: items) }
        return items
    }
}
```

### Composite (fallback chain)

```
class FallbackLoader implements ItemLoader {
    private primary: ItemLoader
    private fallback: ItemLoader

    function load() async throws -> List<Item> {
        do {
            return try await primary.load()
        } catch {
            return try await fallback.load()
        }
    }
}
```

---

## Benefits

1. **Testability** — each layer tests in isolation; only the composition root wires them
2. **Replaceability** — swap `SQLiteItemStore` for `InMemoryItemStore` without touching business logic
3. **Framework independence** — business logic never imports UIKit, SwiftUI, Android, React, etc.
4. **Incremental migration** — add layers to existing code one boundary at a time

---

## Further Reading

- `references/clean_architecture.md` — layer rules and boundary enforcement
- `references/solid_principles.md` — SOLID applied to these layers
- `references/design_patterns.md` — Decorator, Composite, Adapter, Null Object
- `references/concurrency_patterns.md` — Swift-specific async/await, Scheduler, generic presenter
- Clean Architecture by Robert C. Martin
