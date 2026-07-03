#!/usr/bin/env bash
# ===========================================================================
# Test:     overlay-digest-ground-truth.sh                       [NAMED-4]
# AC:       AC-031 (REQ-031) — overlay_digest is GATE-COMPUTED-ONLY ground truth
#   (the S2 fix). The orchestrator does NOT commit overlay_digest; the gate reads
#   override_path/<short>.toml ONCE, recomputes the digest from those RAW
#   LF-normalized bytes, and SIGNS it into the ledger. There is NO
#   producer-claim-vs-gate digest compare (that compare was the Windows/CRLF
#   false-DENY surface). This drives:
#     (a) unmodified .toml, claim has NO overlay_digest -> ALLOW; the SIGNED
#         ledger digest == the gate's LF-normalized recompute (== sha256sum LF).
#     (CRLF) a CRLF .toml + a claim carrying a NAIVE CRLF digest -> ALLOW (the
#         Windows S2 regression: the OLD compare would false-DENY here); the
#         signed digest is the LF-normalized one, NOT the CRLF naive digest.
#     (b) forged override_path escaping the repo (..) -> DENY (structural).
#     (b2) REQ-031 step 1: an IN-REPO override_path OUTSIDE the configured
#         Agent-Overrides allowlist root (default customization/) -> DENY. Locks
#         customization/-allowlist confinement, NOT mere project-root (MEDIUM fix).
#     (c) overlay_source=toml but .toml ABSENT -> DENY + WITNESS_MISMATCH
#         (structural, not a crash).
#     (d) STRICT integrity: a tampered ledger HMAC tag -> PostToolUse audit
#         WITNESS_MISMATCH + exit 2 (the real dispatch-integrity control; stays
#         fail-closed).
#     (e) ADVISORY: a benign post-dispatch edit of an ALREADY-COMPLETED stage's
#         .toml -> audit logs OVERLAY_DRIFT_ADVISORY and exits 0; it must NOT
#         re-fire WITNESS_MISMATCH (Robustness Scn1 "cry wolf" fix — the dispatch
#         already happened with the gate-time content). Integrity rests on the
#         HMAC tag (d) + the gate-time binding (b/b2/c), NOT the audit re-read.
#     (f) STRUCTURAL lock: the gate source carries NO producer-claim digest
#         compare (asserts the S2 surface stays removed forever).
#   Verdict STRING and exit CODE are both asserted (no truthiness).
# ===========================================================================
set -uo pipefail

REPO_ROOT="${AGENT_FLOW_REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$REPO_ROOT" || { echo "FAIL: cannot cd to REPO_ROOT=$REPO_ROOT" >&2; exit 1; }
# shellcheck disable=SC1090
. "$REPO_ROOT/tests/lib/assert.sh"

FAIL=0
fail() { echo "FAIL: $1" >&2; FAIL=1; }

GATE="${AGENT_FLOW_PRE_GATE:-$REPO_ROOT/hooks/validate-dispatch-pre.sh}"
AUDIT="$REPO_ROOT/hooks/validate-dispatch.sh"
PYBIN="$(command -v python3 || command -v python || true)"
[ -n "$PYBIN" ] || { echo "SKIP: python not runnable" >&2; exit 77; }
command -v sha256sum >/dev/null 2>&1 || { echo "SKIP: no sha256sum" >&2; exit 77; }
[ -f "$GATE" ]  || { fail "PreToolUse gate $GATE missing (REQ-016/REQ-031)"; echo "FAIL (RED): gate not implemented" >&2; exit 1; }
[ -f "$AUDIT" ] || { fail "PostToolUse audit $AUDIT missing (REQ-031/A5)"; echo "FAIL (RED): audit not implemented" >&2; exit 1; }

