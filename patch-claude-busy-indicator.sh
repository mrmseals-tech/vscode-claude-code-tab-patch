#!/usr/bin/env bash
# Patches Claude Code VS Code extension:
#   - Green badge on tabs when Claude is actively working
#   - "Claude Code: Rename Tab" command (Ctrl+Shift+P)
# Re-run after extension updates.
#
# All patches use dynamic variable detection so they survive minification
# changes between extension versions. Post-patch verification ensures
# nothing was silently skipped.
#
# SAFETY: Backs up originals first. If things break, run:
#   ./claude-rollback.sh          (sits next to this script)
# Then reload VS Code: Ctrl+Shift+P -> Developer: Reload Window
#
# IDENTIFIER CHARSET — why every anchor captures [\w\$]+ and never \w+:
# A minified JS identifier may be any of [A-Za-z0-9_$], and "$" is a perfectly
# ordinary name that bundlers do emit. Perl's \w is [A-Za-z0-9_] — it does NOT
# match "$" — so an anchor written with \w+ silently stops matching the moment
# upstream's minifier hands the binding we anchor on the name "$".
#
# That is not hypothetical. Extension 2.1.239 was minified to terser-style names
# (e, t, i, Fe); 2.1.245 switched to esbuild-style names, where both the message
# handler parameter and the ExtensionContext became "$". Steps 3, 4, 5 and 6 all
# failed at once with "could not detect variable names", while Steps 2, 7 and 8
# applied cleanly — leaving extension.js completely vanilla with webview/index.js
# and package.json patched, i.e. a "Rename Tab" command in the palette with no
# handler behind it. Step 2 had been hardened for this earlier (note its
# [^\s,)]+ param captures); Steps 3-6 had not.
#
# Rule: anywhere a MINIFIED identifier is matched or captured, use [\w\$]+ (or
# [^\s,)]+ for a parameter list). Never \w+. This applies equally to the
# already-patched guards — a guard that cannot recognise its own output makes the
# script double-inject on re-run — and to the markers in claude-patch-markers.sh,
# which would otherwise report MISSING on a correctly patched file.
#
# Note the backslash before the $: in a Perl character class a bare [\w$] would
# interpolate $], the Perl version variable.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/claude-patch-paths.sh"

EXT_DIR="$CLAUDE_PATCH_EXT_DIR"
BACKUP_DIR="$CLAUDE_PATCH_BACKUP_DIR"
FAILURES=0

fail() { echo "  FAIL: $1" >&2; FAILURES=$((FAILURES + 1)); }

# Find the latest Claude Code extension directory
EXT_PATH="$(claude_find_ext)"

if [[ -z "$EXT_PATH" ]]; then
    echo "ERROR: Claude Code extension not found in $EXT_DIR"
    exit 1
fi

echo "Found extension: $EXT_PATH"

RESOURCES="$EXT_PATH/resources"
WEBVIEW="$EXT_PATH/webview/index.js"
EXTENSION="$EXT_PATH/extension.js"
PACKAGE="$EXT_PATH/package.json"

# --- Step 0: Backup originals ---
mkdir -p "$BACKUP_DIR"
if [[ ! -f "$BACKUP_DIR/extension.js.orig" ]]; then
    # Refuse to snapshot an extension that is ALREADY patched. Without this, a
    # fresh checkout (empty state dir) run against a previously-patched install
    # would record patched files as the pristine ".orig" set, quietly destroying
    # the ability to ever roll back — the backup would restore the patch it was
    # supposed to undo. Reinstall the extension in VS Code to get vanilla files,
    # or point CLAUDE_PATCH_BACKUP_DIR at the backups you already have.
    if grep -q 'claude-logo-busy\.svg' "$EXTENSION" 2>/dev/null; then
        echo "ERROR: no backup in $BACKUP_DIR, but the extension is already patched." >&2
        echo "       Refusing to record patched files as the originals." >&2
        echo "       Fix: reinstall the Claude Code extension in VS Code to restore" >&2
        echo "       vanilla files, or set CLAUDE_PATCH_BACKUP_DIR to your existing backups." >&2
        exit 1
    fi
    cp "$EXTENSION" "$BACKUP_DIR/extension.js.orig"
    cp "$WEBVIEW" "$BACKUP_DIR/webview-index.js.orig"
    cp "$PACKAGE" "$BACKUP_DIR/package.json.orig"
    # Record which extension dir these backups belong to, so auto-patch-claude.sh
    # can tell a genuine version bump (safe to clear+recapture) apart from a
    # same-version retry (must NOT clear — see auto-patch-claude.sh comments).
    echo "$(basename "$EXT_PATH")" > "$BACKUP_DIR/.version"
    echo "Originals backed up to $BACKUP_DIR"
else
    echo "Backup already exists, skipping backup"
fi

