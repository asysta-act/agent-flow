#!/usr/bin/env bash
# core/lib/config-reader.sh
# Pure-bash REFERENCE IMPLEMENTATION of the config reader/resolver contract that
# core/config-reader.md specifies as prose. Precedent: core/lib/stage-invariant.sh —
# this plugin ships executable reference bash for the invariants it wants machine-tested.
#
# It uses ONLY bash builtins (while/read, case, parameter expansion, [[ ]] ) plus
# `sort` for a deterministic dump. It shells out to NO external TOML tooling and depends
# on NO language interpreter, so the limits-resolution path works unchanged on the legacy
# 3.10 host (FC-26/REQ-29).
#
# The prose spec (core/config-reader.md) remains the human contract; this file is the
# reference implementation the tests/scenarios/*.sh harness exercises. It is SOURCED by
# scenarios; therefore it deliberately does NOT `set -e`/`set -o pipefail` at file scope
# (that would leak into the sourcing shell, exactly the toml-merge.sh anti-pattern).
# Every function is `set -u`-safe via ${x:-} defaults.
#
# CONTRACT (mirrors core/config-reader.md):
#   config_reset
#   config_parse FILE [strict]        strict=1 (default) BLOCKs on a missing required section;
#                                     strict=0 parses a fragment without the required check.
#                                     Malformed OPTIONAL construct -> [WARN] + default, exit 0.
#   config_get KEY                    dot-notation "section.key" -> resolved scalar (empty if unset)
#   config_list KEY                   delimited-scalar list -> one element per line (empty => none)
#   config_map KEY                    delimited-scalar map  -> "k=v" per line
#   config_dump                       sorted "section.key=value" lines (byte-comparable)
#   config_overlay_merge LOCAL_FILE   apply config.local.toml with allowlist + denylist (WARNs)
#   resolve_limit AGENT CONFIG LOCAL OVERRIDE_DIR CONFIG_KEY OVERLAY_KEY PLUGIN_DEFAULT
#                                     the SINGLE limits-resolution point:
#                                     plugin default < config.toml < config.local.toml <
#                                     customization/{agent}.toml [limits]  -> echoes ONE value.
#   config_validate FILE             check-setup key-list: [FAIL] missing required, [WARN] unknown key
#   config_migrate CLAUDE_MD OUT [--force]   reference /onboard --migrate transform
#
# Warnings: accumulated in CR_WARN and echoed to stderr with the literal "[WARN]" token.

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
declare -gA CR_CFG=()
declare -gA CR_SECTIONS=()
CR_WARN=""

config_reset() {
  unset CR_CFG CR_SECTIONS 2>/dev/null || true
  declare -gA CR_CFG=()
  declare -gA CR_SECTIONS=()
  CR_WARN=""
}

cr_warn() {
  CR_WARN+="[WARN] $1"$'\n'
  printf '[WARN] %s\n' "$1" >&2
}

cr_block() {
  # Standard Block Comment Template (see core/config-reader.md Failure Handling).
  printf '[agent-flow] 🔴 Pipeline Block\n'
  printf 'Agent: config-reader\n'
  printf 'Step: %s\n' "$1"
  printf 'Reason: %s\n' "$2"
  printf 'Detail: %s\n' "$3"
  printf 'Recommendation: %s\n' "$4"
}