KEYHEX="00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"
RUN="PROJ-77_20260418T140000Z"
WORK="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/ogt_$$")"
trap 'rm -rf "$WORK"' EXIT
PROJ="$WORK/proj"
RDIR="$PROJ/.agent-flow/$RUN"
mkdir -p "$RDIR" "$PROJ/customization"
printf '%s' "$KEYHEX" > "$RDIR/dispatch.key"; chmod 600 "$RDIR/dispatch.key" 2>/dev/null || true

# Byte-exact LF .toml + its LF-normalized digest (== sha256sum of the LF file).
"$PYBIN" - "$PROJ/customization/fixer.toml" <<'PY'
import sys
open(sys.argv[1], "wb").write(b'model = "sonnet"\nstyle = "Terse"\n')
PY
DIG_LF=$(sha256sum "$PROJ/customization/fixer.toml" | awk '{print $1}')

# write_claim OVERRIDE_PATH [BOGUS_DIGEST] [STATUS] [OVERRIDES_ROOT]
#   Corrected model: the CLAIM omits overlay_digest. When BOGUS_DIGEST is given,
#   it is committed anyway to PROVE the gate ignores it (no producer compare).
#   STATUS defaults to in_progress; OVERRIDES_ROOT, when set, is persisted as the
#   top-level agent_overrides_path (the configured Agent-Overrides allowlist root).
write_claim() {
  "$PYBIN" - "$RDIR/state.json" "$1" "${2:-}" "${3:-in_progress}" "${4:-}" <<'PY'
import json, sys
ovp, bogus, status, root = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
stage = {"dispatched_at": "2026-04-18T14:00:00Z", "subagent_type": "agent-flow:fixer",
         "agent_name": "agent-flow:fixer", "model": "opus", "stage_name": "fixer_reviewer",
         "overlay_source": "toml", "override_path": ovp,
         "claim_nonce": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "dispatch_seq": 1,
         "status": status}
if bogus:
    stage["overlay_digest"] = bogus   # deliberately wrong; the gate must ignore it
doc = {"schema_version": "2.0", "stages": {"fixer_reviewer": stage}}
if root:
    doc["agent_overrides_path"] = root
open(sys.argv[1], "w", encoding="utf-8").write(json.dumps(doc, indent=2))
PY
}
# tamper_tag — flip the signed HMAC tag of the single ledger entry (a forged /
# tampered ledger line). The audit MUST catch this as WITNESS_MISMATCH (the real
# integrity control stays strict).
tamper_tag() {
  "$PYBIN" - "$RDIR/dispatch-ledger.jsonl" <<'PY'
import json, sys
p = sys.argv[1]
rows = [json.loads(l) for l in open(p, encoding="utf-8") if l.strip()]
if rows:
    t = str(rows[-1].get("tag") or "")
    # flip the first hex nibble deterministically (stays 64-hex, fails recompute).
    rows[-1]["tag"] = ("f" if t[:1] != "f" else "0") + t[1:]
open(p, "w", encoding="utf-8", newline="\n").write(
    "".join(json.dumps(r, separators=(",", ":")) + "\n" for r in rows))
PY
}
write_marker() {
  WNOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo "2026-04-18T14:00:00Z")
  "$PYBIN" - "$PROJ/.agent-flow/pending-dispatch.json" "$RUN" "$WNOW" <<'PY'
import json, sys
run, wnow = sys.argv[2], sys.argv[3]
m = {"run_id": run, "run_dir": ".agent-flow/%s" % run,
     "state_json": ".agent-flow/%s/state.json" % run, "stage": "fixer_reviewer",
     "subagent_type": "agent-flow:fixer",
     "claim_nonce": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "dispatch_seq": 1, "written_at": wnow}