# --- Step 1: Create claude-logo-busy.svg ---
echo "Creating claude-logo-busy.svg..."
{
cat > "$RESOURCES/claude-logo-busy.svg" << 'SVGEOF'
<svg height="1em" style="flex:none;line-height:1" viewBox="0 0 24 24" width="1em" xmlns="http://www.w3.org/2000/svg"><title>Claude (Busy)</title><defs><mask id="badge-mask"><rect width="24" height="24" fill="white"/><circle cx="19.5" cy="4.5" r="6.5" fill="black"/></mask></defs><path mask="url(#badge-mask)" d="M4.709 15.955l4.72-2.647.08-.23-.08-.128H9.2l-.79-.048-2.698-.073-2.339-.097-2.266-.122-.571-.121L0 11.784l.055-.352.48-.321.686.06 1.52.103 2.278.158 1.652.097 2.449.255h.389l.055-.157-.134-.098-.103-.097-2.358-1.596-2.552-1.688-1.336-.972-.724-.491-.364-.462-.158-1.008.656-.722.881.06.225.061.893.686 1.908 1.476 2.491 1.833.365.304.145-.103.019-.073-.164-.274-1.355-2.446-1.446-2.49-.644-1.032-.17-.619a2.97 2.97 0 01-.104-.729L6.283.134 6.696 0l.996.134.42.364.62 1.414 1.002 2.229 1.555 3.03.456.898.243.832.091.255h.158V9.01l.128-1.706.237-2.095.23-2.695.08-.76.376-.91.747-.492.584.28.48.685-.067.444-.286 1.851-.559 2.903-.364 1.942h.212l.243-.242.985-1.306 1.652-2.064.73-.82.85-.904.547-.431h1.033l.76 1.129-.34 1.166-1.064 1.347-.881 1.142-1.264 1.7-.79 1.36.073.11.188-.02 2.856-.606 1.543-.28 1.841-.315.833.388.091.395-.328.807-1.969.486-2.309.462-3.439.813-.042.03.049.061 1.549.146.662.036h1.622l3.02.225.79.522.474.638-.079.485-1.215.62-1.64-.389-3.829-.91-1.312-.329h-.182v.11l1.093 1.068 2.006 1.81 2.509 2.33.127.578-.322.455-.34-.049-2.205-1.657-.851-.747-1.926-1.62h-.128v.17l.444.649 2.345 3.521.122 1.08-.17.353-.608.213-.668-.122-1.374-1.925-1.415-2.167-1.143-1.943-.14.08-.674 7.254-.316.37-.729.28-.607-.461-.322-.747.322-1.476.389-1.924.315-1.53.286-1.9.17-.632-.012-.042-.14.018-1.434 1.967-2.18 2.945-1.726 1.845-.414.164-.717-.37.067-.662.401-.589 2.388-3.036 1.44-1.882.93-1.086-.006-.158h-.055L4.132 18.56l-1.13.146-.487-.456.061-.746.231-.243 1.908-1.312-.006.006z" fill="#D97757" fill-rule="nonzero"/><circle cx="19.5" cy="4.5" r="4.5" fill="#22C55E"/></svg>
SVGEOF
} || fail "Step 1: SVG resource creation"

# --- Step 2: Patch webview/index.js ---
echo "Patching webview/index.js..."

# Edit A: Add isBusy param to renameTab method definition
# Detects: renameTab(P1,P2,P3){return this.sendRequest({type:"rename_tab",title:P1,...,hasUnseenCompletion:P3})}
# Note: uses [^\s,)]+ not \w+ because minified params can be $ which isn't a \w char
perl -e '
  open F, "<", $ARGV[0] or die; local $/; $c = <F>; close F;

  if ($c =~ /isBusy:[^\s}]+\}/) {
    print STDERR "  - renameTab method: already patched\n";
    exit 0;
  }

  if ($c =~ /renameTab\(([^\s,)]+),([^\s,)]+),([^\s,)]+)\)\{return this\.sendRequest\(\{type:"rename_tab",title:\1,hasPendingPermissions:\2,hasUnseenCompletion:\3\}\)/) {
    my ($p1, $p2, $p3) = ($1, $2, $3);
    # Pick a new param name: W is safe (single uppercase letter not commonly used as first param)
    my $p4 = "W";

    my $old = "renameTab(${p1},${p2},${p3}){return this.sendRequest({type:\"rename_tab\",title:${p1},hasPendingPermissions:${p2},hasUnseenCompletion:${p3}})}";
    my $new = "renameTab(${p1},${p2},${p3},${p4}){return this.sendRequest({type:\"rename_tab\",title:${p1},hasPendingPermissions:${p2},hasUnseenCompletion:${p3},isBusy:${p4}})}";
    my $old_re = quotemeta($old);
    if ($c =~ s/$old_re/$new/) {
      open F, ">", $ARGV[0] or die; print F $c; close F;
      print STDERR "  - renameTab method patched (params: $p1,$p2,$p3 + $p4)\n";
    } else {
      print STDERR "  *** renameTab method: substitution failed\n";
      exit 1;
    }
  } else {
    print STDERR "  *** renameTab method: pattern not found\n";
    exit 1;
  }
' "$WEBVIEW" || fail "Edit A: renameTab method definition"

