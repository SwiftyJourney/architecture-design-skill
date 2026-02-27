# Architecture Decision Records (ADR) — Template & Examples

ADRs document significant architectural decisions: what was decided, why, and what the trade-offs are. They are short, written at decision time, and never retroactively edited (supersede instead of rewrite).

---

## Template

```markdown
# ADR-NNN: <Short imperative title>

## Status
<!-- One of: Proposed | Accepted | Deprecated | Superseded by ADR-NNN -->
Accepted

## Context
<!-- What situation or problem forced this decision?
     1-3 sentences. Focus on forces, constraints, and the problem — not the solution. -->

## Decision
<!-- What was decided? State it clearly and directly.
     "We will..." or "We have decided to..."  -->

## Consequences

### Positive
<!-- What does this decision make easier or better? -->

### Negative
<!-- What does this decision make harder, add overhead, or trade away? -->

## Alternatives Considered
<!-- What other options were evaluated and why were they rejected? -->
```

---

## Example 1: Protocol-Based Dependency Injection

```markdown
# ADR-001: Use Protocol-Based Dependency Injection

## Status
Accepted

## Context
Business logic components need access to infrastructure (network, cache, analytics)
without creating tight coupling that would make them hard to test or replace.
We need a strategy that works consistently across all feature modules.

## Decision
We will inject all dependencies through initializers as protocol/interface types.
No component will instantiate its own dependencies. All wiring happens in the
Composition Root.

## Consequences

### Positive
- Every component can be unit-tested with test doubles (stubs, spies, fakes)
- Implementations are swappable without modifying business logic
- Dependencies are explicit and discoverable from the type signature
- Follows Dependency Inversion Principle

### Negative
- More protocol/interface definitions to maintain
- Composition Root grows as the app grows (acceptable: it's the only place)
- New team members need to understand the injection pattern before contributing

## Alternatives Considered
1. **Service Locator** — Rejected: hides dependencies, makes tests unreliable
2. **Singleton access** — Rejected: tight coupling, difficult to test in isolation
3. **Property injection** — Rejected: allows partial initialization, harder to reason about
```

---

## Example 2: Async IO Protocol Boundaries

```markdown
# ADR-002: Async Protocols for Network, Sync Protocols for Cache

## Status
Accepted

## Context
The app loads data from a remote API and a local cache. Network calls are
inherently asynchronous. Cache/store operations can be synchronous (they run
on a dedicated queue managed internally). We need a consistent strategy for
how async behavior is expressed at protocol boundaries.

## Decision
Network/IO-facing protocols use `async throws`. Cache/store-facing protocols
use synchronous `throws`. A Scheduler bridge (infrastructure concern) handles
the thread hop from synchronous store calls into async contexts when needed.

## Consequences

### Positive
- Network protocols are idiomatic: `try await client.get(url)`, no callbacks
- Store protocols are simple and easy to implement + test synchronously
- The Scheduler is an infrastructure detail — Domain stays clean
- Compiler enforces async correctness at call sites

### Negative
- Developers must understand where async lives (network) vs where it doesn't (store)
- The Scheduler adds one layer of indirection in the composition layer
- Mixing sync and async requires care not to block the main thread

## Alternatives Considered
1. **All async** — Rejected: makes store protocols and tests unnecessarily complex;
   async store protocol would require await even for in-memory implementations
2. **All sync with callbacks** — Rejected: callback chains are error-prone and
   the language provides better primitives
```

---

## Example 3: Generic Presenter Over Per-Feature Presenters

```markdown
# ADR-003: Single Generic ResourcePresenter<Resource, View> for All Features

## Status
Accepted

## Context
Each feature (feed, comments, profile, notifications) needs a presenter that:
handles loading state, maps a resource to a view model, and surfaces errors.
We had been writing a new presenter class per feature with duplicated structure.

## Decision
We will use one generic `ResourcePresenter<Resource, View>` with a `Mapper`
closure that transforms `Resource` into `View.ViewModel`. Features that need
no transformation use the identity mapper overload.

## Consequences

### Positive
- Loading/error logic is written and tested once
- New features only need to provide a mapper — no boilerplate presenter class
- Type system enforces that every feature has the same presenter contract
- `WeakRefVirtualProxy<T>` + conditional conformances give memory-safe view wrappers
  generically for free

### Negative
- Generic types add compile-time complexity; type errors can be verbose
- Developers unfamiliar with generics may struggle with the `where Resource == View.ViewModel` overload
- Debugging stack traces involving generics can be harder to read

## Alternatives Considered
1. **Per-feature presenter** — Rejected: high duplication, inconsistent error/loading behavior
2. **Base class inheritance** — Rejected: Swift favors composition; base classes create
   implicit coupling and prevent testing the base independently
```

---

## Example 4: Composition Root as Entry Point

```markdown
# ADR-004: Single Composition Root in SceneDelegate / AppEntry

## Status
Accepted

## Context
As the app grew, dependency wiring was scattered across view controllers,
environment objects, and factory methods. It became unclear where objects
were created and how to replace them in tests.

## Decision
All concrete type instantiation and dependency wiring happens in one
Composition Root class (SceneDelegate for UIKit apps; @main App struct for
SwiftUI apps). Feature modules receive protocol/interface types only.

## Consequences

### Positive
- Dependency graph is visible in one place
- End-to-end tests can inject doubles by swapping one object at the root
- Feature modules have zero knowledge of other modules' implementations
- Onboarding: one file to understand how the app is assembled

### Negative
- The Composition Root file grows with the app (manageable with helper methods)
- Initial setup requires passing dependencies through several layers
- Can become a bottleneck if multiple developers modify it simultaneously

## Alternatives Considered
1. **DI container / service locator** — Rejected: hides dependencies, makes
   accidental coupling easy, harder to trace at call sites
2. **SwiftUI Environment** — Considered for SwiftUI apps; acceptable for
   read-only shared state, but not for mutable services or protocol-typed deps
   that need test doubles
```

---

## ADR Naming and Organization

```
docs/
└── decisions/
    ├── ADR-001-dependency-injection.md
    ├── ADR-002-async-sync-boundaries.md
    ├── ADR-003-generic-presenter.md
    └── ADR-004-composition-root.md
```

**Rules:**
- Numbered sequentially — never renumber
- Short imperative title (verb + noun)
- Status must be kept current — if superseded, add "Superseded by ADR-NNN" and write the new ADR
- Write at decision time — retroactive ADRs have lower confidence

---

## What Makes a Good ADR

| Element | Good | Avoid |
|---------|------|-------|
| Title | Imperative, specific: "Use async protocols for network boundaries" | Vague: "Async decision" |
| Context | Forces and constraints that drive the choice | Restating the solution |
| Decision | Clear commitment: "We will..." | Hedging: "We might consider..." |
| Consequences | Honest about trade-offs | Only listing positives |
| Alternatives | Named and reason for rejection | "We considered other options" |
