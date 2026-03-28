---
name: github-pr-review
description: Review a GitHub PR and create a pending (draft) review. Takes an optional PR number; defaults to the PR for the current branch.
disable-model-invocation: true
---

# GitHub PR Review

## Overview

Review a GitHub pull request and create a **pending (draft) review** using `gh api`. The draft review is only visible to the authenticated user until they submit it from the GitHub UI, where they can edit comments and choose the event type (Approve, Request Changes, or Comment).

**Multi-Agent Review:** Launch 5 specialized agents (SOLID, Security, Performance, Error Handling, Boundaries) in parallel for comprehensive PR analysis with consistent P0-P3 severity labeling.

## Usage

```
/github-pr-review [PR_NUMBER] [--offline]
```

### Argument Parsing

Parse `$ARGUMENTS` as follows:
- **PR number** — any bare number (e.g. `123`). If absent, resolve from the current branch.
- **`--offline`** — write review JSON and MD files locally but do NOT post to GitHub. The user can review the output and then publish later by re-running without `--offline`.

Examples:
- `/github-pr-review` — review current branch's PR, post draft
- `/github-pr-review 123` — review PR #123, post draft
- `/github-pr-review --offline` — review current branch's PR, write files only
- `/github-pr-review 123 --offline` — review PR #123, write files only
- `/github-pr-review 123` _(after a previous `--offline` run)_ — find existing review and post it

### PR Resolution

1. **If a PR number is provided** — use it directly.
2. **If no PR number is provided** — resolve from the current branch:
   ```bash
   gh pr view --json number --jq '.number'
   ```
   If this fails (no PR for the current branch), **stop immediately** and tell the user:
   ```
   No PR found for the current branch. Please provide a PR number:
     /github-pr-review <PR_NUMBER>
   ```

## Multi-Agent Review (v2.0.0)

**NEW in v2.0.0:** This skill now supports **parallel multi-agent review** using 5 specialized reviewers.

### The 5 Specialized Agents

| Agent | Focus Area | Examples |
|-------|-----------|----------|
| **solid-reviewer** | SOLID Principles + Architecture | SRP violations, god classes, OCP violations |
| **security-reviewer** | Security Vulnerabilities | SQL injection, XSS, IDOR, hardcoded secrets |
| **performance-reviewer** | Performance Issues | N+1 queries, O(n²) algorithms, missing cache |
| **error-handling-reviewer** | Error Handling | Swallowed exceptions, missing error boundaries |
| **boundary-reviewer** | Boundary Conditions | Null dereference, empty arrays, off-by-one |

### Severity Levels

All agents use a consistent **P0-P3 severity system**:

| Level | Name | Action | Event Type |
|-------|------|--------|------------|
| **P0** | Critical | Must fix, blocks merge | `REQUEST_CHANGES` |
| **P1** | High | Should fix before merge | `REQUEST_CHANGES` |
| **P2** | Medium | Fix or create follow-up | `COMMENT` |
| **P3** | Low | Optional improvement | `APPROVE` with notes |

### Suggested Event Type (for user reference)

The multi-agent system suggests an appropriate event type in the human-readable summary. The user chooses the actual event type when submitting the review in the GitHub UI:

```
if (any P0 or P1 findings exist) {
    suggested_event = "REQUEST_CHANGES";
} else if (any P2 findings exist) {
    suggested_event = "COMMENT";
} else if (any P3 findings exist) {
    suggested_event = "APPROVE"; // with notes about P3 issues
} else {
    suggested_event = "APPROVE"; // clean PR
}
```

**Note:** The `event` field is never included in the JSON payload. The review is always created as PENDING. The suggested event type is only shown in the `.md` summary for the user's reference.

### Multi-Agent Workflow

1. **Check gh CLI is installed** — `gh --version`
2. **Resolve PR number** — from `$ARGUMENTS` or current branch (see PR Resolution above)
3. **Get PR details** — commit SHA, diff, changed files
4. **Launch 5 agents in parallel** — each analyzes a specific aspect
5. **Consolidate findings** — merge results by severity level
6. **Determine line numbers** — use file line numbers from the diff
7. **Build review JSON** — no `event` field (always creates PENDING review)
8. **Write files** — write JSON to `/tmp/pr-review-<PR_NUMBER>.json` and summary to `/tmp/pr-review-<PR_NUMBER>.md`
9. **Post or stop** — see "Post or Offline" below

