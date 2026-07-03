# post-publish-hook

## Purpose

Execute pipeline hooks and fire webhooks at stage boundaries.

## Input Contract
- `config` — Automation Config (Hooks section, Notifications section, Custom Agents section)
- `pr_url` — URL of the created PR
- `issue_id` — issue tracker ID
- `branch` — branch name used for the PR

## Process
1. If Hooks → Post-publish exists: run the command via Bash. Log result.
2. If Custom Agents → Post-publish agent exists: read the agent definition from the configured path, dispatch via Task tool using the model from the agent's frontmatter. Log result.
3. If Notifications → Webhook URL exists and `pr-created` is in On events: fire webhook:
   <!-- @snippet:webhook-curl -->
   ```bash
   curl --proto "=http,https" --max-time 5 --retry 0 -X POST -H "Content-Type: application/json" \
     --data-binary @- "${Webhook_URL}" <<EOF
   {"event":"pr-created","issue_id":"${issue_id}","pr_url":"${pr_url}","timestamp":"${ISO8601}"}
   EOF
   ```
   Note: Use a heredoc to pass the JSON body so that special characters (quotes, backslashes) in variable values do not break the shell command. The `--proto "=http,https"` flag restricts the transport to HTTP/HTTPS only, blocking `file://`, `gopher://`, `ftp://`, and other schemes.

## Output Contract
- Per-hook result: `{hook_name}: SUCCESS | FAILED | SKIPPED`
- Overall: advisory — no single failure changes the pipeline outcome.

## Failure Handling
- Post-publish hook execution failure → log warning "[WARN] Post-publish hook failed: {error}", continue. Do NOT block or roll back.
- Post-publish custom agent BLOCK → log warning "[WARN] Post-publish agent blocked: {reason}", continue.
- Webhook failure (non-2xx or timeout) → log warning "[WARN] Webhook delivery failed: {error}", continue.
- All post-publish hooks are advisory only. Failures here never block the pipeline.

## Section 4: Pipeline lifecycle events

Observability Hooks for headless + monitoring integrations. Three events fire at pipeline lifecycle boundaries.

### Events

| Event | When | Purpose |
|---|---|---|
| `pipeline-started` | When a pipeline (fix-bugs/implement-feature/scaffold) begins processing an issue | Notify monitoring that work has started |
| `step-completed` | When a top-level pipeline stage (e.g., triage, code_analysis, fixer_reviewer, publisher) completes successfully or is blocked | Real-time progress and cost visibility |
| `pipeline-completed` | When a pipeline finishes (success OR block) | Final outcome + totals |
| `pipeline-resumed` | When a paused pipeline resumes (operator answers NEEDS_CLARIFICATION by re-invoking the entry-point skill with `--clarification`; auto-resume is detected inline by `core/resume-detection.md`) | Close the pause/resume lifecycle loop |

### Granularity Decision

`step-completed` fires per TOP-LEVEL STAGE only, never per fixer iteration. Stage boundaries are the pipeline's named stages using canonical names: `triage`, `code_analysis`, `reproduction`, `fixer_reviewer`, `test`, `e2e_test`, `browser_verification`, `acceptance_gate`, `publisher`, `deployment`, `spec_analysis`, `architect`, `spec_writer`, `spec_reviewer`, `scaffolder`.

### Payload Contracts

#### pipeline-started

`run_id` format is `"{issue_id}_{YYYYMMDDTHHMMSSZ}"` — compact basic-format ISO-8601, no colons, URL-safe and filename-safe.

```json
{
  "event": "pipeline-started",
  "run_id": "PROJ-42_20260417T143000Z",
  "issue_id": "PROJ-42",
  "pipeline": "fix-bugs",
  "timestamp": "2026-04-17T14:30:00Z"
}
```

#### step-completed

`duration` is in whole seconds. `iteration_count` is 1 for non-loop stages. `step_name` MUST use canonical stage names.

```json
{
  "event": "step-completed",
  "run_id": "PROJ-42_20260417T143000Z",
  "issue_id": "PROJ-42",
  "step_name": "fixer_reviewer",
  "duration": 525,
  "iteration_count": 3,
  "timestamp": "2026-04-17T14:40:00Z"
}
```

#### pipeline-completed

