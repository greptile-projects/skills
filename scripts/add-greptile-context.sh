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

Greptile is an AI code reviewer that reviews changes with full-codebase
context and returns findings as inline comments with a 1-5 confidence
score. The `greptile` CLI reviews the local branch before anything is
pushed; run `greptile review --json` for structured output.

**Workflow:** after each *completed* task (not after every edit), run a
Greptile review of the changes and return the findings to the user for
triage. Do not silently fix or dismiss findings — the user decides which
comments to address. If `greptile` is not installed or not authenticated
(`greptile whoami`), say so instead of skipping the review quietly.
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