### Agent Output Format

Each agent produces structured findings:

```markdown
## [Agent Name] Review

### Critical (P0) - Must Fix
- **[File:Line]** Issue description
  - Confidence: 95
  - Fix: [Suggestion]

### High (P1) - Should Fix
...
```

### Consolidation Example

The orchestrator combines all agent outputs:

```markdown
# Consolidated PR Review

## Summary
- **P0 (Critical)**: 2 issues from security-reviewer
- **P1 (High)**: 5 issues from solid-reviewer, performance-reviewer
- **P2 (Medium)**: 8 issues across all agents
- **P3 (Low)**: 3 optional improvements

## 🔴 Critical (P0) - Must Fix

### From Security Review
- **app/auth.ts:45** - Hardcoded API key
  - Confidence: 100
  - Fix: Move to environment variable

### From Performance Review
- **app/api/users.ts:78** - N+1 query in user list
  - Confidence: 90
  - Fix: Use eager loading with JOIN

## 🟠 High (P1) - Should Fix
...
```

### Running Multi-Agent Review

Use the orchestrator script:

```bash
./commands/multi-agent-review.sh <pr_number> <commit_sha> [output_dir]
```

Example:
```bash
# Get commit SHA first
COMMIT_SHA=$(gh pr view 6 --json commits --jq '.commits[-1].oid')

# Run multi-agent review
./commands/multi-agent-review.sh 6 $COMMIT_SHA /tmp/pr-review-6

# Review the consolidated output
cat /tmp/pr-review-6/consolidated-review.md
```

### Confidence Scoring

All agents use **80+ confidence threshold**:

| Score | Meaning | Reported? |
|-------|---------|-----------|
| 0-49 | Not confident (false positive) | ❌ No |
| 50-79 | Somewhat confident (nitpick) | ❌ No |
| 80-89 | Confident (real issue) | ✅ Yes |
| 90-100 | Very confident (critical) | ✅ Yes |

### Agent Attributed Transparency

The consolidated review maintains **agent attribution** so reviewers understand:

