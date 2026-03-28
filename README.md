# Code Review Skills for Claude Code

Based on [aidankinzett/claude-git-pr-skill#3](https://github.com/aidankinzett/claude-git-pr-skill/pull/3).

Claude Code skills for consistent, professional code reviews — both GitHub PRs and local code — using 5 specialized agents with P0-P3 severity scoring.

## Skills

### `/github-pr-review`

Reviews a GitHub pull request and creates a **pending (draft) review**. The draft is only visible to the authenticated user until they submit it from the GitHub UI — no notifications are sent, and the user can edit comments and choose the final event type before publishing.

```
/github-pr-review [PR_NUMBER] [--offline]
```

### `/local-review`

Reviews local code changes (diff from main branch) or the full codebase. Produces a structured markdown report at `/tmp/local-review.md`.

```
/local-review [path] [--all [path]]
```

## How It Works

Both skills launch 5 specialized review agents in parallel:

| Agent | Focus Area |
|-------|-----------|
| **SOLID + Architecture** | SRP violations, god classes, coupling |
| **Security** | Injection, auth issues, hardcoded secrets, data exposure |
| **Performance** | N+1 queries, inefficient algorithms, missing caching |
| **Error Handling** | Swallowed exceptions, missing boundaries, async issues |
| **Boundary Conditions** | Null dereference, empty collections, off-by-one |

Findings are scored P0-P3 with a confidence threshold of 80%+:

| Level | Name | Meaning |
|-------|------|---------|
| **P0** | Critical | Must fix — security vulnerability, data loss, crash |
| **P1** | High | Should fix — correctness issue, significant problem |
| **P2** | Medium | Consider fixing — code smell, minor performance issue |
| **P3** | Low | Optional improvement — style, naming, clarity |

## Installation

### Plugin Marketplace (Recommended)

Install directly from the marketplace using Claude Code:

```bash
# Add this marketplace
/plugin marketplace add moltenbits/claude-review

# Install the plugins
/plugin install github-pr-review
/plugin install local-review

# Verify installation
/plugin list
```

**For team-wide installation**, add to `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": [
    {
      "name": "claude-review",
      "source": {
        "source": "github",
        "repo": "moltenbits/claude-review"
      }
    }
  ],
  "plugins": {
    "github-pr-review": {
      "enabled": true
    },
    "local-review": {
      "enabled": true
    }
  }
}
```

### Manual Copy

Copy the skills directly to your skills directory:

```bash
# github-pr-review (all projects)
cp -r github-pr-review/skills/github-pr-review ~/.claude/skills/

# local-review (all projects)
cp -r local-review/skills/local-review ~/.claude/skills/

# Or project-specific
cp -r github-pr-review/skills/github-pr-review .claude/skills/
cp -r local-review/skills/local-review .claude/skills/
```

For `github-pr-review`, also copy the supporting directories:

```bash
cp -r github-pr-review/agents ~/.claude/skills/github-pr-review/
cp -r github-pr-review/commands ~/.claude/skills/github-pr-review/
cp -r github-pr-review/references ~/.claude/skills/github-pr-review/
cp -r github-pr-review/templates ~/.claude/skills/github-pr-review/
```

## Prerequisites

- Claude Code
- GitHub CLI (`gh`) installed and authenticated (for `github-pr-review`)

## Repository Structure

```
.claude-plugin/
  marketplace.json          # Plugin marketplace definition
github-pr-review/           # PR review plugin
  skills/
    github-pr-review/
      SKILL.md              # PR review skill definition
  agents/                   # 5 specialized reviewer agents
  commands/                 # Helper scripts (post-review, validation, etc.)
  references/               # Review checklists per agent
  templates/                # JSON payload templates
local-review/               # Local review plugin
  skills/
    local-review/
      SKILL.md              # Local review skill definition
CHANGELOG.md                # Version history and changes
```

## License

MIT
