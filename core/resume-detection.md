# Resume Detection

## Purpose

Shared resume-detection contract used by all pipeline entry-point skills (`fix-bugs`,
`implement-feature`, `scaffold`). Provides a single source of truth for path-traversal validation, state.json
existence check, schema-version warning, status-branch with `--yolo` matrix, phase-scan
loop, staleness check, decomposition-partial detection, and interactive prompt + webhook
firing.

The contract is INVOKED before any agent dispatch in the calling skill. It NEVER blocks the
pipeline on a recoverable condition (corrupt JSON, missing optional field, webhook failure)
— blocking is reserved for path-traversal violations and explicit operator abort.

---

## Input Contract

- **ISSUE_ID** (string, required for single-mode entry-points; for batch-mode set to
  `BATCH_RUN_ID = "batch-{timestamp}"`) — the run identifier used as a directory key under
  `.agent-flow/`.
- **MODE** (enum: `single` | `batch`, required) — supplied by the calling skill.
- **GOT_YOLO** (bool, default false) — passed from skill flag-parsing.
- **GOT_STEP_MODE** (bool, default false) — passed from skill flag-parsing.
- **Webhook_URL** (string, may be absent) — from Automation Config Notifications section.
- **On_events** (CSV string, may be absent) — from Automation Config Notifications section.
- **CLARIFICATION_TEXT** (string, may be absent) — from `--clarification "<text>"` flag.

---

## Output Contract

- **RESUME_POINT** (enum) — one of:
  - `FRESH` — no state.json present, or operator chose `n=restart`; calling skill runs full
    pipeline from step 1.
  - `triage` | `code_analysis` | `reproduction` | `fixer_reviewer` | `decomposition` |
    `test` | `e2e_test` | `browser_verification` | `acceptance_gate` | `publisher` —
    calling skill skips ahead per its own resume mapping (see `skills/fix-bugs/SKILL.md`
    §2.5, `skills/implement-feature/SKILL.md`, `skills/scaffold/SKILL.md`).
  - `PUBLISHED` — pipeline already completed with PR; calling skill displays the PR URL
    and exits 0.
  - `ABORTED_BY_OPERATOR` — operator chose `abort`; calling skill exits 1.
- **RESTORED_CONTEXT** (string, may be empty) — JSON-serialized object with fields the
  calling skill MAY use to skip re-fetch operations: `acceptance_criteria` (array),
  `complexity` (string), `severity` (string), `area` (string), `flags` (array). Sourced
  from state.json `triage.*` and `config.flags`.
- **PIPELINE_TYPE** (enum: `BUG` | `FEATURE` | `SCAFFOLD`) — read from
  `state.pipeline_type`; if absent, derived from state.json structure or defaulted from
  the calling skill's invocation context.

---

## Process

### Step 1 — Issue-ID path-traversal validation

Use the bash `[[ =~ ]]` operator with whole-string anchoring. The `[[ =~ ]]` form anchors
the match to the entire value (NOT per line), so a multi-line ANSI-C payload such as
`$'../../etc/passwd\nPROJ-42'` is rejected. Equivalent `grep -qE` would let the second
line through.

```bash
# Canonical path-traversal defense — single source of truth.
if [[ ! "${ISSUE_ID}" =~ ^[A-Za-z0-9._-]+$ || "${ISSUE_ID}" =~ ^\.+$ ]]; then
  echo "[BLOCK] Invalid issue_id: ${ISSUE_ID}" >&2
  exit 1
fi
```

The character class explicitly forbids `/` and `\\`; the second clause forbids dot-only
strings (`.`, `..`, `...`). Validation failure exits 1 immediately — no state.json access,
no webhook fired.

---

### Step 2 — State file path resolution

```bash
STATE_DIR=".agent-flow/${ISSUE_ID}"
STATE_FILE="${STATE_DIR}/state.json"
```

The path is constructed AFTER Step 1 validation, so the components cannot include `..`,
`/`, or `\\` from operator input.

---

### Step 3 — File existence check

```bash
if [ ! -f "$STATE_FILE" ]; then
  RESUME_POINT="FRESH"
  RESTORED_CONTEXT=""
  PIPELINE_TYPE=""
  # Skip directly to Step 9 (return to caller).
  return 0
fi
```

