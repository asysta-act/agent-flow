---
name: discuss
description: Multi-agent discussion -- brings 2-3 agent perspectives into one conversation
allowed-tools: Task, Read, Glob
argument-hint: "<topic> [--agents <list>]"
---

# Discuss

Input: `$ARGUMENTS` = topic or question + optional `--agents <list>` (comma-separated agent names)

## Steps

1. Parse `$ARGUMENTS`:
   - `--agents reviewer,fixer,architect` → agent_list
   - Default agent_list: `reviewer,fixer,architect` (if not specified)
   - Remainder (everything outside `--agents <list>`) = topic. Topic is always treated as
     literal freeform text — `/discuss` does NOT query the issue tracker or resolve
     issue IDs, even if the topic string looks like one; there is no MCP tool in
     `allowed-tools` to do so.
   - Validate agent_list: dedupe repeated names (case-sensitive, keep first occurrence's
     position). Enumerate valid agent names via `Glob agents/*.md` (filename minus `.md`
     is the agent name). If any requested name doesn't match a file, stop before dispatching
     anything and display: "Unknown agent: {name}. Valid agents: {comma-separated list}."
   - Max 3 agents per discussion. If agent_list (after dedupe) has more than 3 names, keep
     only the first 3 in the order given and tell the user: "Using first 3 agents: {kept}
     (dropped: {dropped})."

2. For each agent in agent_list (in parallel):
   Agent Overrides do NOT apply to `/discuss`. This skill sends each agent an ad-hoc
   discussion prompt, not the agent's full pipeline base prompt that
   `../../core/agent-override-injector.md` renders project customization onto, and this
   skill's `allowed-tools` intentionally excludes `Bash`, which the injector's overlay
   resolution (`skills/setup-agents/lib/toml-merge.sh::resolve_overlay()`) requires. Project
   customization of agent behavior applies only inside the full pipelines
   (`/agent-flow:fix-bugs`, `/agent-flow:implement-feature`, `/agent-flow:scaffold`).
   Read `agents/{agent}.md` frontmatter for that agent's `description`, `style`, and `model`.
   You MUST invoke `Task(subagent_type='agent-flow:{agent}', model='{agent's model from its frontmatter}')`. DO NOT inline-execute.
   Context:
   ```
   You are participating in a multi-agent discussion about: {topic}
   Your role: {agent description from frontmatter}
   Style: {agent style from frontmatter}

   Provide your perspective on this topic in 100-200 words.
   Focus on concerns and insights specific to YOUR expertise.
   Be opinionated — disagree with conventional wisdom if your expertise suggests otherwise.

   This is discussion only — do NOT read, write, or edit any files, and do NOT run
   build/test/deploy commands or invoke any tools. Respond with analysis text only.
   ```

3. Collect all agent responses.

4. Display as structured discussion:
   ```
   ## Discussion: {topic}

   ### {agent-1 name} ({agent-1 style})
   {agent-1 perspective}

   ### {agent-2 name} ({agent-2 style})
   {agent-2 perspective}

   ### {agent-3 name} ({agent-3 style})
   {agent-3 perspective}

   ### Synthesis
   {synthesize key agreements, disagreements, and recommended approach}
   ```

5. Ask: "Follow up on any perspective? [agent name / done]"
   - If the user names an agent that is in the (post-truncation) agent_list from Step 1 →
     re-invoke `Task(subagent_type='agent-flow:{agent}', model='{agent's model from its frontmatter}')`
     with the full discussion context (original topic + all agent responses + synthesis) for
     deeper exploration, under the same no-tool-use restriction as Step 2.
   - If the user names an agent NOT in agent_list → display: "Unknown agent: {name}. Choose
     one of: {agent_list}, or 'done'." and re-ask; do not dispatch.
   - If the user says "done" (or gives no further input) → end the discussion.

## Rules

- Max 3 agents per discussion — excess names are truncated in Step 1 (first 3 kept), not silently dropped without notice
- Every requested agent name is validated against `agents/*.md` before any dispatch; unknown names stop the discussion with an error instead of being skipped silently
- Agent Overrides do not apply to `/discuss` — see Step 2 for why
- Read-only — no code changes; each dispatched agent is explicitly told (Step 2 context) to use no tools and return analysis text only
- Topic is passed through as literal text — no issue-tracker lookup, even for topics shaped like issue IDs
- Each agent response: 100-200 words max
- Discussion is for exploration, not decisions — no pipeline side effects, no state.json writes, no issue tracker updates
