---
name: greploop
description: Iteratively fixes a change until Greptile gives a 5/5 confidence score with zero unresolved comments. On GitHub and GitLab it iterates locally with the Greptile CLI, then pushes and syncs the PR/MR once at the end; on Perforce it uses the hosted shelve-review loop. Use when the user wants to fully optimize a change against Greptile's code review standards.
---

# Greploop

Iteratively fix a change until Greptile gives a perfect review: 5/5 confidence, zero unresolved comments.

Reviews run locally through the Greptile CLI — the same engine as hosted PR reviews — so iteration is fast and produces no PR noise. If a PR/MR exists, it is updated **once** at the end: one push, one hosted review, threads resolved.

## Inputs

- **PR/MR/CL number** (optional): If not provided, detect the PR/MR for the current branch, or the default pending changelist for p4.

## Instructions

### 0. Detect platform

First check for Perforce, then fall back to git remote detection:

```bash
# Check for Perforce environment
if p4 info >/dev/null 2>&1; then
  VCS="perforce"
else
  REMOTE_URL=$(git remote get-url origin)
  if echo "$REMOTE_URL" | grep -qi "gitlab"; then
    VCS="gitlab"
  else
    VCS="github"
  fi
fi
```

For self-hosted GitLab instances whose hostname doesn't contain "gitlab", the user can override by passing `--vcs gitlab` as an input. For Perforce, pass `--vcs perforce`.

**Perforce:** the Greptile CLI does not support Perforce. Follow [references/perforce.md](references/perforce.md) — the hosted shelve-review loop — instead of the steps below. None of the remaining steps in this file apply.

### 1. Check prerequisites

**The CLI must be installed and authenticated:**

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

If authentication is missing, run `greptile login` and wait for the user to finish.

**The current branch must not be the default branch.** The CLI reviews the current branch against its base, so it cannot review from `main`/`master`/the repository default:

```bash
CURRENT_BRANCH=$(git branch --show-current)
DEFAULT_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
```

If the current branch is the default branch, stop and tell the user to switch to (or create) a feature branch containing their changes.

### 2. Identify the PR/MR and announce the mode

**GitHub:**
```bash
gh pr view --json number,headRefName -q '{number: .number, branch: .headRefName}'
```

**GitLab:**
```bash
glab mr view --output json | jq '{iid: .iid, branch: .source_branch}'
```

- **PR/MR exists** → run the full flow. Tell the user up front: iteration happens locally, and the PR/MR will be updated once at the end (one push, threads resolved).
- **No PR/MR** → run the local loop (step 3) only, then report. Do not commit, push, or open a PR/MR unless the user separately asks. Only a lookup that *confirms* no PR/MR exists counts — do not treat a missing tool, authentication failure, or network error as confirmation.

### 3. Local review loop

Repeat until clean. **Max 5 iterations** to avoid runaway loops.

Do not fetch or act on prior Greptile comments from the PR/MR — they may be outdated or already dismissed, and there is no reliable way to tell. Start with a fresh review; the loop is simply review → fix → review.

```bash
greptile review --json
```

If the review is unfinished, continue with `greptile review --resume --json`; if JSON mode is unsupported, use `greptile review --agent`.

Each iteration:

1. Run the review.
2. If it reports **5/5 with no remaining findings** (or, if the CLI output includes no confidence score, **zero remaining findings**), exit the loop.
3. Apply actionable findings; note informational ones and false positives.
4. Run relevant validation (tests, typecheck, lint — whatever the repo uses).
5. Repeat.

If there is no PR/MR, stop here and go to step 5. Do not commit or push.

### 4. Deliver to the PR/MR

One round, not a loop.

**Commit and push once.** Stage only the files modified while addressing findings — do not use `git add -A`, which would sweep in unrelated working-tree changes:

```bash
git add <files modified in step 3>
git commit -m "resolve greptile comments"
git push
```

**Wait for the hosted review.** Most installations review automatically on push, so do not post a trigger comment immediately.

**GitHub** — poll for the Greptile check run on the new head:

```bash
HEAD_SHA=$(gh pr view <PR_NUMBER> --json headRefOid -q .headRefOid)

while true; do
  GREPTILE_CHECK=$(gh api "repos/{owner}/{repo}/commits/$HEAD_SHA/check-runs" \
    --jq '.check_runs[] | select(.name | test("greptile"; "i"))' 2>/dev/null)

  if [ -z "$GREPTILE_CHECK" ]; then
    echo "Waiting for Greptile check to appear..."
    sleep 5
    continue
  fi

  STATUS=$(echo "$GREPTILE_CHECK" | jq -r '.status // "completed"')

  if [ "$STATUS" = "completed" ]; then
    break
  fi

  echo "Waiting for Greptile... (status: $STATUS)"
  sleep 10
done
```

If no Greptile check appears within ~60 seconds, the installation likely doesn't auto-review — post `@greptile review` as a PR comment, then resume polling:

```bash
gh pr comment <PR_NUMBER> --body "@greptile review"
```

