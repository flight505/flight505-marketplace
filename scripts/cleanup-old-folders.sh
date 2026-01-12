#!/bin/bash
set -euo pipefail

# Cleanup old plugin folders script
# Safely removes old standalone plugin folders after marketplace migration

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         Old Folders Cleanup - flight505-marketplace      ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Get parent directory (one level up from marketplace)
PARENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "Working in: $PARENT_DIR"
echo ""

# Folders to check
FOLDERS_CLEAN=(
    "UX-UI_book"
    "nano-banana"
    "storybook-plugin-test"
    "sdk-bridge-test"
)

FOLDERS_UNCOMMITTED=(
    "sdk-bridge-marketplace"
    "claude-project-planner"
)

# Function to check if folder exists
folder_exists() {
    [ -d "$PARENT_DIR/$1" ]
}

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Folders to delete:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

CLEAN_COUNT=0
UNCOMMITTED_COUNT=0
TOTAL_SIZE=0

for folder in "${FOLDERS_CLEAN[@]}"; do
    if folder_exists "$folder"; then
        SIZE=$(du -sh "$PARENT_DIR/$folder" 2>/dev/null | awk '{print $1}')
        echo "✅ $folder (${SIZE}) - No uncommitted changes"
        ((CLEAN_COUNT++))
    fi
done

for folder in "${FOLDERS_UNCOMMITTED[@]}"; do
    if folder_exists "$folder"; then
        SIZE=$(du -sh "$PARENT_DIR/$folder" 2>/dev/null | awk '{print $1}')
        cd "$PARENT_DIR/$folder"
        UNCOMMITTED=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
        if [ "$UNCOMMITTED" -gt 0 ]; then
            echo "⚠️  $folder (${SIZE}) - $UNCOMMITTED uncommitted files"
            ((UNCOMMITTED_COUNT++))
        else
            echo "✅ $folder (${SIZE}) - Clean"
            ((CLEAN_COUNT++))
        fi
        cd "$PARENT_DIR"
    fi
done

echo ""
echo "Summary: $CLEAN_COUNT clean, $UNCOMMITTED_COUNT with uncommitted changes"
echo ""

# Handle uncommitted changes
if [ $UNCOMMITTED_COUNT -gt 0 ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Uncommitted Changes Detected"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    for folder in "${FOLDERS_UNCOMMITTED[@]}"; do
        if folder_exists "$folder"; then
            cd "$PARENT_DIR/$folder"
            UNCOMMITTED=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
            if [ "$UNCOMMITTED" -gt 0 ]; then
                echo "📂 $folder:"
                git status --short | head -5
                echo ""
            fi
            cd "$PARENT_DIR"
        fi
    done

    echo "Options:"
    echo "  1) Commit and push uncommitted changes"
    echo "  2) Create backup patches (saved to ~/Desktop)"
    echo "  3) Discard uncommitted changes (delete anyway)"
    echo "  4) Cancel (don't delete anything)"
    echo ""
    read -p "Choose option (1-4): " OPTION
    echo ""

    case $OPTION in
        1)
            echo "Committing and pushing changes..."
            for folder in "${FOLDERS_UNCOMMITTED[@]}"; do
                if folder_exists "$folder"; then
                    cd "$PARENT_DIR/$folder"
                    UNCOMMITTED=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
                    if [ "$UNCOMMITTED" -gt 0 ]; then
                        echo "  → $folder"
                        git add -A
                        git commit -m "chore: save uncommitted work before cleanup"
                        git push origin main
                    fi
                    cd "$PARENT_DIR"
                fi
            done
            echo "✅ All changes committed and pushed"
            echo ""
            ;;
        2)
            echo "Creating backup patches..."
            for folder in "${FOLDERS_UNCOMMITTED[@]}"; do
                if folder_exists "$folder"; then
                    cd "$PARENT_DIR/$folder"
                    UNCOMMITTED=$(git status --short 2>/dev/null | wc -l | tr -d ' ')
                    if [ "$UNCOMMITTED" -gt 0 ]; then
                        PATCH_FILE="$HOME/Desktop/${folder}-uncommitted-$(date +%Y%m%d-%H%M%S).patch"
                        git diff > "$PATCH_FILE"
                        echo "  → $folder: $PATCH_FILE"
                    fi
                    cd "$PARENT_DIR"
                fi
            done
            echo "✅ Patches saved to ~/Desktop"
            echo ""
            ;;
        3)
            echo "⚠️  Will discard uncommitted changes"
            echo ""
            ;;
        4)
            echo "Cancelled. No folders deleted."
            exit 0
            ;;
        *)
            echo "Invalid option. Cancelled."
            exit 1
            ;;
    esac
fi

# Final confirmation
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Ready to Delete"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "The following folders will be moved to Trash:"
echo ""

for folder in "${FOLDERS_CLEAN[@]}" "${FOLDERS_UNCOMMITTED[@]}"; do
    if folder_exists "$folder"; then
        echo "  • $folder"
    fi
done

echo ""
read -p "Proceed with deletion? (yes/no): " CONFIRM
echo ""

if [ "$CONFIRM" != "yes" ]; then
    echo "Cancelled. No folders deleted."
    exit 0
fi

# Delete folders
echo "Deleting folders..."
for folder in "${FOLDERS_CLEAN[@]}" "${FOLDERS_UNCOMMITTED[@]}"; do
    if folder_exists "$folder"; then
        echo "  → Deleting $folder"
        trash "$PARENT_DIR/$folder"
    fi
done

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                  ✅ Cleanup Complete!                     ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "Remaining structure:"
echo ""
echo "Claude_SDK/"
echo "├── flight505-marketplace/  (with submodules)"
echo "│   ├── sdk-bridge/"
echo "│   ├── storybook-assistant/"
echo "│   ├── claude-project-planner/"
echo "│   └── nano-banana/"
echo "└── (other projects...)"
echo ""
echo "All plugin work now happens in marketplace submodules."
echo "Changes auto-sync to GitHub via webhooks (30 seconds)."