# Edit B: Pass busy.value in reactive watcher
# Pattern A (old): CONN.renameTab(TITLE,PERM,this.hasUnseenCompletion.value)
# Pattern B (new): VAR=this.hasUnseenCompletion.value;Nk(()=>CONN.renameTab(TITLE,PERM,VAR))
#
# WHY THIS IS NOT JUST session.busy — background subagents:
# upstream drives session.busy from the SDK stream bookends ONLY:
#   system/init -> busy=true ... result -> busy=false
# An async subagent (the Agent tool default, "Async agent launched successfully")
# OUTLIVES the turn that spawned it: the parent stops talking, emits result, and
# busy goes false while the subagent is still working — the parent only wakes
# again when a task-notification arrives. For that whole window the tab reported
# isBusy:false and the badge cleared, which is the "does not detect subagent
# work" report. Verified in the extension log against a real run: three async
# agents launched 10:39-10:40Z, parent turn ended, session went idle at 10:45:00Z,
# task-notification at 10:47:41Z put it back to running — 2m41s of invisible work.
#
# session.subagentTasks cannot fill the gap either: upstream CLEARS that map on
# result, and handleTaskProgress early-returns for a task id it does not already
# hold, so it can never repopulate afterwards.
#
# So arg 4 is "main loop busy OR live background work", where the second half is
# _bgBusy — a signal Edits D/E/F add, fed by the system/background_tasks_changed
# event that upstream documents for exactly this purpose ("consumers that only
# need is background work running should replace their set with each payload").
perl -e '
  open F, "<", $ARGV[0] or die; local $/; $c = <F>; close F;

  # Arg 4 of renameTab: main-loop busy OR live background subagent work.
  sub busy_expr { my ($s) = @_; return "(${s}?.busy.value??!1)||(${s}?._bgBusy.value??!1)"; }

  # Already patched with the CURRENT, background-aware expression?
  if ($c =~ /_bgBusy\.value\?\?!1\)/) {
    print STDERR "  - reactive watcher: already patched (background-aware)\n";
    exit 0;
  }

  # Patched by an OLDER version of this script (main-loop busy only)? Upgrade in
  # place — an installed extension must not need a rollback+repatch to gain the
  # background-aware arm. Both old forms end in "SESSION?.busy.value??!1", so
  # anchor on the text that PRECEDES it: vanilla contains that exact substring a
  # few statements away, in the hasUnseenCompletion watcher
  # ("let G=this.activeSession.value,...,U=G?.busy.value??!1"), and an unanchored
  # match would rewrite that instead.
  my $upgraded = 0;
  foreach my $pre ("_isBusy=", "this.hasUnseenCompletion.value,") {
    next if $upgraded;
    my $pre_re = quotemeta($pre);
    if ($c =~ /$pre_re([\w\$]+)\?\.busy\.value\?\?!1/) {
      my $sess = $1;
      my $old_re = quotemeta($pre . "${sess}?.busy.value??!1");
      my $new = $pre . busy_expr($sess);
      if ($c =~ s/$old_re/$new/) {
        $upgraded = 1;
        print STDERR "  - reactive watcher upgraded to background-aware (session=$sess)\n";
      }
    }
  }
  if ($upgraded) {
    open F, ">", $ARGV[0] or die; print F $c; close F;
    exit 0;
  }

  my $patched = 0;

  # Pattern A (old): this.hasUnseenCompletion.value passed inline
  if ($c =~ /([\w\$]+)\.renameTab\(([\w\$]+),([\w\$]+),this\.hasUnseenCompletion\.value\)/) {
    my $target_pos = $-[0];
    my ($conn, $title, $perm) = ($1, $2, $3);
    # Scope-aware: pick the CLOSEST preceding "let X=this.activeSession.value",
    # not the first one anywhere in the file. A leftmost-across-the-whole-file
    # search can grab an unrelated sibling closure'"'"'s binding by pure naming
    # coincidence (minifiers often reuse the same short name across sibling
    # scopes) and splice a variable reference that is out of scope at the
    # injection site, throwing ReferenceError at runtime. Scanning only the
    # prefix up to this match and taking the LAST hit finds the declaration
    # actually nearest to (and therefore in scope at) the renameTab call.
    my $prefix = substr($c, 0, $target_pos);
    my $session_var;
    while ($prefix =~ /let ([\w\$]+)=this\.activeSession\.value/g) {
      $session_var = $1;
    }
    if (!$session_var) {
      print STDERR "  *** reactive watcher: could not detect session variable (pattern A)\n";
      exit 1;
    }
    my $old = "${conn}.renameTab(${title},${perm},this.hasUnseenCompletion.value)";
    my $new = "${conn}.renameTab(${title},${perm},this.hasUnseenCompletion.value," . busy_expr($session_var) . ")";
    my $old_re = quotemeta($old);
    if ($c =~ s/$old_re/$new/) {
      $patched = 1;
      print STDERR "  - reactive watcher patched pattern A (conn=$conn, session=$session_var)\n";
    }
  }

  # Pattern B (new): hasUnseenCompletion.value assigned to var, then var passed in renameTab via untracked wrapper
  # IMPORTANT: busy.value must be read OUTSIDE the Nk/untracked wrapper so the reactive system tracks it
  if (!$patched && $c =~ /([\w\$]+)=this\.hasUnseenCompletion\.value;.*?([\w\$]+)\(\(\)=>([\w\$]+)\.renameTab\(([\w\$]+),([\w\$]+),\1\)\)/s) {
    my $target_pos = $-[0];
    my ($unseen_var, $wrapper, $conn, $title, $perm) = ($1, $2, $3, $4, $5);
    # Scope-aware: same fix as pattern A above — take the CLOSEST preceding
    # "let X=this.activeSession.value" (last match in the prefix up to this
    # call site), not the first one in the whole file.
    my $prefix = substr($c, 0, $target_pos);
    my $session_var;
    while ($prefix =~ /let ([\w\$]+)=this\.activeSession\.value/g) {
      $session_var = $1;
    }
    if (!$session_var) {
      print STDERR "  *** reactive watcher: could not detect session variable (pattern B)\n";
      exit 1;
    }
    # Read the busy signals BEFORE the untracked wrapper so p4() reactive effect
    # tracks BOTH of them — a read inside the wrapper is untracked, and the tab
    # would then never repaint when only the background half changes.
    my $old = "${unseen_var}=this.hasUnseenCompletion.value;${wrapper}(()=>${conn}.renameTab(${title},${perm},${unseen_var}))";
    my $busy_var = "_isBusy";
    my $new = "${unseen_var}=this.hasUnseenCompletion.value,${busy_var}=" . busy_expr($session_var) . ";${wrapper}(()=>${conn}.renameTab(${title},${perm},${unseen_var},${busy_var}))";
    my $old_re = quotemeta($old);
    if ($c =~ s/$old_re/$new/) {
      $patched = 1;
      print STDERR "  - reactive watcher patched pattern B (conn=$conn, session=$session_var, wrapper=$wrapper)\n";
    }
  }

  if ($patched) {
    open F, ">", $ARGV[0] or die; print F $c; close F;
  } else {
    print STDERR "  *** reactive watcher: pattern not found\n";
    exit 1;
  }
' "$WEBVIEW" || fail "Edit B: reactive watcher (busy.value passthrough)"

