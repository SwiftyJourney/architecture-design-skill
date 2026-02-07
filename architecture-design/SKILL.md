---
name: architecture-design
version: 1.0.0
description: Transform code into clean, testable architecture using SOLID principles, Clean Architecture, and proven design patterns
author: SwiftyJourney
tags:
  - architecture
  - clean-architecture
  - solid
  - design-patterns
  - testing
  - dependency-injection
  - swift
---

# Architecture & Design Principles Skill

Transform codebases into maintainable, testable, and scalable architectures using Clean Architecture principles, SOLID design patterns, and industry best practices from the Essential Developer methodology.

## Overview

This skill guides you through a structured 5-step process to:

1. **Analyze Requirements** → Identify components, responsibilities, and boundaries
2. **Apply SOLID Principles** → Design with SRP, OCP, LSP, ISP, DIP
3. **Define Clean Architecture** → Establish layers, boundaries, and dependency rules
4. **Design Testing Strategy** → Plan unit tests, integration tests, and test boundaries
5. **Document Decisions** → Create Architecture Decision Records (ADRs)

## When to Use This Skill

Use this skill when you need to:

- Refactor legacy code into clean architecture
- Design a new feature with proper separation of concerns
- Review existing architecture for SOLID violations
- Create testable components with clear boundaries
- Document architectural decisions
- Establish dependency injection patterns
- Plan modular design strategies

## Core Philosophy

> "Good architecture is a byproduct of good team processes and communication"

This skill follows these principles:

- **Framework Independence** - Business logic doesn't depend on frameworks
- **Testability** - Architecture enables easy testing
- **UI Independence** - UI can change without affecting business rules
- **Database Independence** - Business rules don't know about the database
- **External Agency Independence** - Business rules don't depend on external services

## The 5-Step Process

### Step 1: Analyze Requirements

**Objective**: Identify components, responsibilities, and architectural boundaries

**Actions**:
1. Break down feature into distinct responsibilities
2. Identify core business logic vs infrastructure concerns
3. Recognize cross-cutting concerns (logging, analytics, caching)
4. Map data flow through the system
5. Identify potential architectural boundaries

**Key Questions to Ask**:
- What is the core business logic?
- What are the external dependencies (network, database, UI)?
- What needs to be testable in isolation?
- What components might change independently?
- What are the inputs and outputs of each component?

**Output**: Component diagram with clear responsibilities

**Reference**: See `references/modular_design.md` for component identification patterns

---

### Step 2: Apply SOLID Principles

**Objective**: Design components following SOLID principles

**SOLID Breakdown**:

#### S - Single Responsibility Principle (SRP)
- Each class/module has one reason to change
- Separate business logic from infrastructure
- One responsibility per component

**Example Violations**:
- ❌ A class that loads data AND presents it
- ❌ A view controller that makes network requests
- ❌ A model that knows how to save itself

**Example Solutions**:
- ✅ Separate UseCase for business logic
- ✅ Separate Loader for data fetching
- ✅ Separate Presenter for view logic

#### O - Open/Closed Principle (OCP)
- Open for extension, closed for modification
- Use protocols/interfaces for abstraction
- Compose behaviors instead of inheritance

**Example Pattern**:
```swift
// Open for extension via protocols
protocol FeedLoader {
    func load(completion: @escaping (Result<[FeedItem], Error>) -> Void)
}

// Closed for modification - implementations extend behavior
class RemoteFeedLoader: FeedLoader { ... }
class LocalFeedLoader: FeedLoader { ... }
class FallbackFeedLoader: FeedLoader { ... }
```

#### L - Liskov Substitution Principle (LSP)
- Subtypes must be substitutable for base types
- Contracts must be honored by implementations
- No surprising behavior in substitutions

#### I - Interface Segregation Principle (ISP)
- Clients shouldn't depend on interfaces they don't use
- Create focused, specific interfaces
- Avoid fat interfaces

**Example**:
```swift
// ❌ Fat interface
protocol DataStore {
    func save(_ data: Data)
    func load() -> Data
    func delete()
    func migrate()
    func backup()
}

// ✅ Segregated interfaces
protocol DataSaver {
    func save(_ data: Data)
}

protocol DataLoader {
    func load() -> Data
}
```

#### D - Dependency Inversion Principle (DIP)
- High-level modules don't depend on low-level modules
- Both depend on abstractions
- Abstractions don't depend on details

**Example**:
```swift
// High-level policy
class FeedViewController {
    private let loader: FeedLoader  // Depends on abstraction
    
    init(loader: FeedLoader) {
        self.loader = loader
    }
}

// Low-level detail
class APIFeedLoader: FeedLoader { ... }
```