`outcome` is one of: `success`, `blocked`, `failed`. `pr_url` is `null` when no PR was created. _(Note: outcome `"failed"` covers logical fall-through only — does NOT fire on process death, OOM, or SIGKILL; those leave `state.json` in `running` until external intervention.)_

```json
{
  "event": "pipeline-completed",
  "run_id": "PROJ-42_20260417T143000Z",
  "issue_id": "PROJ-42",
  "status": "completed",
  "outcome": "success",
  "duration": 692,
  "pr_url": "https://gitea.example.com/owner/repo/pulls/99",
  "timestamp": "2026-04-17T14:42:00Z"
}
```

### Curl Pattern (identical to Section 3 pr-created)

Transport, curl invocation, and failure handling are identical to Section 3. Use the same `curl --max-time 5 --retry 0` pattern with a heredoc to pass the JSON body. Advisory failure: log `[WARN] Webhook delivery failed: {error}` and continue pipeline. Never block.

**Variable naming convention:** Skills read the `Webhook URL` config key into a bash variable named `${Webhook_URL}` (config-key casing, mixed-case). For heredoc-style curl calls the variable is used directly as `"${Webhook_URL}"`. For jq-pipe-style calls (e.g., pipeline-paused), skills first assign `WEBHOOK_URL="${Webhook_URL}"` and use the uppercase form `"${WEBHOOK_URL}"`. Both refer to the same `Webhook URL` config value — the two variable names are not different config keys. Maintainers MUST update BOTH if renaming.