# Edit C: Patch renameTab wrapper to pass through isBusy (4th arg)
# Detects: renameTab=(P1,P2,P3)=>{let V=this.comms.connection.value;if(V&&V.config.value?.openNewInTab)return V.renameTab(P1,P2,P3),!0;return!1}
# Note: uses [^\s,)]+ not \w+ because minified params can be $ which isn't a \w char
perl -e '
  open F, "<", $ARGV[0] or die; local $/; $c = <F>; close F;

  # Check if already patched: wrapper has 4 params
  if ($c =~ /renameTab=\([^)]+,[^)]+,[^)]+,[^)]+\)=>\{let [^=]+=this\.comms\.connection\.value/) {
    print STDERR "  - renameTab wrapper: already patched\n";
    exit 0;
  }

  if ($c =~ /renameTab=\(([^\s,)]+),([^\s,)]+),([^\s,)]+)\)=>\{let ([\w\$]+)=this\.comms\.connection\.value;if\(\4&&\4\.config\.value\?\.openNewInTab\)return \4\.renameTab\(\1,\2,\3\),!0;return!1\}/) {
    my ($p1, $p2, $p3, $cv) = ($1, $2, $3, $4);
    my $p4 = "W";

    my $old = "renameTab=(${p1},${p2},${p3})=>{let ${cv}=this.comms.connection.value;if(${cv}&&${cv}.config.value?.openNewInTab)return ${cv}.renameTab(${p1},${p2},${p3}),!0;return!1}";
    my $new = "renameTab=(${p1},${p2},${p3},${p4})=>{let ${cv}=this.comms.connection.value;if(${cv}&&${cv}.config.value?.openNewInTab)return ${cv}.renameTab(${p1},${p2},${p3},${p4}),!0;return!1}";
    my $old_re = quotemeta($old);
    if ($c =~ s/$old_re/$new/) {
      open F, ">", $ARGV[0] or die; print F $c; close F;
      print STDERR "  - renameTab wrapper patched (params: $p1,$p2,$p3 + $p4, connVar=$cv)\n";
    } else {
      print STDERR "  *** renameTab wrapper: substitution failed\n";
      exit 1;
    }
  } else {
    print STDERR "  *** renameTab wrapper: pattern not found\n";
    exit 1;
  }
' "$WEBVIEW" || fail "Edit C: renameTab wrapper"

# Edit D: Add the _bgBusy signal to the session class
# Sits next to upstream's own "busy" signal so it is created by every code path
# that builds a session (the constructor runs class fields; fromServer and
# fromStateInfo both go through "new"). The signal factory name is captured from
# the busy declaration rather than assumed, since it is minified.
perl -e '
  open F, "<", $ARGV[0] or die; local $/; $c = <F>; close F;

  if ($c =~ /_bgBusy=[\w\$]+\(!1\)/) {
    print STDERR "  - _bgBusy signal: already patched\n";
    exit 0;
  }

  # busy and pendingInput are declared adjacently in the session class. Requiring
  # BOTH, with a back-reference on the factory, pins the session class rather than
  # matching any incidental "busy=X(!1)" elsewhere in the bundle.
  if ($c =~ /busy=([\w\$]+)\(!1\);pendingInput=\1\(!1\)/) {
    my $sig = $1;
    my $old = "busy=${sig}(!1);pendingInput=${sig}(!1)";
    my $new = "busy=${sig}(!1);_bgBusy=${sig}(!1);pendingInput=${sig}(!1)";
    my $old_re = quotemeta($old);
    if ($c =~ s/$old_re/$new/) {
      open F, ">", $ARGV[0] or die; print F $c; close F;
      print STDERR "  - _bgBusy signal added (factory=$sig)\n";
    } else {
      print STDERR "  *** _bgBusy signal: substitution failed\n";
      exit 1;
    }
  } else {
    print STDERR "  *** _bgBusy signal: could not detect the session busy declaration\n";
    exit 1;
  }
' "$WEBVIEW" || fail "Edit D: _bgBusy session signal"

# Edit E: Feed _bgBusy from system/background_tasks_changed
# Upstream ships this event specifically for host activity indicators:
#   {type:"system",subtype:"background_tasks_changed",
#    tasks:[{task_id,task_type,description,ambient?}]}
#   "Every live background task after the change. REPLACE semantics: swap your
#    set for this payload." ... "A level signal, unlike the task_started/
#    task_notification edge bookends: consumers that only need is background work
#    running should replace their set with each payload rather than pairing
#    edges, so a missed bookend cannot wedge a stale running indicator."
# Neither webview/index.js nor extension.js consumes it today, which is why the
# information never reaches the tab. Level semantics also mean this cannot latch
# on: every membership change re-sends the FULL set, and the last one is empty.
#
# ambient entries are excluded on upstream instruction: "True for housekeeping
# tasks the CLI does not surface as user work (every skip_transcript task, plus
# auto-started live-update watchers); hosts should exclude them from activity
# indicators."
#
# Injected as a new arm on the existing system-subtype chain, immediately after
# task_notification and before the result arm. No other message shape can reach
# it, so no previously-handled message changes route.
perl -e '
  open F, "<", $ARGV[0] or die; local $/; $c = <F>; close F;

  if ($c =~ /background_tasks_changed"\)this\._bgBusy\.value=/) {
    print STDERR "  - background_tasks_changed handler: already patched\n";
    exit 0;
  }

  if ($c =~ /else if\(([\w\$]+)\.type==="system"&&\1\.subtype==="task_notification"\)this\.handleTaskNotification\(\1\);/) {
    my $m = $1;
    my $anchor = "else if(${m}.type===\"system\"&&${m}.subtype===\"task_notification\")this.handleTaskNotification(${m});";
    my $inject = "else if(${m}.type===\"system\"&&${m}.subtype===\"background_tasks_changed\")"
               . "this._bgBusy.value=Array.isArray(${m}.tasks)&&${m}.tasks.some((_bt)=>_bt&&!_bt.ambient);";
    my $anchor_re = quotemeta($anchor);
    if ($c =~ s/$anchor_re/$anchor$inject/) {
      open F, ">", $ARGV[0] or die; print F $c; close F;
      print STDERR "  - background_tasks_changed handler added (msg=$m)\n";
    } else {
      print STDERR "  *** background_tasks_changed handler: substitution failed\n";
      exit 1;
    }
  } else {
    print STDERR "  *** background_tasks_changed handler: could not detect the task_notification arm\n";
    exit 1;
  }
' "$WEBVIEW" || fail "Edit E: background_tasks_changed handler"

