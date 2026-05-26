# Step 01: Mode Resolve — Infrastructure, MCP, Brainstorm

This step resolves the effective pipeline mode, collects infrastructure intent, verifies MCP
connectivity, and conditionally runs the brainstorm phase for vague project descriptions.

## 01a. State Detection

Before anything else, check the target directory:

1. **Empty directory** (or does not exist) → full scaffold
2. **Existing project without CLAUDE.md** → offer: "Project exists but has no CLAUDE.md. Do you want `/scaffold add claude-md`?"
3. **Existing project with CLAUDE.md** → offer: "Project already has Automation Config. Do you want `/implement-feature`?"
4. **Existing git repo with uncommitted changes** → warn: "Uncommitted changes. Commit or stash them."

If state is not 1 and user does not confirm → STOP.

## 01b. Step 0-INFRA: Infrastructure Declaration

Collect infrastructure intent. Always runs regardless of MODE (including --yolo).

**--infra flag preset:** If `infra_preset` is set:
- Parse named pairs (`tracker:{ready|later},sc:{ready|later}`; shorthand already expanded at validation)
- Set `tracker_effective_status` and `sc_effective_status`
- Display: `Infrastructure preset from --infra flag: tracker={tracker}, SC={sc}`
- If tracker preset is `"ready"`: still ask for tracker type, instance URL, project key
- If SC preset is `"ready"`: still ask for remote and base branch

**Interactive mode** (no --infra flag):
```
Before we scaffold, tell me about your infrastructure:
1. Issue tracker: (a) Ready  (b) Not now — set up later
2. Source control: (a) Ready  (b) Not now — set up later
```

If `--issue` provided: auto-set tracker = "ready"; skip tracker question.

Collect details for services declared "ready":
- Tracker: type (`youtrack/github/jira/linear/gitea/redmine`), instance URL, project key
- SC: remote (owner/repo), base branch (default: main)

Resolve `{trackers_md_path}` once (Glob `.claude/plugins/**/docs/reference/trackers.md` → fallback → bare `docs/reference/trackers.md`). Show format examples from that file.

**Store in-memory variables:**

| Variable | Value |
|----------|-------|
| `tracker_type` | User's tracker type or `null` |
| `tracker_instance` | User's instance URL or `null` |
| `tracker_project` | User's project key or `null` |
| `sc_remote` | User's remote (owner/repo) or `null` |
| `sc_base_branch` | User's base branch or `"main"` |
| `tracker_effective_status` | `"ready"` or `"later"` |
| `sc_effective_status` | `"ready"` or `"later"` |

Write to state.json (atomic, `../../../core/state-manager.md`): `infrastructure.*` keys.
Initialize state.json: `status: "running"`, `pipeline: "scaffold"`, `run_id`, `mode`.
Generate `run_id = "{project_slug}_{YYYYMMDDTHHMMSSZ}"` (max 20 chars, alphanumeric+hyphen).

**On resume (state.json exists):** Restore in-memory variables. If `--infra` provided on re-invocation: override and update state.json.

## 01c. Step 0-MCP: MCP Verification

Only checks services declared "ready". Follow `../../../core/mcp-detection.md`.

For each "ready" service:
- Detect and verify MCP tool availability + connectivity
- Tracker: also check write access (`check_write=true`); display write-access warning before test
- If MCP unavailable: offer `(a) Configure now  (b) Skip  (c) Abort`
  - **On "Configure now" (interactive mode only — unreachable in `--yolo`):** BEFORE displaying
    the STOP message, write to state.json (atomic, `../../../core/state-manager.md`):
    `{ "mcp_setup_pending": true, "mcp_pause_step": "0-MCP", "status": "paused" }`.
    Fire `pipeline-paused` webhook if configured. Then display:
    `"STOP scaffold — restart Claude Code session and resume with /agent-flow:scaffold resume"`
  - **On "Skip":** continue in local-only mode. Write `{ "mcp_setup_pending": false }` to
    state.json to ensure the marker is cleared (guard against re-entering 0-MCP on future resume).
  - In --yolo mode: auto-downgrade (or BLOCK if `--issue` provided with no tracker MCP)
- Set `{service}_effective_status` to `"ready"` / `"later"` / `"downgraded"`

After all checks, update state.json with final `tracker_effective_status` and `sc_effective_status`.
Clear `mcp_setup_pending` (set to `false`) once the 0-MCP step reaches its natural end — meaning all
declared-ready services have either passed the MCP check or been explicitly downgraded/skipped.
This clear is the single authoritative location; SKILL.md Resume Detection does NOT duplicate it.

Fire `pipeline-started` webhook if configured (per `../../../core/post-publish-hook.md` Section 4).

## 01d. Brainstorm (vague descriptions only)

**Vague description heuristic:**
A description is **vague** unless BOTH conditions hold:
- `word_count >= 20` (count whitespace-delimited tokens in description)
- Contains at least one technical term matching POSIX ERE:
  `(^|[^A-Za-z0-9])(API|SDK|OAuth|REST|GraphQL|Docker|Kubernetes|React|TypeScript|Python|Java|Rust|Go|PostgreSQL|Redis|Nginx|JWT|WebSocket)([^A-Za-z0-9]|$)`

If MODE = yolo → skip brainstorm entirely (no brainstorm regardless of description vagueness).
If MODE = default AND description is vague → trigger brainstorm.
If MODE = default AND description is NOT vague (>=20 words AND technical term found) → skip brainstorm.
If MODE = step-mode → apply same vague heuristic as default mode.

**Brainstorm flow (if triggered):**
1. Tell user: "Let's explore your idea before writing a spec. I'll ask a few questions."
2. Ask up to 5 divergent questions (primary user, success metric, out-of-scope, competitors, riskiest assumption)
3. After each answer, synthesize and probe deeper (max 2 follow-ups per question)
4. Synthesize into enriched description (200–400 words); display: "Here's what I understood. Continue? [Yes / Edit / Abort]"
5. Anti-bias: do NOT lead with suggestions; present ≥2 contrasting approaches; explicitly name trade-offs

If `--spec` or `--brainstorm` flag provided: follow existing spec-path or force-brainstorm logic respectively.
