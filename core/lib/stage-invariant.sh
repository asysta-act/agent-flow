#!/usr/bin/env bash
# core/lib/stage-invariant.sh
# Runtime dispatch invariant helpers.
#
# NOT sourced by any hook. hooks/validate-dispatch.sh (PostToolUse audit) is a
# single pure-Python process and sources nothing; the PreToolUse gate is the
# sole keyed signer (see hooks/lib/witness_core.py). This bash library is a
# DEMOTED, non-authoritative parity-pinned helper retained only for `--self-test`
# and the agents/acceptance-gate.md self-check; it carries no keyed-HMAC path.
# Skills do NOT source this file directly; thin-controller prose instructs the
# orchestrator what to write to state.json before each Task() call.
#
# POSIX-compatible. Tested on Windows Git-Bash, macOS BSD-grep, Linux GNU-grep.
# jq-free per fix-bugs convention.
#
# Tools used: bash builtins + printf + grep -E + sed -E + awk + sha256sum
# (or shasum -a 256 fallback for macOS systems without coreutils).

set -uo pipefail

# -----------------------------------------------------------------------------
# __sha256_hex  (private)
#   Read bytes from stdin, emit lowercase 64-char sha256 hex on stdout.
#   Reuses the same tool-selection order everywhere (sha256sum first,
#   shasum -a 256 fallback for macOS without coreutils). Returns non-zero
#   when no sha256 tool is available.
# -----------------------------------------------------------------------------
__sha256_hex() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    echo "stage-invariant: no sha256 tool available (need sha256sum or shasum)" >&2
    return 1
  fi
}

# -----------------------------------------------------------------------------
# compute_dispatch_witness STAGE SUBAGENT_TYPE MODEL PROMPT_HEAD_128 \
#                          OVERLAY_SOURCE OVERLAY_DIGEST
#   Emit sha256 hex string (lowercase, 64 chars) for the dispatch tuple.
#   STDOUT-only on success.
#
#   Canonical input (5-tuple, pipe-separated, no trailing newline):
#     "<SUBAGENT_TYPE>|<MODEL>|<PROMPT_HEAD_128>|<OVERLAY_SOURCE>|<OVERLAY_DIGEST>"
#
#   CRITICAL: PROMPT_HEAD_128 must be the first 128 UTF-8-safe bytes of the
#   prompt template BEFORE Tier-1 variable expansion. The caller is responsible
#   for performing the 128-byte truncation on the RAW prompt string (with
#   ${VAR} placeholders un-expanded). This function does NOT expand any Tier-1
#   variables (ISSUE_ID, BRANCH_NAME, TICKET_ID, etc.) - doing so would defeat
#   witness stability across resume cycles.
#
#   OVERLAY_SOURCE is one of `toml` | `none` | `md_rejected` (the exact value
#   the Agent Override Injector records). OVERLAY_DIGEST is the rendered-block
#   sha256 hex when OVERLAY_SOURCE=toml, otherwise the literal `none` /
#   `md_rejected` string (see compute_overlay_digest). Folding both into the
#   witness binds the overlay into the dispatch receipt: dropping a TOML
#   overlay flips overlay_source toml->none AND overlay_digest->none, changing
#   the witness so the drop is detectable.
#
#   STAGE is accepted as the first positional arg for caller-side clarity
#   but is NOT included in the hash (the hash covers what was dispatched,
#   not which slot it was dispatched into).
#
#   Returns 0 on success, non-zero on missing args or no sha256 tool.
# -----------------------------------------------------------------------------
compute_dispatch_witness() {
  local stage="${1:?usage: compute_dispatch_witness STAGE SUBAGENT_TYPE MODEL PROMPT_HEAD_128 OVERLAY_SOURCE OVERLAY_DIGEST}"
  local subagent_type="${2:?missing SUBAGENT_TYPE}"
  local model="${3:?missing MODEL}"
  local prompt_head_128="${4:?missing PROMPT_HEAD_128}"
  local overlay_source="${5:?missing OVERLAY_SOURCE}"
  local overlay_digest="${6:?missing OVERLAY_DIGEST}"
  printf '%s|%s|%s|%s|%s' \
    "$subagent_type" "$model" "$prompt_head_128" "$overlay_source" "$overlay_digest" \
    | __sha256_hex
}

