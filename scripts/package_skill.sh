#!/bin/bash

# Architecture & Design Skill Packaging Script
# Packages the skill into a .skill file for distribution

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SKILL_DIR="$PROJECT_ROOT/architecture-design"
OUTPUT_DIR="$PROJECT_ROOT"
SKILL_FILE="architecture-design.skill"

echo "📦 Packaging Architecture & Design Skill..."

# Check if skill directory exists
if [ ! -d "$SKILL_DIR" ]; then
    echo "❌ Error: Skill directory not found at $SKILL_DIR"
    exit 1
fi

# Check if SKILL.md exists
if [ ! -f "$SKILL_DIR/SKILL.md" ]; then
    echo "❌ Error: SKILL.md not found in $SKILL_DIR"
    exit 1
fi

# Create temporary directory for packaging
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Copy skill contents to temp directory
echo "📋 Copying skill files..."
cp -r "$SKILL_DIR"/* "$TEMP_DIR/"

# Create the .skill file (zip archive)
echo "🗜️  Creating .skill archive..."
cd "$TEMP_DIR"
zip -r "$OUTPUT_DIR/$SKILL_FILE" . -x "*.DS_Store"

cd "$PROJECT_ROOT"

# Verify the package
if [ -f "$OUTPUT_DIR/$SKILL_FILE" ]; then
    SIZE=$(du -h "$OUTPUT_DIR/$SKILL_FILE" | cut -f1)
    echo "✅ Success! Package created: $SKILL_FILE ($SIZE)"
    echo "📍 Location: $OUTPUT_DIR/$SKILL_FILE"
else
    echo "❌ Error: Failed to create package"
    exit 1
fi

echo ""
echo "🎉 Packaging complete!"
echo ""
echo "To use this skill:"
echo "1. Upload $SKILL_FILE to Claude.ai"
echo "2. Or use: npx skills add SwiftyJourney/architecture-design-skill"
