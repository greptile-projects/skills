# Greploop — Perforce

The Greptile CLI does not support Perforce. On Perforce, greploop uses the hosted shelve-review loop below instead of the CLI-first flow in SKILL.md.

## Identify the CL

```bash
# List pending changelists for current user/client
p4 changes -s pending -u $P4USER -c $P4CLIENT

# Describe a specific CL
p4 describe -s <CL_NUMBER>
```

Ensure the correct workspace (`p4 client`) is set before proceeding.

Key fields: changelist number, `P4CLIENT`, shelved files.

## Loop

Repeat the following cycle. **Max 5 iterations** to avoid runaway loops.

If a prior Greptile review already exists on the CL, fetch its comments (step B) and fix actionable ones (step D) before triggering the first review — don't spend a review cycle on feedback that is already known.

### A. Trigger Greptile review

Push/shelve the latest changes (if any):

```bash
# Re-shelve to update the shelved files for review
p4 shelve -f -c <CL_NUMBER>
```

Wait for checks to start after push/shelve:

```bash
sleep 5
```

Perforce does not have native check runs. If Greptile is integrated via a webhook triggered on `p4 shelve`, wait for it to process. Check your Greptile installation's webhook endpoint or dashboard for the review status. Poll by re-fetching the Greptile review comment on the CL until a score appears.

### B. Fetch Greptile review results

Greptile may surface its score in several places — check **all** of the relevant sources:

**1. CL description:**
```bash
p4 describe -s <CL_NUMBER>
```
Check the description field for a Greptile-appended score block.

**2. CL comments / review notes:**
If your installation uses a review tool such as Helix Swarm, fetch comments via its API.

Example (Swarm API):
GET /api/v11/comments?topic=reviews/<REVIEW_ID>

Response fields of interest typically include:
- user (author username)
- body (comment text)
- flags/state indicating whether the comment is resolved

Filter to comments authored by the Greptile bot:
- Prefer exact username match if known
- Otherwise, use a heuristic where the author name contains "greptile" (case-insensitive)

Parse the text for:
- **Confidence score**: a pattern like `3/5` or `5/5` (or `Confidence: 3/5`).
- **Comment count**: Number of inline review comments noted in the summary.

Use whichever source has the **most recently updated** score.

Also fetch all unresolved inline comments. If using Swarm:

# Fetch inline diff comments for the review associated with the CL
GET /api/v11/comments?topic=reviews/<REVIEW_ID>

Filter to comments from the Greptile bot user that have not been marked as resolved/addressed.

### C. Check exit conditions

Stop the loop if **any** of these are true:

- Confidence score is **5/5** AND there are **zero unresolved comments**
- Max iterations reached (report current state)

### D. Fix actionable comments

For each unresolved Greptile comment:

1. Read the file and understand the comment in context.
2. Determine if it's actionable (code change needed) or informational.
3. If actionable, make the fix.
4. If informational or a false positive, note it but still resolve the thread.

### E. Re-shelve

```bash
# Stage changes back into the CL and re-shelve for the next review round
p4 shelve -f -c <CL_NUMBER>
```

Wait for checks to start after push/shelve:

```bash
sleep 5
```

Then go back to step **A**.

## Report

After exiting the loop, summarize:

| Field              | Value      |
| ------------------ | ---------- |
| Platform           | Perforce   |
| Changelist         | N          |
| Iterations         | N          |
| Final confidence   | X/5        |
| Comments resolved  | N          |
| Remaining comments | N (if any) |

If the loop exited due to max iterations, list any remaining unresolved comments and suggest next steps.

**Example:**

```
Greploop complete.
  Platform:      Perforce
  Changelist:    12345
  Iterations:    3
  Confidence:    5/5
  Resolved:      9 comments
  Remaining:     0
```