# ---------------------------------------------------------------------------
# cr_trim STR  -> STR with leading+trailing whitespace removed (stdout)
# ---------------------------------------------------------------------------
cr_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# ---------------------------------------------------------------------------
# cr_strip_comment LINE -> LINE with a trailing "# ..." comment removed, but only
# when the '#' is OUTSIDE a double-quoted string (so `on_block = "comment" # note`
# keeps the value `comment`). Pure-bash char walk; SIGPIPE-free.
# ---------------------------------------------------------------------------
cr_strip_comment() {
  local s="$1" out="" c inq=0 i n=${#1}
  for (( i=0; i<n; i++ )); do
    c="${s:i:1}"
    if [ "$c" = '"' ]; then inq=$((1-inq)); out+="$c"; continue; fi
    if [ "$c" = '#' ] && [ "$inq" -eq 0 ]; then break; fi
    out+="$c"
  done
  printf '%s' "$out"
}

# ---------------------------------------------------------------------------
# config_parse FILE [strict=1]
#   Line-oriented pure-bash TOML-subset parser. Populates CR_CFG (dot-notation)
#   and CR_SECTIONS. Strips a trailing \r (CRLF) and a UTF-8 BOM on line 1.
#   Malformed OPTIONAL construct -> [WARN] + skip (default applies), exit 0.
#   strict=1 and a missing REQUIRED [section] -> [agent-flow] BLOCK, return 2.
# ---------------------------------------------------------------------------
config_parse() {
  local file="$1"
  local strict="${2:-1}"
  config_reset
  if [ ! -f "$file" ]; then
    cr_block "config parsing" \
      ".agent-flow/config.toml not found." \
      "Missing file: $file" \
      "Create .agent-flow/config.toml, or run /agent-flow:onboard --migrate."
    return 3
  fi

  local raw line t key val trimmed
  local cur_section="" in_ml=0 ml_key="" ml_val="" first=1

  while IFS= read -r raw || [ -n "$raw" ]; do
    line="${raw%$'\r'}"                       # strip trailing CR
    if [ "$first" -eq 1 ]; then
      line="${line#$'\xEF\xBB\xBF'}"          # strip UTF-8 BOM on first line
      first=0
    fi

    if [ "$in_ml" -eq 1 ]; then
      trimmed="$(cr_trim "$line")"
      if [ "$trimmed" = '"""' ]; then
        CR_CFG["$cur_section.$ml_key"]="$ml_val"
        in_ml=0; ml_key=""; ml_val=""
      else
        if [ -z "$ml_val" ]; then ml_val="$line"; else ml_val="$ml_val"$'\n'"$line"; fi
      fi
      continue
    fi

    line="$(cr_strip_comment "$line")"
    t="$(cr_trim "$line")"
    [ -z "$t" ] && continue

    case "$t" in
      '[['*']]')
        # array-of-tables (pipeline_profiles) — record the header; scalar keys that
        # follow attach to this section name (sufficient for the subset the tests use).
        local aot="${t#\[\[}"; aot="${aot%\]\]}"
        cur_section="$(cr_trim "$aot")"
        CR_SECTIONS["$cur_section"]=1
        ;;
      '['*']')
        local name="${t#\[}"; name="${name%\]}"
        cur_section="$(cr_trim "$name")"
        CR_SECTIONS["$cur_section"]=1
        ;;
      *=*)
        key="$(cr_trim "${t%%=*}")"
        val="$(cr_trim "${t#*=}")"
        if [ "$val" = '"""' ]; then
          in_ml=1; ml_key="$key"; ml_val=""
        elif [[ "$val" == '"'*'"' ]]; then
          val="${val#\"}"; val="${val%\"}"
          CR_CFG["$cur_section.$key"]="$val"
        elif [ "$val" = "true" ] || [ "$val" = "false" ]; then
          CR_CFG["$cur_section.$key"]="$val"
        elif [[ "$val" =~ ^-?[0-9]+$ ]]; then
          CR_CFG["$cur_section.$key"]="$val"
        else
          # Out-of-subset / garbage scalar: degrade to a [WARN], do NOT crash.
          cr_warn "${cur_section:-<root>}: unparsable scalar for key '$key'; using default"
        fi
        ;;
      *)
        cr_warn "${cur_section:-<root>}: unparsable line ignored"
        ;;
    esac
  done < "$file"

  if [ "$in_ml" -eq 1 ]; then
    cr_warn "${cur_section:-<root>}: unterminated \"\"\" block for key '$ml_key'; using default"
  fi

  if [ "$strict" = "1" ]; then
    local missing=() req
    for req in issue_tracker source_control pr_rules pr_description_template build_and_test; do
      [ -n "${CR_SECTIONS[$req]:-}" ] || missing+=("[$req]")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
      cr_block "config parsing" \
        ".agent-flow/config.toml is missing one or more required sections." \
        "Missing required section(s): ${missing[*]}" \
        "Add the required section(s) to .agent-flow/config.toml, or run /agent-flow:onboard --migrate."
      return 2
    fi
  fi
  return 0
}

config_get() { printf '%s' "${CR_CFG[$1]:-}"; }

