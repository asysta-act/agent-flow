#!/usr/bin/env bash
# hooks/validate-dispatch.sh
# PostToolUse audit (2nd layer; CANNOT block — runs after the tool, finding A8).
#
# Sweep 1 — dispatched_at presence (always advisory).
# Sweep 2 — dispatch-witness audit, DUAL-MODE keyed by KEY-FILE PRESENCE (REQ-022):
#   * keyed run (0600 dispatch.key present, schema_version "2.0"): re-verify the
#     gate-owned ledger. Every ledger line's HMAC tag is recomputed via the
#     shared Python core (hooks/lib/witness_core.py); the per-stage verdict uses
#     the latest ledger entry matching the current CLAIM. A key-present,
#     non-skipped, CLAIMED stage with no matching ledger line is row f
#     (WITNESS_UNVERIFIABLE). A legacy-shape / stripped-`alg` tag fails the HMAC
#     recompute -> WITNESS_MISMATCH (key-file presence is the downgrade
#     authority — REQ-013, never a silent skip).
#   * keyed-CLAIMED but key absent on a PROGRESSED run (>=1 completed stage OR
#     non-empty ledger) -> WITNESS_UNVERIFIABLE (row d; the "delete the key to
#     skip the gate" disarm is LOUD, never silent).
#   * legacy keyless run (no key, schema "1.0"/unset): the existing V1 sha256
#     recompute + V2 overlay-presence dual-mode — NEVER a false WITNESS_MISMATCH
#     on a valid v1.0 state (REQ-023).
#
# This hook re-verifies; it never signs and never blocks (only the PreToolUse
# gate hooks/validate-dispatch-pre.sh blocks). The keyed compute/verify lives
# ONLY in Python (witness_core.py) — bash holds NO keyed path (REQ-010).
#
# EXIT: 0 normally. STRICT-BY-DEFAULT for the witness audit: exit 2 when any
#       stage produces WITNESS_MISMATCH or WITNESS_UNVERIFIABLE, unless advisory
#       (AGENT_FLOW_STRICT_DISPATCH="0" OR a STRICT_DISPATCH_OFF flag file).
#       WITNESS_MISSING NEVER exits 2. The dispatched_at presence audit is always
#       advisory. (PostToolUse exit 2 cannot block — it is a forensic signal.)
# LOG:  .agent-flow/dispatch-audit.log (best-effort append-only; records ONLY
#       "<ISO-ts> <stage> <verdict>" — NO key, NO tag, NO preimage — REQ-028).
#
# Env vars (clean-break AGENT_FLOW_ prefix):
#   - AGENT_FLOW_STRICT_DISPATCH : strict ON unless == "0" (advisory)
#   - AGENT_FLOW_AUDIT_LOG       : audit-log path override
#   - AGENT_FLOW_STATE_JSON      : state.json path override
#   - AGENT_FLOW_DISPATCH_KEY_FILE : key-file PATH override (never the value)
#   - AGENT_FLOW_LEDGER          : gate ledger path override
#   - AGENT_FLOW_OVERRIDE_PATH   : overlay override dir for legacy V2 (default customization/)
#
# Security contracts:
#   - STAGES are hardcoded; never derived from state.json field names.
#   - state.json / ledger are parsed, never eval'd.
set -uo pipefail

# --- strict determination (env + TOP-LEVEL flag) for the no-Python fail path ---
strict=1
[ "${AGENT_FLOW_STRICT_DISPATCH:-}" = "0" ] && strict=0
[ -f ".agent-flow/STRICT_DISPATCH_OFF" ] && strict=0

# --- runnability probe (A4 / REQ-018): probe `-c 'import sys'`, NOT command -v.
#     A Windows-Store python.exe stub is ON PATH but exits non-zero on -c; the
#     old silent `exit 0` was a one-line disarm of the security audit.
PYBIN=""
for cand in python3 python; do
  if command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'import sys' >/dev/null 2>&1; then
    PYBIN="$cand"
    break
  fi
