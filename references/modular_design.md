# Modular Design & Component Organization

Guide to organizing code into cohesive, loosely coupled modules.

---

## Module Organization Principles

### 1. High Cohesion
Components within a module should be strongly related.

### 2. Loose Coupling
Modules should have minimal dependencies on each other.

### 3. Single Responsibility
Each module has one clear purpose.

---

## Recommended Project Structure

```
MyApp/
├── Domain/                      # Business logic layer
│   ├── Entities/
│   │   ├── FeedItem.swift
│   │   └── ImageComment.swift
│   ├── UseCases/
│   │   ├── LoadFeed.swift
│   │   └── CacheFeed.swift
│   └── Boundaries/
│       ├── FeedLoader.swift
│       └── FeedCache.swift
│
├── Infrastructure/              # External dependencies
│   ├── Network/
│   │   ├── HTTPClient.swift
│   │   ├── URLSessionHTTPClient.swift
│   │   └── FeedItemsMapper.swift
│   └── Persistence/
│       ├── FeedStore.swift
│       └── CoreDataFeedStore.swift
│
├── Presentation/                # Presentation logic
│   ├── FeedPresenter.swift
│   ├── FeedViewModel.swift
│   └── FeedView.swift
│
├── UI/                          # UI components
│   ├── FeedViewController.swift
│   └── FeedCell.swift
│
└── Main/                        # Composition root
    └── SceneDelegate.swift
```

---

## Module Boundaries

### Domain Module
- **Contains**: Entities, use cases, business rules
- **Depends on**: Nothing
- **Depended on by**: All other modules

### Infrastructure Module
- **Contains**: Network, database, external services
- **Depends on**: Domain interfaces
- **Depended on by**: Composition root only

### Presentation Module
- **Contains**: Presenters, view models
- **Depends on**: Domain interfaces
- **Depended on by**: UI module

### UI Module
- **Contains**: View controllers, views
- **Depends on**: Presentation interfaces
- **Depended on by**: Composition root only

---

## Component Identification

### Steps to Identify Components

1. **Identify core business rules** → Domain entities
2. **Identify application logic** → Use cases
3. **Identify external systems** → Infrastructure
4. **Identify presentation needs** → Presenters
5. **Identify UI requirements** → Views/Controllers

### Example: Feed Feature

**Business Rules**:
- FeedItem entity
- Feed loading rules

**Application Logic**:
- Load feed from remote
- Cache feed locally
- Validate cache age

**External Systems**:
- HTTP client
- CoreData store

**Presentation**:
- Format feed for display
- Handle loading states

**UI**:
- Display feed items
- Handle user interactions

---

## Module Communication

### Through Abstractions

```swift
// Domain defines the contract
protocol FeedLoader {
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void)
}

// Infrastructure implements
class RemoteFeedLoader: FeedLoader { }

// Presentation uses
class FeedPresenter {
    private let loader: FeedLoader
    init(loader: FeedLoader) {
        self.loader = loader
    }
}
```

---

## Modularization Strategies

### 1. By Layer (Horizontal)
- Domain module
- Infrastructure module
- Presentation module
- UI module

### 2. By Feature (Vertical)
- Feed module
- Comments module
- Profile module

### 3. Hybrid Approach
Combine both for large apps.

---

## Further Reading
- Clean Architecture by Robert C. Martin
- Essential Developer: https://www.essentialdeveloper.com/
