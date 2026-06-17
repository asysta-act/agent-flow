# React + Jira — Automation Config Template

> Copy the section below into your project's CLAUDE.md

## Automation Config

### Issue Tracker
| Key | Value |
|------|---------|
| Type | jira |
| Instance | `<org>.atlassian.net` |
| Project | `<PROJECT_KEY>` |
| Bug query | `project = <PROJECT_KEY> AND status = Open AND type = Bug` |
| State transitions | In Progress: `transition:In Progress`, Blocked: `transition:Blocked`, For Review: `transition:In Review`, Done: `transition:Done` |
| On start set | `transition:In Progress` |

### Source Control
| Key | Value |
|------|---------|
| Remote | `github.com/<owner/repo>` |
| Base branch | `main` |
| Branch naming | `fix/{issue}-{short-description}` |

### PR Rules
| Key | Value |
|------|---------|
| Labels | `ForReview` |
| Title format | `{issue-id}-{mode}-{summary}` |

### PR Description Template

## Summary
{summary}

## Changes
{changes}

## Testing
{testing}

Fixes {issue_key}

### Build & Test
| Key | Value |
|------|---------|
| Build command | `npm run build` |
| Test command | `npm test` |

> **Uncomment and customize optional sections as needed.**

<!--
### Autopilot (optional)
| Key | Value |
|-----|-------|
| Max issues per run | 1 |
| Lock timeout | 120 |
| Log file | .agent-flow/autopilot.log |
| Bug limit | 0 |
| Feature limit | 0 |
| On error | skip |
| Dry run | false |

### Pause Limits (optional)
| Key | Value |
|-----|-------|
| Pause timeout | 30 days |
-->