open(sys.argv[1], "w", encoding="utf-8").write(json.dumps(m, indent=2))
PY
}
run_gate() {  # echoes "rc|stdout"; resets+rewrites the ledger+marker each call
  : > "$RDIR/dispatch-ledger.jsonl"
  write_marker
  local stdin_json rc out
  stdin_json=$("$PYBIN" - <<'PY'
import json
print(json.dumps({"hook_event_name":"PreToolUse","tool_name":"Task",
  "tool_input":{"subagent_type":"agent-flow:fixer","prompt":"do the fix","description":"x"}}))
PY
)
  rc=0
  out=$( cd "$PROJ" && printf '%s' "$stdin_json" | \
    env -u AGENT_FLOW_STRICT_DISPATCH \
    AGENT_FLOW_LEDGER="$RDIR/dispatch-ledger.jsonl" \
    AGENT_FLOW_DISPATCH_KEY_FILE="$RDIR/dispatch.key" \
    AGENT_FLOW_AUDIT_LOG="$WORK/audit.log" bash "$GATE" 2>/dev/null ) || rc=$?
  printf '%s|%s' "$rc" "$out"
}
ledger_digest() {  # echoes the SIGNED overlay_digest of the last ledger entry
  "$PYBIN" - "$RDIR/dispatch-ledger.jsonl" <<'PY'
import json, sys
last = None
try:
    for ln in open(sys.argv[1], encoding="utf-8"):
        ln = ln.strip()
        if ln:
            last = json.loads(ln)
except OSError:
    pass
print((last or {}).get("overlay_digest", ""))
PY
}
run_audit() {  # echoes rc; re-verifies the ledger that the gate just signed
  local rc=0
  : > "$WORK/postaudit.log"
  ( cd "$PROJ" && \
    env -u AGENT_FLOW_STRICT_DISPATCH \
    AGENT_FLOW_STATE_JSON="$RDIR/state.json" \
    AGENT_FLOW_LEDGER="$RDIR/dispatch-ledger.jsonl" \
    AGENT_FLOW_DISPATCH_KEY_FILE="$RDIR/dispatch.key" \
    AGENT_FLOW_AUDIT_LOG="$WORK/postaudit.log" bash "$AUDIT" >/dev/null 2>&1 ) || rc=$?
  printf '%s' "$rc"
}

# (a) unmodified LF .toml, claim WITHOUT overlay_digest -> ALLOW; signed == LF.
write_claim "customization/"
R=$(run_gate); rc="${R%%|*}"; out="${R#*|}"
[ "$rc" = "0" ] || fail "(a) allow: gate exited $rc on a present overlay with no claim digest (expected ALLOW/0)"
! contains "$out" '"permissionDecision":"deny"' || fail "(a) allow: deny emitted on a clean overlay dispatch"
SIGNED=$(ledger_digest)
[ "$SIGNED" = "$DIG_LF" ] || fail "(a) signed: ledger overlay_digest ($SIGNED) != gate LF recompute ($DIG_LF)"

# (CRLF / S2 regression) CRLF .toml + a NAIVE CRLF digest in the claim -> ALLOW.
#   The OLD code compared the claim digest to the gate recompute and DENIED here
#   on Windows. The corrected gate signs its own LF-normalized digest and ignores
#   the claim, so the dispatch ALLOWs and the SIGNED value is the LF digest.
"$PYBIN" - "$PROJ/customization/fixer.toml" <<'PY'
import sys
open(sys.argv[1], "wb").write(b'model = "sonnet"\r\nstyle = "Terse"\r\n')
PY
DIG_CRLF=$(sha256sum "$PROJ/customization/fixer.toml" | awk '{print $1}')
[ "$DIG_CRLF" != "$DIG_LF" ] || fail "(CRLF) precondition: naive CRLF digest must differ from LF digest"
write_claim "customization/" "$DIG_CRLF"   # commit the WRONG (CRLF-naive) digest
R=$(run_gate); rc="${R%%|*}"; out="${R#*|}"
[ "$rc" = "0" ] || fail "(CRLF) S2-regression: gate exited $rc on a CRLF overlay (false-DENY — the S2 bug). Expected ALLOW/0"
! contains "$out" '"permissionDecision":"deny"' || fail "(CRLF) S2-regression: gate DENIED a CRLF overlay (producer-vs-gate compare reintroduced)"
SIGNED=$(ledger_digest)
[ "$SIGNED" = "$DIG_LF" ] || fail "(CRLF) signed: ledger digest ($SIGNED) != LF-normalized ($DIG_LF) — gate did not normalize"
[ "$SIGNED" != "$DIG_CRLF" ] || fail "(CRLF) signed: gate signed the NAIVE CRLF claim digest (must sign its own LF recompute)"