# Edit F: Clear _bgBusy when the Claude process goes away
# Background tasks belong to the CLI process that owns them, so a process that
# ends takes its tasks with it. Upstream calls resetPerProcessState() from the
# readMessages finally block (stream ended) and on restart, and already clears
# busy and subagentTasks there. Without this the badge could stay lit after a
# crash that never delivers the closing background_tasks_changed.
perl -e '
  open F, "<", $ARGV[0] or die; local $/; $c = <F>; close F;

  if ($c =~ /resetPerProcessState\(\)\{if\(this\._bgBusy\.value=!1/) {
    print STDERR "  - _bgBusy reset: already patched\n";
    exit 0;
  }

  my $old = "resetPerProcessState(){if(this.busy.value=!1,";
  my $new = "resetPerProcessState(){if(this._bgBusy.value=!1,this.busy.value=!1,";
  my $old_re = quotemeta($old);
  if ($c =~ s/$old_re/$new/) {
    open F, ">", $ARGV[0] or die; print F $c; close F;
    print STDERR "  - _bgBusy reset added\n";
  } else {
    print STDERR "  *** _bgBusy reset: resetPerProcessState anchor not found\n";
    exit 1;
  }
' "$WEBVIEW" || fail "Edit F: _bgBusy reset on process end"

# --- Step 3: Patch extension.js — busy icon ---
# 2.1.260 moved the goalposts: upstream hoisted icon selection out of the
# rename_tab message handler into a new applyTabIcon() method that reads a
# STORED flags object (this.lastRenameTabFlags), set from the request. Two
# consequences, and a patch that fixes only the first is worse than useless:
#   a) the handler stores ONLY hasPendingPermissions + hasUnseenCompletion, so
#      isBusy is discarded before applyTabIcon() ever runs -> the busy branch
#      would be a dead test that can never be true;
#   b) the branch itself now reads "$?.hasPendingPermissions" (optional chain,
#      no ".request." prefix), so the old single anchor stopped matching and
#      Step 3 failed with "could not detect variable names" on 2.1.260.
# Hence 3a (feed) then 3b (consumer), each with its own marker.
echo "Patching extension.js..."

# Step 3a: carry isBusy into the stored flags object (2.1.260+ shape only).
perl -e '
  open F, "<", $ARGV[0] or die; local $/; $c = <F>; close F;

  if ($c !~ /lastRenameTabFlags=\{/) {
    print STDERR "  - busy flag store: n/a (pre-2.1.260 inline shape)\n";
    exit 0;
  }
  if ($c =~ /lastRenameTabFlags=\{[^}]*isBusy:/) {
    print STDERR "  - busy flag store: already patched\n";
    exit 0;
  }
  if ($c =~ s/(lastRenameTabFlags=\{hasPendingPermissions:([\w\$]+)\.request\.hasPendingPermissions,hasUnseenCompletion:\2\.request\.hasUnseenCompletion)\}/$1,isBusy:$2.request.isBusy}/) {
    open F, ">", $ARGV[0] or die; print F $c; close F;
    print STDERR "  - busy flag store patched (req=$2)\n";
  } else {
    print STDERR "  *** busy flag store: could not detect lastRenameTabFlags shape\n";
    exit 1;
  }
' "$EXTENSION" || fail "Step 3a: isBusy in lastRenameTabFlags (extension.js)"

# Step 3b: add the busy branch to the icon selection.
# Dynamically detect the minified variable names (they change between versions).
#
# 2.1.261 moved the goalposts AGAIN. Upstream replaced the if/else assignment
# chain with a pure CLASSIFIER that returns a key, plus a separate lookup table:
#     function ug$(F,anchor,helpers){if(F?.hasPendingPermissions)return"pending";
#                                    ...return"done";return"plain"}
#     var mg$={pending:"claude-logo-pending.svg",done:"...",plain:"claude-logo.svg"};
# The old anchor required X="claude-logo-pending.svg";else if(...) — text that no
# longer exists anywhere in the bundle, so Step 3b failed with "could not detect
# variable names" on 2.1.261. Shape A below handles the classifier form; shape B
# is the pre-2.1.261 inline chain, kept so 2.1.246/2.1.251/2.1.260 still patch.
#
# Shape A needs TWO edits — a busy arm in the classifier AND a busy entry in the
# table — and either one alone is worse than neither: an arm returning a key the
# table lacks makes mg$[key] undefined (join() throws on the icon path), and a
# table entry no arm ever returns is a dead branch that can never fire. So the
# file is written only if BOTH substitutions succeed, and each gets its own
# marker — same rule as the 2.1.260 feed/branch split in Step 3a.
perl -e '
  open F, "<", $ARGV[0] or die; local $/; $c = <F>; close F;

  if ($c =~ /claude-logo-busy\.svg/) {
    print STDERR "  - icon selection: already patched\n";
    exit 0;
  }

  # --- Shape A: 2.1.261+ classifier + lookup table ---
  # Arity is left open ((?:,[\w\$]+)*) so an extra upstream helper param does not
  # break detection; the backreference to the first param is what actually pins
  # this to the icon classifier.
  if ($c =~ /function ([\w\$]+)\(([\w\$]+)(?:,[\w\$]+)*\)\{if\(\2\?\.hasPendingPermissions\)return"pending";/) {
    my ($fn, $flags) = ($1, $2);
    my $map;
    if ($c =~ /var ([\w\$]+)=\{pending:"claude-logo-pending\.svg",done:"claude-logo-done\.svg",plain:"claude-logo\.svg"\}/) {
      $map = $1;
    } else {
      print STDERR "  *** icon selection: classifier found but icon table did not match\n";
      exit 1;
    }
    my $fn_re  = quotemeta($fn);
    my $map_re = quotemeta($map);
    my $arm = 0; my $tab = 0;
    # Insert ahead of the final return, so precedence stays pending > done >
    # busy > plain — the same order the inline chain used.
    $arm = 1 if $c =~ s/(function $fn_re\(.*?)return"plain"\}/${1}if(${flags}?.isBusy)return"busy";return"plain"}/s;
    $tab = 1 if $c =~ s/(var $map_re=\{pending:"claude-logo-pending\.svg",done:"claude-logo-done\.svg",plain:"claude-logo\.svg")\}/${1},busy:"claude-logo-busy.svg"}/;
    if ($arm && $tab) {
      open F, ">", $ARGV[0] or die; print F $c; close F;
      print STDERR "  - icon selection patched, shape A (fn=$fn, flags=$flags, table=$map)\n";
      exit 0;
    }
    print STDERR "  *** icon selection: shape A substitution failed (arm=$arm table=$tab)\n";
    exit 1;
  }

  # --- Shape B: pre-2.1.261 inline if/else chain ---
  # One anchor, both older upstream shapes — capture the flags ACCESSOR whole so
  # the injected test is written in the same dialect as the branches around it:
  #   <= 2.1.251  "$.request" . hasPendingPermissions  (inline in the handler)
  #      2.1.260  "$?"        . hasPendingPermissions  (applyTabIcon())
  # The done-branch condition is captured too: 2.1.260 hoisted it into a local
  # ("else if(J)") instead of testing the request field inline.
  if ($c =~ /([\w\$]+(?:\.request|\?))\.hasPendingPermissions\)([\w\$]+)="claude-logo-pending\.svg";else if\(([^()]+)\)\2="claude-logo-done\.svg";else \2="claude-logo\.svg"/) {
    my ($flags_acc, $icon_var, $done_cond) = ($1, $2, $3);
    my $old = qq{else if(${done_cond})${icon_var}="claude-logo-done.svg";else ${icon_var}="claude-logo.svg"};
    my $new = qq{else if(${done_cond})${icon_var}="claude-logo-done.svg";else if(${flags_acc}.isBusy)${icon_var}="claude-logo-busy.svg";else ${icon_var}="claude-logo.svg"};
    my $old_re = quotemeta($old);
    if ($c =~ s/$old_re/$new/) {
      open F, ">", $ARGV[0] or die; print F $c; close F;
      print STDERR "  - icon selection patched, shape B (flags=$flags_acc, icon=$icon_var)\n";
    } else {
      print STDERR "  *** icon selection: shape B substitution failed\n";
      exit 1;
    }
  } else {
    print STDERR "  *** icon selection: could not detect variable names\n";
    exit 1;
  }
