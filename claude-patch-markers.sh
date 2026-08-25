#!/usr/bin/env bash
# Single source of truth for the Claude Code patch markers.
#
# Sourced by:
#   - patch-claude-busy-indicator.sh   (Step 9 post-patch verification)
#   - auto-patch-claude.sh             (is-it-already-patched decision)
#   - verify-claude-patch.sh           (standalone self-test)
#
# WHY THIS FILE EXISTS: the three scripts used to carry their own copies of the
# marker list, and they drifted. A loose package.json marker matched the menu
# entry instead of the command definition, so a real Step 7 failure on the
# 2.1.167 update read as "fully patched" and the right-click Rename option
# silently vanished. One list, used everywhere, makes that class of bug
# impossible — fix a marker here and every consumer gets it.
#
# Each marker asserts the OUTCOME of one patch step. If you add/change a step in
# patch-claude-busy-indicator.sh, add/adjust its marker here in the same commit.

# claude_check_markers EXT_PATH [quiet]
#   Prints "OK:" / "MISSING:" lines (suppress the OK lines with the literal
#   second arg "quiet"). Sets the global CLAUDE_MARKERS_MISSING to the number of
#   failed markers. Returns 0 when all pass, 1 when any are missing.
claude_check_markers() {
    local ext="$1" quiet="${2:-}"
    local webview="$ext/webview/index.js"
    local extension="$ext/extension.js"
    local package="$ext/package.json"
    local resources="$ext/resources"
    CLAUDE_MARKERS_MISSING=0

    _cm_grep() {  # file pattern label
        if grep -qP "$2" "$1" 2>/dev/null; then
            [[ "$quiet" == "quiet" ]] || echo "  OK:      $3"
        else
            echo "  MISSING: $3"
            CLAUDE_MARKERS_MISSING=$((CLAUDE_MARKERS_MISSING + 1))
        fi
    }
    _cm_file() {  # path label
        if [[ -f "$1" ]]; then
            [[ "$quiet" == "quiet" ]] || echo "  OK:      $2"
        else
            echo "  MISSING: $2"
            CLAUDE_MARKERS_MISSING=$((CLAUDE_MARKERS_MISSING + 1))
        fi
    }

    # --- webview/index.js ---
    _cm_grep "$webview"   'isBusy:[^\s}]+\}'                                     "webview: renameTab method has isBusy param"
    # Pattern A (older): busy.value passed inline. Pattern B (2.1.167+): read into
    # _isBusy before the untracked wrapper. Either form is correctly patched.
    _cm_grep "$webview"   '_isBusy=.*?busy\.value|\.renameTab\([^)]*busy\.value' "webview: reactive watcher passes busy.value"
    _cm_grep "$webview"   'renameTab=\([^)]+,[^)]+,[^)]+,[^)]+\)=>'              "webview: renameTab wrapper has 4 params"

    # --- extension.js ---
    _cm_grep "$extension" 'claude-logo-busy\.svg'                               "extension: busy icon selection"
    # [\w\$]+ not \w+: a minified identifier can be "$" (esbuild names the message
    # handler binding "$" as of 2.1.245), which \w does not match. Same reason as
    # the IDENTIFIER CHARSET note in patch-claude-busy-indicator.sh.
    _cm_grep "$extension" '_customTitle\|\|[\w\$]+\.request\.title'            "extension: sticky custom title"
    _cm_grep "$extension" 'claude-vscode\.renameTab'                            "extension: renameTab command registered"
    # Anchored on "_st" — the literal, hardcoded local var name Step 6 uses in its
    # injected restore block (this._st, not a minified-per-version placeholder).
    # Step 5's independently-similar text uses "titles"/"ct" instead, so this
    # cannot be satisfied by Step 5 alone the way the old 'customTabTitles.*_customTitle'
    # pattern could (that pattern matched Step 5's own injected renameTab command
    # handler, which also happens to contain both substrings — a 2.1.167-class
    # false pass, found in audit and fixed here).
    _cm_grep "$extension" '_st=this\.context\.globalState\.get\("customTabTitles"\).*?_st\.includes\(' "extension: panel restore logic"

    # --- package.json ---
    # Assert the command DEFINITION via its title string — it appears ONLY in the
    # command def, never in the menu entry. A bare "claude-vscode.renameTab" match
    # would also hit the menu entry and mask a missing definition (the 2.1.167 bug).
    _cm_grep "$package"   'Claude Code: Rename Tab'                             "package.json: renameTab command DEF (title)"
    _cm_grep "$package"   'editor/title/context'                               "package.json: right-click context menu"

    # --- resource file ---
    _cm_file "$resources/claude-logo-busy.svg"                                 "resources: claude-logo-busy.svg exists"

    [[ "$CLAUDE_MARKERS_MISSING" -eq 0 ]]
}
