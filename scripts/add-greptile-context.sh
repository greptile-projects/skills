#!/bin/sh
# Add a Greptile section to a repo's agent instruction files.
# Writes AGENTS.md (created if missing) and CLAUDE.md (only if it exists).
# Idempotent: re-running replaces the marked section instead of duplicating it.
# Usage: add-greptile-context.sh [<repo-path>]
set -eu

repo=${1:-.}
[ -d "$repo" ] || { printf 'error: no such directory: %s\n' "$repo" >&2; exit 1; }

begin='<!-- greptile:begin -->'
end='<!-- greptile:end -->'

section=$(cat <<'EOF'
<!-- greptile:begin -->
## Greptile

This repo uses Greptile, an AI code reviewer with full-codebase context.
The `greptile` CLI reviews the local branch before pushing.

After completing a task that changes code (not after every edit):

1. Commit the changes from this task. If you are on main, create a
   temporary branch (e.g. `greptile-review/<task>`) and commit there
   instead of main.
2. Run `greptile review` on the committed changes. Use
   `greptile review --json` when summarizing findings, so confidence
   scores and file locations are preserved.
3. Report every finding and the overall confidence score to the user
   for triage. Never silently fix or dismiss a finding; the user
   decides what gets addressed.
4. If you created a temporary branch, leave it in place and tell the
   user its name; do not merge it to main yourself.

If `greptile` is not installed or not logged in (`greptile whoami`),
tell the user rather than skipping the review.
<!-- greptile:end -->
EOF
)

write_section() {
  file=$1
  if [ -f "$file" ] && grep -qF "$begin" "$file"; then
    # Replace the existing marked section in place.
    awk -v b="$begin" -v e="$end" '
      $0 == b { skip = 1 }
      !skip { print }
      $0 == e { skip = 0 }
    ' "$file" >"$file.tmp"
    printf '%s\n' "$section" >>"$file.tmp"
    mv "$file.tmp" "$file"
  else
    [ ! -f "$file" ] || [ -z "$(tail -c 1 "$file")" ] || printf '\n' >>"$file"
    printf '%s\n' "$section" >>"$file"
  fi
  printf 'updated %s\n' "$file"
}

write_section "$repo/AGENTS.md"
[ -f "$repo/CLAUDE.md" ] && write_section "$repo/CLAUDE.md"

exit 0
