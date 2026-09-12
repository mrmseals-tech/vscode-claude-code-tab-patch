#!/usr/bin/env node
// Behaviour test for the tab-icon precedence, run against a PATCHED extension.js.
//
//   node test-icon-precedence.js /path/to/extension.js
//
// Exit status: 0 = all cases pass, 1 = a case failed, 2 = classifier not found.
//
// WHY THIS FILE EXISTS
// --------------------
// claude-patch-markers.sh asserts that our edits are PRESENT. It cannot assert
// that they BEHAVE. Those are different questions, and the gap between them
// shipped a real bug:
//
// Upstream sets `hasUnseenCompletion` when a turn ends while the tab is not
// visible, and clears it only when the tab becomes visible — nothing clears it
// when the next turn starts. Our busy arm originally sat AFTER upstream's done
// arm, so a new task arrived as isBusy:true alongside a stale
// hasUnseenCompletion:true, `done` won, and the tab sat orange for the whole
// turn (going green only on click, because clicking cleared the flag).
//
// Every marker was green throughout. A presence-only assertion cannot see
// ordering, so it reported a healthy patch while the feature was wrong. This
// test is the assertion that can: it pulls the REAL classifier out of the built
// file, evaluates it, and checks which icon each flag combination resolves to.
//
// Keep it in the loop for any future badge change. If a truth-table row here
// ever has to be edited to make a patch pass, that is the moment to stop and
// ask whether the patch or the expectation is wrong.

const fs = require('fs');

const file = process.argv[2];
if (!file) { console.error('usage: test-icon-precedence.js <extension.js>'); process.exit(2); }
const src = fs.readFileSync(file, 'utf8');

const PENDING = 'claude-logo-pending.svg';
const BUSY    = 'claude-logo-busy.svg';
const DONE    = 'claude-logo-done.svg';
const PLAIN   = 'claude-logo.svg';

