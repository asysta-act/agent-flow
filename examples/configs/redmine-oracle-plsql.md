# Oracle PL/SQL + Redmine — Automation Config Template

> Copy the section below into your project's CLAUDE.md

## Automation Config

### Issue Tracker
| Key | Value |
|------|---------|
| Type | redmine |
| Instance | `<your-redmine-instance>` |
| Project | `<project-identifier>` |
| Bug query | `project_id=<project-identifier>&status_id=open&tracker_id=<bug-tracker-id>` |
| State transitions | In Progress: `status_id:2`, Blocked: `status_id:4`, For Review: `status_id:4`, Done: `status_id:5` |
| On start set | `status_id:2` |

<!-- TODO: Verify status IDs match your Redmine instance (GET /issue_statuses.json). Common defaults: 1=New, 2=In Progress, 3=Resolved, 4=Feedback, 5=Closed, 6=Rejected -->
<!-- TODO: Verify tracker_id corresponds to "Bug" tracker (GET /projects/<id>/trackers.json) -->

### Source Control
| Key | Value |
|------|---------|
| Remote | `<owner/repo>` |
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

## Root Cause
{root_cause}

## Changes
{changes}

## Testing
- Build: {build_result}
- Unit tests (utPLSQL): {test_result}

Refs #{issue_id}

### Build & Test
| Key | Value |
|------|---------|
| Build command | `bash db/scripts/deploy.sh` |
| Test command | `bash db/scripts/test.sh` |

<!-- TODO: deploy.sh should run Flyway migrations + SQLcl compilation + validation -->
<!-- TODO: test.sh should run utPLSQL test suite and return exit code -->

### Retry Limits
| Key | Value |
|------|---------|
| Fixer iterations | 3 |
| Test attempts | 2 |
| Build retries | 2 |
| Spec iterations | 3 |
| Root cause iterations | 2 |

<!-- Conservative limits for Oracle PL/SQL — opus fixer-reviewer loop is the main cost driver -->

### Pipeline Profiles
| Profile | Skip stages | Extra stages |
|---------|-------------|--------------|
| oracle-backend | browser-agent-reproduce, browser-agent-verify, test-engineer-e2e | |

<!-- Oracle backend projects typically don't need browser/UI verification stages -->

### Agent Overrides
| Key | Value |
|------|---------|
| Path | `customization/` |

<!-- Create customization/fixer.md with Oracle PL/SQL coding conventions -->
<!-- Create customization/test-engineer.md with utPLSQL testing conventions -->
<!-- See agent-flow docs/guides/custom-agents.md for Agent Override format -->

### Local Deployment
| Key | Value |
|------|---------|
| Type | docker |
| Start command | `docker start <oracle-container-name>` |
| Stop command | `docker stop <oracle-container-name>` |
| Health check URL | `sqlplus -S <user>/<pass>@localhost:1521/<service> <<< "SELECT 1 FROM DUAL;"` |
| Health check timeout | 60 |
| Ports | 1521 |

<!-- TODO: Replace <oracle-container-name> with your Oracle XE container name -->
<!-- TODO: Adjust connection string for your Oracle setup (XE 21c default service: XEPDB1) -->

### Error Handling
| Key | Value |
|------|---------|
| On block | comment |
| Max blocked per run | 3 |

### Decomposition
| Key | Value |
|------|---------|
| Max subtasks | 5 |
| Fail strategy | fail-fast |
| Commit strategy | squash |
| Create tracker subtasks | disabled |

### Autopilot
| Key | Value |
|-----|-------|
| Max issues per run | 1 |
| Lock timeout | 120 |
| Log file | .agent-flow/autopilot.log |
| Bug limit | 0 |
| Feature limit | 0 |
| On error | skip |
| Dry run | false |

### Pause Limits
| Key | Value |
|-----|-------|
| Pause timeout | 30 days |

> **Uncomment and customize optional sections as needed.**

<!--
### Feature Workflow (optional)
| Key | Value |
|------|---------|
| Feature query | `project_id=<project-identifier>&status_id=open&tracker_id=<feature-tracker-id>` |
| On start set | `status_id:2` |

### Hooks (optional)
| Key | Value |
|------|---------|
| Pre-fix | `bash db/scripts/check_errors.sh` |
| Post-fix | `bash db/scripts/deploy.sh` |
| Pre-publish | `bash db/scripts/test.sh` |
| Post-publish | `echo "Published"` |

### Custom Agents (optional)
| Key | Value |
|------|---------|
| Post-fix agent | security-analyst |
| Pre-publish agent | compliance-checker |

### Notifications (optional)
| Key | Value |
|------|---------|
| Webhook URL | `<webhook-url>` |
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

### Browser Verification (optional)
| Key | Value |
|------|---------|
| Base URL | `http://localhost:3000` |
| Start command | `npm start` |
| Stop command | `npm stop` |
| On events | `reproduce, verify` |
| Timeout | 30 |
| Max pages | 3 |
| Screenshot storage | `.agent-flow/screenshots/` |
| Exploration | disabled |
| Exploration max clicks | 5 |

### Module Docs (optional)
| Key | Value |
|------|---------|
| Path | `docs/` |

### Metrics (optional)
| Key | Value |
|------|---------|
| Output | stdout |
| Period | 30 |
-->
