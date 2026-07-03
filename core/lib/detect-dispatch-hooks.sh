#!/usr/bin/env bash
# core/lib/detect-dispatch-hooks.sh
# Tree-aware detection of the agent-flow dispatch-enforcement hooks across the
# Claude Code settings tree.
#
# WHY THIS EXISTS
#   Claude Code merges a TREE of settings files and HOOKS COMBINE across scopes:
#   a PreToolUse/PostToolUse hook registered in .claude/settings.local.json fires
#   even when it is absent from ~/.claude/settings.json (none overrides another;
#   only `disableAllHooks: true` turns them off). The earlier check that read
#   ONLY ~/.claude/settings.json therefore reported a hook wired at the project
#   or project-local scope as "not configured" (a false negative).
#
#   This helper scans, in Claude Code precedence order, the three scopes a
#   portable shell can read:
#       local   -> <proj>/.claude/settings.local.json   (highest of the three)
#       project -> <proj>/.claude/settings.json
#       user    -> <home>/.claude/settings.json          (lowest)
#   Because hooks COMBINE, a hook is "wired" when present in ANY scanned scope;
#   GATE_SCOPES / AUDIT_SCOPES report exactly where each was found.
#
#   Managed/enterprise (OS-level) settings — Windows registry policy /
#   %ProgramFiles%\ClaudeCode\managed-settings.json, macOS plist domain
#   com.anthropic.claudecode / /Library/Application Support/ClaudeCode, Linux
#   /etc managed JSON — are NOT inspected. Those paths are platform-specific and
#   out of a portable shell's reach, so they are an advisory gap (a hook wired
#   only there cannot be statically confirmed here), never reported as
#   wired/not-wired. The caller surfaces that gap as a note.
#
# DETECTION IS BY SCRIPT FILENAME (the two filenames are disjoint, so there is
# NO substring collision — "validate-dispatch.sh" is NOT a substring of
# "validate-dispatch-pre.sh", which carries the "-pre" infix before ".sh"):
#       gate  -> validate-dispatch-pre.sh  (PreToolUse, matcher "Task"; the only
#                                           component that can BLOCK a dispatch)
#       audit -> validate-dispatch.sh      (PostToolUse; advisory second layer)
#
# OUTPUT — KEY=VALUE lines on stdout (consume with the tests/lib/assert.sh
# `contains` helper, or `grep '^KEY='`):
#       PARSER=python|grep
#       FILES_SCANNED=<n>
#       SETTINGS_FILES=<path|path|...>            (existing, parseable files)
#       GATE_WIRED=0|1
#       GATE_SCOPES=<comma scopes>                (where validate-dispatch-pre.sh found)
#       GATE_MATCHER_TASK=0|1|unknown             (a PreToolUse gate entry with matcher "Task")
#       GATE_MATCHER_TASK_SCOPES=<comma scopes>
#       AUDIT_WIRED=0|1
#       AUDIT_SCOPES=<comma scopes>
#       DISABLE_ALL_HOOKS=0|1
#       DISABLE_ALL_HOOKS_SCOPES=<comma scopes>
#
#   GATE_MATCHER_TASK distinguishes "blocking gate correctly wired" (1) from
#   "gate command present but not on the Task matcher / wrong event" (0) — the
#   latter is wired but will NOT gate dispatches. The grep fallback cannot read
#   structure, so it reports `unknown`.
#
# CONTRACT: read-only, no side effects, ALWAYS returns 0. This is informational;
#   the CALLER decides verdicts (e.g. check-setup keeps it advisory, fix-bugs
#   logs an [INFO]/[WARN] preflight line). Safe to source: defines functions
#   only, changes no shell options.

