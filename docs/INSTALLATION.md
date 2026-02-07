# Installation Guide

Detailed installation instructions for all supported tools.

---

## Prerequisites

- AI agent tool that supports [Agent Skills open format](https://agentskills.io)
- For CLI: Node.js installed (for `npx` command)

---

## Option A: Using Skills CLI (Recommended)

The easiest way to install:

```bash
npx skills add SwiftyJourney/architecture-design-skill
```

This automatically:
- Downloads the skill
- Installs it in the correct location
- Makes it available to your AI tools

**Supports:**
- Claude Code
- Cursor
- Windsurf
- Other CLI-compatible tools

---

## Option B: Manual Installation

### For Claude.ai

1. **Download the skill file:**
   - Go to [Releases](https://github.com/SwiftyJourney/architecture-design-skill/releases)
   - Download `architecture-design.skill` from the latest release

2. **Upload to Claude:**
   - Open https://claude.ai
   - Go to Settings → Features
   - Click "Upload Skill"
   - Select `architecture-design.skill`

3. **Verify:**
   - Start a new chat
   - Try: "Help me apply SOLID principles"
   - Claude should use the skill automatically

### For Claude Code

```bash
# Clone the repository
git clone https://github.com/SwiftyJourney/architecture-design-skill.git

# Copy to Claude Code skills directory
mkdir -p ~/.anthropic/skills
cp -r architecture-design-skill/architecture-design ~/.anthropic/skills/

# Restart Claude Code
```

### For Cursor

```bash
# Clone the repository
git clone https://github.com/SwiftyJourney/architecture-design-skill.git

# Copy to Cursor skills directory (Mac)
mkdir -p ~/Library/Application\ Support/Cursor/User/globalStorage/skills/
cp -r architecture-design-skill/architecture-design ~/Library/Application\ Support/Cursor/User/globalStorage/skills/

# Restart Cursor
```

### For Windsurf

```bash
# Clone the repository
git clone https://github.com/SwiftyJourney/architecture-design-skill.git

# Copy to Windsurf skills directory
cp -r architecture-design-skill/architecture-design ~/.windsurf/skills/

# Restart Windsurf
```

---

## Verification

After installation, verify the skill works:

```
Test prompt: "Help me apply the Single Responsibility Principle"
```

You should get:
- Explanation of SRP
- Examples
- Anti-patterns to avoid
- Refactoring suggestions

---

## Troubleshooting

### Skill not recognized

**Solutions:**
1. Verify the skill is in the correct directory
2. Restart your AI tool
3. Try with a direct prompt about architecture

### Installation failed

**Solutions:**
1. Update Node.js: `npm install -g npm`
2. Try manual installation instead

---

## Next Steps

- [Quick Start Guide](QUICKSTART.md) - Get started in 5 minutes
- [README](../README.md) - Complete documentation
- [Examples](../examples/) - Real-world usage

---

**Having trouble?** Open an issue! 🚀