// Both upstream dialects have to be supported: ninja1 still runs 2.1.246, and
// the patch keeps a fallback path for it, so a test that only understood the
// current shape would silently stop covering that install.
//
//   shape A (2.1.261+) a classifier returning a KEY, plus a lookup table:
//     function lc$($,Q,J){if($?.hasPendingPermissions)return"pending"; ... return"plain"}
//     var dc$={pending:"claude-logo-pending.svg",...}
//
//   shape B (<=2.1.260) an inline if/else chain assigning the filename:
//     let J;if($.request.hasPendingPermissions)J="claude-logo-pending.svg";else if...
//
// Either way we end up with iconFor(flags) -> filename, so the truth table below
// is written once, against what actually reaches VS Code: the icon file.
function buildIconFor(src) {
    // ---- shape A ----
    // Locate the classifier by the arm we know is in it, then walk BACKWARD to
    // its enclosing function head. Do NOT require the pending arm to be the
    // FIRST statement: upstream inserting any arm above it would then look
    // exactly like "file not patched", which is the wrong diagnosis and hides a
    // real precedence break behind a plausible-sounding message. (That is not
    // hypothetical — an injected upstream-style arm did exactly this.)
    const armIdx = src.search(/[\w$]+\??\.hasPendingPermissions\)return"pending";/);
    if (armIdx !== -1) {
        const heads = [...src.slice(0, armIdx).matchAll(/function ([\w$]+)\(([\w$,]*)\)\{/g)];
        if (!heads.length) return { err: 'shape A: no enclosing function head before the pending arm' };
        const start = heads[heads.length - 1].index;   // nearest preceding head
        let depth = 0, end = -1;
        for (let j = src.indexOf('{', start); j < src.length; j++) {
            if (src[j] === '{') depth++;
            else if (src[j] === '}' && --depth === 0) { end = j + 1; break; }
        }
        if (end < 0) return { err: 'shape A: unbalanced classifier body' };
        if (end <= armIdx) return { err: 'shape A: pending arm is not inside the located function' };
        const classify = eval('(' + src.slice(start, end) + ')');

        const tbl = src.match(/var [\w$]+=(\{pending:"claude-logo-pending\.svg"[^}]*\})/);
        if (!tbl) return { err: 'shape A: icon lookup table not found' };
        const table = eval('(' + tbl[1] + ')');

        // The split-edit rule: an arm returning a key the table lacks is a dead
        // branch that markers cannot see. Assert the table side explicitly.
        if (typeof table.busy !== 'string') {
            return { err: 'shape A: icon table has no "busy" entry (busy arm would resolve to undefined)' };
        }
        // Q and J are upstream's tab + helper arguments. Q must be an object
        // (undefined short-circuits the unread lookup and would mask the done
        // arm entirely); J must be an object because `J.isBindingConfirmed?.()`
        // optional-calls a property on a NON-optional J.
        return { shape: 'A', iconFor: (flags) => table[classify(flags, {}, {})] };
    }

    // ---- shape B ----
    const chain = src.match(
        /let ([\w$]+);(if\(([\w$.]+)\.hasPendingPermissions\)\1="claude-logo-pending\.svg";(?:else if\([\w$.]+\.[\w$]+\)\1="claude-logo[\w-]*\.svg";)*else \1="claude-logo\.svg";)/);
    if (chain) {
        const [, resultVar, body, flagsExpr] = chain;
        // Symmetric to shape A's table.busy check above. Upstream's own chain is
        // a valid match for the regex (pending / done / plain), so without this a
        // VANILLA file would reach the truth table and report "cases failed" —
        // true, but the wrong diagnosis. Absent edit and misbehaving edit must
        // not look alike: exit 2 means our arm is not there, exit 1 means it is
        // there and wrong.
        if (!body.includes(BUSY)) {
            return { err: `shape B: no "${BUSY}" arm in the icon chain (is this file patched?)` };
        }
        // Rewrite upstream's flags expression ($.request) to our parameter.
        const rewritten = body.split(flagsExpr + '.').join('f.');
        if (rewritten.includes(flagsExpr + '.')) return { err: 'shape B: flags rewrite incomplete' };
        const iconFor = eval(`(function(f){let ${resultVar};${rewritten}return ${resultVar};})`);
        return { shape: 'B', iconFor };
    }

    return { err: 'no known icon classifier found — is this file patched?' };
}

const built = buildIconFor(src);
if (built.err) { console.error(`FATAL: ${built.err}`); process.exit(2); }
const { shape, iconFor } = built;

// The truth table. Case 1 is the regression this test was written for: it FAILS
// on a build whose busy arm sits after the done arm.
const cases = [
    ['busy + stale unseen completion -> BUSY   (the orange-while-working bug)',
        { isBusy: true, hasUnseenCompletion: true }, BUSY],
    ['idle + unseen completion      -> done',
        { isBusy: false, hasUnseenCompletion: true }, DONE],
    ['busy, nothing unseen          -> busy',
        { isBusy: true, hasUnseenCompletion: false }, BUSY],
    ['pending outranks busy         -> pending',
        { hasPendingPermissions: true, isBusy: true, hasUnseenCompletion: true }, PENDING],
    ['idle, nothing to report       -> plain',
        {}, PLAIN],
];

console.log(`icon precedence (shape ${shape}): ${file}`);
let bad = 0;
for (const [label, flags, want] of cases) {
    let got;
    try { got = iconFor(flags); } catch (e) { got = `threw ${e.message}`; }
    const ok = got === want;
    if (!ok) bad++;
    console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}`);
    if (!ok) console.log(`          got=${JSON.stringify(got)} want=${JSON.stringify(want)}  flags=${JSON.stringify(flags)}`);
}
console.log(bad ? `\n${bad} precedence case(s) FAILED` : '\nall precedence cases PASS');
process.exit(bad ? 1 : 0);
