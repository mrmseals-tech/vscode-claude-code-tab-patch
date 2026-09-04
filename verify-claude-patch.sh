#!/usr/bin/env bash
# Self-test for the Claude Code VS Code extension patch.
#
# Asserts the COMPLETE marker set (all 15 — every patch step), not the smaller
# subset the auto-patcher uses for its is-it-patched decision. Run it any time:
#
#   ./verify-claude-patch.sh
#
# and it is invoked automatically by auto-patch-claude.sh after every patch.
#
# On any missing marker it escalates VISIBLY so a half-applied patch can't go
# unnoticed the way the 2.1.167 command-definition failure did:
#   - a PERSISTENT critical desktop notification (stays until dismissed)
#   - a BROKEN flag file you (or a shell prompt) can spot
#   - a clear, per-marker report to stdout + the systemd journal
# Exit status: 0 = all markers present, 1 = at least one missing.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/claude-patch-paths.sh"
source "$HERE/claude-patch-markers.sh"

EXT_DIR="$CLAUDE_PATCH_EXT_DIR"
FLAG="$CLAUDE_PATCH_FLAG"
# Resolve the rollback script next to this one. It was once hardcoded to an
# absolute path where no such file existed — so the recovery command printed
# into the BROKEN flag would itself fail at the exact moment you needed it.
# Keep it $HERE-relative like the re-apply command below.
ROLLBACK="$HERE/claude-rollback.sh"

notify_critical() {  # title body
    command -v notify-send &>/dev/null || return 0
    notify-send -u critical -t 0 "$1" "$2" 2>/dev/null || true
}

EXT_PATH="$(claude_find_ext)"
if [[ -z "$EXT_PATH" ]]; then
    echo "No Claude Code extension found in $EXT_DIR — nothing to verify."
    exit 0
fi

VER="$(basename "$EXT_PATH")"
echo "Self-test: $VER"
echo ""

if claude_check_markers "$EXT_PATH"; then
    echo ""
    echo "PASS: all patch markers present ($VER)."
    # Clear any stale failure flag from a previous broken run.
    if [[ -f "$FLAG" ]]; then
        rm -f "$FLAG"
        echo "Cleared previous failure flag."
    fi
    exit 0
fi

# --- failure path: escalate loudly ---
echo ""
echo "FAIL: $CLAUDE_MARKERS_MISSING patch marker(s) MISSING on $VER."
echo "The rename-tab / busy-indicator patch is partially applied or broken."

mkdir -p "$(dirname "$FLAG")"
{
    echo "Claude Code patch self-test FAILED"
    echo "when:      $(date '+%Y-%m-%d %H:%M:%S')"
    echo "extension: $VER"
    echo "missing:   $CLAUDE_MARKERS_MISSING marker(s) — see 'MISSING:' lines below"
    echo ""
    claude_check_markers "$EXT_PATH" quiet
    echo ""
    echo "To re-apply:  bash $HERE/patch-claude-busy-indicator.sh"
    echo "To roll back: bash $ROLLBACK   (then reload VS Code)"
} > "$FLAG"

echo ""
echo "Wrote details to: $FLAG"

notify_critical "Claude Code patch BROKEN" \
    "$VER: $CLAUDE_MARKERS_MISSING marker(s) missing.
See $FLAG
Re-run: verify-claude-patch.sh"

exit 1