done
if [ -z "$PYBIN" ]; then
  echo "validate-dispatch: no runnable Python 3 (required by agent-flow; no bash fallback)" >&2
  # LOUD-not-silent: fail closed under strict (exit 2), advisory downgrades to 0.
  [ "$strict" -eq 1 ] && exit 2
  exit 0
fi

# --- resolve the shared Python lib dir (sibling of this hook) ------------------
SELF="${BASH_SOURCE[0]:-$0}"
HOOKDIR="$(cd "$(dirname "$SELF")" 2>/dev/null && pwd)"
[ -n "$HOOKDIR" ] || HOOKDIR="$(dirname "$SELF")"
LIBDIR="$HOOKDIR/lib"

exec "$PYBIN" - "$LIBDIR" <<'PY'
import sys, os, json, glob, hashlib, datetime

LIBDIR = sys.argv[1] if len(sys.argv) > 1 else ""
if LIBDIR:
    sys.path.insert(0, LIBDIR)
import witness_core as wc      # canon / tag (HMAC) — single keyed authority
import witness_key as wk       # read_key / ledger_is_nonempty
import witness_overlay as wo   # overlay binding helpers (A5/A6, REQ-031/032)

# Hardcoded stage whitelist (no dynamic discovery from state.json).
STAGES = ["triage", "code_analysis", "reproduce_browser", "fixer_reviewer",
          "smoke_check", "test", "e2e_test", "browser_verification",
          "acceptance_gate", "publisher"]
# Legacy V1 sub-tuple (sha256 dual-mode for keyless "1.0" runs).
WITNESS_FIELDS = ("agent_name", "model", "prompt_head_128", "overlay_source", "overlay_digest")
HEX = set("0123456789abcdef")

# --- resolve state.json (explicit override, else latest .agent-flow/*/state.json) ---
state_json = os.environ.get("AGENT_FLOW_STATE_JSON") or ""
if not state_json:
    cands = sorted(glob.glob(os.path.join(".agent-flow", "*", "state.json")))
    state_json = cands[-1] if cands else ""
if not state_json or not os.path.isfile(state_json):
    sys.exit(0)  # not a pipeline run

try:
    with open(state_json, encoding="utf-8") as f:
        doc = json.load(f) or {}
except Exception:
    sys.exit(0)  # unreadable / invalid JSON -> behave like "no run", never block
stages = doc.get("stages", {}) or {}
if not isinstance(stages, dict):
    stages = {}
schema_ver = str(doc.get("schema_version") or "")

audit_log     = os.environ.get("AGENT_FLOW_AUDIT_LOG", os.path.join(".agent-flow", "dispatch-audit.log"))
override_path = os.environ.get("AGENT_FLOW_OVERRIDE_PATH", "customization/")
# Configured Agent-Overrides allowlist root (REQ-031 step 1): the project's
# `### Agent Overrides` `Path` when persisted as top-level agent_overrides_path;
# None -> witness_overlay defaults it to customization/. The per-stage CLAIM
# override_path is confined to it (same boundary the gate enforces).
_aor = doc.get("agent_overrides_path")
agent_overrides_root = _aor if isinstance(_aor, str) and _aor else None
run_dir       = os.path.dirname(state_json)

# Strict honoring env + TOP-LEVEL flag + per-run flag (REQ-020/REQ-050).
strict = os.environ.get("AGENT_FLOW_STRICT_DISPATCH", "") != "0"
if os.path.exists(os.path.join(".agent-flow", "STRICT_DISPATCH_OFF")):
    strict = False
if run_dir and os.path.exists(os.path.join(run_dir, "STRICT_DISPATCH_OFF")):
    strict = False

ts    = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
lines = []
# Advisory notices (e.g. benign post-dispatch overlay .toml drift). Written to the
# audit log but NEVER counted toward saw_block / exit 2 — they cannot block and the
# audit cannot distinguish a benign edit from an attack (Robustness Scn1 fix).
advisories = []

