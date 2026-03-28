---
name: local-review
description: Review local code changes (or full codebase) and produce a structured review summary with P0-P3 severity findings from 5 specialized agents.
disable-model-invocation: true
---

# Local Review

## Overview

Review local code — either changes from the main branch or the full codebase — using 5 specialized review agents in parallel. Produces a structured markdown report at `/tmp/local-review.md` with P0-P3 severity findings.

This skill uses the same agents, severity system, and confidence threshold as `github-pr-review`, but targets local code instead of a GitHub PR.

## Usage

```
/local-review [path] [--all [path]]
```

### Argument Parsing

Parse `$ARGUMENTS` as follows:
- **No arguments** — review only code changed from the main branch (default)
- **A file path or glob** — scope the diff review (e.g. `src/auth.ts`, `src/**`)
- **`--all`** — review ALL tracked code in the repository, not just the diff
- **`--all <path>`** — review all tracked code under the given directory (e.g. `--all ./roles/base`)

If `--all` is present, extract it and any path that follows it. Everything else is ignored.
Otherwise, any remaining text is treated as a path/glob scope for the diff.

## Workflow

**REQUIRED STEPS (do not skip):**

### 1. Determine the main branch

```bash
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'
```

If that fails, fall back to checking for `main` then `master`:
```bash
git rev-parse --verify main 2>/dev/null && echo main || echo master
```

Store the result as `$MAIN_BRANCH`.

### 2. Get the changeset

**Default mode (diff from main branch):**
```bash
# Changes on this branch compared to main
git diff $MAIN_BRANCH...HEAD
```

If `$ARGUMENTS` contains a path/glob (but not `--all`), limit the diff:
```bash
git diff $MAIN_BRANCH...HEAD -- $PATH
```

If the diff is empty, check for uncommitted changes (`git diff HEAD`). If still empty, tell the user there are no changes to review and **stop**.

If there are untracked files the user likely cares about, note them but don't review their full contents unless they appear related to the changed files.

**`--all` mode (full codebase):**
- If a path was provided (e.g. `--all ./roles/base`), identify all tracked files under that path:
  ```bash
  git ls-files -- <path>
  ```
- If no path was provided, identify all tracked files:
  ```bash
  git ls-files
  ```
- There is no diff in this mode. Agents review the full source files directly.

### 3. Get the list of files to review

**Default mode:**
```bash
git diff $MAIN_BRANCH...HEAD --name-only
```

**`--all` mode:**
Use the file list from step 2.

### 4. Launch 5 review agents in parallel

Each agent analyzes the changeset (or full files in `--all` mode) for their specialty:

| Agent | Focus Area | Examples |
|-------|-----------|----------|
| **SOLID + Architecture** | SRP violations, god classes, coupling | OCP violations, hidden dependencies |
| **Security** | Injection, auth issues, hardcoded secrets | Data exposure, IDOR, XSS |
| **Performance** | N+1 queries, inefficient algorithms | Missing caching, O(n^2) |
| **Error Handling** | Swallowed exceptions, missing boundaries | Async error issues, unchecked returns |
| **Boundary Conditions** | Null dereference, empty collections | Off-by-one, overflow, race conditions |

Each agent uses the **same P0-P3 severity system and >= 80% confidence threshold** as `github-pr-review`.

Agents should **read the actual source files** (not just the diff) to understand context.

### Agent Prompt Template

When launching each agent, provide:

1. The mode (diff review or full review)
2. The file list
3. The diff (if in diff mode) or instruction to read full files (if in `--all` mode)
4. The agent's specialty area and what to look for
5. The output format (below)

### Agent Output Format

Each agent produces structured findings:

```markdown
## [Agent Name] Review

### Critical (P0) - Must Fix
- **[file:line]** Issue description
  - Confidence: 95%
  - Fix: [Suggestion or explanation]

### High (P1) - Should Fix
- **[file:line]** Issue description
  - Confidence: 85%
  - Fix: [Suggestion]

### Medium (P2) - Consider Fixing
...

### Low (P3) - Optional
...
```

When a concrete code fix is available, agents MUST include a GitHub-style suggestion block:

````
```suggestion
// the corrected code
```
````

### Severity Levels

All agents use a consistent **P0-P3 severity system**:

| Level | Name | Action |
|-------|------|--------|
| **P0** | Critical | Must fix — security vulnerability, data loss, crash |
| **P1** | High | Should fix — correctness issue, significant maintainability problem |
| **P2** | Medium | Consider fixing — code smell, minor performance issue |
| **P3** | Low | Optional improvement — style, naming, minor clarity |

### Confidence Scoring

All agents use **80+ confidence threshold**:

| Score | Meaning | Reported? |
|-------|---------|-----------|
| 0-49 | Not confident (false positive) | No |
| 50-79 | Somewhat confident (nitpick) | No |
| 80-89 | Confident (real issue) | Yes |
| 90-100 | Very confident (critical) | Yes |

### 5. Consolidate findings

Write a single markdown file to `/tmp/local-review.md`:

```markdown
# Local Review

**Branch:** <current branch>
**Mode:** <"Changes from <main branch>" or "Full review" or "Full review (./path)">
**Files reviewed:** <count>
**Review date:** <date>

## Summary

<1-3 sentence overview of the changeset and overall quality>

| Severity | Count |
|----------|-------|
| P0 Critical | N |
| P1 High | N |
| P2 Medium | N |
| P3 Low | N |

## Critical (P0) — Must Fix

### <file:line> — <title>
**Agent:** <which reviewer> | **Confidence:** <N>%

<description>

```suggestion
// fix if available
```

## High (P1) — Should Fix

...

## Medium (P2) — Consider Fixing

...

## Low (P3) — Optional

...
```

**Omit severity sections that have no findings.**

### 6. Open the review file

- If `mcp__ide__openFile` tool is available, use it to open `/tmp/local-review.md` in the IDE.
- Otherwise, run: `idea <current_project_dir> /tmp/local-review.md` (falls back to `open /tmp/local-review.md` if `idea` is not available). The project dir ensures IntelliJ opens the file in the correct window.

### 7. Tell the user

```
Review written to /tmp/local-review.md with <N> findings.

<severity summary, e.g.: 1 Critical (P0), 3 High (P1), 2 Medium (P2)>
```

## When to Use

- Reviewing local changes before committing or opening a PR
- Full codebase audits (`--all`)
- Scoped audits on a subdirectory (`--all ./src/auth`)
- Pre-PR quality checks on the current branch

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Reviewing only the diff without reading source for context | Agents must read full source files to understand context |
| Skipping empty-diff check | Always check for empty diff and stop early |
| Not checking uncommitted changes when branch diff is empty | Fall back to `git diff HEAD` |
| Reporting findings below 80% confidence | Only report >= 80% confidence |
| Missing severity sections in output | Omit empty sections, don't show "None" |

## Red Flags - You're About to Violate the Pattern

Stop if you're thinking:
- **"The diff is enough context"** — No. Agents must read full source files for context.
- **"I'll skip the confidence threshold"** — No. Only report >= 80%.
- **"I'll just review without agents"** — No. Launch all 5 agents in parallel.
- **"I'll post this to GitHub"** — No. This is local-only. Use `/github-pr-review` for PRs.
