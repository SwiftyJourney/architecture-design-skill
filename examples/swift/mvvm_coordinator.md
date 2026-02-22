# MVVM + Coordinator Pattern (Swift / SwiftUI)

Pattern source: Matteo Manferdini — "How to Use the Coordinator Pattern in SwiftUI"

---

## Overview

Combines MVVM (separation of view and view-model) with the Coordinator pattern (centralised navigation). The Coordinator owns the navigation stack and decides which screen to show next, keeping individual ViewModels free of navigation concerns.

**When to use**: apps with complex, multi-step navigation flows where navigation logic would otherwise be scattered across ViewModels or Views.

**Trade-offs**: adds indirection (ViewModel → Coordinator protocol → Coordinator concrete type); simpler apps may not need it.

---

## Core Components

### 1. Coordinator Protocol

Defines the navigation actions available to a ViewModel without exposing concrete types:

```swift
protocol ItemsCoordinator: AnyObject {
    func showDetail(for item: Item)
    func showCreation()
}
```

### 2. ViewModel

Holds view state and delegates navigation to the coordinator. Receives the coordinator via dependency injection (not created inline):

```swift
@Observable
@MainActor
final class ItemsViewModel {
    var items: [Item] = []
    var isLoading = false
    var error: Error?

    private weak var coordinator: (any ItemsCoordinator)?

    init(coordinator: any ItemsCoordinator) {
        self.coordinator = coordinator
    }

    func load() async {
        isLoading = true
        do {
            items = try await ItemsRepository.shared.fetchAll()
        } catch {
            self.error = error
        }
        isLoading = false
    }

    func didSelectItem(_ item: Item) {
        coordinator?.showDetail(for: item)
    }

    func didTapCreate() {
        coordinator?.showCreation()
    }
}
```

### 3. Coordinator

Owns the `NavigationPath` (or `NavigationStack`) and responds to navigation events:

```swift
@Observable
@MainActor
final class AppCoordinator: ItemsCoordinator {
    var path = NavigationPath()

    enum Destination: Hashable {
        case itemDetail(Item)
        case itemCreation
    }

    func showDetail(for item: Item) {
        path.append(Destination.itemDetail(item))
    }

    func showCreation() {
        path.append(Destination.itemCreation)
    }
}
```

### 4. Root View

Wires the coordinator and navigation stack together:

```swift
struct AppView: View {
    @State private var coordinator = AppCoordinator()

    var body: some View {
        NavigationStack(path: $coordinator.path) {
            ItemsView(
                viewModel: ItemsViewModel(coordinator: coordinator)
            )
            .navigationDestination(for: AppCoordinator.Destination.self) { destination in
                switch destination {
                case .itemDetail(let item):
                    ItemDetailView(item: item)
                case .itemCreation:
                    ItemCreationView(coordinator: coordinator)
                }
            }
        }
    }
}
```

### 5. Feature View

Stays thin — delegates all actions to ViewModel:

```swift
struct ItemsView: View {
    @State var viewModel: ItemsViewModel

    var body: some View {
        List(viewModel.items) { item in
            Button(item.name) {
                viewModel.didSelectItem(item)
            }
        }
        .toolbar {
            Button("Add", action: viewModel.didTapCreate)
        }
        .task { await viewModel.load() }
        .overlay {
            if viewModel.isLoading { ProgressView() }
        }
    }
}
```

---

## Key Principles

- **ViewModel depends on protocol, not concrete Coordinator** — makes unit testing straightforward (inject a mock)
- **Coordinator owns navigation state** — ViewModels never push to NavigationPath directly
- **Views stay thin** — they call ViewModel methods; ViewModel decides whether to update state or trigger navigation
- **Coordinator is injected** — never created by the ViewModel itself

---

## Testing a ViewModel with a Mock Coordinator

```swift
final class MockItemsCoordinator: ItemsCoordinator {
    var shownDetailItem: Item?
    var showCreationCalled = false

    func showDetail(for item: Item) { shownDetailItem = item }
    func showCreation() { showCreationCalled = true }
}

// In tests (Swift Testing)
@Test func selectingItemNavigatesToDetail() async {
    let coordinator = MockItemsCoordinator()
    let viewModel = await MainActor.run { ItemsViewModel(coordinator: coordinator) }
    let item = Item(id: 1, name: "Test")

    await MainActor.run { viewModel.didSelectItem(item) }

    #expect(coordinator.shownDetailItem == item)
}
```

---

## Relationship to Architecture Skill Topics

| Concern | Handled by |
|---------|-----------|
| Navigation state | Coordinator (owns `NavigationPath`) |
| View state & business logic | ViewModel |
| Rendering | SwiftUI View |
| Dependency injection | Composition Root (see `composition_root.md`) |

See also `two_layer_views.md` for how to split views into Root (wires data) and Content (pure display) to complement this pattern.