config_list() {
  local raw="${CR_CFG[$1]:-}"
  [ -z "$raw" ] && return 0
  local -a parts=(); IFS=',' read -ra parts <<< "$raw"
  local p
  for p in "${parts[@]}"; do
    p="$(cr_trim "$p")"
    printf '%s\n' "$p"
  done
}

config_map() {
  local raw="${CR_CFG[$1]:-}"
  [ -z "$raw" ] && return 0
  local -a recs=(); IFS=';' read -ra recs <<< "$raw"
  local r k v
  for r in "${recs[@]}"; do
    r="$(cr_trim "$r")"
    [ -z "$r" ] && continue
    k="$(cr_trim "${r%%:*}")"
    v="$(cr_trim "${r#*:}")"
    printf '%s=%s\n' "$k" "$v"
  done
}

config_dump() {
  local k
  {
    for k in "${!CR_CFG[@]}"; do printf '%s=%s\n' "$k" "${CR_CFG[$k]}"; done
  } | LC_ALL=C sort
}

# ---------------------------------------------------------------------------
# Denylist — team-consistency / security-critical keys that MUST NOT be
# personally overridden even if allowlisted. (core/config-reader.md §overlay.)
# ---------------------------------------------------------------------------
cr_is_denylisted() {
  case "$1" in
    source_control.remote|source_control.base_branch|notifications.webhook_url|issue_tracker.instance|issue_tracker.project) return 0 ;;
    pr_rules.*) return 0 ;;
  esac
  return 1
}

# ---------------------------------------------------------------------------
# config_overlay_merge LOCAL_FILE
#   GENERAL per-developer overlay merge. This governs FULL-SECTION per-dev
#   overrides and is a SEPARATE mechanism from resolve_limit's [retry_limits]
#   chain. Allowlist = {browser_verification, local_deployment}; denylist gate
#   on top. Any key outside the allowlist (incl. [retry_limits] keys, which are
#   handled by resolve_limit, NOT here) is ignored + [WARN]. Absent file = no-op.
# ---------------------------------------------------------------------------
config_overlay_merge() {
  local localfile="$1"
  [ -f "$localfile" ] || return 0
  local raw line t key val fullkey cur="" first=1
  while IFS= read -r raw || [ -n "$raw" ]; do
    line="${raw%$'\r'}"
    if [ "$first" -eq 1 ]; then line="${line#$'\xEF\xBB\xBF'}"; first=0; fi
    line="$(cr_strip_comment "$line")"
    t="$(cr_trim "$line")"
    [ -z "$t" ] && continue
    case "$t" in
      '['*']')
        cur="${t#\[}"; cur="${cur%\]}"; cur="$(cr_trim "$cur")"
        ;;
      *=*)
        key="$(cr_trim "${t%%=*}")"
        val="$(cr_trim "${t#*=}")"
        if [[ "$val" == '"'*'"' ]]; then val="${val#\"}"; val="${val%\"}"; fi
        fullkey="$cur.$key"
        if cr_is_denylisted "$fullkey"; then
          cr_warn "config.local.toml: '$fullkey' is denylisted (team-consistency/security) and was NOT applied"
        elif [ "$cur" = "browser_verification" ] || [ "$cur" = "local_deployment" ]; then
          CR_CFG["$fullkey"]="$val"
        else
          cr_warn "config.local.toml: '$fullkey' is outside the per-developer allowlist (browser_verification, local_deployment) and was ignored"
        fi
        ;;
    esac
  done < "$localfile"
  return 0
}