When no state.json exists, the contract returns FRESH — the calling skill runs its full
pipeline from step 1 with a new `run_id`.

---

### Step 4 — Status detection (grep-based)

```bash
STATUS=$(grep -oE '"status"[[:space:]]*:[[:space:]]*"[a-z_]+"' "$STATE_FILE" \
         | head -1 | grep -oE '"[a-z_]+"$' | tr -d '"')
PLUGIN_VERSION=$(grep -oE '"plugin_version"[[:space:]]*:[[:space:]]*"[0-9.]+"' "$STATE_FILE" \
                 | grep -oE '"[0-9.]+"$' | tr -d '"')
PIPELINE_TYPE_RAW=$(grep -oE '"pipeline_type"[[:space:]]*:[[:space:]]*"[a-z_]+"' "$STATE_FILE" \
                    | grep -oE '"[a-z_]+"$' | tr -d '"')
UPDATED_AT=$(grep -oE '"updated_at"[[:space:]]*:[[:space:]]*"[^"]+"' "$STATE_FILE" \
             | grep -oE '"[^"]+"$' | tr -d '"')
BLOCK_REASON=$(grep -oE '"reason"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" \
               | head -1 | grep -oE '"[^"]*"$' | tr -d '"')
```

`BLOCK_REASON` is sourced from the `block.reason` field (per `state/schema.md` and
`core/block-handler.md` Process step 5, the only object in state.json carrying a bare
`"reason"` key) and is only meaningful when `$STATUS = "blocked"`; it is surfaced in the
Step 9 prompt (see below).

If `$STATUS` is empty (corrupt JSON or absent field), log
`[WARN] state.json present but status field unreadable; treating as FRESH`, set
`RESUME_POINT="FRESH"`, return 0.

`PIPELINE_TYPE_RAW` maps to the OUTPUT contract `PIPELINE_TYPE`: `bug_fix` → `BUG`,
`feature` → `FEATURE`, `scaffold` → `SCAFFOLD`. If `PIPELINE_TYPE_RAW` does not match the
calling skill's expected pipeline type, log
`[WARN] state.json pipeline_type=${PIPELINE_TYPE_RAW} does not match invoking skill; continuing.`
and continue (advisory only — never blocks).

---

### Step 5 — `--step-mode` override

If `GOT_STEP_MODE=true` AND `RESUME_POINT != FRESH`, ALL subsequent status branches in
Step 6 route unconditionally to the Step 9 interactive prompt (regardless of `$STATUS`).
This implements AC-020: the interactive prompt is shown ALWAYS when `--step-mode` is
active and a non-FRESH state exists. `--step-mode` is mutually exclusive with `--yolo`
(the calling skill enforces this), so the `--yolo` columns in the matrix below are never
reached when `GOT_STEP_MODE=true`.

---

### Step 6 — Status branch with `--yolo` matrix

| `$STATUS` | Default action | `--yolo` action |
|-----------|---------------|-----------------|
| `running` | Continue to Step 7 (staleness) → Step 8 (phase-scan) → Step 9 (prompt) | Auto-resume; log `[INFO] --yolo: auto-resuming from {stage}`; skip prompt |
| `paused` | If CLARIFICATION_TEXT non-empty: write to `clarification.answer`, flip status, continue at asked-at-step. Else interactive prompt with question shown | If CLARIFICATION_TEXT non-empty: same as default. Else `[WARN] --yolo: pipeline paused awaiting clarification — provide --clarification "<answer>"` and exit 1 |
| `completed` | Display PR URL; return `RESUME_POINT="PUBLISHED"`. Calling skill exits 0 | Archive `state.json` to `state.json.bak-{timestamp}` (same convention as `n=restart`, Step 9); set `RESUME_POINT="FRESH"` |
| `blocked` | Continue to Step 7 (staleness) → Step 8 (phase-scan) → Step 9 (prompt, `Reason: ${BLOCK_REASON}` shown, `Retry from checkpoint? [Y/n/abort]` wording) | `[WARN] --yolo: skipping blocked pipeline — needs human resolution. Re-invoke without --yolo to retry.` and exit 1 |
| `aborted_by_system` | Same as `running` | Auto-resume |
| anything else | Treat as `running` (continue to Step 7) | Treat as `running` |

