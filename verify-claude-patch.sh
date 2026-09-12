#!/usr/bin/env bash
# Self-test for the Claude Code VS Code extension patch.
#
# Asserts the COMPLETE marker set (all 16 — every patch step), not the smaller
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
# It then runs test-icon-precedence.js, a BEHAVIOUR gate: markers prove our
# edits are present, not that they are correct. The orange-while-working bug
# had all 16 markers green, so presence and correctness are checked separately.
# Exit status: 0 = markers present and behaviour correct, 1 = either failed.

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

# --- behaviour gate -------------------------------------------------------
# Markers are greps: they assert our edits EXIST. They structurally cannot
# assert the icon precedence is right, and that gap shipped a bug (busy arm
# below upstream's done arm -> orange tab for the whole turn, 16/16 green).
# test-icon-precedence.js evaluates the real classifier and checks which icon
# each flag combination resolves to. See that file's header for the full story.
#
# Its exit codes are meaningful and must NOT be collapsed:
#   0  every case passed
#   1  our arm is present but resolves to the wrong icon
#   2  our arm is absent — a direct contradiction of green markers
#   3  (ours) the test could not run here at all: no node, or file missing
BEHAVIOUR_TEST="$HERE/test-icon-precedence.js"
BEHAVIOUR_OUT=""
run_behaviour_test() {
    [[ -f "$BEHAVIOUR_TEST" ]] || { BEHAVIOUR_OUT="test-icon-precedence.js not found beside this script"; return 3; }
    command -v node &>/dev/null  || { BEHAVIOUR_OUT="node is not installed on this host"; return 3; }
    BEHAVIOUR_OUT="$(node "$BEHAVIOUR_TEST" "$EXT_PATH/extension.js" 2>&1)"
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
    run_behaviour_test
    case "$?" in
        0)  echo "$BEHAVIOUR_OUT" ;;
        3)  # Cannot run != passed. Say so plainly rather than imply coverage
            # this host does not have.
            echo "SKIP: icon-precedence behaviour test not run — $BEHAVIOUR_OUT."
            echo "      Markers are green; icon PRECEDENCE is unverified here." ;;
        *)  echo "$BEHAVIOUR_OUT"
            echo ""
            echo "FAIL: markers are all present but the icon precedence is WRONG ($VER)."
            echo "This is the orange-while-working class of bug: the patch applied, but"
            echo "the busy branch is in the wrong position or resolves to no icon."
            mkdir -p "$(dirname "$FLAG")"
            {
                echo "Claude Code patch behaviour test FAILED"
                echo "when:      $(date '+%Y-%m-%d %H:%M:%S')"
                echo "extension: $VER"
                echo "note:      all 16 markers PRESENT — this is a precedence/behaviour failure"
                echo ""
                echo "$BEHAVIOUR_OUT"
                echo ""
                echo "To re-apply:  bash $HERE/patch-claude-busy-indicator.sh"
                echo "To roll back: bash $ROLLBACK   (then reload VS Code)"
            } > "$FLAG"
            echo ""
            echo "Wrote details to: $FLAG"
            notify_critical "Claude Code patch BEHAVIOUR BROKEN" \
                "$VER: markers green but tab icon precedence is wrong.
See $FLAG"
            exit 1 ;;
    esac
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