**Field value safety:** The heredoc prevents shell-word-splitting and glob expansion, but a raw
`"${var}"` substitution inside a heredoc JSON literal does NOT JSON-encode field values. Any field
whose value originates from external input (e.g., `issue_id` read from the tracker, `pr_url` from
the SCM) MUST be safe for direct JSON string embedding — free of `"`, `\`, and control characters.
The `issue_id` regex gate (see issue_id validation in skills' Step 0, R-ITEM-2.1 through R-ITEM-2.6)
ensures `issue_id` and `run_id` contain only `[A-Za-z0-9#_-]` characters and are therefore safe to
interpolate directly. The `pr_url` field in `pipeline-completed` payloads SHOULD be percent-encoded
by the SCM tool before being written to state.json; implementers MUST NOT construct `pr_url` from
raw user-controlled input. For agent-generated free-form prose fields (e.g., `reason` in
`agent-flow-block` events), use `jq -n --arg` structural payload construction (see
`core/block-handler.md` Step 6 for the canonical pattern) rather than interpolating variables into
a quoted JSON literal.

Example for `pipeline-started`:

<!-- @snippet:webhook-curl -->
```bash
curl --proto "=http,https" --max-time 5 --retry 0 -X POST -H "Content-Type: application/json" \
  --data-binary @- "${Webhook_URL}" <<EOF
{"event":"pipeline-started","run_id":"${run_id}","issue_id":"${issue_id}","pipeline":"${pipeline}","timestamp":"${ISO8601}"}
EOF
```

The `--proto "=http,https"` flag restricts the transport to HTTP/HTTPS only. This blocks `file://`, `gopher://`, `ftp://`, and other URL schemes that could be used for SSRF. All Section 3 and Section 4 curl webhook invocations MUST include this flag.

### On events Filter

Project CLAUDE.md Automation Config "Notifications" section supports these `On events` tokens (CSV):
- `pr-created`, `issue-blocked`
- `pipeline-started`, `step-completed`, `pipeline-completed`
- `pipeline-paused`
- `pipeline-resumed`

If a token is present in the `On events` list, the webhook fires for that event. If omitted, the event is skipped silently.

### Webhook event: pipeline-paused

Fires once per `paused` transition (NEEDS_CLARIFICATION pause). Optional in `On events` config — absence preserves default behavior. MUST NOT fire `pipeline-completed` on the same pause transition.

Subject to the in-memory circuit breaker (Section 4.2) — the failure counter is shared with `pipeline-completed` et al. Curl invocation MUST use `--proto "=http,https"`, `--max-time 5`, `--retry 0`, and advisory-failure logging (same pattern as other Section 4 events).

Payload shape:

```json
{
  "event": "pipeline-paused",
  "run_id": "{issue_id}_{YYYYMMDDTHHMMSSZ}",
  "issue_id": "PROJ-42",
  "paused_at": "2026-04-20T14:30:00Z",
  "clarification": {
    "question": "<sanitized via sanitize_block_reason() to ≤280 chars>",
    "asked_by_agent": "fixer",
    "asked_at_step": "fixer-iteration-2"
  },
  "iteration": 2
}
```

`run_id` format is `"{issue_id}_{YYYYMMDDTHHMMSSZ}"` (consistent with other Section 4 events). `iteration` refers to the fixer-reviewer iteration counter at the time the pause was triggered. `clarification.question` is sanitized via `sanitize_block_reason()` (truncated to ≤280 chars).

Example curl invocation (uses `jq -n --arg` structural construction for safe field encoding — see Field value safety note above):

```bash
<!-- @snippet:webhook-curl -->
# pipeline-paused webhook firing site (circuit-breaker scope)
# Subject to in-memory circuit breaker (counter shared with pipeline-completed et al.)
jq -nc \
  --arg event "pipeline-paused" \
  --arg run_id "${RUN_ID}" \
  --arg issue_id "${ISSUE_ID}" \
  --arg paused_at "$(date -u +%FT%TZ)" \
  --arg question "$(printf '%s' "$RAW_QUESTION" | sanitize_block_reason)" \
  --arg asked_by_agent "${ASKED_BY_AGENT}" \
  --arg asked_at_step "${ASKED_AT_STEP}" \
  --argjson iteration "${ITERATION:-0}" \
  '{event: $event, run_id: $run_id, issue_id: $issue_id, paused_at: $paused_at,
    clarification: {question: $question, asked_by_agent: $asked_by_agent, asked_at_step: $asked_at_step},
    iteration: $iteration}' \
| curl --proto "=http,https" --max-time 5 --retry 0 \
    -X POST -H "Content-Type: application/json" \
    --data-binary @- "${WEBHOOK_URL}" \
    > /dev/null 2>&1 || echo "[WARN] Webhook delivery failed"
```

Invariant: `pipeline-completed` MUST NOT fire on a pause transition. `pipeline-paused` is the dedicated terminal-of-segment event for the pause transition. The firing site lives in `core/agent-states.md`.

### Webhook event: pipeline-resumed

Fires once when inline auto-resume detection (`core/resume-detection.md`) transitions state from `paused` → `running` (immediately after the state.json write). Optional in `On events` config — absence preserves default behavior.

**Negative invariant (unchanged):** `pipeline-completed` MUST NOT fire at the paused→running transition. `pipeline-resumed` is the counterpart to `pipeline-paused` — it signals that the pipeline has re-entered active processing. `pipeline-completed` fires only at the final `completed` state, which may follow after the resumed pipeline runs to completion.

Subject to the in-memory circuit breaker (Section 4.2) — the failure counter is shared with `pipeline-paused`, `pipeline-completed`, and all other Section 4 events. Curl invocation MUST use `--proto "=http,https"`, `--max-time 5`, `--retry 0`, and advisory-failure logging (same pattern as other Section 4 events).

Payload shape:

```json
{
  "event": "pipeline-resumed",
  "run_id": "{issue_id}_{YYYYMMDDTHHMMSSZ}",
  "issue_id": "PROJ-42",
  "resumed_at": "2026-04-20T15:00:00Z",
  "clarification": {
    "question": "<sanitized via sanitize_block_reason() to ≤280 chars>",
    "answer": "<first 100 chars of clarification.answer, sanitized via sanitize_block_reason()>"
  },
  "iteration": 2
}
```

`run_id` format is `"{issue_id}_{YYYYMMDDTHHMMSSZ}"` (consistent with other Section 4 events). `iteration` refers to the fixer-reviewer iteration counter at the time the pause was originally triggered (read from `state.json.clarification` at resume time). `clarification.question` is the original question (from `state.json.clarification.question`), sanitized via `sanitize_block_reason()`. `clarification.answer` is the first 100 chars of `state.json.clarification.answer`, also sanitized via `sanitize_block_reason()` (truncated after sanitation to avoid leaking credential-bearing prose).

Example curl invocation (uses `jq -n --arg` structural construction for safe field encoding — see Field value safety note above):

<!-- @snippet:webhook-curl -->
```bash
# pipeline-resumed webhook firing site (circuit-breaker scope shared with Section 4 events)
# Subject to in-memory circuit breaker (counter shared with pipeline-paused, pipeline-completed et al.)
jq -nc \
  --arg event "pipeline-resumed" \
  --arg run_id "${RUN_ID}" \
  --arg issue_id "${ISSUE_ID}" \
  --arg resumed_at "$(date -u +%FT%TZ)" \
  --arg question "$(printf '%s' "${CLARIFICATION_QUESTION}" | sanitize_block_reason)" \
  --arg answer "$(printf '%s' "${CLARIFICATION_ANSWER}" | sanitize_block_reason | cut -c1-100)" \
  --argjson iteration "${ITERATION:-0}" \
  '{event: $event, run_id: $run_id, issue_id: $issue_id, resumed_at: $resumed_at,
    clarification: {question: $question, answer: $answer},
    iteration: $iteration}' \
| curl --proto "=http,https" --max-time 5 --retry 0 \
    -X POST -H "Content-Type: application/json" \
    --data-binary @- "${WEBHOOK_URL}" \
    > /dev/null 2>&1 || echo "[WARN] Webhook delivery failed"
```

Fired by inline auto-resume detection (`core/resume-detection.md`) at the point where state transitions from `paused` back to `running`, after the state.json write. Gated on: `On events` config includes `pipeline-resumed`.

### State-Commit Ordering

Fire order is STRICT:
- For `pipeline-started`: fire AFTER `state.json` has been atomically initialized.
- For `step-completed`: fire AFTER `state.json` has been atomically written with the stage's `tokens_used`, `duration_ms`, `tool_uses`, `completed_at`. If the state.json write fails, the webhook is suppressed — the webhook stream is a projection of committed state, not an in-flight view.
- For `pipeline-completed`: fire AFTER the terminal `status` has been committed to `state.json`.

### No Skipped-Stage Event

The system does NOT emit any webhook for skipped stages. Skipped stages produce no webhook output. Pipeline skill files and this contract file MUST NOT contain emission logic for any skipped-stage event token.

### Backward Compatibility

Existing events (`pr-created`, `agent-flow-block`) are unchanged. No existing payload field has been renamed. Section 3 curl invocation is unchanged. Webhook payloads are forward-compatible — additive fields may be added in future MINOR versions. Consumers should use lenient JSON parsing (ignore unknown fields).

### 4.2 Circuit breaker semantics

To prevent runaway latency from a dead webhook endpoint (each call costs up to 5s with `--max-time 5`), the post-publish hook maintains an **in-memory per-pipeline-run failure counter**:

- Counter starts at 0 at the beginning of every pipeline-run.
- Counter increments by 1 each time a webhook delivery emits `[WARN] Webhook delivery failed`.
- When the counter reaches **3 consecutive failures**, the circuit OPENS:
  - All subsequent webhook calls in this pipeline-run are SKIPPED (no curl invocation).
  - The skill emits exactly once: `[WARN] Circuit breaker open: 3 consecutive webhook failures. Suppressing remaining webhooks for this run.`
- Counter resets to 0 at the START of the next pipeline-run (no cross-run persistence; not stored in state.json).
- Circuit suppression is **advisory** — pipeline progression is NEVER blocked by an open circuit.

Operators monitoring a pipeline log should treat repeated `Circuit breaker open` lines across runs as a misconfiguration signal (dead webhook endpoint) OR a malicious-PR signal (covert-channel DoS via injected `Webhook URL`). See `docs/guides/autopilot.md` "Webhook Reliability" subsection.

## Section 5: pipeline-history.md append

Fires AFTER Section 4 `pipeline-completed` webhook. Advisory failure semantics — never blocks the pipeline.

### Append target
`.agent-flow/pipeline-history.md` (NOT `.claude/`; consistent with all other plugin state under `.agent-flow/`).

### Per-run entry format
```markdown
## {run_id}
- date: {started_at}
- pipeline: {mode}
- outcome: {final state.status}
- agents_touched: {comma-separated stages with status:completed}
- block_agent: {block.agent or null}
- block_step: {block.step or null}
- block_reason: {sanitize_block_reason(block.reason) or null}
- complexity: {triage.complexity or null}
- duration_s: {pipeline.total_duration_ms / 1000 or null}
```

### Sensitive field exclusion (hard contract)
This Section 5 stores `block.reason` (a sanitized 2-sentence summary) ONLY. NEVER `block.detail`. See `state/schema.md` Sensitive field exclusion contract.

### `sanitize_block_reason()` Bash function (centralized credential redaction — POSIX-portable, 18 patterns)

Uses ONLY POSIX-portable regex constructs (no word-boundary, non-whitespace, digit, or word-char shorthand escapes — those are PCRE/Perl extensions that GNU `sed -E` accepts but BSD `sed -E` on macOS/FreeBSD silently treats as literal characters, causing silent credential leakage). Replacements: word-boundary → `(^|[[:space:]])` with capture-group preservation; non-whitespace class → `[^[:space:]]+`; digit class → `[0-9]`. All anchored alternation explicit; `LC_ALL=C` set for byte-locale stability.

Covers 18 patterns including: URL credentials, env-var assignments (upper and lowercase), Bearer/Authorization headers, AWS access keys, Slack tokens, GitHub tokens, generic API keys, JWTs, PGP/SSH private-key BEGIN/END sentinels, Stripe live keys, Google API keys, OAuth refresh tokens, bare-keyword credential variable names (`password=`, `secret=`, `token=`, `key=`, `auth=`), and JSON-style credential fields (`{"password": "secret"}`).

```bash
sanitize_block_reason() {
  local input="$1"
  LC_ALL=C
  # 18-row credential-pattern redaction list (POSIX-portable, apply in order, additive across releases)
  printf '%s' "$input" \
    | sed -E 's![A-Za-z][A-Za-z0-9+.-]*://[^/[:space:]:]+:[^/[:space:]@]+@[^[:space:]]+![REDACTED-URL]!g' \
    | sed -E 's!(^|[[:space:]])([A-Z_][A-Z0-9_]*=)[^[:space:]]+!\1\2[REDACTED-VAR]!g' \
    | sed -E 's![Bb]earer[[:space:]]+[A-Za-z0-9._~+/=-]+![REDACTED-BEARER]!g' \
    | sed -E 's![Aa]uthorization:[[:space:]]*[^[:space:]]+![REDACTED-AUTH]!g' \
    | sed -E 's!(AKIA|ASIA)[A-Z0-9]{16}![REDACTED-AWS-AKID]!g' \
    | sed -E 's!AWS_(SECRET|ACCESS_KEY)_?ID?=[^[:space:]]+![REDACTED-AWS-VAR]!g' \
    | sed -E 's!xox[bporsa]-[A-Za-z0-9-]+![REDACTED-SLACK-TOKEN]!g' \
    | sed -E 's!(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}![REDACTED-GITHUB-TOKEN]!g' \
    | sed -E 's!([Aa]pi[_-]?[Kk]ey|[Aa]pikey)[[:space:]]*[:=][[:space:]]*[^[:space:]]+![REDACTED-APIKEY]!g' \
    | sed -E 's!eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+![REDACTED-JWT]!g' \
    | sed -E 's!-----BEGIN [A-Z ]*PRIVATE KEY[A-Z ]*-----![REDACTED-PRIVATE-KEY]!g' \
    | sed -E 's!-----END [A-Z ]*PRIVATE KEY[A-Z ]*-----![REDACTED-PRIVATE-KEY-END]!g' \
    | sed -E 's!sk_live_[A-Za-z0-9]+![REDACTED-STRIPE-LIVE]!g' \
    | sed -E 's!AIza[A-Za-z0-9_-]{35}![REDACTED-GOOGLE-API-KEY]!g' \
    | sed -E 's!1//0[A-Za-z0-9_-]+![REDACTED-OAUTH-REFRESH]!g' \
    | sed -E 's!(^|[[:space:]])(pass(word)?|secret|token|key|api[-_]?key|access[-_]?key|auth)=[^[:space:]]+!\1\2=[REDACTED-LOWER-VAR-BARE]!gi' \
    | sed -E 's!(^|[[:space:]])([A-Za-z_][A-Za-z0-9_]*([Pp][Aa][Ss][Ss]([Ww][Oo][Rr][Dd])?|[Ss][Ee][Cc][Rr][Ee][Tt]|[Tt][Oo][Kk][Ee][Nn]|[Kk][Ee][Yy]))=[^[:space:]]+!\1\2=[REDACTED-LOWER-VAR]!g' \
    | sed -E 's!"([Pp]assword|[Ss]ecret|[Tt]oken|[Aa]pi_?[Kk]ey|[Aa]ccess_?[Kk]ey|[Cc]redential)"[[:space:]]*:[[:space:]]*"[^"]+"!"\1": "[REDACTED-JSON-FIELD]"!g'
}
```

**Multi-line credential limitation:** `sed -E` operates line-by-line (no `N` accumulator in the pattern list above), so multi-line credential bodies (e.g., the base64 body lines between `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----`) are NOT redacted as a single block. Both delimiters are captured (`[REDACTED-PRIVATE-KEY]` for BEGIN, `[REDACTED-PRIVATE-KEY-END]` for END), but the body lines in-between still leak through. Operators with multi-line PGP/SSH key material in `block.detail` SHOULD use the upstream defense at the issue-tracker comment layer (`block.reason` is the only field surfaced to webhook/history channels — see Sensitive field exclusion contract in `state/schema.md`); full multi-line redaction via `awk`-style accumulator is a future enhancement.

**POSIX portability test recommendation:** the credential-redaction test scenario MUST be runnable on both GNU sed (Linux + Git-Bash on Windows) AND BSD sed (macOS, FreeBSD) — preferably as a CI matrix entry covering `ubuntu-latest` AND `macos-latest`. As a fallback validation when only one platform is available, the test SHOULD assert the function output for inputs containing `PASSWORD=secret123` (no leading word boundary) results in `[REDACTED-VAR]` — proves the `(^|[[:space:]])` anchored-alternation portable substitute is working.

**Pattern enumeration verification (machine-checkable):** All 18 redaction tags MUST appear in the function body. Verifier greps:
- `[REDACTED-URL]`, `[REDACTED-VAR]`, `[REDACTED-BEARER]`, `[REDACTED-AUTH]`, `[REDACTED-AWS-AKID]`, `[REDACTED-AWS-VAR]`, `[REDACTED-SLACK-TOKEN]`, `[REDACTED-GITHUB-TOKEN]`, `[REDACTED-APIKEY]`, `[REDACTED-JWT]`, `[REDACTED-PRIVATE-KEY]`, `[REDACTED-PRIVATE-KEY-END]`, `[REDACTED-STRIPE-LIVE]`, `[REDACTED-GOOGLE-API-KEY]`, `[REDACTED-OAUTH-REFRESH]`, `[REDACTED-LOWER-VAR-BARE]`, `[REDACTED-LOWER-VAR]`, `[REDACTED-JSON-FIELD]`.

### Retention
After every append, count H2 anchors (`## ` at line start). If `count > 50`, trim oldest H2 sections until `count == 50`. Implementation (Bash) — section-count-aware (a prior line-counter approximation `awk '/^## /{i++} i>=NR-50'` was incorrect: it counted by file line number, not section count, and so silently truncated arbitrary numbers of sections depending on per-section line length):

```bash
file=".agent-flow/pipeline-history.md"
total_sections=$(grep -c '^## ' "$file" 2>/dev/null || echo 0)
if [ "$total_sections" -gt 50 ]; then
  cutoff=$((total_sections - 50))
  # Keep the LAST 50 sections — print everything from the (cutoff+1)-th section onward.
  # Lines before the first H2 (preamble) are dropped; subsequent appends rebuild the file.
  awk -v cutoff="$cutoff" '
    /^## / { section_num++ }
    section_num > cutoff
  ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
fi
```

Section boundaries are preserved because the awk gate (`section_num > cutoff`) flips on the H2 line itself and stays on for all subsequent lines until the next H2 increments `section_num` — so each H2 block is kept whole. Atomic mv: a mid-trim crash leaves `$file.tmp` orphan but original `$file` intact.

### Failure semantics
All errors logged as `[WARN] pipeline-history.md append failed: <reason>`. Pipeline continues unconditionally.