# detect_dispatch_hooks [project_root] [home_dir]
#   project_root default "."   home_dir default "$HOME"
detect_dispatch_hooks() {
  local proj="${1:-.}"
  local home_dir="${2:-${HOME:-}}"

  local f_local="$proj/.claude/settings.local.json"
  local f_proj="$proj/.claude/settings.json"
  local f_user="$home_dir/.claude/settings.json"

  # Runnability probe (not just `command -v`): a Windows-Store python.exe stub is
  # ON PATH but exits non-zero on -c. Mirrors the hooks' A4/REQ-018 probe.
  local PYBIN="" cand
  for cand in python3 python; do
    if command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'import sys' >/dev/null 2>&1; then
      PYBIN="$cand"; break
    fi
  done

  if [ -n "$PYBIN" ]; then
    # On MSYS2/Git Bash a NATIVE Windows python cannot stat an MSYS path like
    # /tmp/... or /c/Users/... — translate to the native form for the parser
    # (identity on Linux/macOS, where cygpath is absent). The "scope:" prefix
    # carries the first colon, so a translated "C:\..." drive-letter colon is
    # preserved intact by Python's partition(":").
    "$PYBIN" - \
      "local:$(_ddh_native "$f_local")" \
      "project:$(_ddh_native "$f_proj")" \
      "user:$(_ddh_native "$f_user")" <<'PY'
import sys, os, json

GATE_FN  = "validate-dispatch-pre.sh"   # the blocking PreToolUse Task gate
AUDIT_FN = "validate-dispatch.sh"       # the advisory PostToolUse audit


def event_commands(doc, event):
    """Yield (matcher, command) for each command entry under hooks[event]."""
    hooks = doc.get("hooks")
    if not isinstance(hooks, dict):
        return
    arr = hooks.get(event)
    if not isinstance(arr, list):
        return
    for entry in arr:
        if not isinstance(entry, dict):
            continue
        matcher = entry.get("matcher")
        inner = entry.get("hooks")
        if not isinstance(inner, list):
            continue
        for h in inner:
            if isinstance(h, dict):
                cmd = h.get("command")
                if isinstance(cmd, str):
                    yield (matcher, cmd)


gate_scopes, gate_task_scopes, audit_scopes, disable_scopes = [], [], [], []
files_scanned, settings_files = 0, []

for arg in sys.argv[1:]:
    scope, _, path = arg.partition(":")
    if not path or not os.path.isfile(path):
        continue
    try:
        with open(path, encoding="utf-8") as f:
            doc = json.load(f)
    except Exception:
        # Unreadable / invalid JSON: behave as "absent" (never crash the probe).
        continue
    if not isinstance(doc, dict):
        continue
    files_scanned += 1
    settings_files.append(path)

    if doc.get("disableAllHooks") is True:
        disable_scopes.append(scope)

    gate_here = gate_task_here = audit_here = False
    # Gate belongs in PreToolUse with matcher "Task"; also flag a misplaced gate
    # in PostToolUse so the caller can warn it will not actually gate dispatches.
    for matcher, cmd in event_commands(doc, "PreToolUse"):
        if GATE_FN in cmd:
            gate_here = True
            if str(matcher) == "Task":
                gate_task_here = True
        # audit filename is NOT a substring of the gate filename (the "-pre"
        # infix), so this is unambiguous even if the audit is wired pre-tool.
        if AUDIT_FN in cmd and GATE_FN not in cmd:
            audit_here = True
    for matcher, cmd in event_commands(doc, "PostToolUse"):
        if GATE_FN in cmd:
            gate_here = True            # present but wrong event -> not task-ok
        if AUDIT_FN in cmd and GATE_FN not in cmd:
            audit_here = True

    if gate_here:
        gate_scopes.append(scope)
    if gate_task_here:
        gate_task_scopes.append(scope)
    if audit_here:
        audit_scopes.append(scope)


def jl(lst):
    return ",".join(lst)


out = [
    "PARSER=python",
    "FILES_SCANNED=%d" % files_scanned,
    "SETTINGS_FILES=%s" % "|".join(settings_files),
    "GATE_WIRED=%d" % (1 if gate_scopes else 0),
    "GATE_SCOPES=%s" % jl(gate_scopes),
    "GATE_MATCHER_TASK=%d" % (1 if gate_task_scopes else 0),
    "GATE_MATCHER_TASK_SCOPES=%s" % jl(gate_task_scopes),
    "AUDIT_WIRED=%d" % (1 if audit_scopes else 0),
    "AUDIT_SCOPES=%s" % jl(audit_scopes),
    "DISABLE_ALL_HOOKS=%d" % (1 if disable_scopes else 0),
    "DISABLE_ALL_HOOKS_SCOPES=%s" % jl(disable_scopes),
]
# Write via the binary buffer so the output is LF-only — a NATIVE Windows Python
# in text mode would translate "\n" to "\r\n", and the trailing CR would corrupt
# exact-match parsing of KEY=VALUE lines by the bash caller.
sys.stdout.buffer.write(("\n".join(out) + "\n").encode("utf-8"))
PY
    return 0
  fi

  # --- grep fallback (no runnable Python) ------------------------------------
  # Filename presence only — no event/matcher structure, so GATE_MATCHER_TASK is
  # `unknown`. No producer|grep pipe is used (avoids the pipefail/SIGPIPE race
  # documented in tests/lib/assert.sh); grep reads each file directly. The audit
  # filename "validate-dispatch.sh" is NOT a substring of the gate filename, so a
  # bare grep -F for it never matches the gate line.
  _ddh_grep_fallback "$f_local" "$f_proj" "$f_user"
  return 0
}

