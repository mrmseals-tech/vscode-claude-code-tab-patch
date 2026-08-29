#!/usr/bin/env bash
# Single source of truth for every filesystem path these scripts use.
#
# Sourced by:
#   - patch-claude-busy-indicator.sh
#   - auto-patch-claude.sh
#   - verify-claude-patch.sh
#   - claude-rollback.sh            (defensively — see the fallback there)
#
# WHY THIS FILE EXISTS: same reason as claude-patch-markers.sh. These paths were
# previously spelled out inline in four scripts, and a stale copy in one of them
# printed a recovery command pointing at a file that did not exist — at exactly
# the moment you needed it to work. One definition, sourced everywhere.
#
# Everything is overridable from the environment, so nothing here assumes a
# particular checkout location:
#
#   CLAUDE_PATCH_STATE_DIR   where backups + the BROKEN flag live
#   CLAUDE_PATCH_BACKUP_DIR  vanilla extension files, for rollback
#   CLAUDE_PATCH_FLAG        self-test failure marker
#   CLAUDE_PATCH_EXT_DIR     VS Code extensions dir (see the variants below)
#   CLAUDE_PATCH_EXT_PATTERN glob identifying the Claude Code extension dir

CLAUDE_PATCH_STATE_DIR="${CLAUDE_PATCH_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/claude-code-tab-patch}"
CLAUDE_PATCH_BACKUP_DIR="${CLAUDE_PATCH_BACKUP_DIR:-$CLAUDE_PATCH_STATE_DIR/backup}"
CLAUDE_PATCH_FLAG="${CLAUDE_PATCH_FLAG:-$CLAUDE_PATCH_STATE_DIR/claude-patch-BROKEN.flag}"

# VS Code stores extensions in a different directory per build. Override
# CLAUDE_PATCH_EXT_DIR for anything that is not stock desktop VS Code:
#   VS Code Insiders   ~/.vscode-insiders/extensions
#   VSCodium / OSS     ~/.vscode-oss/extensions
#   Remote SSH host    ~/.vscode-server/extensions
#   Cursor             ~/.cursor/extensions
CLAUDE_PATCH_EXT_DIR="${CLAUDE_PATCH_EXT_DIR:-$HOME/.vscode/extensions}"
CLAUDE_PATCH_EXT_PATTERN="${CLAUDE_PATCH_EXT_PATTERN:-anthropic.claude-code-*}"

# claude_find_ext — echo the newest installed Claude Code extension directory,
# or nothing at all when none is present. Callers decide whether that is fatal.
claude_find_ext() {
    # The trailing "|| true" matters: callers run under "set -e -o pipefail"
    # and take this through a command substitution, so a non-zero find aborts
    # their ENTIRE script with no message and no trace. find returns 1 for
    # reasons unrelated to the result, e.g. "Failed to restore initial working
    # directory" when invoked from a cwd the running user cannot read. Report
    # nothing found and let the caller produce the real diagnostic.
    find "$CLAUDE_PATCH_EXT_DIR" -maxdepth 1 -type d -name "$CLAUDE_PATCH_EXT_PATTERN" 2>/dev/null | sort -V | tail -1 || true
}