' "$EXTENSION" || fail "Step 3b: icon selection in extension.js"

# --- Step 4: Patch extension.js — sticky custom title for rename tab ---
echo "Patching extension.js for rename tab..."

perl -e '
  open F, "<", $ARGV[0] or die; local $/; $c = <F>; close F;

  if ($c =~ /_customTitle\|\|(?:[\w\$]+\()?[\w\$]+\.request\.title/) {
    print STDERR "  - sticky custom title: already patched\n";
    exit 0;
  }

  if ($c =~ /([\w\$]+)\.request\.type==="rename_tab"/) {
    my $req_var = $1;
    my $req_re  = quotemeta($req_var);
    # 2.1.261 wraps the incoming title in a clamp helper — gJ($.request.title),
    # where gJ truncates to 200 chars — so the bare assignment this step used to
    # anchor on ("this.panelTab.title=$.request.title") no longer exists and the
    # substitution silently failed. Match either dialect and KEEP whatever
    # upstream wrapped it in on the fallback arm: the custom title still wins,
    # and an upstream-supplied title is still clamped exactly as upstream meant.
    if ($c =~ s/this\.panelTab\.title=([\w\$]+\($req_re\.request\.title\)|$req_re\.request\.title)/this.panelTab.title=this._customTitle||$1/) {
      open F, ">", $ARGV[0] or die; print F $c; close F;
      print STDERR "  - sticky custom title patched (var: $req_var)\n";
    } else {
      print STDERR "  *** sticky custom title: substitution failed\n";
      exit 1;
    }
  } else {
    print STDERR "  *** sticky custom title: could not detect request variable\n";
    exit 1;
  }
' "$EXTENSION" || fail "Step 4: sticky custom title"

# --- Step 5: Patch extension.js — register renameTab command ---
perl -e '
  open F, "<", $ARGV[0] or die; local $/; $c = <F>; close F;

  if ($c =~ /claude-vscode\.renameTab/) {
    print STDERR "  - renameTab command: already patched\n";
    exit 0;
  }

  if ($c =~ /([\w\$]+)\.subscriptions\.push\(([\w\$]+)\.commands\.registerCommand\("claude-vscode\.newConversation",async\(\)=>\{([\w\$]+)\.notifyCreateNewConversation\(\)\}\)\)([;,])/) {
    my ($ctx_var, $vscode_var, $comms_var, $sep) = ($1, $2, $3, $4);
    my $anchor = qq{${ctx_var}.subscriptions.push(${vscode_var}.commands.registerCommand("claude-vscode.newConversation",async()=>{${comms_var}.notifyCreateNewConversation()}))${sep}};
    my $inject = qq{${ctx_var}.subscriptions.push(${vscode_var}.commands.registerCommand("claude-vscode.renameTab",async()=>{for(let ct of ${comms_var}.allComms){if(ct.panelTab&&ct.panelTab.visible){let nm=await ${vscode_var}.window.showInputBox({prompt:"Enter tab name (empty to reset)"});if(nm===void 0)break;let titles=${ctx_var}.globalState.get("customTabTitles")||[];if(nm===""){titles=titles.filter(t=>t!==ct._customTitle);ct._customTitle=null;ct.panelTab.title="Claude Code"}else{if(ct._customTitle)titles=titles.filter(t=>t!==ct._customTitle);titles.push(nm);ct._customTitle=nm;ct.panelTab.title=nm}${ctx_var}.globalState.update("customTabTitles",titles);break}}}))${sep}};
    my $anchor_re = quotemeta($anchor);
    if ($c =~ s/$anchor_re/$anchor$inject/) {
      open F, ">", $ARGV[0] or die; print F $c; close F;
      print STDERR "  - renameTab command patched (ctx=$ctx_var, vscode=$vscode_var, comms=$comms_var)\n";
    } else {
      print STDERR "  *** renameTab command: substitution failed\n";
      exit 1;
    }
  } else {
    print STDERR "  *** renameTab command: could not detect variable names\n";
    exit 1;
  }
' "$EXTENSION" || fail "Step 5: renameTab command registration"

# --- Step 6: Patch extension.js — restore custom titles on panel deserialize ---
# Injects: when VS Code restores a panel whose title is one the user set (kept in
# globalState "customTabTitles"), reattach it to the comms object as _customTitle
# so Step 4's sticky-title logic keeps it across a window reload.
#
# The bundle has shipped three shapes for the tab-panel path, and this step has
# now broken TWICE — both times because upstream moved a neighbouring statement,
# not because the thing we anchor on changed:
#
#   <= 2.1.224 — add() and the message handler are adjacent:
#     this.allComms.add(COMMS),PANEL.webview.onDidReceiveMessage
#
#   >= 2.1.226 — the webviews-registry object moved BELOW add(), gained
#   reveal/comms fields, and deliverStashedAtMention() was inserted:
#     this.allComms.add(COMMS);let E={isVisible:()=>PANEL.visible,isChatSurface:!0,
#       reveal:()=>PANEL.reveal(),comms:COMMS};this.webviews.add(E),...
#
#   >= 2.1.229 — onClientInit was inserted BETWEEN add() and the registry:
#     this.allComms.add(COMMS),COMMS.onClientInit=()=>this.broadcastSessionStates();
#       let E={isVisible:()=>PANEL.visible,isChatSurface:!0,...}
#
# The 2.1.224 anchor required "add(X) adjacent to onDidReceiveMessage"; 2.1.226
# broke it. Its replacement required "add(X); adjacent to the registry literal";
# 2.1.229 broke that the same way. Each time the step failed alone while the
# other nine applied — a half-patched extension whose rename survives the session
# but not a window reload, which is exactly the silent-partial-failure mode this
# script's marker set exists to catch.
#
# So the primary anchor no longer mentions add() at all. It matches the registry
# literal ALONE, requiring only a statement boundary in front of it (so the
# injected block statement is syntactically legal where it lands), and injects
# the restore block immediately before it. The literal pins the tab panel on its
# own: of the three webview registration sites, it is the ONLY one whose reveal()
# is PANEL.reveal() — both sidebars use PANEL.show() — so isChatSurface:!0 plus a
# back-referenced .reveal() identifies it uniquely. Nothing about statement ORDER
# is assumed any more, so a future inserted neighbour cannot break it again.
#
# The anchor must also match EXACTLY ONCE. If upstream ever gives a sidebar a
# reveal(), two sites match and the old "patch the first hit" behaviour would
# silently inject into the wrong one; we bail loudly instead. A check that cannot
# fail is worth nothing.
#
# The pre-2.1.226 adjacency form is kept as a fallback for older extension dirs.
perl -e '
  open F, "<", $ARGV[0] or die; local $/; $c = <F>; close F;

  # Already patched? Anchor on _st, the literal local var name this step injects
  # (Step 5 reads customTabTitles too, but names its local differently, so this
  # cannot be satisfied by Step 5 alone). Must stay in sync with the marker in
  # claude-patch-markers.sh. The old check keyed on our block sitting immediately
  # before .webview.onDidReceiveMessage, which is only true for Form A — under
  # Form B it would miss and the step would double-inject on a re-run.
  if ($c =~ /_st=this\.context\.globalState\.get\("customTabTitles"\)/) {
    print STDERR "  - setupPanel restore: already patched\n";
    exit 0;
  }

  sub restore_block {
    my ($panel, $comms) = @_;
    return "{let _st=this.context.globalState.get(\"customTabTitles\")||[];"
         . "if(${panel}.title&&_st.includes(${panel}.title))"
         . "${comms}._customTitle=${panel}.title};";
  }

  my ($old, $new, $form, $panel_var, $comms_var);

  # Primary anchor: the webviews-registry literal, order-independent. The
  # lookbehind only asserts a statement boundary so that injecting a bare block
  # in front of it stays valid JS — it does NOT assume which statement that is.
  my $registry_re = qr/(?<=[;}])(let [\w\$]+=\{isVisible:\(\)=>(?<panel>[\w\$]+)\.visible,isChatSurface:!0,reveal:\(\)=>\k<panel>\.reveal\(\),comms:(?<comms>[\w\$]+)\})/;

  # Count MATCHES, not capture groups. "my $n = () = (/re/g)" counts the flattened
  # capture list, so a single match with three groups reports 3 and would trip the
  # guard below on a perfectly good bundle. Increment per iteration instead.
  my $hits = 0;
  $hits++ while $c =~ /$registry_re/g;
  if ($hits > 1) {
    print STDERR "  *** setupPanel restore: registry anchor matched $hits sites, expected exactly 1 — refusing to guess which is the tab panel\n";
    exit 1;
  }

  if ($hits == 1 && $c =~ /$registry_re/) {
    ($form, $panel_var, $comms_var) = ("registry", $+{panel}, $+{comms});
    $old = $1;
    $new = restore_block($panel_var, $comms_var) . $1;
  } elsif ($c =~ /([\w\$]+)\.reveal\(\),.+?this\.allComms\.add\(([\w\$]+)\),\1\.webview\.onDidReceiveMessage/s) {
    ($form, $panel_var, $comms_var) = ("adjacency", $1, $2);
    $old = "this.allComms.add(${comms_var}),${panel_var}.webview.onDidReceiveMessage";
    $new = "this.allComms.add(${comms_var});" . restore_block($panel_var, $comms_var)
         . "${panel_var}.webview.onDidReceiveMessage";
  } else {
    print STDERR "  *** setupPanel restore: could not detect tab panel path\n";
    exit 1;
  }

  my $old_re = quotemeta($old);
  if ($c =~ s/$old_re/$new/) {
    open F, ">", $ARGV[0] or die; print F $c; close F;
    print STDERR "  - setupPanel restore patched (form=$form, panel=$panel_var, comms=$comms_var)\n";
  } else {
    print STDERR "  *** setupPanel restore: substitution failed\n";
    exit 1;
  }