# ---------------------------------------------------------------------------
# cr_scalar_from_file FILE SECTION KEY -> scalar value (stdout, empty if absent)
#   Focused pure-bash extractor used by resolve_limit for each tier. Handles the
#   int/quoted-string subset, strips \r + first-line BOM, ignores comments.
# ---------------------------------------------------------------------------
cr_scalar_from_file() {
  local file="$1" want_section="$2" want_key="$3"
  [ -f "$file" ] || return 0
  local raw line t key val cur="" first=1
  while IFS= read -r raw || [ -n "$raw" ]; do
    line="${raw%$'\r'}"
    if [ "$first" -eq 1 ]; then line="${line#$'\xEF\xBB\xBF'}"; first=0; fi
    line="$(cr_strip_comment "$line")"
    t="$(cr_trim "$line")"
    [ -z "$t" ] && continue
    case "$t" in
      '['*']')
        cur="${t#\[}"; cur="${cur%\]}"; cur="$(cr_trim "$cur")"
        ;;
      *=*)
        [ "$cur" = "$want_section" ] || continue
        key="$(cr_trim "${t%%=*}")"
        if [ "$key" = "$want_key" ]; then
          val="$(cr_trim "${t#*=}")"
          if [[ "$val" == '"'*'"' ]]; then val="${val#\"}"; val="${val%\"}"; fi
          printf '%s' "$val"
          return 0
        fi
        ;;
    esac
  done < "$file"
  return 0
}

# ---------------------------------------------------------------------------
# resolve_limit AGENT CONFIG_TOML LOCAL_TOML OVERRIDE_DIR CONFIG_KEY OVERLAY_KEY PLUGIN_DEFAULT
#   THE single limits-resolution point (core/config-reader.md §"Single
#   limits-resolution point"). Precedence, lowest -> highest:
#     plugin default < config.toml [retry_limits] < config.local.toml [retry_limits]
#       < customization/{agent}.toml [limits]
#   Pure bash — no interpreter, no external TOML tooling, NOT routed through the
#   setup-agents overlay-merge library (REQ-29/FC-26).
#   Returns ONE value; whatever calls this for loop-enforcement and for
#   prompt-injection gets the SAME number, so the two channels cannot diverge (§2.4).
# ---------------------------------------------------------------------------
resolve_limit() {
  local agent="$1" config_toml="$2" local_toml="$3" override_dir="$4"
  local config_key="$5" overlay_key="$6" plugin_default="$7"
  local value="$plugin_default" v

  v="$(cr_scalar_from_file "$config_toml" retry_limits "$config_key")"
  [ -n "$v" ] && value="$v"

  if [ -n "$local_toml" ] && [ -f "$local_toml" ]; then
    v="$(cr_scalar_from_file "$local_toml" retry_limits "$config_key")"
    [ -n "$v" ] && value="$v"
  fi

  if [ -n "$override_dir" ] && [ -f "$override_dir/$agent.toml" ]; then
    v="$(cr_scalar_from_file "$override_dir/$agent.toml" limits "$overlay_key")"
    [ -n "$v" ] && value="$v"
  fi

  printf '%s' "$value"
}

# ---------------------------------------------------------------------------
# Known-key schema for config_validate (unknown-key detection).
# ---------------------------------------------------------------------------
cr_known_key() {
  local section="$1" key="$2"
  case "$section.$key" in
    issue_tracker.type|issue_tracker.instance|issue_tracker.project|issue_tracker.bug_query|issue_tracker.state_transitions|issue_tracker.on_start_set) return 0 ;;
    source_control.remote|source_control.base_branch|source_control.branch_naming) return 0 ;;
    pr_rules.labels|pr_rules.title_format) return 0 ;;
    pr_description_template.template) return 0 ;;
    build_and_test.build_command|build_and_test.test_command|build_and_test.verify_command) return 0 ;;
    retry_limits.fixer_iterations|retry_limits.test_attempts|retry_limits.build_retries|retry_limits.spec_iterations|retry_limits.root_cause_iterations) return 0 ;;
    module_docs.path) return 0 ;;
    hooks.pre_fix|hooks.post_fix|hooks.pre_publish|hooks.post_publish) return 0 ;;
    custom_agents.post_fix_agent|custom_agents.pre_publish_agent) return 0 ;;
    notifications.webhook_url|notifications.on_events) return 0 ;;
    worktrees.batch_size|worktrees.base_path|worktrees.cleanup) return 0 ;;
    e2e_test.framework|e2e_test.command) return 0 ;;
    browser_verification.base_url|browser_verification.start_command|browser_verification.stop_command|browser_verification.on_events|browser_verification.timeout|browser_verification.max_pages|browser_verification.screenshot_storage|browser_verification.exploration|browser_verification.exploration_max_clicks) return 0 ;;
    error_handling.on_block|error_handling.max_blocked_per_run) return 0 ;;
    feature_workflow.feature_query|feature_workflow.on_start_set) return 0 ;;
    decomposition.max_subtasks|decomposition.fail_strategy|decomposition.commit_strategy|decomposition.create_tracker_subtasks) return 0 ;;
    pipeline_profiles.name|pipeline_profiles.skip_stages|pipeline_profiles.extra_stages) return 0 ;;
    metrics.output|metrics.period) return 0 ;;
    agent_overrides.path) return 0 ;;
    local_deployment.type|local_deployment.start_command|local_deployment.stop_command|local_deployment.health_check_url|local_deployment.health_check_timeout|local_deployment.ports) return 0 ;;
    sprint_planning.sprint_duration|sprint_planning.capacity_unit|sprint_planning.team_capacity|sprint_planning.velocity_target|sprint_planning.sprint_field|sprint_planning.mode|sprint_planning.max_issues|sprint_planning.epic_template) return 0 ;;
    autopilot.max_issues_per_run|autopilot.lock_timeout|autopilot.log_file|autopilot.bug_limit|autopilot.feature_limit|autopilot.on_error|autopilot.dry_run) return 0 ;;
    pause_limits.pause_timeout) return 0 ;;
  esac
  return 1
}

