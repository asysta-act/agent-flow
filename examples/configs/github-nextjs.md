# Next.js + GitHub — Automation Config Template

> Copy the section below into your project's CLAUDE.md

## Automation Config

### Issue Tracker
| Key | Value |
|------|---------|
| Type | github |
| Instance | `github.com` |
| Project | `<owner/repo>` |
| Bug query | `is:issue is:open label:bug` |
| State transitions | In Progress: `add label:in-progress`, Blocked: `add label:blocked`, For Review: `add label:for-review`, Done: `close` |
| On start set | `add label:in-progress` |

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

Fixes #{issue_number}

### Build & Test
| Key | Value |
|------|---------|
| Build command | `npm run build` |
| Test command | `npm test` |

> **Uncomment and customize optional sections as needed.**

<!--
### Build & Test (extended — Verify command)
| Key | Value |
|------|---------|
| Build command | `npm run build` |
| Test command | `npm test` |
| Verify command | `npm run verify-fix` |

### Retry Limits (optional)
| Key | Value |
|------|---------|
| Fixer iterations | 5 |
| Test attempts | 3 |
| Build retries | 3 |

### Hooks (optional)
| Key | Value |
|------|---------|
| Pre-fix | `npm run lint` |
| Post-fix | `npm run lint:fix` |
| Pre-publish | `npm run build` |
| Post-publish | `echo "Published"` |

### Custom Agents (optional)
| Key | Value |
|------|---------|
| Post-fix agent | security-analyst |
| Pre-publish agent | compliance-checker |

### Notifications (optional)
| Key | Value |
|------|---------|
| Webhook URL | `https://hooks.slack.com/services/XXX/YYY/ZZZ` |
| On events | `pipeline-completed, issue-blocked, pr-created` |

### Worktrees (optional)
| Key | Value |
|------|---------|
| Batch size | 3 |
| Base path | `.worktrees/` |
| Cleanup | auto |

### E2E Test (optional)
| Key | Value |
|------|---------|
| Framework | playwright |
| Command | `npx playwright test` |

### Error Handling (optional)
| Key | Value |
|------|---------|
| On block | comment |
| Max blocked per run | 5 |

### Feature Workflow (optional)
| Key | Value |
|------|---------|
| Feature query | `is:issue is:open label:feature` |
| On start set | `add label:in-progress` |

### Decomposition (optional)
| Key | Value |
|------|---------|
| Max subtasks | 7 |
| Fail strategy | fail-fast |
| Commit strategy | squash |

### Pipeline Profiles (optional)
| Profile | Skip stages | Extra stages |
|--------|-------------|-------------|
| fast | analyst-triage, analyst-impact, test-engineer | — |
| strict | — | test-engineer-e2e |
| minimal | analyst-triage, analyst-impact, test-engineer, test-engineer-e2e | — |

### Metrics (optional)
| Key | Value |
|------|---------|
| Output | stdout |
| Period | 30 |

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
