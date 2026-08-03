# Greptile skills

Skills for reviewing code with Greptile.

## Skills

- `review-changes` — Review local changes.
- `address-pr-feedback` — Address review feedback.
- `greploop` — Fix changes until Greptile gives them a 5/5 review.

## Install

```bash
npx skills add greptile-projects/skills
```

For Claude Code:

```bash
claude plugin marketplace add greptile-projects/skills
claude plugin install greptile@greptile
```

For Codex:

```bash
codex plugin marketplace add greptile-projects/skills
codex plugin add greptile@greptile
```

## Pre-push hook

A git hook that blocks pushes unless `greptile review` scores 5/5. Results are
saved to `.git/greptile/last-review.json`.

```bash
sh hooks/install.sh --repo /path/to/your/repo
```

Bypass with `git push --no-verify` or `GREPTILE_SKIP_REVIEW=1 git push`.