---

### Step 7 — Staleness warning

```bash
if [ -n "$UPDATED_AT" ]; then
  NOW_EPOCH=$(date -u +%s)
  UPDATED_EPOCH=$(date -u -d "$UPDATED_AT" +%s 2>/dev/null || echo 0)
  if [ "$UPDATED_EPOCH" -gt 0 ]; then
    AGE_SEC=$((NOW_EPOCH - UPDATED_EPOCH))
    if [ "$AGE_SEC" -gt 604800 ]; then
      AGE_DAYS=$((AGE_SEC / 86400))
      STALENESS_WARN="[WARN] Pipeline state is stale (last updated ${AGE_DAYS} days ago — may be from a crashed or abandoned run)."
    fi
  fi
fi
```

Threshold: 7 days = 604800 seconds. The warning is informational — it is surfaced inside
the Step 9 prompt above the `[Y/n/abort]` line, but does NOT auto-dismiss the resume.
Under `--yolo`, the warning is logged to stderr and the pipeline continues.

Schema major-version comparison runs alongside staleness:

```bash
CURRENT_VERSION=$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[0-9.]+"' .claude-plugin/plugin.json \
                  | grep -oE '"[0-9.]+"$' | tr -d '"')
if [ -n "$PLUGIN_VERSION" ] && [ -n "$CURRENT_VERSION" ]; then
  STATE_MAJOR="${PLUGIN_VERSION%%.*}"
  CURRENT_MAJOR="${CURRENT_VERSION%%.*}"
  if [ "$STATE_MAJOR" != "$CURRENT_MAJOR" ]; then
    echo "[WARN] Plugin major version mismatch: state was created with v${PLUGIN_VERSION}, current is v${CURRENT_VERSION}. Major version change may affect pipeline behavior." >&2
  fi
fi
```

Major-version mismatch is advisory — never blocks resume.

---

### Step 8 — Last-step derivation (phase-scan loop)

Find the last `completed` stage (for display) and the next `in_progress` or `pending`
stage (for resume):

```bash
LAST_COMPLETED=$(grep -oE '"(triage|code_analysis|reproduction|fixer_reviewer|decomposition|test|e2e_test|browser_verification|acceptance_gate|publisher)"[[:space:]]*:[[:space:]]*\{[^}]*"status"[[:space:]]*:[[:space:]]*"completed"' "$STATE_FILE" \
                 | grep -oE '"(triage|code_analysis|reproduction|fixer_reviewer|decomposition|test|e2e_test|browser_verification|acceptance_gate|publisher)"' \
                 | tr -d '"' | tail -1)
LAST_COMPLETED="${LAST_COMPLETED:-unknown}"

NEXT_STAGE=$(grep -oE '"(triage|code_analysis|reproduction|fixer_reviewer|decomposition|test|e2e_test|browser_verification|acceptance_gate|publisher)"[[:space:]]*:[[:space:]]*\{[^}]*"status"[[:space:]]*:[[:space:]]*"in_progress"' "$STATE_FILE" \
             | grep -oE '"(triage|code_analysis|reproduction|fixer_reviewer|decomposition|test|e2e_test|browser_verification|acceptance_gate|publisher)"' \
             | tr -d '"' | head -1)
if [ -z "$NEXT_STAGE" ]; then
  NEXT_STAGE=$(awk -F'"' '/"(triage|code_analysis|reproduction|fixer_reviewer|decomposition|test|e2e_test|browser_verification|acceptance_gate|publisher)"[[:space:]]*:/{name=$2}/"status"[[:space:]]*:[[:space:]]*"pending"/{print name; exit}' "$STATE_FILE")
fi
RESUME_POINT="${NEXT_STAGE:-FRESH}"
```

This loop is the single source of truth — the design rejects any
`last_committed_stage` top-level field.

**Decomposition-partial override:** if `.claude/decomposition/${ISSUE_ID}.yaml` exists,
override `RESUME_POINT="decomposition"` regardless of the phase-scan result.