- Which agent found each issue
- Why it was flagged (agent's expertise area)
- What severity level was assigned
- Confidence score for the finding

Example attribution:
```markdown
- **src/auth.ts:45** - Hardcoded API key (security-reviewer, P0, 100% confidence)
```

### When to Use Multi-Agent vs Manual

**Use Multi-Agent (v2.0.0) for:**
- Comprehensive PR reviews with multiple aspects to check
- Large PRs with many files changed
- Security-sensitive code requiring thorough analysis
- Performance-critical code paths
- Teams wanting consistent review coverage

**Use Manual (v1.x) for:**
- Small, straightforward PRs
- Quick sanity checks
- Focused review on specific aspects
- Learning the PR review workflow

---

## CRITICAL: JSON Payload vs Array Syntax

**⚠️ IMPORTANT: Always use JSON payload for reviews with code suggestions.**

### The Markdown Escaping Problem

When using the `-f` flag with array syntax, backslashes and special characters get escaped, breaking markdown code blocks:

```bash
# ❌ PROBLEMATIC: -f flag breaks markdown
gh api .../reviews \
  -f 'comments[][body]=Fix this:\n\n```suggestion\nconst x = 1;\n```'
# Result: Backslashes get escaped (\\n\\n instead of \n\n)
# Markdown breaks, suggestions appear as plain text
```

### Solution: JSON Payload Approach

**✅ RECOMMENDED: Always use JSON payload with `--input` flag**

```bash
# Create JSON file with proper newlines (no "event" field — creates PENDING review)
cat > /tmp/review.json <<'EOF'
{
  "commit_id": "abc123",
  "body": "Found 2 issues",
  "comments": [
    {
      "path": "src/file.ts",
      "line": 13,
      "body": "Fix the import:\n\n```suggestion\nimport { foo } from './bar';\n```"
    }
  ]
}
EOF

# Post with --input (creates pending/draft review)
gh api .../reviews --input /tmp/review.json
```

### Comparison Table

| Aspect | Array Syntax (-f) | JSON Payload (--input) |
|--------|-------------------|----------------------|
| Markdown rendering | ❌ Breaks with special chars | ✅ Works correctly |
| Type handling | ❌ Numbers become strings | ✅ Types preserved |
| Multiple comments | ❌ Fragile, mixed flags | ✅ Reliable |
| Validation | ❌ Hard to validate | ✅ Can validate first |
| File reuse | ❌ Must recreate each time | ✅ Can save and reuse |

### Helper Commands (v2.1.0+)

The skill includes helper commands for reliable review posting:

```bash
# Validate review JSON before posting
./commands/validate-review.sh <pr_number> <json_file>

# Post review with proper handling
./commands/post-review.sh <pr_number> <json_file>

# Dry run to test
./commands/post-review.sh <pr_number> <json_file> dry_run
```

### Red Flags - You're About to Break Markdown

Stop if you're thinking:
- "I'll use `-f 'body=```suggestion...'`" - **This will break**
- "The `-f` flag should work fine" - **It breaks with backticks**
- "I'll escape the backslashes" - **Don't, use JSON instead**
- "Array syntax is simpler" - **JSON is more reliable**

---

## When to Use

- Reviewing pull requests (`/github-pr-review` or `/github-pr-review 123`)
- Adding code suggestions to PRs
- Comprehensive multi-agent code review

## Prerequisites

**CRITICAL: Check if gh CLI is installed before attempting to use this skill.**

### Check for gh CLI

Before starting any PR review workflow, verify the gh CLI is available:

```bash
gh --version
```

**If gh is not installed:**

1. **Stop immediately** - Do not attempt to run gh api commands
2. **Inform the user** with this message:

```
The GitHub CLI (gh) is required for this skill but is not installed.

Please install it from: https://cli.github.com/

Installation options:
- macOS: brew install gh
- Windows: winget install GitHub.cli
- Linux: See https://cli.github.com/ for your distro

After installing, authenticate with:
  gh auth login

Then try your PR review request again.
```

3. **Do not proceed** with the review workflow until gh is installed

### After Installation

Once gh is installed, users must authenticate:
```bash
gh auth login
```

## Core Workflow

**REQUIRED STEPS (do not skip):**

### Comprehensive Review (Multi-Agent) — Default

1. **Check gh CLI** — `gh --version`
2. **Resolve PR and flags** — parse `$ARGUMENTS` for PR number and `--offline`
3. **Check for pre-existing review** — look for `/tmp/pr-review-<PR_NUMBER>.json`
   - If the file exists AND `--offline` is NOT set: **skip to step 8** (post the existing review)
4. **Get PR details** — commit SHA and diff
5. **Launch 5 agents in parallel** — SOLID, Security, Performance, Error Handling, Boundaries
6. **Consolidate** — build JSON, write to `/tmp/pr-review-<PR_NUMBER>.json`
7. **Write summary** — write human-readable summary to `/tmp/pr-review-<PR_NUMBER>.md`
8. **Post or stop** — see "Post or Offline" below

### Quick/Focused Review

For small PRs or when the user asks for a focused review on a specific aspect:

1. **Check gh CLI** — `gh --version`
2. **Resolve PR and flags** — parse `$ARGUMENTS` for PR number and `--offline`
3. **Check for pre-existing review** — look for `/tmp/pr-review-<PR_NUMBER>.json`
   - If the file exists AND `--offline` is NOT set: **skip to step 7** (post the existing review)
4. **Get PR diff** — analyze and prepare comments with correct line numbers
5. **Build JSON** — write to `/tmp/pr-review-<PR_NUMBER>.json`
6. **Write summary** — write to `/tmp/pr-review-<PR_NUMBER>.md`
7. **Post or stop** — see "Post or Offline" below

### Post or Offline

**If `--offline` is NOT set (default):**
- Run `~/.claude/skills/github-pr-review/commands/post-review.sh <PR_NUMBER> /tmp/pr-review-<PR_NUMBER>.json no_confirm`
- Tell the user:
  ```
  Draft review created on PR #<PR_NUMBER> with <N> comments.

  <severity summary, e.g.: 1 Critical (P0), 3 High (P1), 2 Medium (P2)>

  Open the PR on GitHub to review your pending comments and submit the review.
  ```

**If `--offline` IS set:**
- Do NOT run `post-review.sh`. Do NOT call `gh api`.
- Open the MD file for the user to review:
  - If `mcp__ide__openFile` tool is available, use it to open `/tmp/pr-review-<PR_NUMBER>.md` in the IDE.
  - Otherwise, run: `idea <current_project_dir> /tmp/pr-review-<PR_NUMBER>.md` (falls back to `open /tmp/pr-review-<PR_NUMBER>.md` if `idea` is not available). The project dir ensures IntelliJ opens the file in the correct window.
- Tell the user:
  ```
  Review generated for PR #<PR_NUMBER> with <N> comments (offline mode).

  <severity summary>

  Files written:
    /tmp/pr-review-<PR_NUMBER>.md    (human-readable summary)
    /tmp/pr-review-<PR_NUMBER>.json  (API payload)

  To publish as a pending draft review:
    /github-pr-review <PR_NUMBER>
  ```

## Specifying Comment Locations

Use the `line` and `side` parameters to specify where a review comment should appear. The `position` parameter is deprecated (closing down) — do NOT use it.

Per the GitHub docs: *"The position parameter is closing down. If you use position, the line, side, start_line, and start_side parameters are not required."*

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `line` | integer | Yes | The line number in the diff that the comment applies to. For added/modified lines, this is the line number in the new file. For deleted lines, this is the line number in the old file. |
| `side` | string | No | `RIGHT` (default) for additions and unchanged lines, `LEFT` for deletions. |
| `start_line` | integer | No | For multi-line comments, the first line of the range. |
| `start_side` | string | No | For multi-line comments, the side of the first line. |

### How to determine the correct `line` value

1. **Get the diff:** `gh pr diff <PR_NUMBER> -- path/to/file.ts`
2. **Read the `@@` hunk header** — e.g., `@@ -20,9 +22,13 @@` means the old file chunk starts at line 20, the new file chunk starts at line 22
3. **For added (`+`) and context (` `) lines:** use the line number from the new file (the `+` side of the hunk header), counting down
4. **For removed (`-`) lines:** use the line number from the old file (the `-` side of the hunk header) and set `"side": "LEFT"`

**Example:**
```diff
@@ -20,9 +20,13 @@ export class AuthManager {
   private token: string | null = null;    // line 21 (new file)

+  validateToken() {                       // line 23 (new file)
+    if (!this.token) {                    // line 24
+      throw new Error('No token');        // line 25
+    }                                     // line 26
+  }                                       // line 27
+
   login() {                              // line 29
```

To comment on `throw new Error('No token')`: `"line": 25, "side": "RIGHT"`

### Important

- The `line` must fall within a hunk that is part of the PR diff. You cannot comment on lines outside the diff.
- For most comments (on new or modified code), use `"side": "RIGHT"` or omit `side` entirely (it defaults to `RIGHT`).
- Only use `"side": "LEFT"` when commenting on a deleted line that no longer exists in the new file.

## GitHub API Limitations

### Pending Reviews Cannot Be Updated

**CRITICAL:** Once a pending review is created, you CANNOT add more comments to it.

Include ALL comments when creating the review. If a batch post fails, fall back to posting comments individually via `POST /repos/{owner}/{repo}/pulls/{pull_number}/comments` using `line`/`side`.

## Validation Checklist

Before posting any review, verify:

- [ ] `commit_id` is set to the latest commit SHA
- [ ] All `comments[][path]` values are non-empty strings
- [ ] All `comments[][line]` values are positive integers matching lines within the diff
- [ ] All `comments[][body]` values are non-empty strings
- [ ] `side` is `"RIGHT"` for added/context lines, `"LEFT"` for deleted lines (or omitted to default to `RIGHT`)
- [ ] API headers are included: `Accept` and `X-GitHub-Api-Version`

### Error Reference

| Error Message | Cause | Fix |
|---------------|-------|-----|
| `Expected value to not be null` (line) | Missing or invalid `line` value | Ensure `line` is a positive integer within the diff |
| `Expected value to not be null` (path) | Empty or null path value | Ensure all comments have valid file paths |
| `Expected value to not be null` (body) | Empty or null comment body | Ensure all comments have non-empty text |
| `Field is not defined on DraftPullRequestReviewComment` (side) | Using invalid `side` parameter | Remove `side` from all comments |
| `"comments", "commit_id" are not permitted keys` | Trying to update pending review | Delete and recreate, or use individual comments |
| `Pull request review thread line must be part of the diff` | `line` is outside the diff range | Check `gh pr diff` to find valid line numbers |
| `invalid key: "body@-"` | Using `--raw-field body@-` syntax | Use `-F body@-` or file-based approach |
| Shell command not found errors | Special characters in body causing shell interpretation | Use file-based approach for complex bodies |
| `Could not comment pull request review` | Calling events API on already-submitted review | Review was auto-submitted (you included `event` in payload) - don't call events API again |

## Handling Complex Comment Bodies

Always use JSON payloads with `--input` — this avoids all shell escaping issues with backticks, quotes, and code blocks. In JSON, use `\n` for newlines and escape inner double quotes with `\"`.

## Quick Reference

```bash
# Get commit SHA
gh pr view <PR_NUMBER> --json commits --jq '.commits[-1].oid'

# Get the diff to determine line numbers
gh pr diff <PR_NUMBER>

# Get diff for specific file
gh pr diff <PR_NUMBER> -- path/to/file.ts
```

### Required Parameters

- `commit_id`: Latest commit SHA from the PR
- `comments[][path]`: File path relative to repo root (must be non-empty)
- `comments[][line]`: Line number in the diff (the file line number from the new file for additions/context, from the old file for deletions)
- `comments[][body]`: Comment text with optional ```suggestion block (must be non-empty)

### Optional Parameters

- `comments[][side]`: `RIGHT` (default) for additions/context, `LEFT` for deleted lines
- `comments[][start_line]`: For multi-line comments, the first line of the range
- `comments[][start_side]`: For multi-line comments, the side of the first line
- `event`: Omit for PENDING, or use `COMMENT`/`APPROVE`/`REQUEST_CHANGES`

### Rules

- Always use JSON payload with `--input` — never `-f`/`-F` array syntax
- Use `line`/`side` — never the deprecated `position` parameter
- Never include `event` in JSON — always create PENDING reviews
- All comments must have non-empty `path`, `line`, and `body`
- `line` must fall within a diff hunk

## Code Suggestions Format

**IMPORTANT:** When a concrete code fix is available, ALWAYS include a GitHub `suggestion` block in the comment body. This lets the PR author apply the fix with one click.

In the comment `body`, use a `suggestion` code block:

```json
{
  "path": "src/file.ts",
  "line": 45,
  "side": "RIGHT",
  "body": "**P1 | Security** Fix the import:\n\n```suggestion\nimport { foo } from './bar';\n```\n\nThe path was incorrect."
}
```

- The `suggestion` block replaces the line specified by `line`. Make sure the suggested code is complete and correct for that line.
- For multi-line suggestions, use `start_line` and `start_side` to specify the range, and include all replacement lines in the suggestion block.
- Not every comment needs a suggestion — use them when you have a specific code fix, not for architectural advice or questions.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Re-running full review when JSON already exists | If `/tmp/pr-review-<PR>.json` exists and `--offline` is not set, just post it |
| "Only one comment so no need for pending" | Use pending anyway - consistent workflow, allows adding more later |
| Forgetting single quotes around `comments[][]` | Always quote: `'comments[][path]'` not `comments[][path]` |
| Using deprecated `position` parameter | Use `line`/`side` instead — `position` is closing down |
| Not getting commit SHA | Run `gh pr view <NUMBER> --json commits --jq '.commits[-1].oid'` |
| Using wrong event type | Security/bugs → REQUEST_CHANGES, Style → APPROVE, Questions → COMMENT |
| Null/empty body values | Ensure all comments have non-empty body text |
| Null/empty path values | Ensure all comments have valid file paths |
| Invalid line values | Ensure `line` falls within a diff hunk — you can only comment on lines in the diff |
| Missing API headers | Always include `-H "Accept: application/vnd.github+json"` and `-H "X-GitHub-Api-Version: 2022-11-28"` |
| Trying to update pending review | Cannot update - must include all comments when creating |
| Using `-f`/`-F` array syntax | Use JSON payload with `--input` instead |
| Including `event` in JSON then calling events API | Review auto-submits - don't call events API again, or omit `event` for two-call pattern |

## Red Flags - You're About to Violate the Pattern

Stop if you're thinking:
- **"I'll include `event` in the JSON"** — No. Omit it. Always PENDING.
- **"I'll call `gh api` directly instead of `post-review.sh`"** — Use the script; it strips `event` and handles errors.
- **"I'll use the deprecated `position` parameter"** — No. Use `line`/`side`.
- **"I can update the pending review later with more comments"** — No. Include all comments at creation.
- **"I can comment on any line in the file"** — No. The `line` must fall within a diff hunk.
- **"gh is probably installed, no need to check"** — Always check first.
- **"I'll re-run the full review even though a review JSON already exists"** — No. If `/tmp/pr-review-<PR_NUMBER>.json` exists and `--offline` is not set, just post it.

**ALL of these are wrong. Never include `event` in the JSON. The review is always PENDING — the user submits from the GitHub UI.**

**Why PENDING?** The review is a draft visible only to the authenticated user:
- User can edit comments and adjust tone in the GitHub UI before submitting
- No notifications sent until the user clicks "Submit review"
- Safe even with `--dangerously-skip-permissions` since nothing is published

**Why `line`/`side` instead of `position`?** GitHub's docs say `position` is closing down:
- `line` uses the actual file line number — intuitive and less error-prone
- `side` specifies LEFT (deletions) or RIGHT (additions/context, default)
- `position` required counting lines from `@@` hunk headers — fragile and model-unfriendly

## Complete Example

```bash
# 1. Resolve PR and get details
PR_NUMBER=123  # or from: gh pr view --json number --jq '.number'
COMMIT_SHA=$(gh pr view $PR_NUMBER --json commits --jq '.commits[-1].oid')

# 2. Get diff to identify line numbers
gh pr diff $PR_NUMBER > /tmp/pr-diff-$PR_NUMBER.txt

# 3. Build review JSON (no "event" field — always PENDING; use "line"/"side" not "position")
cat > /tmp/pr-review-$PR_NUMBER.json <<'EOF'
{
  "commit_id": "<COMMIT_SHA>",
  "body": "Found 2 issues.",
  "comments": [
    {
      "path": "src/components/Button.tsx",
      "line": 17,
      "side": "RIGHT",
      "body": "Missing loading state..."
    },
    {
      "path": "src/auth.ts",
      "line": 25,
      "side": "RIGHT",
      "body": "Token validation is missing..."
    }
  ]
}
EOF

# 4. Post as draft review
~/.claude/skills/github-pr-review/commands/post-review.sh $PR_NUMBER /tmp/pr-review-$PR_NUMBER.json no_confirm

# 5. User opens GitHub, reviews pending comments, and clicks "Submit review"
```

## Error Handling Guide

### When Line Number Errors Occur

If the API rejects a comment due to its line number:

1. **Verify the line is within the diff:**
   ```bash
   gh pr diff <PR_NUMBER> -- path/to/file.ts
   ```
   The `line` value must fall within a hunk in the diff. You cannot comment on lines outside changed hunks.

2. **Check `side` is correct:**
   - `RIGHT` for added/context lines (new file line number)
   - `LEFT` for deleted lines (old file line number)

3. **Use the fallback strategy:**
   - Create a review without comments
   - Add comments individually using the `/comments` endpoint

### When Batch Post Fails

If creating the pending review fails with multiple comments:

1. **Check for null/empty values:**
   - All `path` values must be non-empty
   - All `body` values must be non-empty
   - All `line` values must be positive integers within the diff

2. **Try with fewer comments:**
   - Split into smaller batches
   - Or use the fallback strategy

3. **Use individual comment posting:**
   ```bash
   # Create a simple review
   gh api repos/:owner/:repo/pulls/123/reviews \
     -X POST \
     -H "Accept: application/vnd.github+json" \
     -H "X-GitHub-Api-Version: 2022-11-28" \
     -f commit_id="$COMMIT_SHA" \
     -f event="COMMENT" \
     -f body="Please see inline comments."

   # Add comments individually using line/side
   gh api repos/:owner/:repo/pulls/123/comments \
     -X POST \
     -H "Accept: application/vnd.github+json" \
     -H "X-GitHub-Api-Version: 2022-11-28" \
     -f commit_id="$COMMIT_SHA" \
     -f path="src/file.ts" \
     -F line=15 \
     -f side="RIGHT" \
     -f body="Comment text..."
   ```

## Why This Approach

- **All feedback batched** into one coherent draft review
- **No notifications** until the user manually submits from GitHub UI
- **User retains control** — can edit comments, adjust tone, and choose event type before submitting
- **Safe with `--dangerously-skip-permissions`** — pending reviews are private drafts
- **Optional offline mode** — use `--offline` to review generated files before publishing, then re-run without the flag to post
