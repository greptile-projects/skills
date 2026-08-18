---
name: review-changes
description: Review local changes with Greptile.
---

# Review Changes

Review the current local changes with Greptile and summarize the findings.

## Instructions

### 1. Confirm repository context

Start from the current repository root:

```bash
git rev-parse --show-toplevel
```

If the command fails, tell the user that a Greptile code review must be run from a git repository.

**The current branch must not be the default branch.** The CLI reviews the current branch against its base, so it cannot review from `main`/`master`/the repository default:

```bash
CURRENT_BRANCH=$(git branch --show-current)
DEFAULT_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
```

If the current branch is the default branch, stop and tell the user to switch to (or create) a feature branch containing their changes.

### 2. Prepare Greptile

Check whether the `greptile` command is available:

```bash
command -v greptile
```

If it is missing, do not install it automatically. Ask the user for permission, then show the recommended install command:

```bash
npm i -g greptile
```

If npm is unavailable, offer the shell installer fallback:

```bash
curl -fsSL "https://greptile.com/cli/install" | sh
```

After installation, re-run `command -v greptile`.

### 3. Ensure authentication

Check the signed-in account:

```bash
greptile whoami
```

If authentication is missing, run:

```bash
greptile login
```

Wait for the user to complete the login flow before continuing.

### 4. Run the review

Prefer JSON output:

```bash
greptile review --json
```

If JSON output is unsupported or fails with a usage error, fall back to:

```bash
greptile review --agent
```

Do not hide the raw command failure if both commands fail. Summarize the failing command and the next action the user needs to take.

### 5. Summarize results

Parse JSON output when available and report:

- Review status
- Number of findings
- Highest-severity findings first
- Files that need edits
- Suggested next command or fix path

When output is plain text, preserve the same structure as much as possible. Keep the summary concise and focused on actionable findings.