```bash
DECOMP_YAML=".claude/decomposition/${ISSUE_ID}.yaml"
if [ -f "$DECOMP_YAML" ]; then
  RESUME_POINT="decomposition"
fi
```

---

### Step 9 — Interactive prompt + webhook firing

If not in `--yolo` mode AND `RESUME_POINT != FRESH`:

```
[agent-flow] Found in-progress pipeline for ${ISSUE_ID} (last step: ${LAST_COMPLETED}).
${STALENESS_WARN:-}
Continue? [Y=resume / n=restart / abort]
```

**Blocked-status variant:** when `$STATUS = "blocked"` (routed here per Step 6), replace the
`Continue?` line with `Reason: ${BLOCK_REASON:-<unavailable>}` followed by
`Retry from checkpoint? [Y/n/abort]`. The `Y`/`n`/`abort` semantics below are otherwise
identical — only the prompt wording differs, reflecting that a blocked pipeline needs
explicit operator acknowledgement of the block reason before retrying.

- `Y` (default, also accepts empty input) → return current `RESUME_POINT`.
- `n` → archive `state.json` to `.agent-flow/${ISSUE_ID}/state.json.bak-$(date -u +%s)`,
  set `RESUME_POINT="FRESH"`.
- `abort` → set `RESUME_POINT="ABORTED_BY_OPERATOR"`; calling skill exits 1.
- Re-prompt on any other input.

Under `--step-mode` (Step 5 routed here), pause regardless of status — the prompt is the
human-decision gate.

After RESUME_POINT is finalized AND it is not FRESH/ABORTED, fire the `pipeline-resumed`
webhook if `Webhook_URL` is configured AND `pipeline-resumed` is in `On_events`. The
payload has `clarification.{question, answer}`
and `iteration` fields are present when the resume consumed a clarification answer; for
non-paused resumes (running phase-scan, decomposition, etc.), those fields are absent.

```bash
if [ -n "${Webhook_URL:-}" ] && printf '%s' "${On_events:-}" | grep -qF 'pipeline-resumed'; then
  RUN_ID=$(grep -oE '"run_id"[[:space:]]*:[[:space:]]*"[^"]+"' "$STATE_FILE" \
           | grep -oE '"[^"]+"$' | tr -d '"' | head -1)
  RESUMED_AT="$(date -u +%FT%TZ)"

  CLARIFICATION_PAYLOAD=""
  ITERATION_PAYLOAD=""
  if [ "$STATUS" = "paused" ] && [ -n "${CLARIFICATION_TEXT:-}" ]; then
    CQ=$(grep -oE '"question"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" \
         | head -1 | grep -oE '"[^"]*"$' | tr -d '"')
    CA="${CLARIFICATION_TEXT}"
    ITER=$(grep -oE '"last_clarification_iteration"[[:space:]]*:[[:space:]]*[0-9]+' "$STATE_FILE" \
           | grep -oE '[0-9]+$' | head -1)
    ITER="${ITER:-0}"
    CQ_SAN=$(printf '%s' "$CQ" | sanitize_block_reason)
    CA_SAN=$(printf '%s' "$CA" | sanitize_block_reason | cut -c1-100)
    CQ_ESC="${CQ_SAN//\"/\\\"}"
    CA_ESC="${CA_SAN//\"/\\\"}"
    CLARIFICATION_PAYLOAD=",\"clarification\":{\"question\":\"${CQ_ESC}\",\"answer\":\"${CA_ESC}\"}"
    ITERATION_PAYLOAD=",\"iteration\":${ITER}"
  fi

  printf '{"event":"pipeline-resumed","run_id":"%s","issue_id":"%s","resumed_at":"%s","resume_point":"%s"%s%s}\n' \
    "${RUN_ID}" "${ISSUE_ID}" "${RESUMED_AT}" "${RESUME_POINT}" \
    "${CLARIFICATION_PAYLOAD}" "${ITERATION_PAYLOAD}" \
  | curl --proto "=http,https" --max-time 5 --retry 0 \
      -X POST -H "Content-Type: application/json" \
      --data-binary @- "${Webhook_URL}" \
      > /dev/null 2>&1 || echo "[WARN] Webhook delivery failed"
fi
```

