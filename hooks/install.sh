#!/bin/sh
# Greptile pre-push hook installer.
# Usage: install.sh [--repo <path>] [--min-confidence <1-5>]
set -eu

usage() {
  cat >&2 <<'EOF'
Install the Greptile pre-push review hook into a git repository.

Usage: install.sh [options]
  --repo <path>            Target repository (default: current directory)
  --min-confidence <1-5>   Block pushes below this confidence score (default: 5)
  -h, --help               Show this help

The hook path respects core.hooksPath. An existing non-greptile pre-push hook
is never overwritten (exit 2); greptile-installed hooks are upgraded in place.
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit "${2:-1}"; }

repo=.
min_confidence=5
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) [ $# -ge 2 ] || die "--repo requires a value" 2; repo=$2; shift 2 ;;
    --min-confidence)
      [ $# -ge 2 ] || die "--min-confidence requires a value" 2
      case "$2" in
        [1-5]) min_confidence=$2 ;;
        *) die "--min-confidence must be 1-5, got '$2'" 2 ;;
      esac
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "unknown argument: $1" 2 ;;
  esac
done

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
src="$script_dir/pre-push"
[ -f "$src" ] || die "cannot find the pre-push hook next to this installer ($src)"

git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 \
  || die "'$repo' is not a git repository"

dest=$(git -C "$repo" rev-parse --path-format=absolute --git-path hooks/pre-push 2>/dev/null) \
  || dest="$(git -C "$repo" rev-parse --absolute-git-dir)/hooks/pre-push"
mkdir -p "$(dirname "$dest")"

tmp="$dest.greptile-tmp.$$"
trap 'rm -f "$tmp"' EXIT INT TERM
sed "s/^MIN_CONFIDENCE=.*/MIN_CONFIDENCE=$min_confidence # baked by installer; runtime override: GREPTILE_MIN_CONFIDENCE=<1-5>/" "$src" >"$tmp"
chmod 0755 "$tmp"

action=installed
if [ -e "$dest" ]; then
  if cmp -s "$tmp" "$dest"; then
    printf 'Greptile pre-push hook already installed (up to date): %s\n' "$dest" >&2
    exit 0
  elif grep -q '^# greptile-pre-push-hook v' "$dest"; then
    action=upgraded
  else
    hint=""
    case "$dest" in *".husky"*) hint=" (this looks like a husky hook)" ;; esac
    printf 'error: %s already exists and is not a greptile hook%s.\n' "$dest" "$hint" >&2
    printf '  Refusing to overwrite. To chain hooks, call the greptile hook from your\n' >&2
    printf '  existing pre-push, or move it aside and re-run this installer.\n' >&2
    exit 2
  fi
fi
mv "$tmp" "$dest"
chmod 0755 "$dest"
trap - EXIT INT TERM

GREEN=''; BOLD=''; DIM=''; RESET=''
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != "dumb" ]; then
  case "${COLORTERM:-}" in
    *truecolor*|*24bit*) GREEN='\033[38;2;40;233;159m' ;;
    *)                   GREEN='\033[92m' ;;
  esac
  BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
fi

{
  printf '%b\n' "${GREEN}${BOLD}Greptile pre-push hook $action.${RESET}"
  printf '  %-18s%s\n' "Hook:" "$dest"
  printf '  %-18s%s\n' "Blocks below:" "$min_confidence/5 confidence"
  printf '  %-18s%s\n' "Results:" "<repo>/.git/greptile/last-review.json"
  printf '%b\n' "${DIM}  Bypass a push: git push --no-verify   (or GREPTILE_SKIP_REVIEW=1 git push)${RESET}"
} >&2