# ---------------------------------------------------------------------------
# config_validate FILE
#   /check-setup key-list validation. Emits [FAIL] on a missing required section
#   (returns 1); emits a [WARN] per unknown key (still returns 0 for that class).
# ---------------------------------------------------------------------------
config_validate() {
  local file="$1"
  # strict parse detects missing required sections (BLOCK -> rc 2).
  if ! config_parse "$file" 1 >/dev/null 2>&1; then
    printf '[FAIL] .agent-flow/config.toml is missing one or more required sections\n'
    return 1
  fi
  local fullkey section key had_unknown=0
  for fullkey in "${!CR_CFG[@]}"; do
    section="${fullkey%%.*}"; key="${fullkey#*.}"
    if ! cr_known_key "$section" "$key"; then
      printf '[WARN] unknown key: %s\n' "$fullkey"
      had_unknown=1
    fi
  done
  [ "$had_unknown" -eq 0 ] && printf '[OK] config.toml key-list valid\n'
  return 0
}

# ---------------------------------------------------------------------------
# cr_snake NAME -> snake_case identifier ("Build & Test" -> "build_and_test")
# ---------------------------------------------------------------------------
cr_snake() {
  local s="$1"
  s="${s// & / and }"
  s="${s,,}"
  local out="" c i n=${#s} prev_us=1
  for (( i=0; i<n; i++ )); do
    c="${s:i:1}"
    case "$c" in
      [a-z0-9]) out+="$c"; prev_us=0 ;;
      *) if [ "$prev_us" -eq 0 ]; then out+="_"; prev_us=1; fi ;;
    esac
  done
  out="${out%_}"; out="${out#_}"
  printf '%s' "$out"
}