**GitLab** — poll for the Greptile pipeline job on the new head (see [GitLab API reference](references/gitlab-api.md)); if no pipeline appears within ~60 seconds, post the trigger:

```bash
glab mr note <MR_IID> --message "@greptile review"
```

**Fetch the hosted review results.** Greptile may surface its score in several places — check **all** of the relevant sources:

**GitHub:**

**1. PR description (body):**
```bash
gh pr view <PR_NUMBER> --json body -q '.body'
```

**2. General PR comments (issue comments):**
```bash
gh api --paginate "repos/{owner}/{repo}/issues/<PR_NUMBER>/comments?per_page=100"
```

Filter for Greptile-authored comments and use the body from the most recently updated comment (`updated_at`), not the most recently created comment. Greptile may edit the same general PR comment on each review cycle; parse the current body, including the "Prompt to fix all with AI" section, before deciding there are no remaining issues.

**3. PR reviews:**
```bash
gh api repos/{owner}/{repo}/pulls/<PR_NUMBER>/reviews
```

Look for the most recent entry from `greptile-apps[bot]` or `greptile-apps-staging[bot]`.

**GitLab:**

**1. MR description (body):**
```bash
glab mr view <MR_IID> --output json | jq -r '.description'
```

**2. MR notes (comments):**
```bash
glab api "projects/:fullpath/merge_requests/<MR_IID>/notes"
```

Filter for notes from the Greptile bot user (check the `author.username` field — the exact username may vary per installation; verify on first run).

For both platforms, parse the text for:
- **Confidence score**: a pattern like `3/5` or `5/5` (or `Confidence: 3/5`).
- **Comment count**: Number of inline review comments noted in the summary.

Use whichever source has the **most recently updated** score. For GitHub, prefer `updated_at` from issue comments when comparing an edited Greptile summary against older review entries.

Also fetch all unresolved inline comments:

**GitHub:**
```bash
gh api repos/{owner}/{repo}/pulls/<PR_NUMBER>/comments
```

**GitLab:**
```bash
glab api "projects/:fullpath/merge_requests/<MR_IID>/discussions"
```

Filter to `DiffNote` type discussions (`notes[0].type == "DiffNote"`) from Greptile that are on the latest commit and not yet resolved (`"resolved": false`).

Because the CLI and the hosted review use the same engine, the hosted round should confirm 5/5 with no new findings. If new findings do appear, treat them as input and return to step 3 — they count against the same 5-iteration cap.

**Resolve addressed threads.**

**GitHub** — fetch unresolved review threads and resolve all that have been addressed (see [GraphQL reference](references/graphql-queries.md)):

```bash
gh api graphql -f query='
query($cursor: String) {
  repository(owner: "OWNER", name: "REPO") {
    pullRequest(number: PR_NUMBER) {
      reviewThreads(first: 100, after: $cursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          isResolved
          comments(first: 1) {
            nodes { body path author { login } }
          }
        }
      }
    }
  }
}'
```

Resolve addressed threads:

```bash
gh api graphql -f query='
mutation {
  t1: resolveReviewThread(input: {threadId: "ID1"}) { thread { isResolved } }
  t2: resolveReviewThread(input: {threadId: "ID2"}) { thread { isResolved } }
}'
```

**GitLab** — fetch unresolved discussions and resolve each one (see [GitLab API reference](references/gitlab-api.md)):

```bash
glab api "projects/:fullpath/merge_requests/<MR_IID>/discussions?per_page=100"
```

Filter for `"resolved": false` discussions. Then resolve each by its `id`:

```bash
glab api --method PUT \
  "projects/:fullpath/merge_requests/<MR_IID>/discussions/<DISCUSSION_ID>" \
  --field resolved=true
```

Repeat for each unresolved discussion ID. (GitLab has no batch resolution — loop through each one.)

**Post a summary comment.** One comment with the resolved count — this is where the count lives, not in the commit message:

**GitHub:**
```bash
gh pr comment <PR_NUMBER> --body "greploop: resolved <N> comments"
```

**GitLab:**
```bash
glab mr note <MR_IID> --message "greploop: resolved <N> comments"
```

### 5. Report

After finishing, summarize:

| Field              | Value      |
| ------------------ | ---------- |
| Platform           | GitHub / GitLab |
| Local iterations   | N          |
| Final confidence   | X/5        |
| Comments resolved  | N          |
| Remaining comments | N (if any) |

If the loop exited due to max iterations, list any remaining unresolved findings and suggest next steps.

For Perforce, see the report format in [references/perforce.md](references/perforce.md).

## Output format

```
Greploop complete.
  Platform:         GitHub
  Local iterations: 2
  Confidence:       5/5
  Resolved:         7 comments
  Remaining:        0
```

If not fully resolved:

```
Greploop stopped after 5 iterations.
  Platform:         GitLab
  Local iterations: 5
  Confidence:       4/5
  Resolved:         12 comments
  Remaining:        2

Remaining issues:
  - src/auth.ts:45 — "Consider rate limiting this endpoint"
  - src/db.ts:112 — "Missing index on user_id column"
```