# -----------------------------------------------------------------------------
# compute_overlay_digest OVERLAY_SOURCE [RENDERED_BLOCK]   (LEGACY v1.0 ONLY)
#   Produce the LEGACY v1.0 overlay_digest column (5th sha256 witness input).
#   NOT the keyed-witness authority: on keyed (schema 2.0) runs the gate computes
#   and SIGNS the overlay digest from the RAW LF-normalized .toml bytes via
#   hooks/lib/witness_overlay.py::recompute_overlay_digest (the ONE LF-normalizing
#   authority). This helper hashes the RENDERED_BLOCK as-given (no LF-normalize),
#   so it is never on any keyed producer-vs-gate compared path (S2 fix).
#     - OVERLAY_SOURCE=toml         -> sha256 hex (64 lc) of RENDERED_BLOCK.
#     - OVERLAY_SOURCE=none         -> literal string `none`.
#     - OVERLAY_SOURCE=md_rejected  -> literal string `md_rejected`.
#   Returns 0 on success, non-zero on no sha256 tool (toml path only).
# -----------------------------------------------------------------------------
compute_overlay_digest() {
  local overlay_source="${1:?usage: compute_overlay_digest OVERLAY_SOURCE [RENDERED_BLOCK]}"
  local rendered_block="${2:-}"
  case "$overlay_source" in
    toml)
      printf '%s' "$rendered_block" | __sha256_hex
      ;;
    none|md_rejected)
      printf '%s' "$overlay_source"
      ;;
    *)
      # Unknown source value: treat as literal pass-through so the witness
      # still binds whatever the injector recorded (defensive; not expected).
      printf '%s' "$overlay_source"
      ;;
  esac
}

# Internal helpers (private, double-underscore prefix).
# __regex_escape_stage escapes POSIX BRE metacharacters in user-controlled
# stage names before they reach the grep pattern in check_dispatch_witness.
# __validate_witness_format gates the witness shape early so a malformed
# witness can never be threaded into a further regex context.
__regex_escape_stage() {
    printf '%s' "$1" | sed 's/[][\.*^$/]/\\&/g'
}
__validate_witness_format() {
    printf '%s' "$1" | grep -qE '^[0-9a-f]{64}$'
}

# -----------------------------------------------------------------------------
# __read_stage_field STAGE STATE_JSON FIELD
#   Read stages.<STAGE>.<FIELD> from state.json. Echoes the value BYTE-EXACT
#   (no trailing newline), or empty string when the field/stage is absent or
#   JSON null.
#
#   A1 FIX (REQ-029): this used to extract the field with
#   `sed -E '...([^",}]*)...'`, which TRUNCATED any value at the first `}` / `,`
#   / `"` -- so a prompt_head_128 containing `{ISSUE_ID}` became `triage {ISSUE_ID`
#   and produced a FALSE WITNESS_MISMATCH. It now shells to Python json.load --
#   the SAME canonicalization the hook uses -- so there is exactly ONE JSON
#   reader and no truncation. The value is written as raw UTF-8 bytes
#   (sys.stdout.buffer) so non-ASCII heads survive the Windows/MSYS2 cp1252
#   stdout trap byte-for-byte.
#
#   Used by check_dispatch_witness to pull every stored witness input:
#   agent_name, model, prompt_head_128, overlay_source, overlay_digest,
#   dispatch_witness, status.
# -----------------------------------------------------------------------------
__read_stage_field() {
  local stage="$1"
  local state_json="$2"
  local field="$3"
  [ -f "$state_json" ] || { printf ''; return 0; }
  local pybin
  pybin="$(command -v python3 || command -v python || true)"
  [ -n "$pybin" ] || { printf ''; return 0; }
  "$pybin" - "$state_json" "$stage" "$field" <<'PY'
import json, sys
try:
    doc = json.load(open(sys.argv[1], encoding="utf-8"))
    v = doc.get("stages", {}).get(sys.argv[2], {}).get(sys.argv[3])
except Exception:
    v = None
sys.stdout.buffer.write(b"" if v is None else str(v).encode("utf-8"))
PY
}

