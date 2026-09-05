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
    # Multiline variant. With -z the whole file is a single record, so \s* can
    # span newlines — needed to assert a JSON object's shape rather than a bare
    # substring that a different block could satisfy.
    _cm_grepz() {  # file pattern label
        if grep -qPz "$2" "$1" 2>/dev/null; then
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
    # Background-subagent arm (Edits B/D/E/F). session.busy alone goes false at
    # the result bookend, so an async subagent that outlives its parent turn is
    # invisible to the tab; these four assert the _bgBusy path that covers it.
    # All four must hold together — _bgBusy without its feed is a dead signal,
    # and the feed without the renameTab arm never reaches the badge, so a
    # partial application has to read as MISSING rather than as patched.
    _cm_grep "$webview"   '_bgBusy=[\w\$]+\(!1\)'                                "webview: session has _bgBusy signal"
    _cm_grep "$webview"   'background_tasks_changed"\)this\._bgBusy\.value='     "webview: background_tasks_changed feeds _bgBusy"
    _cm_grep "$webview"   '_bgBusy\.value\?\?!1\)'                               "webview: renameTab busy includes background work"
    _cm_grep "$webview"   'resetPerProcessState\(\)\{if\(this\._bgBusy\.value=!1' "webview: _bgBusy cleared on process end"

    # --- extension.js ---
    # Step 3a's feed, asserted separately from the branch it feeds. 2.1.260
    # hoisted icon selection into applyTabIcon(), which reads a STORED
    # this.lastRenameTabFlags that upstream fills with its own two flags only —
    # so a busy branch without isBusy in that object is a dead test that can
    # never fire, and the marker below would pass straight over it. The second
    # alternative covers the pre-2.1.260 inline shape, where the branch reads
    # the request field directly and no flags object exists.
    _cm_grep "$extension" 'lastRenameTabFlags=\{[^}]*isBusy:|\.request\.isBusy\)[\w\$]+="claude-logo-busy\.svg"' "extension: isBusy reaches icon selection"
    # 2.1.261 replaced the if/else icon chain with a classifier returning a KEY
    # plus a lookup table, so the busy icon now takes TWO edits that must be
    # asserted separately. Either half alone is a broken patch that the old
    # single 'claude-logo-busy.svg' marker would have passed over: a table entry
    # with no arm returning "busy" is a dead branch, and an arm with no table
    # entry resolves to undefined and throws on the icon path. Second
    # alternative in each is the pre-2.1.261 inline shape, where one assignment
    # is genuinely both halves.
    _cm_grep "$extension" 'busy:"claude-logo-busy\.svg"|="claude-logo-busy\.svg"'  "extension: busy icon selection"
    _cm_grep "$extension" 'isBusy\)return"busy"|\.isBusy\)[\w\$]+="claude-logo-busy\.svg"' "extension: busy branch reaches icon"
    # [\w\$]+ not \w+: a minified identifier can be "$" (esbuild names the message
    # handler binding "$" as of 2.1.245), which \w does not match. Same reason as
    # the IDENTIFIER CHARSET note in patch-claude-busy-indicator.sh.
    # The optional (?:[\w\$]+\()? is 2.1.261: upstream wraps the incoming title in
    # a clamp helper, gJ($.request.title). Step 4 keeps that wrapper on the
    # fallback arm, so the patched text reads _customTitle||gJ($.request.title)
    # and a marker demanding the bare form would report MISSING on a good patch.
    _cm_grep "$extension" '_customTitle\|\|(?:[\w\$]+\()?[\w\$]+\.request\.title'  "extension: sticky custom title"
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
    # NOT the bare section name: 2.1.261 ships its own "editor/title/context"
    # section, so that string is present on a completely unpatched file — a
    # false pass that hid Step 8 doing nothing. The trailing "when" is what
    # separates a MENU ENTRY from the Step 7 command DEFINITION, which carries
    # the identical command id followed by "title" instead.
    _cm_grepz "$package"  '"claude-vscode\.renameTab",\s*"when":\s*"activeWebviewPanelId' "package.json: right-click context menu ENTRY"

    # --- resource file ---
    _cm_file "$resources/claude-logo-busy.svg"                                 "resources: claude-logo-busy.svg exists"

    [[ "$CLAUDE_MARKERS_MISSING" -eq 0 ]]
}