Webhook delivery failure is advisory — the pipeline continues unconditionally.

**NEGATIVE invariant:** the `pipeline-completed` event MUST NOT fire
from this contract. A paused resume transitions through `running` before reaching
`completed`; the `completed` event fires only at the orchestrator's terminal-state commit.

---

## Test Coverage

13 TDD scenarios (under `tests/scenarios/`) cover this contract:

1. `resume-detection-fresh.sh` — no state.json → RESUME_POINT=FRESH.
2. `resume-detection-running-phasescan.sh` — running status, last completed =
   code_analysis → RESUME_POINT=fixer_reviewer.
3. `resume-detection-paused-clarification.sh` — paused with CLARIFICATION_TEXT →
   answer written, status flipped, RESUME_POINT={asked_at_step}.
4. `resume-detection-paused-yolo-blocks.sh` — paused without CLARIFICATION_TEXT
   under `--yolo` → exit 1 with documented warning.
5. `resume-detection-completed-archives.sh` — completed status under `--yolo` →
   state.json archived, RESUME_POINT=FRESH.
6. `resume-detection-blocked-warns.sh` — blocked status; default mode prompts;
   `--yolo` exits 1.
7. `resume-detection-pathtrav-rejected.sh` — `ISSUE_ID="../../etc/passwd"` (and
   ANSI-C multi-line bypass) → exit 1 with [BLOCK].
8. `resume-detection-corrupt-json.sh` — malformed state.json → [WARN],
   RESUME_POINT=FRESH.
9. `resume-detection-schemaversion-mismatch.sh` — state plugin_version mismatch
   → [WARN], RESUME_POINT=phase-scan result.
10. `resume-detection-staleness-warn.sh` — state updated_at = 8 days ago →
    STALENESS_WARN populated.
11. `resume-detection-decomp-partial.sh` —
    `.claude/decomposition/{ISSUE_ID}.yaml` exists → RESUME_POINT=decomposition.
12. `resume-detection-webhook-fired.sh` — RESUME_POINT non-FRESH, Webhook_URL set,
    On_events contains `pipeline-resumed` → curl fired with correct payload.
13. `resume-detection-step-mode-pauses.sh` — `--step-mode` with non-FRESH
    RESUME_POINT → ALWAYS prompts even on running status.

---

## Constraints

- NEVER invoke any JSON command-line parser. All state.json parsing MUST use `grep`,
  `sed`, `awk`, and `tr` only. This preserves the parser-free reduction direction (no
  three-letter J-then-Q binary). Enforced with a zero-match assertion.
- NEVER block the pipeline on corrupt or unreadable state.json (recover by treating as
  FRESH with `[WARN]`).
- NEVER write to state.json from this contract EXCEPT in the explicit cases:
  - `clarification.answer` write when CLARIFICATION_TEXT is provided AND `$STATUS = paused`.
  - State archive on `n=restart` (Step 9) OR on `completed` status under `--yolo` (Step 6) —
    both cases move the file to the same `state.json.bak-{timestamp}` filename convention;
    this contract uses a single archive-naming pattern, never a second one.
  - Status flip from `paused` → `running` on the top-level `status` field after
    CLARIFICATION_TEXT is consumed. This contract never sets a phase's own `{stage}.status`
    to `awaiting_clarification` — no pause-write site produces that value (the phase status
    stays `in_progress`, as set at pre-dispatch), so no corresponding flip-back happens here
    either; see `state/schema.md` Step Status Enum.
- NEVER follow symlinks outside `.agent-flow/`. The path is constructed from validated
  ISSUE_ID; no `realpath` resolution that could escape the directory.
- NEVER fire the `pipeline-completed` webhook from this contract: the
  `completed` event fires ONLY at the orchestrator's terminal-state commit.
- NEVER hardcode the `customization/` path — resume detection has no overlay logic.
- NEVER increment `clarification.clarifications_consumed` here — the increment-side-of-truth
  lives in the orchestrator at the NEEDS_CLARIFICATION detection site, BEFORE the
  transition to paused.
- NEVER duplicate the `.md`-only short-circuit logic from `core/agent-override-injector.md`
  — resume detection has nothing to do with overrides.
