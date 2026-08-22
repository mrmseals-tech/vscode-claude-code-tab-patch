#!/usr/bin/env bash
# Emergency rollback - restores original Claude Code extension files.
# Run this from a terminal if Claude Code breaks after patching.
# Then do Ctrl+Shift+P -> "Developer: Reload Window" in VS Code.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# This is the break-glass script, so it must still work if it has been copied
# somewhere on its own. Prefer the shared path definitions when they are next to
# us; fall back to the identical defaults inline when they are not.
if [[ -f "$HERE/claude-patch-paths.sh" ]]; then
    source "$HERE/claude-patch-paths.sh"
else
    CLAUDE_PATCH_STATE_DIR="${CLAUDE_PATCH_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/claude-code-tab-patch}"
    CLAUDE_PATCH_BACKUP_DIR="${CLAUDE_PATCH_BACKUP_DIR:-$CLAUDE_PATCH_STATE_DIR/backup}"
    CLAUDE_PATCH_EXT_DIR="${CLAUDE_PATCH_EXT_DIR:-$HOME/.vscode/extensions}"
    CLAUDE_PATCH_EXT_PATTERN="${CLAUDE_PATCH_EXT_PATTERN:-anthropic.claude-code-*}"
    claude_find_ext() {
        find "$CLAUDE_PATCH_EXT_DIR" -maxdepth 1 -type d -name "$CLAUDE_PATCH_EXT_PATTERN" 2>/dev/null | sort -V | tail -1
    }
fi

BACKUP_DIR="$CLAUDE_PATCH_BACKUP_DIR"
EXT_PATH="$(claude_find_ext)"

FAILURES=0
fail() { echo "  FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }

if [[ -z "$EXT_PATH" ]]; then
    echo "ERROR: Claude Code extension not found"
    exit 1
fi

# All three backups are required. package.json.orig used to be optional here,
# which meant a missing package.json backup silently left package.json in its
# patched state (still declaring the renameTab command + context menu) while
# extension.js/webview/index.js were reverted to vanilla underneath it — a
# broken half-rolled-back state with a command that has no registered handler.
if [[ ! -f "$BACKUP_DIR/extension.js.orig" ]] || [[ ! -f "$BACKUP_DIR/webview-index.js.orig" ]] || [[ ! -f "$BACKUP_DIR/package.json.orig" ]]; then
    echo "ERROR: Backup files not found in $BACKUP_DIR"
    echo "       All three are required: extension.js.orig, webview-index.js.orig, package.json.orig"
    exit 1
fi

echo "Restoring original files..."
cp "$BACKUP_DIR/extension.js.orig" "$EXT_PATH/extension.js" || fail "restore extension.js"
cp "$BACKUP_DIR/webview-index.js.orig" "$EXT_PATH/webview/index.js" || fail "restore webview/index.js"
cp "$BACKUP_DIR/package.json.orig" "$EXT_PATH/package.json" || fail "restore package.json"
rm -f "$EXT_PATH/resources/claude-logo-busy.svg" || fail "remove claude-logo-busy.svg resource"

echo ""
if [[ $FAILURES -gt 0 ]]; then
    echo "ROLLBACK INCOMPLETE: $FAILURES step(s) failed. See FAIL lines above."
    exit 1
fi

echo "Rollback successful: extension.js, webview/index.js, package.json restored to originals; busy-indicator resource removed."
echo "Now reload VS Code: Ctrl+Shift+P -> Developer: Reload Window"