**Output**: SOLID-compliant component design

**Reference**: See `references/solid_principles.md` for detailed patterns and anti-patterns

---

### Step 3: Define Clean Architecture

**Objective**: Establish clear architectural layers with proper dependency flow

**The Clean Architecture Layers**:

```
┌─────────────────────────────────────────┐
│          Presentation Layer             │
│    (UI, ViewModels, Presenters)        │
└─────────────────┬───────────────────────┘
                  │ depends on
┌─────────────────▼───────────────────────┐
│         Domain/Business Layer           │
│      (Use Cases, Entities, Rules)      │
└─────────────────┬───────────────────────┘
                  │ depends on
┌─────────────────▼───────────────────────┐
│         Infrastructure Layer            │
│   (Network, Database, Framework Code)  │
└─────────────────────────────────────────┘
```

**Dependency Rule**: Source code dependencies point **inward only**

**Key Patterns**:

1. **Use Cases (Interactors)**
   - Contain business rules
   - Orchestrate data flow
   - Independent of UI and frameworks

2. **Boundaries (Protocols/Interfaces)**
   - Define contracts between layers
   - Enable testability and flexibility
   - Invert dependencies

3. **Adapters**
   - Convert data between layers
   - Implement boundary protocols
   - Handle framework-specific code

4. **Composition Root**
   - Wire dependencies together
   - Configure the object graph
   - Keep business logic clean

**Example Structure**:
```
Feature/
├── Domain/
│   ├── UseCases/
│   │   └── LoadFeedUseCase.swift
│   ├── Entities/
│   │   └── FeedItem.swift
│   └── Boundaries/
│       └── FeedLoader.swift
├── Infrastructure/
│   ├── Network/
│   │   └── RemoteFeedLoader.swift
│   └── Cache/
│       └── LocalFeedLoader.swift
└── Presentation/
    ├── Views/
    │   └── FeedViewController.swift
    └── Presenters/
        └── FeedPresenter.swift
```

**Output**: Layered architecture with clear boundaries

**Reference**: See `references/clean_architecture.md` for detailed layer definitions

---

### Step 4: Design Testing Strategy

**Objective**: Plan comprehensive testing at all architectural layers

**Testing Pyramid**:

```
        ┌──────────┐
        │    UI    │ Few - End to End
        ├──────────┤
        │Integration│ Some - Integration
        ├──────────┤
        │   Unit   │ Many - Fast & Isolated
        └──────────┘
```

**Testing Boundaries**:

1. **Domain Layer Testing** (Unit Tests)
   - Test use cases in isolation
   - Mock all dependencies
   - Fast, reliable, independent

2. **Infrastructure Layer Testing** (Integration Tests)
   - Test adapters with real dependencies
   - Test network, database, etc.
   - May be slower, still valuable

3. **Presentation Layer Testing** (Unit Tests)
   - Test presenters/view models in isolation
   - Mock use cases and boundaries
   - Verify UI logic without UI framework

**Key Testing Patterns**:

**Test Doubles**:
- **Stubs**: Provide canned answers
- **Spies**: Record calls for verification
- **Mocks**: Verify behavior expectations
- **Fakes**: Working implementations for testing

**Example Test Structure**:
```swift
class LoadFeedUseCaseTests: XCTestCase {
    func test_load_deliversItemsOnLoaderSuccess() {
        let (sut, loader) = makeSUT()
        let items = [makeItem(), makeItem()]
        
        expect(sut, toCompleteWith: .success(items), when: {
            loader.complete(with: items)
        })
    }
    
    func test_load_deliversErrorOnLoaderFailure() {
        let (sut, loader) = makeSUT()
        
        expect(sut, toCompleteWith: .failure(anyError()), when: {
            loader.complete(with: anyError())
        })
    }
    
    // MARK: - Helpers
    
    private func makeSUT() -> (sut: LoadFeedUseCase, loader: LoaderSpy) {
        let loader = LoaderSpy()
        let sut = LoadFeedUseCase(loader: loader)
        return (sut, loader)
    }
}
```

**Testing Strategies**:
- Test behavior, not implementation
- Test one thing at a time
- Use descriptive test names
- Arrange, Act, Assert pattern
- Extract helper methods for clarity

**Output**: Comprehensive testing strategy document

**Reference**: See `references/testing_strategies.md` for patterns and best practices

---

### Step 5: Document Decisions

**Objective**: Create clear architectural documentation and decision records

**Architecture Decision Records (ADRs)**:

Document key architectural decisions using this format:

```markdown
# ADR-001: Use Protocol-Based Dependency Injection

## Status
Accepted

## Context
We need a way to decouple high-level business logic from low-level infrastructure 
details while maintaining testability and flexibility.

## Decision
We will use protocol-based dependency injection throughout the codebase. All 
dependencies will be injected through initializers, and abstractions will be 
defined as Swift protocols.

## Consequences

### Positive
- Enables easy unit testing with test doubles
- Allows runtime composition of different implementations
- Follows Dependency Inversion Principle
- Makes dependencies explicit and clear

### Negative
- More protocols to maintain
- Requires composition root configuration
- Initial learning curve for team members

## Alternatives Considered
1. Service Locator pattern - Rejected due to hidden dependencies
2. Property injection - Rejected due to optional dependencies
3. Concrete types - Rejected due to tight coupling
```

**Documentation Requirements**:

1. **Architecture Overview**
   - System context diagram
   - Component diagram
   - Layer relationships

2. **Component Documentation**
   - Purpose and responsibilities
   - Dependencies and boundaries
   - Usage examples

3. **Design Patterns Used**
   - Which patterns and why
   - Implementation examples
   - Trade-offs considered

4. **Testing Strategy**
   - What gets tested and how
   - Test organization
   - Mock/stub strategies

**Output**: Complete architectural documentation

**Reference**: See `examples/` for real-world examples

---

## Best Practices

### DO ✅

- Separate business logic from infrastructure
- Depend on abstractions, not concretions
- Make dependencies explicit through injection
- Write tests for all business logic
- Keep components small and focused
- Document significant decisions
- Use composition over inheritance
- Design for testability from the start

### DON'T ❌

- Let business logic depend on frameworks
- Use singletons for dependency management
- Skip testing because "it's too hard"
- Mix presentation and business logic
- Create god classes with multiple responsibilities
- Couple modules tightly together
- Ignore the Single Responsibility Principle
- Make untestable components

---

## Common Architectural Patterns

This skill supports various architectural patterns:

1. **Clean Architecture** (Recommended)
   - Clear separation of concerns
   - Dependency rule: inward only
   - Framework independence

2. **Hexagonal Architecture (Ports & Adapters)**
   - Business logic at the center
   - Ports define boundaries
   - Adapters implement ports

3. **MVVM (Model-View-ViewModel)**
   - Separation of UI and logic
   - Testable view models
   - Data binding support

4. **MVC (Model-View-Controller)**
   - Traditional separation
   - Can be combined with Clean Architecture
   - Controller as composition root

**Reference**: See `examples/generic/` for pattern implementations

---

## Integration with Requirements Engineering

This skill works seamlessly with the Requirements Engineering Skill:

1. Start with requirements → Use Cases → BDD scenarios
2. Apply this skill → Architecture → Component design
3. Implement → Following architectural patterns
4. Test → Using defined testing strategy

---

## Language-Specific Guidance

### Swift/iOS
- Use protocols for abstractions
- Leverage Swift's value types
- Apply Composition Root pattern in AppDelegate/SceneDelegate
- Use dependency injection containers if needed

**Reference**: See `examples/swift/` for Swift-specific patterns

### Generic/Agnostic
- Apply SOLID principles universally
- Use interfaces/traits/protocols depending on language
- Adapt patterns to language features
- Maintain Clean Architecture layers

**Reference**: See `examples/generic/` for language-agnostic examples

---

## References

Inside the `references/` directory, you'll find:

- **clean_architecture.md** - Clean Architecture layers and rules
- **solid_principles.md** - Detailed SOLID explanations with examples
- **design_patterns.md** - Common patterns (Adapter, Decorator, Composite, Null Object, etc.)
- **null_object_pattern.md** - Null Object Pattern in detail with testing examples
- **command_query_separation.md** - CQS principle for cache design
- **dependency_management.md** - DI patterns and strategies
- **testing_strategies.md** - Testing patterns and best practices
- **modular_design.md** - Module organization and boundaries

Inside the `examples/` directory:

- **swift/** - Real implementations from Essential Feed
- **generic/** - Language-agnostic examples

---

## Output Format

When applying this skill, provide:

1. **Component Analysis** - Identified components and responsibilities
2. **SOLID Review** - Applied principles with rationale
3. **Architecture Diagram** - Layers and dependencies (Mermaid)
4. **Testing Strategy** - Test structure and coverage plan
5. **ADRs** - Key decisions documented
6. **Implementation Guide** - Step-by-step refactoring or implementation plan

---

## Credits

Based on the Essential Developer's proven architecture methodology:
- [Essential Feed Case Study](https://github.com/essentialdevelopercom/essential-feed-case-study)
- [Essential Developer Resources](https://www.essentialdeveloper.com/)

---

## Version History

- **1.0.0** - Initial release with 5-step process