# _ddh_native <path> — translate an MSYS/Cygwin path to its native Windows form
# for a non-MSYS Python; identity where cygpath is unavailable (Linux/macOS).
_ddh_native() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1" 2>/dev/null || printf '%s' "$1"
  else
    printf '%s' "$1"
  fi
}

# _ddh_grep_fallback <local-path> <project-path> <user-path>
_ddh_grep_fallback() {
  local gate_scopes="" audit_scopes="" disable_scopes="" files="" n=0
  local pair scope path
  for pair in "local:$1" "project:$2" "user:$3"; do
    scope="${pair%%:*}"; path="${pair#*:}"
    [ -f "$path" ] || continue
    n=$((n + 1)); files="${files:+$files|}$path"
    if grep -qF 'validate-dispatch-pre.sh' "$path" 2>/dev/null; then
      gate_scopes="${gate_scopes:+$gate_scopes,}$scope"
    fi
    if grep -qF 'validate-dispatch.sh' "$path" 2>/dev/null; then
      audit_scopes="${audit_scopes:+$audit_scopes,}$scope"
    fi
    if grep -Eq '"disableAllHooks"[[:space:]]*:[[:space:]]*true' "$path" 2>/dev/null; then
      disable_scopes="${disable_scopes:+$disable_scopes,}$scope"
    fi
  done
  printf 'PARSER=grep\n'
  printf 'FILES_SCANNED=%d\n' "$n"
  printf 'SETTINGS_FILES=%s\n' "$files"
  printf 'GATE_WIRED=%d\n' "$([ -n "$gate_scopes" ] && echo 1 || echo 0)"
  printf 'GATE_SCOPES=%s\n' "$gate_scopes"
  printf 'GATE_MATCHER_TASK=unknown\n'
  printf 'GATE_MATCHER_TASK_SCOPES=\n'
  printf 'AUDIT_WIRED=%d\n' "$([ -n "$audit_scopes" ] && echo 1 || echo 0)"
  printf 'AUDIT_SCOPES=%s\n' "$audit_scopes"
  printf 'DISABLE_ALL_HOOKS=%d\n' "$([ -n "$disable_scopes" ] && echo 1 || echo 0)"
  printf 'DISABLE_ALL_HOOKS_SCOPES=%s\n' "$disable_scopes"
}