# -----------------------------------------------------------------------------
# __overlay_short_name AGENT_NAME
#   Map a Task subagent_type to the overlay file short name used on disk.
#   `agent-flow:fixer` -> `fixer`. A bare `fixer` passes through unchanged.
#   Strips any `<plugin>:` prefix. PATH-TRAVERSAL GUARD (REQ-038): reject a short
#   name with `/`, `\`, or `..` (return non-zero) before forming a traversal path.
# -----------------------------------------------------------------------------
__overlay_short_name() {
  local agent_name="$1"
  local short="${agent_name##*:}"
  case "$short" in
    *'/'*|*'\'*|*'..'*) return 1 ;;
  esac
  printf '%s' "$short"
}

# -----------------------------------------------------------------------------
# check_dispatch_witness STAGE STATE_JSON [OVERRIDE_PATH]
#   V1+V2 dispatch-witness verification (jq-free). OVERRIDE_PATH defaults to
#   `customization/`.
#
#   Echoes verdict to stdout: WITNESS_OK | WITNESS_MISSING | WITNESS_MISMATCH.
#   Exit codes:
#     0 = OK       (V1 recompute matches stored witness AND V2 overlay-presence holds)
#     1 = MISSING  (a required input field is absent / null; or the stage was
#                   legitimately skipped -> not evaluated)
#     2 = MISMATCH (V1 recompute != stored witness, OR V2 detects an available
#                   overlay that was not applied/recorded, OR the stored
#                   witness is malformed)
#
#   V1 (consistency recompute): recompute
#     sha256(agent_name|model|prompt_head_128|overlay_source|overlay_digest)
#   from the STORED stage fields and compare to the stored dispatch_witness.
#   Any difference => WITNESS_MISMATCH. Binds the overlay into the receipt and
#   catches witness-field tampering/corruption.
#
#   V2 (overlay-presence): derive the agent short name from agent_name
#   (`agent-flow:fixer` -> `fixer`) and test whether
#   <OVERRIDE_PATH>/<short>.toml exists on disk. If the .toml EXISTS but the
#   stage's overlay_source != toml => WITNESS_MISMATCH (an available overlay
#   was not applied/recorded). The hook reads the DEFAULT override path only
#   (documented limitation).
#
#   Precedence: a legitimately skipped stage (status:"skipped") is NOT
#   evaluated -> WITNESS_MISSING (never a MISMATCH). A missing required input
#   (and not skipped) => WITNESS_MISSING. Otherwise V1 then V2 decide.
#
#   Assumes pretty-printed (2-space indent) state.json per state/schema.md A-5.
# -----------------------------------------------------------------------------
check_dispatch_witness() {
  local stage="${1:?usage: check_dispatch_witness STAGE STATE_JSON [OVERRIDE_PATH]}"
  local state_json="${2:?missing STATE_JSON}"
  local override_path="${3:-customization/}"
  [ -f "$state_json" ] || { echo "WITNESS_MISSING"; return 1; }

  # Legitimate skip: not evaluated, never a MISMATCH.
  local status
  status=$(__read_stage_field "$stage" "$state_json" "status")
  if [ "$status" = "skipped" ]; then
    echo "WITNESS_MISSING"; return 1
  fi

  # Pull stored witness inputs.
  local stored_witness agent_name model prompt_head_128 overlay_source overlay_digest
  stored_witness=$(__read_stage_field "$stage" "$state_json" "dispatch_witness")
  agent_name=$(__read_stage_field "$stage" "$state_json" "agent_name")
  model=$(__read_stage_field "$stage" "$state_json" "model")
  prompt_head_128=$(__read_stage_field "$stage" "$state_json" "prompt_head_128")
  overlay_source=$(__read_stage_field "$stage" "$state_json" "overlay_source")
  overlay_digest=$(__read_stage_field "$stage" "$state_json" "overlay_digest")

  # Any required witness input absent => MISSING (not a MISMATCH).
  if [ -z "$stored_witness" ] || [ -z "$agent_name" ] || [ -z "$model" ] \
     || [ -z "$prompt_head_128" ] || [ -z "$overlay_source" ] || [ -z "$overlay_digest" ]; then
    echo "WITNESS_MISSING"; return 1
  fi

  # Stored witness must be well-formed before any comparison.
  __validate_witness_format "$stored_witness" || { echo "WITNESS_MISMATCH"; return 2; }

  # --- V1: consistency recompute --------------------------------------------
  local recomputed
  recomputed=$(compute_dispatch_witness \
                 "$stage" "$agent_name" "$model" "$prompt_head_128" \
                 "$overlay_source" "$overlay_digest" 2>/dev/null) || {
    # No sha256 tool: cannot recompute. Treat as MISSING (not a false MISMATCH).
    echo "WITNESS_MISSING"; return 1
  }
  if [ "$recomputed" != "$stored_witness" ]; then
    echo "WITNESS_MISMATCH"; return 2
  fi

  # --- V2: overlay-presence -------------------------------------------------
  local short toml_path
  short=$(__overlay_short_name "$agent_name")
  toml_path="${override_path%/}/${short}.toml"
  if [ -f "$toml_path" ] && [ "$overlay_source" != "toml" ]; then
    echo "WITNESS_MISMATCH"; return 2
  fi

  echo "WITNESS_OK"; return 0
}