# --- key-file presence is the dual-mode authority (REQ-013/REQ-022) -----------
key_path    = os.environ.get("AGENT_FLOW_DISPATCH_KEY_FILE") or os.path.join(run_dir, "dispatch.key")
ledger_path = os.environ.get("AGENT_FLOW_LEDGER") or os.path.join(run_dir, "dispatch-ledger.jsonl")
keyhex      = wk.read_key(key_path)            # None if absent/empty/unreadable
key_present = keyhex is not None
completed   = sum(1 for s in stages.values()
                  if isinstance(s, dict) and s.get("status") == "completed")
ledger_nonempty = wk.ledger_is_nonempty(ledger_path)

if key_present:
    mode = "KEYED"                                   # rows a / c / e / f
elif schema_ver == "2.0" and (completed >= 1 or ledger_nonempty):
    mode = "ROWD"                                    # key lost on a progressed run
elif schema_ver == "2.0":
    mode = "FRESH"                                   # gate-bootstrap pending; nothing signed yet
else:
    mode = "LEGACY"                                  # keyless v1.0 sha256 dual-mode

# Parse the gate-owned ledger once (keyed mode).
ledger_entries = []
if mode == "KEYED":
    try:
        with open(ledger_path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    ledger_entries.append(json.loads(line))
                except Exception:
                    continue
    except (FileNotFoundError, NotADirectoryError, IsADirectoryError, OSError):
        ledger_entries = []


def _safe_int(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        return -1


def is_claimed(s):
    """A non-skipped stage the orchestrator actually dispatched (has a claim)."""
    if not isinstance(s, dict) or s.get("status") == "skipped":
        return False
    return bool(s.get("claim_nonce")) or str(s.get("dispatched_at") or "")[:1].isdigit()


def legacy_verdict(s):
    """Existing V1 sha256 recompute + V2 overlay-presence dual-mode (REQ-023)."""
    vals = {k: s.get(k) for k in ("dispatch_witness",) + WITNESS_FIELDS}
    if all(vals[k] not in (None, "") for k in vals):
        stored = str(vals["dispatch_witness"])
        if len(stored) == 64 and set(stored) <= HEX:
            canon = "|".join(str(vals[k]) for k in WITNESS_FIELDS)
            if hashlib.sha256(canon.encode("utf-8")).hexdigest() == stored:
                short = str(vals["agent_name"]).rsplit(":", 1)[-1]
                # A6: prefer the per-stage persisted override_path from the CLAIM
                # (the hook never inherits the skill's env); env/default is last resort.
                ovp = str(s.get("override_path") or "") or override_path
                toml  = os.path.join(ovp, short + ".toml")
                if os.path.isfile(toml) and vals["overlay_source"] != "toml":
                    return "WITNESS_MISMATCH"
                return "WITNESS_OK"
            return "WITNESS_MISMATCH"
        return "WITNESS_MISMATCH"  # malformed stored witness
    return "WITNESS_MISSING"


def keyed_verdict(s, st):
    """Re-verify the gate signature for one stage against the gate-owned ledger."""
    if not is_claimed(s):
        return "WITNESS_MISSING"
    cn = str(s.get("claim_nonce") or "")
    matches = [e for e in ledger_entries
               if str(e.get("stage") or "") == st and str(e.get("claim_nonce") or "") == cn]
    if not matches:
        return "WITNESS_UNVERIFIABLE"   # row f: claimed keyed stage, no ledger entry
    # latest entry wins (highest dispatch_seq, then signed_at).
    matches.sort(key=lambda e: (_safe_int(e.get("dispatch_seq")), str(e.get("signed_at") or "")))
    e = matches[-1]
    c = wc.canon(
        str(e.get("subagent_type") or ""), str(e.get("model") or ""),
        str(e.get("prompt_head_128") or ""), str(e.get("overlay_source") or ""),
        str(e.get("overlay_digest") or ""), str(e.get("stage") or ""),
        str(e.get("run_id") or ""), str(e.get("claim_nonce") or ""))
    # STRICT — the REAL integrity control. Key-file presence is the authority: a
    # ledger-line HMAC tag that does not recompute (a tampered/forged ledger line,
    # a legacy-shape / stripped-alg tag) -> WITNESS_MISMATCH (fail-closed, exit 2
    # under strict). This is the dispatch-integrity check and stays strict.
    if str(e.get("tag") or "") != wc.tag(keyhex, c):
        return "WITNESS_MISMATCH"
    # ADVISORY — NOT a dispatch-integrity failure (Robustness Scn1 "cry wolf" fix).
    # Re-read the live on-disk .toml and compare its LF-normalized digest to the
    # gate-SIGNED ledger digest. A difference means the .toml was edited AFTER the
    # gate read+signed it at dispatch — a benign operator tuning the overlay, a
    # fixer/scaffolder whose task is to write customization/*.toml, a formatter, or
    # a branch switch. The dispatch already happened with the gate-time content, so
    # this is NOT an integrity failure; the audit cannot tell a benign edit from an
    # attack and PostToolUse cannot block anyway (A8). Integrity rests on the ledger
    # HMAC tag (above, strict) and the gate-time binding (PreToolUse DENY on
    # absent/allowlist-escape/traversal). So: log a clear notice, never MISMATCH /
    # exit 2. See state/schema.md (Key-loss / overlay drift section).
    if str(e.get("overlay_source") or "") == "toml":
        eshort = str(e.get("subagent_type") or "").rsplit(":", 1)[-1]
        ovp = str(s.get("override_path") or "") or override_path
        ov_status, ov_val = wo.recompute_overlay_digest(
            ovp, eshort, project_root=os.getcwd(), override_root=agent_overrides_root)
        if ov_status != wo.OVERLAY_OK or ov_val != str(e.get("overlay_digest") or ""):
            advisories.append(
                "%s %s OVERLAY_DRIFT_ADVISORY on-disk .toml != gate-signed digest "
                "(post-dispatch edit; not a dispatch-integrity failure — integrity "
                "rests on the ledger HMAC tag + the gate-time binding)" % (ts, st))
    return "WITNESS_OK"


# --- Sweep 1: dispatched_at presence (value must start with a digit = ISO ts) ---
for st in STAGES:
    da = str((stages.get(st) or {}).get("dispatched_at") or "")
    lines.append(f"{ts} {st} {'OK' if da[:1].isdigit() else 'MISSING'}")

# --- Sweep 2: dispatch-witness audit (dual-mode by key-file presence) ----------
saw_block = False  # MISMATCH or UNVERIFIABLE -> strict exit 2 (MISSING never does)
for st in STAGES:
    s = stages.get(st) or {}
    if s.get("status") == "skipped":
        verdict = "WITNESS_MISSING"
    elif mode == "LEGACY":
        verdict = legacy_verdict(s)
    elif mode == "KEYED":
        verdict = keyed_verdict(s, st)
    elif mode == "ROWD":
        # keyed-CLAIMED but key lost on a progressed run -> UNVERIFIABLE (loud).
        verdict = "WITNESS_UNVERIFIABLE" if is_claimed(s) else "WITNESS_MISSING"
    else:  # FRESH: zero completed + empty ledger + key absent; nothing signed yet
        verdict = "WITNESS_MISSING"
    if verdict in ("WITNESS_MISMATCH", "WITNESS_UNVERIFIABLE"):
        saw_block = True
    lines.append(f"{ts} {st} {verdict}")

# Advisory notices are recorded but NEVER affect saw_block / the exit code.
lines.extend(advisories)

# --- append audit lines (best-effort; never fail the tool on a log write error) ---
try:
    d = os.path.dirname(audit_log)
    if d:
        os.makedirs(d, exist_ok=True)
    with open(audit_log, "a", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
except Exception:
    pass

sys.exit(2 if (strict and saw_block) else 0)
PY
