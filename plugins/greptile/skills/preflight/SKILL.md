---
name: preflight
description: Reviews high-consequence code with Greptile before it runs — migrations, backfills, bulk operations, infra changes, or any script whose execution is hard to undo. Produces a blast-radius report (data touched, downstream consumers, per-row side effects, reversibility) and a run / fix-first verdict. Use when the user asks to check, preflight, or review something before running it. Never run automatically; if the agent authored a consequential script, it may offer a preflight, but only proceed when the user agrees.
---

# Preflight

Review code that is about to be **executed**, not merged, and report what it will actually do to data and downstream systems before anyone runs it.

Preflight is for code whose execution has consequences beyond the process: database migrations and backfills, bulk API calls, `terraform`/`kubectl` changes, one-off data scripts. It is **not** for single destructive shell commands (`rm -rf`, `sudo`, etc.) — the agent harness's permission system already gates those. Preflight reads the code the permission prompt can't see inside.

Division of labor: **Greptile finds defects in the code** (its native review — the wrong filter, the pagination bug, the timezone error are what cause most incidents). **The agent maps consequences** (side effects, consumers, reversibility) and re-ranks findings by execution stakes. The report merges both. Do not present the Greptile review alone as a blast-radius analysis.

## Inputs

- **Target** (optional): path(s) to the script or files about to run. If not provided, infer from the conversation (the script just written or discussed) and confirm with the user before proceeding.

## Instructions

### 1. Check prerequisites

Preflight requires a git repository (the Greptile CLI does not support Perforce):

```bash
git rev-parse --show-toplevel
```

Check whether the `greptile` command is available:

```bash
command -v greptile
greptile whoami
```

If the CLI is missing, do not install it automatically. Ask the user for permission, then show the recommended install command:

```bash
npm i -g greptile
```

If npm is unavailable, offer the shell installer fallback:

```bash
curl -fsSL "https://greptile.com/cli/install" | sh
```

If authentication is missing, run `greptile login` and wait for the user to complete the login flow.

### 2. Make the target reviewable

The CLI reviews the current branch against its base. Determine which case applies:

**a. The target is already part of the current feature branch's diff** — review directly; skip the temp-branch steps below.

**b. The target is untracked or modified, and the current branch is the default branch** (common for data work) — use a temporary branch:

```bash
ORIGINAL_BRANCH=$(git branch --show-current)
git checkout -b greptile-preflight
git add <target files only>
git commit -m "preflight: review before execution

This change is about to be RUN, not merged. Review it as code about to
execute against live systems: data touched, downstream consumers of that
data, side effects fired per row (hooks, webhooks, notifications), failure
and partial-completion behavior, and reversibility."
```

Stage **only** the target files — never `git add -A`. Do not push this branch. The commit message doubles as review framing in case the reviewer weighs commit messages.

**c. The target is already committed on the default branch with no local changes** (rare) — create the temp branch from the parent of the commit that introduced the file, then bring in the current version:

```bash
ORIGINAL_BRANCH=$(git branch --show-current)
BASE=$(git rev-list HEAD -- <target> | tail -1)
git checkout -b greptile-preflight "$BASE"^
git checkout "$ORIGINAL_BRANCH" -- <target>
git add <target> && git commit -m "preflight: review before execution"
```

### 3. Run the review

```bash
greptile review --json
```

If the review is unfinished, continue with `greptile review --resume --json`; if JSON mode is unsupported, use `greptile review --agent`.

Do not treat a network or authentication error as a passing result — report the failure and stop.

**Verify the target was actually reviewed.** The CLI holds back changed files that look like they contain secrets (API keys, connection strings — common in data scripts). Check that the target files appear in the review output; if a target was held back, tell the user the review did not cover it and suggest moving credentials to environment variables before re-running the preflight.

### 4. Map the consequences (agent work)

While or after the review runs, investigate the execution checklist yourself by reading the repo — this is not covered by the review:

- **Data touched**: which tables/collections/resources, roughly how many rows/objects (read the query filters; check for a `WHERE`-equivalent at all).
- **Per-row side effects**: do the models/functions the script calls fire hooks, webhooks, emails, notifications, cache invalidations, or audit events on save/update? Read the model definitions, not just the script.
- **Downstream consumers**: what reads the data being mutated — jobs, endpoints, views, exports?
- **Failure behavior**: what happens on partial completion? Is it resumable? Idempotent if re-run?
- **Batching and rate**: does it batch, or load/update everything at once? Any rate limits on external calls it makes?
- **Dry-run support**: is there a dry-run flag, and does it actually skip the writes?
- **Environment targeting**: how does it pick its target (env var, config, hardcoded)? Could it hit production when staging was intended?
- **Reversibility**: is there a snapshot, backup, soft-delete, or inverse operation? Or is this a one-way door?

### 5. Clean up (temp-branch cases only)

Restore the working tree exactly as found:

```bash
git reset --mixed HEAD~1
git checkout "$ORIGINAL_BRANCH"
git branch -D greptile-preflight
```

Verify the target files still exist on disk with their original content after cleanup.

### 6. Report

Merge the review findings and the consequence map, **re-ranked by execution stakes** — a logic bug in the write path outranks everything; style and merge-oriented findings (naming, docstrings, structure) are advisory at most or omitted. Do not report a confidence score; scores describe merge-readiness, not run-readiness.

Never execute the target yourself, during or after the preflight, unless the user separately asks.

## Output format

```
Preflight: backfill_emails.py
  Verdict:       FIX FIRST (2 blocking)

Blast radius:
  Writes:        users.email_normalized (~2.1M rows, no WHERE filter beyond deleted_at)
  Side effects:  User.save() fires `user.updated` webhook per row (app/models/user.py:88)
  Consumers:     digest job, /api/users serializer, warehouse sync
  Reversibility: column overwrite, no snapshot — not recoverable

Blocking:
  1. backfill_emails.py:41 — cursor never advances past page 1; rows reprocessed indefinitely
  2. app/models/user.py:88 — save() in the loop will emit ~2.1M webhooks; use bulk update or suppress hooks

Advisory:
  - No dry-run flag; consider --dry-run before the real run
  - Not resumable; a crash at row 1.4M means starting over
```

If nothing blocks:

```
Preflight: backfill_emails.py
  Verdict:       OK TO RUN

Blast radius:
  Writes:        users.email_normalized (~2.1M rows)
  Side effects:  none found — script uses bulk_update, bypassing save hooks
  Consumers:     digest job, /api/users serializer, warehouse sync
  Reversibility: previous values copied to email_raw first — recoverable

Advisory:
  - Consider running against staging first; env comes from DATABASE_URL
```