# -----------------------------------------------------------------------------
# emit_witness_audit STAGE VERDICT AUDIT_LOG_PATH
#   Append "<ISO-TS> <STAGE> <VERDICT>" line to the audit log (top-level
#   .agent-flow/dispatch-audit.log). Best-effort - never
#   fails the caller even if the path is unwritable.
# -----------------------------------------------------------------------------
emit_witness_audit() {
  local stage="${1:?usage: emit_witness_audit STAGE VERDICT AUDIT_LOG}"
  local verdict="${2:?missing VERDICT}"
  local audit_log="${3:?missing AUDIT_LOG}"
  stage="${stage//[$'\n\r']/_}"
  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo unknown)"
  local audit_dir="${audit_log%/*}"
  if [ "$audit_dir" != "$audit_log" ] && [ -n "$audit_dir" ]; then
    mkdir -p "$audit_dir" 2>/dev/null || true
  fi
  printf '%s %s %s\n' "$ts" "$stage" "$verdict" >> "$audit_log" 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Self-test mode: `bash core/lib/stage-invariant.sh --self-test`
# Synthetic 5-tuple V1+V2 smoke, then KEYED ROUND-TRIPS (REQ-030): bash holds NO
# HMAC -- shell to witness_core.py (tag) + witness_key.py (key/bootstrap) for
# key-present / key-absent / wrong-key round-trips; skipped if Python is absent.
# -----------------------------------------------------------------------------
if [ "${1:-}" = "--self-test" ]; then
  agent="agent-flow:analyst"
  model="sonnet"
  head="ABC"
  src="none"
  dig=$(compute_overlay_digest "none") || { echo "self-test: overlay-digest failed"; exit 1; }
  [ "$dig" = "none" ] || { echo "self-test: expected overlay_digest=none got $dig"; exit 1; }
  w=$(compute_dispatch_witness "triage" "$agent" "$model" "$head" "$src" "$dig") \
    || { echo "self-test: compute failed"; exit 1; }
  printf '%s' "$w" | grep -qE '^[0-9a-f]{64}$' || { echo "self-test: bad shape: $w"; exit 1; }

  tmp_state=$(mktemp 2>/dev/null || echo /tmp/st_$$)
  # Isolated override path so V2 finds no .toml for analyst (overlay_source=none is consistent).
  tmp_override=$(mktemp -d 2>/dev/null || echo /tmp/sto_$$)
  mkdir -p "$tmp_override" 2>/dev/null || true
  trap 'rm -rf "$tmp_state" "$tmp_override"' EXIT
  printf '{\n  "stages": {\n    "triage": {\n      "status": "in_progress",\n      "agent_name": "%s",\n      "model": "%s",\n      "prompt_head_128": "%s",\n      "overlay_source": "%s",\n      "overlay_digest": "%s",\n      "dispatch_witness": "%s"\n    }\n  }\n}\n' \
    "$agent" "$model" "$head" "$src" "$dig" "$w" > "$tmp_state"

  v=$(check_dispatch_witness triage "$tmp_state" "$tmp_override") || { echo "self-test: check rc != 0 verdict=$v"; exit 1; }
  [ "$v" = "WITNESS_OK" ] || { echo "self-test: expected WITNESS_OK got $v"; exit 1; }

  # Negative check: corrupting a stored input must produce WITNESS_MISMATCH.
  bad_state=$(mktemp 2>/dev/null || echo /tmp/stb_$$)
  printf '{\n  "stages": {\n    "triage": {\n      "status": "in_progress",\n      "agent_name": "%s",\n      "model": "opus",\n      "prompt_head_128": "%s",\n      "overlay_source": "%s",\n      "overlay_digest": "%s",\n      "dispatch_witness": "%s"\n    }\n  }\n}\n' \
    "$agent" "$head" "$src" "$dig" "$w" > "$bad_state"
  vb=$(check_dispatch_witness triage "$bad_state" "$tmp_override"); rc=$?
  rm -f "$bad_state"
  [ "$vb" = "WITNESS_MISMATCH" ] && [ "$rc" -eq 2 ] || { echo "self-test: expected WITNESS_MISMATCH/2 got $vb/$rc"; exit 1; }

  # --- keyed round-trips: shell to the Python authority (REQ-030) -------------
  pybin=$(command -v python3 || command -v python || true)
  sd=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)
  cpy="$sd/hooks/lib/witness_core.py"; kpy="$sd/hooks/lib/witness_key.py"
  if [ -n "$pybin" ] && [ -f "$cpy" ] && [ -f "$kpy" ]; then
    kf() { echo "self-test: keyed $1" >&2; rm -f "$kt" 2>/dev/null || true; exit 1; }
    "$pybin" "$cpy" --self-test >/dev/null 2>&1 || kf "core golden (key-present tag)"
    "$pybin" "$kpy" --self-test >/dev/null 2>&1 || kf "key lifecycle + bootstrap (key-absent)"
    kt=$(mktemp -u 2>/dev/null || echo "${TMPDIR:-/tmp}/ks_$$")
    K=$("$pybin" "$kpy" generate "$kt" 2>/dev/null) || kf "key generate"
    [[ "$K" =~ ^[0-9a-f]{64}$ ]] || kf "key not 64-hex (len ${#K})"
    ta() { "$pybin" "$cpy" tag "$1" agent-flow:fixer opus HEAD none none fixer_reviewer RUN-1 nonce-1; }
    T1=$(ta "$K"); [[ "$T1" =~ ^[0-9a-f]{64}$ ]] || kf "key-present tag shape"
    [ "$(ta ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)" != "$T1" ] || kf "wrong-key same tag"
    rm -f "$kt" 2>/dev/null || true
  fi

  echo "self-test: PASS"
  exit 0
fi
