# Snippet — dispatch-enforcement preflight

Canonical advisory-only Bash block that reports whether the agent-flow dispatch
witness is actually **enforcing** — i.e. whether the blocking PreToolUse `Task`
gate (`hooks/validate-dispatch-pre.sh`) is wired anywhere in the Claude Code
settings tree (`~/.claude/settings.json` user, `.claude/settings.json` project,
`.claude/settings.local.json` project-local). It exists so the orchestrator does
not assume "advisory only" when the gate is in fact wired at the project or
project-local scope — **hooks COMBINE across scopes** (none overrides another;
only `"disableAllHooks": true` disables them). Cite this from orchestration step
boundaries that benefit from knowing whether dispatches are gated.

Detection is delegated to the shared helper `core/lib/detect-dispatch-hooks.sh`
(the same helper `/agent-flow:check-setup` Block 6 uses), so the skill and the
setup check report identical wiring.

```bash
# Dispatch-enforcement preflight — advisory only, non-blocking (always exits 0).
ddh_lib=""
for _c in \
  "${HOME:-}"/.claude/plugins/cache/agent-flow/agent-flow/*/core/lib/detect-dispatch-hooks.sh \
  "${CLAUDE_PLUGIN_ROOT:-}"/core/lib/detect-dispatch-hooks.sh \
  ./core/lib/detect-dispatch-hooks.sh ; do
  [ -f "$_c" ] && ddh_lib="$_c"
done

if [ -z "$ddh_lib" ]; then
  echo "[INFO] dispatch preflight: detect-dispatch-hooks.sh not found — enforcement state unknown (treating as advisory)."
else
  # shellcheck disable=SC1090
  . "$ddh_lib"
  _out="$(detect_dispatch_hooks "$PWD" "${HOME:-}")"
  # Pipe-free, CR-safe KEY=VALUE extractor (no `| head` -> no pipefail/SIGPIPE race).
  _val() {
    local l
    while IFS= read -r l; do
      l="${l%$'\r'}"
      case "$l" in "$1="*) printf '%s' "${l#*=}"; return 0 ;; esac
    done <<EOF
$_out
EOF
  }
  gw=$(_val GATE_WIRED); gt=$(_val GATE_MATCHER_TASK); gs=$(_val GATE_SCOPES); dis=$(_val DISABLE_ALL_HOOKS)
  if [ "$gw" = "1" ] && [ "$gt" = "1" ] && [ "$dis" != "1" ]; then
    echo "[INFO] dispatch preflight: PreToolUse Task gate WIRED (${gs}) — dispatch mismatches are BLOCKING-enforced."
  elif [ "$gw" = "1" ] && [ "$dis" = "1" ]; then
    echo "[WARN] dispatch preflight: gate wired (${gs}) but \"disableAllHooks\": true — enforcement is OFF until that is removed."
  elif [ "$gw" = "1" ]; then
    echo "[WARN] dispatch preflight: gate command present (${gs}) but matcher is not \"Task\" — dispatches are NOT gated (advisory only)."
  else
    echo "[INFO] dispatch preflight: PreToolUse Task gate not wired (user/project/local) — dispatch enforcement is advisory only. See docs/guides/dispatch-enforcement.md."
  fi
fi
```

**Why advisory:** the gate is spawned by Claude Code, not by the skill, so this
preflight cannot itself enforce — it only **reports posture** into the run log so
the orchestrator (and operators reading `pipeline.log`) know whether a dispatch
mismatch would actually be BLOCKED (gate wired + matcher `Task` + hooks enabled)
or merely audited after the fact. The block always exits 0; the pipeline proceeds
regardless of the verdict.

**Managed/OS-level settings** (Windows registry policy, macOS plist, Linux managed
JSON) are not inspected by the helper — a gate wired ONLY there is reported as
not-wired. This is the documented tree-scan boundary, not a defect.

## Used by:
- `skills/fix-bugs/SKILL.md` (citation marker `<!-- @snippet:dispatch-enforcement-preflight -->`)
