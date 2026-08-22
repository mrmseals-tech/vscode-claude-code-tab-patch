#!/usr/bin/env bash
# Auto-patch wrapper for Claude Code VS Code extension.
# Called by systemd path unit when ~/.vscode/extensions/ changes.
# Only runs the patch if the latest extension version is unpatched.
# Verifies ALL patch markers, not just one — catches partial failures.

set -euo pipefail

LOG_TAG="claude-auto-patch"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/claude-patch-paths.sh"

EXT_DIR="$CLAUDE_PATCH_EXT_DIR"
PATCH_SCRIPT="$HERE/patch-claude-busy-indicator.sh"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1"; }

# Find the latest Claude Code extension directory
EXT_PATH="$(claude_find_ext)"

if [[ -z "$EXT_PATH" ]]; then
    log "No Claude Code extension found, skipping"
    exit 0
fi

EXTENSION="$EXT_PATH/extension.js"
WEBVIEW="$EXT_PATH/webview/index.js"
PACKAGE="$EXT_PATH/package.json"

if [[ ! -f "$EXTENSION" || ! -f "$WEBVIEW" ]]; then
    log "extension.js or webview/index.js not found in $EXT_PATH, skipping"
    exit 0
fi

# Decide whether a (re)patch is needed by asserting the COMPLETE marker set
# (single source of truth — see claude-patch-markers.sh). The previous inline
# subset is exactly what let a partial failure slip through as "fully patched".
source "$HERE/claude-patch-markers.sh"

if claude_check_markers "$EXT_PATH" quiet; then
    log "Fully patched: $(basename "$EXT_PATH")"
    exit 0
fi

log "Unpatched/partially patched ($CLAUDE_MARKERS_MISSING marker(s) missing): $(basename "$EXT_PATH")"
log "Running patch script..."

# Only clear backups when the extension version has genuinely changed since they
# were captured (a real VS Code update -> genuinely vanilla files to back up).
# Retrying the patch against the SAME version (e.g. a prior partial failure, or
# the path unit firing more than once during one update) must NEVER wipe a
# still-valid backup — that silently corrupted the safety net: the patch script's
# "no backup exists" check would then re-capture whatever the CURRENT
# (already-partially-or-fully-patched) files looked like as the new ".orig",
# so rollback would restore already-patched content instead of vanilla.
# Tracked via a small sentinel file recording which extension dir the current
# backups belong to; patch-claude-busy-indicator.sh writes/refreshes it
# whenever it actually captures a fresh backup.
BACKUP_DIR="$CLAUDE_PATCH_BACKUP_DIR"
VERSION_FILE="$BACKUP_DIR/.version"
CURRENT_VER="$(basename "$EXT_PATH")"
mkdir -p "$BACKUP_DIR"

if [[ -f "$VERSION_FILE" ]]; then
    RECORDED_VER="$(cat "$VERSION_FILE")"
    if [[ "$RECORDED_VER" != "$CURRENT_VER" ]]; then
        log "Extension version changed ($RECORDED_VER -> $CURRENT_VER) — clearing stale backups"
        rm -f "$BACKUP_DIR"/*.orig "$VERSION_FILE"
    else
        log "Backups already match $CURRENT_VER — leaving them untouched; letting the idempotent patch fill in whatever's still missing"
    fi
elif [[ -f "$BACKUP_DIR/extension.js.orig" ]]; then
    # Backups exist but pre-date version tracking (e.g. first run after this fix
    # was deployed). We can't know for certain which version they came from —
    # assume they match the current extension (the common case: they were made
    # against it) and start tracking from here, rather than blindly wiping what
    # may be the only real original on disk.
    log "Untagged backups found (pre-date version tracking) — adopting them as belonging to $CURRENT_VER"
    echo "$CURRENT_VER" > "$VERSION_FILE"
else
    log "No existing backups — patch script will create fresh ones for $CURRENT_VER"
fi

if bash "$PATCH_SCRIPT" 2>&1; then
    log "Patch script reported success"
else
    rc=$?
    log "WARNING: patch script exited non-zero ($rc) — self-test will confirm final state"
fi

# Final authority + visible escalation: assert the FULL marker set via the
# self-test, which fires a persistent critical notification and writes a BROKEN
# flag file on any miss. This is what guarantees a half-applied patch can't pass
# unnoticed again.
if bash "$HERE/verify-claude-patch.sh"; then
    log "Self-test PASSED — fully patched and verified"
    if command -v notify-send &>/dev/null; then
        notify-send -u normal -t 10000 \
            "Claude Code Patched" \
            "$(basename "$EXT_PATH") patched and verified.\nReload VS Code to apply."
    fi
    exit 0
else
    log "ERROR: self-test FAILED after patch — see claude-patch-BROKEN.flag and journalctl --user -u claude-auto-patch"
    exit 1
fi