# ---------------------------------------------------------------------------
# config_migrate CLAUDE_MD OUT_TOML [--force]
#   Reference /onboard --migrate transform: extract the inline "## Automation Config"
#   Markdown block ("### Section" + "| Key | Value |" tables) into OUT_TOML as
#   [section] tables, then rewrite that CLAUDE.md section to a 1-2 line pointer.
#   Robustness (design §4.3): NEVER half-write. A malformed REQUIRED section aborts
#   (rc 2, nothing written, CLAUDE.md untouched). A malformed OPTIONAL section is
#   skipped + [WARN]. Idempotent: OUT_TOML already exists + no --force -> rc 3, WARN.
# ---------------------------------------------------------------------------
config_migrate() {
  local claude="$1" out="$2" force="${3:-}"
  if [ ! -f "$claude" ]; then
    cr_warn "migrate: $claude not found"; return 4
  fi
  if [ -f "$out" ] && [ "$force" != "--force" ]; then
    cr_warn "migrate: $out already exists; re-run with --force to overwrite (idempotence guard, never clobber)"
    return 3
  fi

  # Extract the ## Automation Config block (heading -> next '## ' or EOF).
  local block
  block="$(awk '
    /^## Automation Config[[:space:]]*$/ {inb=1; next}
    inb && /^## / {inb=0}
    inb {print}
  ' "$claude")"
  if [ -z "$block" ]; then
    cr_warn "migrate: no '## Automation Config' block found in $claude"; return 5
  fi

  local required_re='^(issue_tracker|source_control|pr_rules|pr_description_template|build_and_test)$'

  # Pass 1: walk sections, classify well-formed vs malformed, detect required aborts.
  local -a sec_order=()
  local -A sec_rows=()        # section_id -> newline-joined "key\tvalue" rows
  local -A sec_bad=()         # section_id -> 1 if malformed
  local cur_id="" line rowtrim k v
  while IFS= read -r line; do
    line="${line%$'\r'}"
    case "$line" in
      '### '*)
        cur_id="$(cr_snake "${line#### }")"
        sec_order+=("$cur_id")
        sec_rows["$cur_id"]="${sec_rows[$cur_id]:-}"
        ;;
      '|'*)
        [ -z "$cur_id" ] && continue
        rowtrim="$(cr_trim "$line")"
        # Well-formed table rows start AND end with '|'. Missing trailing '|' => malformed.
        if [[ "$rowtrim" != *'|' ]]; then
          sec_bad["$cur_id"]=1
          continue
        fi
        # Separator row (all dashes/pipes/spaces) -> skip.
        if [[ "$rowtrim" =~ ^[-|[:space:]]+$ ]]; then continue; fi
        # Strip outer pipes, split on first '|'.
        local inner="${rowtrim#|}"; inner="${inner%|}"
        k="$(cr_trim "${inner%%|*}")"
        v="$(cr_trim "${inner#*|}")"
        # Skip the header row "| Key | Value |".
        if [ "$k" = "Key" ] && [ "$v" = "Value" ]; then continue; fi
        [ -z "$k" ] && continue
        sec_rows["$cur_id"]+="$(cr_snake "$k")"$'\t'"$v"$'\n'
        ;;
    esac
  done <<< "$block"

  # Abort if any REQUIRED section is malformed — never half-write, CLAUDE.md untouched.
  local id
  for id in "${sec_order[@]}"; do
    if [ "${sec_bad[$id]:-0}" = "1" ] && [[ "$id" =~ $required_re ]]; then
      cr_warn "migrate: required section [$id] is malformed and could not be extracted; aborting (config.toml NOT written, CLAUDE.md left untouched)"
      return 2
    fi
  done

  # Pass 2: emit TOML for well-formed sections; skip malformed OPTIONAL ones with a WARN.
  mkdir -p "$(dirname "$out")" 2>/dev/null || true
  local tmp="${out}.tmp.$$"
  : > "$tmp"
  local rows row rk rv wrote=0
  for id in "${sec_order[@]}"; do
    if [ "${sec_bad[$id]:-0}" = "1" ]; then
      cr_warn "migrate: optional section [$id] is malformed; skipped (each section it could not extract is reported)"
      continue
    fi
    printf '[%s]\n' "$id" >> "$tmp"
    rows="${sec_rows[$id]:-}"
    while IFS=$'\t' read -r rk rv; do
      [ -z "$rk" ] && continue
      if [[ "$rv" =~ ^-?[0-9]+$ ]]; then
        printf '%s = %s\n' "$rk" "$rv" >> "$tmp"
      else
        printf '%s = "%s"\n' "$rk" "$rv" >> "$tmp"
      fi
    done <<< "$rows"
    printf '\n' >> "$tmp"
    wrote=1
  done

  if [ "$wrote" -eq 0 ]; then
    rm -f "$tmp" 2>/dev/null || true
    cr_warn "migrate: no extractable sections found; nothing written"
    return 6
  fi

  mv "$tmp" "$out"

  # Rewrite the CLAUDE.md ## Automation Config block down to a pointer.
  local claude_tmp="${claude}.tmp.$$"
  awk '
    /^## Automation Config[[:space:]]*$/ {
      print "## Automation Config"
      print ""
      print "Automation Config lives in [`.agent-flow/config.toml`](.agent-flow/config.toml)."
      print "This section is a pointer only — no inline tables."
      inb=1; next
    }
    inb && /^## / {inb=0; print; next}
    inb {next}
    {print}
  ' "$claude" > "$claude_tmp" && mv "$claude_tmp" "$claude"

  return 0
}