# (b) forged override_path escaping the repo (..) -> DENY (structural).
"$PYBIN" - "$PROJ/customization/fixer.toml" <<'PY'
import sys
open(sys.argv[1], "wb").write(b'model = "sonnet"\nstyle = "Terse"\n')
PY
write_claim "../../../../etc/"
R=$(run_gate); rc="${R%%|*}"; out="${R#*|}"
[ "$rc" = "2" ] || fail "(b) escape: forged override_path outside repo exited $rc (expected DENY/2)"
contains "$out" '"permissionDecision":"deny"' || fail "(b) escape: no deny on repo escape"

# (b2) REQ-031 step 1: an IN-REPO override_path OUTSIDE the configured allowlist
#   root (default customization/) -> DENY. Locks customization/-allowlist
#   confinement, NOT mere project-root confinement (the MEDIUM fix). A real
#   .toml exists at the target, so only the allowlist check can produce the DENY.
mkdir -p "$PROJ/elsewhere"
"$PYBIN" - "$PROJ/elsewhere/fixer.toml" <<'PY'
import sys
open(sys.argv[1], "wb").write(b'model = "sonnet"\nstyle = "Terse"\n')
PY
write_claim "elsewhere/"   # no agent_overrides_path persisted -> allowlist = customization/
R=$(run_gate); rc="${R%%|*}"; out="${R#*|}"
[ "$rc" = "2" ] || fail "(b2) allowlist: in-repo override_path outside customization/ exited $rc (expected DENY/2 — confinement still project-root, MEDIUM not fixed)"
contains "$out" '"permissionDecision":"deny"' || fail "(b2) allowlist: no deny on an in-repo path outside the configured allowlist"
rm -rf "$PROJ/elsewhere"

# (c) overlay_source=toml but the .toml is ABSENT -> WITNESS_MISMATCH, NOT a crash.
rm -f "$PROJ/customization/fixer.toml"
write_claim "customization/"
R=$(run_gate); rc="${R%%|*}"; out="${R#*|}"
[ "$rc" = "2" ] || fail "(c) absent: gate exited $rc (expected 2) when claimed .toml is missing"
contains "$out" 'WITNESS_MISMATCH' || fail "(c) absent: missing .toml must be WITNESS_MISMATCH, not GATE_ERROR (got: $out)"

# (d) STRICT — ledger HMAC tag tamper -> audit WITNESS_MISMATCH/2. The signed
#     ledger line's HMAC tag is the REAL dispatch-integrity control; tampering it
#     (a forged/edited ledger) MUST fail closed. Sign a clean overlay, flip the
#     tag, re-audit.
"$PYBIN" - "$PROJ/customization/fixer.toml" <<'PY'
import sys
open(sys.argv[1], "wb").write(b'model = "sonnet"\nstyle = "Terse"\n')
PY
write_claim "customization/"
R=$(run_gate); rc="${R%%|*}"
[ "$rc" = "0" ] || fail "(d) seed: gate did not ALLOW the clean overlay (rc=$rc) — cannot seed the audit"
arc=$(run_audit)
[ "$arc" = "0" ] || fail "(d) pre-tamper audit: re-verify exited $arc on an untampered ledger (expected 0)"
matches_re "$(cat "$WORK/postaudit.log")" 'fixer_reviewer WITNESS_OK' || fail "(d) pre-tamper: expected WITNESS_OK"
tamper_tag    # flip the signed HMAC tag on the ledger line
arc=$(run_audit)
[ "$arc" = "2" ] || fail "(d) tag-tamper audit: exited $arc (expected MISMATCH/2 — the ledger HMAC tag is the strict integrity control)"
matches_re "$(cat "$WORK/postaudit.log")" 'fixer_reviewer WITNESS_MISMATCH' \
  || fail "(d) tag-tamper: audit must record WITNESS_MISMATCH (forged ledger HMAC tag)"

