# Snippet — issue_id validation regex

The canonical Bash conditional for validating an `$ISSUE_ID` value before it is interpolated into any path or URL. Cite this file from any new issue-id consumer.

```bash
[[ "$ISSUE_ID" =~ ^[A-Za-z0-9#._-]+$ && ! "$ISSUE_ID" =~ ^\.+$ ]] || {
  echo "Error: invalid issue_id (must match ^[A-Za-z0-9#._-]+$ and not be dot-only)"; exit 1
}
```

**Why two clauses:**
1. `^[A-Za-z0-9#._-]+$` — accepted character class (Jira dotted-keys like `PROJ.NAME-123` are permitted).
2. `! "$ISSUE_ID" =~ ^\.+$` — REJECT dot-only inputs (`.`, `..`, `...`). Without this guard, the regex would accept `..`, which produces `.agent-flow/../state.json` — path-traversal escapes the plugin state directory.

## Used by:
- `docs/reference/pipeline.md:41-46` — Entry `SKILL.md` responsibility #3 ("Issue-ID validation"), same accepted-charset + dot-only-rejection regex.
- `core/agent-states.md:79` — NEEDS_CLARIFICATION webhook variable-provenance note (`${ISSUE_ID}` already validated per this snippet).
- `skills/publish/SKILL.md:383` — Citations section cross-reference (Step 0d issue_id extraction / path-traversal defense).

No file in this repo currently embeds a literal `<!-- @snippet:issue-id-validation -->` transclusion marker (unlike `webhook-curl`, `architecture-freshness`, `pipeline-completion`, and `metrics-json-schema`, which do); the sites above reference this snippet's regex in prose/citation form only. Verify with `grep -rn "issue-id-validation" .` before relying on this list — it is not enforced by a test scenario.

