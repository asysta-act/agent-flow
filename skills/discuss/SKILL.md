---
name: discuss
description: Multi-agent discussion -- brings 2-3 agent perspectives into one conversation
allowed-tools: Task, Read, Glob, Grep
argument-hint: "<topic> [--agents <list>]"
---

# Discuss

Input: `$ARGUMENTS` = topic or question + optional `--agents <list>` (comma-separated agent names)

## Steps

1. Parse `$ARGUMENTS`:
   - `--agents reviewer,fixer,architect` → agent_list
   - Default agent_list: `reviewer,fixer,architect` (if not specified)
   - Remainder = topic
   - Max 3 agents per discussion

2. For each agent in agent_list (in parallel):
   Before dispatch, check Agent Overrides: for each agent you dispatch, follow `../../core/agent-override-injector.md` for that agent's overrides.
   Run agent via Task tool with context:
   ```
   You are participating in a multi-agent discussion about: {topic}
   Your role: {agent description from frontmatter}
   Style: {agent style from frontmatter}

   Provide your perspective on this topic in 100-200 words.
   Focus on concerns and insights specific to YOUR expertise.
   Be opinionated — disagree with conventional wisdom if your expertise suggests otherwise.
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
   If user picks an agent → run that agent again with the full discussion context for deeper exploration.

## Rules

- Max 3 agents per discussion
- Read-only — no code changes
- Each agent response: 100-200 words max
- Discussion is for exploration, not decisions — no pipeline side effects
