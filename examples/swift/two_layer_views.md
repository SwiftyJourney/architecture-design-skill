# Two-Layer View Pattern (Swift / SwiftUI)

Pattern source: Matteo Manferdini — "How to Structure Views in SwiftUI"

---

## Overview

Split each screen into two view types:

- **Root View** ("container"): wires data, state, and actions. Observes models, creates ViewModels, passes data down. Not reusable — it knows about the environment.
- **Content View** ("presentation"): receives primitives or value types; purely declarative. Fully reusable and trivially previewable.

**When to use**: any non-trivial screen. The pattern scales from simple lists to complex forms.

**Trade-offs**: adds a layer of indirection; for very simple screens (e.g., a static About page) the split may be overkill.

---

## The Pattern

```
Screen = Root View + Content View
              │              │
    wires state/data    pure display
    accesses models     receives primitives
    calls actions       calls callbacks
```

---

## Example: User Profile Screen

### Content View (pure, reusable)

Receives only what it needs to display. No `@Observable`, no environment access, no async calls.

```swift
struct ProfileContentView: View {
    // Primitives — makes previews trivial
    let name: String
    let handle: String
    let avatarURL: URL?
    let followerCount: Int
    let isFollowing: Bool

    // Callbacks — no coupling to model layer
    var onFollowToggle: () -> Void
    var onMessageTap: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            AsyncImage(url: avatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.secondary.opacity(0.2)
            }
            .frame(width: 80, height: 80)
            .clipShape(.circle)

            VStack(spacing: 4) {
                Text(name).font(.title2).bold()
                Text(handle).foregroundStyle(.secondary)
            }

            Text("\(followerCount) followers")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(isFollowing ? "Unfollow" : "Follow", action: onFollowToggle)
                    .buttonStyle(.borderedProminent)

                Button("Message", action: onMessageTap)
                    .buttonStyle(.bordered)
            }
        }
        .padding()
    }
}

// Preview with no model setup needed
#Preview {
    ProfileContentView(
        name: "Ada Lovelace",
        handle: "@ada",
        avatarURL: nil,
        followerCount: 1_843,
        isFollowing: false,
        onFollowToggle: { },
        onMessageTap: { }
    )
}
```

### Root View (wires data)

Observes the model and translates it into the content view's parameters:

```swift
struct ProfileRootView: View {
    @Environment(UserStore.self) private var store
    let userID: User.ID

    // Optional: ViewModel for complex async/error state
    @State private var viewModel: ProfileViewModel

    init(userID: User.ID) {
        self.userID = userID
        _viewModel = State(wrappedValue: ProfileViewModel(userID: userID))
    }

    var body: some View {
        Group {
            if let user = store.user(id: userID) {
                ProfileContentView(
                    name: user.displayName,
                    handle: "@\(user.username)",
                    avatarURL: user.avatarURL,
                    followerCount: user.followerCount,
                    isFollowing: store.isFollowing(userID),
                    onFollowToggle: { Task { await viewModel.toggleFollow() } },
                    onMessageTap: { viewModel.startMessage() }
                )
            } else {
                ProgressView()
            }
        }
        .task { await viewModel.load() }
        .navigationTitle("Profile")
    }
}
```

---

## What Goes in Each Layer

| Concern | Root View | Content View |
|---------|-----------|--------------|
| `@Environment` access | ✅ | ❌ |
| `@State` / ViewModel | ✅ | ❌ |
| Async data loading | ✅ | ❌ |
| Navigation push | ✅ | via callback → Root |
| Display logic | delegates to Content | ✅ |
| Accessibility labels | ✅ (when contextual) | ✅ (when static) |
| Previews | complex (needs env) | trivial |

---

## Primitives Rule

Content views receive **primitive or value types** (String, Int, URL, Bool, enums), not model objects.

**Why:**
- Previews require no model setup
- Content views are reusable across different model types
- Clear boundary: if a property changes type in the model, the Root View adapts; the Content View doesn't change
- Easier to test rendering in isolation

**Exception**: when a content view binds to many properties of a model (e.g., an edit form), pass `@Bindable var model: SomeModel` instead of individual bindings — the boilerplate of decomposing defeats the purpose.

---

## Integration with MVVM + Coordinator

In an app using the MVVM + Coordinator pattern (see `mvvm_coordinator.md`):

- **Coordinator** → manages `NavigationPath`, pushes destinations
- **ViewModel** → holds business state, calls Coordinator for navigation
- **Root View** → observes ViewModel, wires callbacks to ViewModel methods, renders Content View
- **Content View** → pure display, receives primitives, fires callbacks

```
Coordinator ←── Root View ──→ Content View
     ↑               │
  navigation     ViewModel
                 (state + logic)
```

---

## Checklist

- [ ] Each screen has a Root View (data wiring) and a Content View (display)
- [ ] Content View receives only primitive / value types
- [ ] Content View has no environment access, no async calls
- [ ] Content View is previewable without model setup
- [ ] Navigation actions flow through Root View (or Coordinator), not Content View
- [ ] Root View creates or receives the ViewModel; Content View does not
