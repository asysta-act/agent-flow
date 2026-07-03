# Step 05 — Smoke Check (Build + Test)

After the fixer ↔ reviewer loop approves the change, verify that the codebase still builds and the existing test suite still passes BEFORE running the full test-engineer pass. This guards against regressions in files the fixer did not touch.

**Stage binding (state.json):** `smoke_check` (OPTIONAL per `<stage_allowlist>` in `skills/implement-feature/SKILL.md`).

## Gate

If neither `Build command` nor `Test command` is configured in Automation Config (`Build & Test` section):

- Write `state.json[stages.smoke_check].status = "skipped"`, `stage_name = "smoke_check"`, `agent_name = null`, `dispatched_at = <now>`, `prompt_head_128 = null`, `overlay_source = null`, `overlay_digest = null`, `dispatch_witness = null` per `../../../core/state-manager.md` atomic write protocol.
- Skip the `step-completed` webhook for skipped stages.
- Proceed to step 06.

## Pre-dispatch witness write

`smoke_check` is a controller-driven stage with NO agent dispatch — the controller runs Bash commands directly. The witness fields are written for audit-log parity (the hook still emits a line per stage; a `null` witness paired with `status = "completed"` is the canonical "ran-without-agent" pattern).

```bash
DISPATCHED_AT="$(date -u +%FT%TZ)"
# state.json[stages.smoke_check] = {
#   dispatched_at: $DISPATCHED_AT, stage_name: "smoke_check",
#   agent_name: null, prompt_head_128: null, overlay_source: null,
#   overlay_digest: null, dispatch_witness: null, status: "in_progress"
# } atomically per ../../../core/state-manager.md.
```

## Run

1. Read `Build command` from `Build & Test` config; run via Bash. Capture stdout + exit code.
2. Read `Test command` from `Build & Test` config; run via Bash. Capture stdout + exit code.
3. Both exit 0 → write `state.json[stages.smoke_check].status = "completed"`, `completed_at = <now>`, `duration_ms = <elapsed>`. Continue to step 06.
4. Either command fails → proceed to Block handler (step X) with `agent = smoke-check`, `Step = 05`, `Reason = Build|Test command failed after fixer↔reviewer approval`. Set `state.json[stages.smoke_check].status = "blocked"` and include the failing command + stdout tail (last 50 lines) in the block object.

## Webhook

After the atomic state.json write succeeds (`status = "completed"` only — not on skip), if `Webhook URL` is configured AND `step-completed` is in `On events`, fire with `step_name: "smoke_check"`, `iteration_count: 1`. Advisory failure: log `[WARN]` and continue.

## Profile skip

If the Pipeline Profile's `Skip stages` list contains `smoke-check`: record `[SKIP] smoke-check (profile: {name})`, write `state.json[stages.smoke_check].status = "skipped"` atomically, skip the webhook, proceed to step 06.
