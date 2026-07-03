#!/usr/bin/env bash
# hooks/probe-task-shape.sh
# One-time Task `tool_input`-shape probe (REQ-021b).
#
# The exact `Task` tool_input schema is less formally documented than the
# top-level hook contract, so this probe records — ONCE per machine — which
# fields the local Claude Code build actually supplies on a `Task` dispatch
# (confirming `subagent_type` and `prompt`, and whether `model` is present).
# This de-risks the gate's observe-and-sign / model cross-check (REQ-003/REQ-048)
# without coupling the gate to an assumed shape.
#
# This is a PURE PROBE: it NEVER blocks and NEVER signs. It always exits 0 (it
# is safe to register as either a PreToolUse or PostToolUse `Task` matcher).
# It writes a single best-effort line to .agent-flow/.task-shape-probe and to
# the audit log, then does nothing on subsequent dispatches (the marker exists).
#
# Env vars:
#   AGENT_FLOW_AUDIT_LOG          audit-log path override
#   AGENT_FLOW_TASK_SHAPE_PROBE   probe-marker path override
set -uo pipefail

# Runnability probe (A4): mere PATH presence is not enough.
PYBIN=""
for cand in python3 python; do
  if command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'import sys' >/dev/null 2>&1; then
    PYBIN="$cand"
    break
  fi
done
# No runnable Python -> this advisory probe simply no-ops (never blocks).
[ -n "$PYBIN" ] || exit 0

HOOK_IN="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/afprobe_in_$$")"
cat > "$HOOK_IN"

"$PYBIN" - "$HOOK_IN" <<'PY'
import sys, os, json, datetime

HOOK_IN = sys.argv[1]


def now_iso():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def best_effort_append(path, text):
    try:
        d = os.path.dirname(path)
        if d:
            os.makedirs(d, exist_ok=True)
        with open(path, "a", encoding="utf-8") as f:
            f.write(text)
    except Exception:
        pass


def main():
    probe = os.environ.get("AGENT_FLOW_TASK_SHAPE_PROBE",
                           os.path.join(".agent-flow", ".task-shape-probe"))
    # One-time: if we already recorded the shape, do nothing.
    try:
        if os.path.exists(probe):
            return 0
    except Exception:
        return 0

    try:
        with open(HOOK_IN, encoding="utf-8") as f:
            hook = json.load(f)
    except Exception:
        return 0
    if (hook or {}).get("tool_name") != "Task":
        return 0   # only probe the Task tool shape

    ti = (hook or {}).get("tool_input") or {}
    shape = {
        "has_subagent_type": "subagent_type" in ti,
        "has_prompt": "prompt" in ti,
        "has_model": "model" in ti,
        "keys": sorted(k for k in ti.keys()),
        "recorded_at": now_iso(),
    }
    line = json.dumps(shape, separators=(",", ":"))
    best_effort_append(probe, line + "\n")
    best_effort_append(
        os.environ.get("AGENT_FLOW_AUDIT_LOG",
                       os.path.join(".agent-flow", "dispatch-audit.log")),
        "%s [INFO] Task tool_input shape probed: %s\n" % (now_iso(), line))
    return 0


sys.exit(main())
PY
rc=$?
rm -f "$HOOK_IN" 2>/dev/null || true
# Pure probe: never propagate a non-zero exit (never blocks).
exit 0