' "$EXTENSION" || fail "Step 6: setupPanel restore"

# --- Step 7: Patch package.json — add renameTab command definition ---
# Insert the command object into contributes.commands immediately after the
# newConversation command, regardless of which command follows it. The old
# approach text-anchored on newConversation being directly followed by "update"
# — a new neighbor (reopenClosedSession in 2.1.167) silently broke it, and the
# verification only string-matched "renameTab" (which also hit the Step 8 menu
# entry), masking the failure. We now match the newConversation command BLOCK
# itself and append after it, preserving the file's existing formatting.
echo "Patching package.json..."

perl -e '
  open F, "<", $ARGV[0] or die; local $/; $c = <F>; close F;

  # Already patched? Detect the command DEFINITION (command+title pair), not a
  # bare "renameTab" string which the Step 8 menu entry also contains.
  if ($c =~ /"command":\s*"claude-vscode\.renameTab",\s*"title":\s*"Claude Code: Rename Tab"/) {
    print STDERR "  - package.json: command def already present\n";
    exit 0;
  }

  # Match the newConversation command object: { "command": "...newConversation", "title": "..." },
  # capturing the indentation of its opening brace so the inserted block lines up.
  if ($c =~ /([ \t]*)\{\s*"command":\s*"claude-vscode\.newConversation",\s*"title":\s*"[^"]*"\s*\},/) {
    my $indent = $1;
    my $block  = $&;
    my $inner  = $indent . "\t";
    my $ins = "\n${indent}\{\n${inner}\"command\": \"claude-vscode.renameTab\",\n${inner}\"title\": \"Claude Code: Rename Tab\"\n${indent}\},";
    my $block_re = quotemeta($block);
    if ($c =~ s/$block_re/$block$ins/) {
      open F, ">", $ARGV[0] or die; print F $c; close F;
      print STDERR "  - package.json command def added (after newConversation)\n";
    } else {
      print STDERR "  *** package.json: command insert substitution failed\n";
      exit 1;
    }
  } else {
    print STDERR "  *** package.json: newConversation command anchor not found\n";
    exit 1;
  }
