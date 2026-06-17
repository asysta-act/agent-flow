# Ruby on Rails + Redmine — Automation Config Template

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

## Changes
{changes}

## Testing
{testing}

Refs #{issue_id}

### Build & Test
| Key | Value |
|------|---------|
| Build command | `bundle exec rails assets:precompile` |
| Test command | `bundle exec rspec` |

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

