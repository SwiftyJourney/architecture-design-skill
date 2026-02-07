# Quick Start Guide

Get started with the Architecture & Design Principles Skill in 5 minutes.

---

## Installation

### Option 1: Skills CLI (Recommended)

```bash
npx skills add SwiftyJourney/architecture-design-skill
```

### Option 2: Manual

Download `architecture-design.skill` from [Releases](https://github.com/SwiftyJourney/architecture-design-skill/releases) and upload to your AI tool.

---

## First Use

Try this prompt:

```
Help me refactor this God class to follow SOLID principles:

class UserManager {
    func loginUser() { }
    func saveUserData() { }
    func sendEmail() { }
    func logActivity() { }
}
```

The skill will:
1. Identify SRP violations
2. Suggest proper separation
3. Show Clean Architecture layers
4. Provide testing strategy

---

## Common Prompts

### SOLID Principles
```
"Help me apply Single Responsibility Principle to this class"
"Show me an example of Open/Closed Principle"
"What's Dependency Inversion and when should I use it?"
```

### Clean Architecture
```
"How do I structure this feature with Clean Architecture?"
"Explain the dependency rule with a diagram"
"Show me a Composition Root example"
```

### Testing
```
"How do I test this without mocking everything?"
"What's the Null Object Pattern?"
"Show me the testing pyramid for this feature"
```

### Design Patterns
```
"When should I use the Adapter pattern?"
"Show me Decorator vs Composite"
"Explain Command-Query Separation"
```

---

## What You Get

When using this skill, Claude will:

✅ Analyze your code structure  
✅ Identify architectural issues  
✅ Suggest Clean Architecture layers  
✅ Provide SOLID-compliant refactoring  
✅ Show testing strategies  
✅ Give real-world examples  

---

## Example Output

**Input:**
```
How do I cache this feed loader?
```

**Output:**
- Decorator pattern explanation
- Code example from Essential Feed
- Clean Architecture placement
- Testing with Null Object Pattern
- Command-Query Separation guidance

---

## Next Steps

- Read [Installation Guide](INSTALLATION.md) for detailed setup
- See [README](../README.md) for complete feature list
- Check [examples](../examples/) for real-world code

---

**Ready to build clean architecture?** Start refactoring! ✨