' "$PACKAGE" || fail "Step 7: package.json command"

# --- Step 8: Patch package.json — add right-click context menu for rename ---
# 2.1.261 ships its OWN "editor/title/context" section (renameSessionTab,
# addSessionTabToGroup, markSessionUnread). The old guard tested for that
# section NAME, so it declared "already patched" and inserted nothing — the
# right-click Rename Tab entry silently vanished — while the old marker tested
# the same section name, matched upstream's own text and reported green. That is
# the 2.1.167 false-pass all over again, in the very step it was found in.
#
# The guard now asks the only question that distinguishes patched from vanilla:
# is OUR command in that menu array? Parsed as JSON, not string-matched, because
# "claude-vscode.renameTab" also appears in the Step 7 command DEFINITION and a
# bare substring test would go green on Step 7 alone. Insertion appends into an
# existing section and only creates one when upstream ships none.
echo "Patching package.json context menu..."

python3 -c '
import json, sys

path = sys.argv[1]
with open(path, "r") as f:
    c = f.read()

SECTION = "editor/title/context"
CMD = "claude-vscode.renameTab"

menus = json.loads(c).get("contributes", {}).get("menus", {})
if any(e.get("command") == CMD for e in menus.get(SECTION, [])):
    print("  - context menu: already patched", file=sys.stderr)
    sys.exit(0)

entry = """\t\t\t\t{
\t\t\t\t\t"command": "claude-vscode.renameTab",
\t\t\t\t\t"when": "activeWebviewPanelId == '"'"'claudeVSCodePanel'"'"'",
\t\t\t\t\t"group": "2_claude"
\t\t\t\t},"""

header = "\t\t\t\"" + SECTION + "\": ["
if header in c:
    c = c.replace(header, header + "\n" + entry, 1)
    how = "appended to upstream section"
else:
    anchor = "\t\t\t\"editor/title\": ["
    if anchor not in c:
        print("  *** context menu: anchor pattern not found", file=sys.stderr)
        sys.exit(1)
    c = c.replace(anchor, header + "\n" + entry.rstrip(",") + "\n\t\t\t],\n" + anchor, 1)
    how = "section created"

json.loads(c)   # refuse to write anything that is not valid JSON
with open(path, "w") as f:
    f.write(c)
print("  - context menu added (" + how + ")", file=sys.stderr)
' "$PACKAGE" || fail "Step 8: package.json context menu"

# --- Step 9: Post-patch verification (shared marker set) ---
# Markers live in claude-patch-markers.sh — the single source of truth shared
# with auto-patch-claude.sh and verify-claude-patch.sh, so the lists can never
# drift apart again (that drift is what hid the 2.1.167 failure).
echo ""
echo "Verifying patches..."
source "$HERE/claude-patch-markers.sh"
if claude_check_markers "$EXT_PATH"; then
    VERIFY_FAIL=0
else
    VERIFY_FAIL=1
fi

echo ""

if [[ $FAILURES -gt 0 || $VERIFY_FAIL -gt 0 ]]; then
    echo "PATCH INCOMPLETE: $FAILURES patch failures, verification $([ $VERIFY_FAIL -eq 0 ] && echo 'passed' || echo 'FAILED')"
    echo "Check output above for FAIL/MISSING lines."
    exit 1
fi

echo "All patches applied and verified."
echo "Reload VS Code: Ctrl+Shift+P -> Developer: Reload Window"
echo ""
echo "If something breaks, run:"
# Resolve next to this script — a hardcoded absolute path here once pointed at
# a file that did not exist, so the printed recovery command itself failed.
echo "  bash $HERE/claude-rollback.sh"