# (e) ADVISORY — benign post-dispatch edit of an ALREADY-COMPLETED stage's .toml.
#     The dispatch already happened with the gate-time content; a later edit is
#     NOT a dispatch-integrity failure (Robustness Scn1 "cry wolf" fix). The audit
#     LOGS an OVERLAY_DRIFT_ADVISORY notice and exits 0 — it must NOT emit
#     WITNESS_MISMATCH/2 (the audit cannot block, nor tell benign from malicious;
#     integrity rests on the HMAC tag (d) + the gate-time binding (b/b2/c)).
"$PYBIN" - "$PROJ/customization/fixer.toml" <<'PY'
import sys
open(sys.argv[1], "wb").write(b'model = "sonnet"\nstyle = "Terse"\n')
PY
write_claim "customization/" "" "completed"   # stage already completed; gate still signs
R=$(run_gate); rc="${R%%|*}"
[ "$rc" = "0" ] || fail "(e) seed: gate did not ALLOW the clean overlay (rc=$rc) — cannot seed the audit"
arc=$(run_audit)
[ "$arc" = "0" ] || fail "(e) pre-edit audit: re-verify exited $arc on an unedited overlay (expected 0)"
matches_re "$(cat "$WORK/postaudit.log")" 'fixer_reviewer WITNESS_OK' || fail "(e) pre-edit: expected WITNESS_OK"
! contains "$(cat "$WORK/postaudit.log")" 'OVERLAY_DRIFT_ADVISORY' || fail "(e) pre-edit: unexpected drift advisory on an unedited overlay"
# Edit the COMPLETED stage's .toml AFTER the gate signed -> benign post-dispatch drift.
"$PYBIN" - "$PROJ/customization/fixer.toml" <<'PY'
import sys
open(sys.argv[1], "wb").write(b'model = "sonnet"\nstyle = "terse"\n')   # T->t, one byte
PY
arc=$(run_audit)
[ "$arc" = "0" ] || fail "(e) post-edit audit: exited $arc (expected ADVISORY/0 — a benign post-dispatch overlay edit must NOT re-fire as a tamper alarm)"
contains "$(cat "$WORK/postaudit.log")" 'fixer_reviewer OVERLAY_DRIFT_ADVISORY' \
  || fail "(e) post-edit: audit must record an OVERLAY_DRIFT_ADVISORY notice"
! matches_re "$(cat "$WORK/postaudit.log")" 'fixer_reviewer WITNESS_MISMATCH' \
  || fail "(e) post-edit: a benign post-dispatch overlay edit must NOT be WITNESS_MISMATCH (cry-wolf regression)"

# (f) STRUCTURAL lock: the gate carries NO producer-claim-vs-gate digest compare.
if grep -qE 'overlay_digest recomputed|ov_val[[:space:]]*!=[[:space:]]*overlay_digest' "$GATE"; then
  fail "(f) S2-lock: the gate still compares a producer-claim overlay_digest (false-DENY surface reintroduced)"
fi

if [ "$FAIL" -eq 0 ]; then
  echo "PASS: overlay-digest-ground-truth — gate-computed-only digest; CRLF overlay ALLOWs (S2 fixed); repo/allowlist escape + absent DENY at gate; ledger-tag tamper -> audit MISMATCH/2; benign post-dispatch overlay edit -> audit ADVISORY (not MISMATCH); no producer compare"
  exit 0
fi
exit 1
