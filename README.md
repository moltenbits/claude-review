# Code Review Skills for Claude Code

Based on [aidankinzett/claude-git-pr-skill#3](https://github.com/aidankinzett/claude-git-pr-skill/pull/3).

Claude Code skills for consistent, professional code reviews — both GitHub PRs and local code — using 5 specialized agents with P0-P3 severity scoring.

## Skills

### `/github-pr-review`

Reviews a GitHub pull request and creates a **pending (draft) review**. The draft is only visible to the authenticated user until they submit it from the GitHub UI — no notifications are sent, and the user can edit comments and choose the final event type before publishing.

```
/github-pr-review [PR_NUMBER] [--offline]
```

- **`PR_NUMBER`** — the PR to review. If omitted, resolves from the current branch.
- **`--offline`** — write review JSON and markdown files locally but don't post to GitHub. You can review the output and then publish later by re-running without `--offline`.

### `/local-review`

Reviews local code changes (diff from main branch) or the full codebase. Produces a structured markdown report at `/tmp/local-review.md`.

```
/local-review [path] [--all [path]]
```

- **No arguments** — review only code changed from the main branch.
- **`path`** — scope the diff review to a file or glob (e.g. `src/auth.ts`, `src/**`).
- **`--all`** — review all tracked files in the repository, not just the diff.
- **`--all path`** — review all tracked files under a specific directory (e.g. `--all ./src/auth`).

## What These Skills Do

These skills teach Claude to:
- **Always create pending (draft) reviews** — no notifications until you submit from the GitHub UI
- **Batch all comments** into a single review instead of scattered individual comments
- **Create code suggestions** using the ` ```suggestion ` syntax for one-click fixes
- **Use correct `gh api` syntax** with JSON payloads and `--input` (not fragile `-f` array syntax)
- **Review local code** before opening a PR, with the same rigor as a PR review

## Usage

```
You: "Review PR #123"
Claude: *Launches 5 agents, creates pending review with batched comments and suggestions*

You: "/local-review"
Claude: *Reviews branch diff, writes structured report to /tmp/local-review.md*

You: "/local-review --all ./src/auth"
Claude: *Reviews all tracked files under src/auth*
```

## What Makes These Skills Different

**Without these skills**, Claude might:
- Post comments immediately without batching them
- Skip pending reviews under time pressure
- Use incorrect `gh api` syntax that breaks markdown rendering
- Miss issues that a specialized reviewer (security, performance, etc.) would catch

**With these skills**, Claude will:
- Always create pending reviews first — you control when they're published
- Batch all comments together in one coherent review
- Use code suggestions with ` ```suggestion ` blocks for one-click fixes
- Run 5 specialized agents in parallel for comprehensive coverage
- Use correct JSON payload syntax that preserves markdown formatting

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

## PR Review Workflow

The `github-pr-review` skill enforces this workflow:

### 1. Analyze
Claude fetches the PR diff and launches 5 specialized agents in parallel.

### 2. Consolidate
Agent findings are merged by severity, deduplicated, and written to:
- `/tmp/pr-review-<PR_NUMBER>.json` — API payload
- `/tmp/pr-review-<PR_NUMBER>.md` — human-readable summary

### 3. Post (or save offline)
- **Default:** Posts as a pending (draft) review via `gh api`. The review is only visible to you until you submit it from the GitHub UI.
- **`--offline`:** Writes files only. Review later with `/github-pr-review <PR_NUMBER>` to post.

## Development

To test changes locally:

```bash
# Symlink for testing
ln -s $(pwd)/github-pr-review/skills/github-pr-review ~/.claude/skills/github-pr-review
ln -s $(pwd)/local-review/skills/local-review ~/.claude/skills/local-review

# Or use the plugin marketplace locally
/plugin marketplace add file://$(pwd)
/plugin install github-pr-review
/plugin install local-review
```
