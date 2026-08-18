#!/bin/sh
set -eu

# The test script doubles as the fake greptile executable through a symlink
# created below.
case ${0##*/} in
  greptile)
    printf '%s\n' "$*" >>"$MOCK_CALLS"
    if [ "${1:-}" = review ] && [ "${2:-}" = status ]; then
      case "$MOCK_MODE" in
        completed)
          printf '{"commit":"%s","headSha":"%s","confidence":5,"commentCount":0,"runId":"run-1"}\n' \
            "$MOCK_SHA" "$MOCK_SHA"
          exit 0
          ;;
        low-confidence)
          printf '{"commit":"%s","headSha":"%s","confidence":1,"commentCount":2,"runId":"run-low"}\n' \
            "$MOCK_SHA" "$MOCK_SHA"
          exit 0
          ;;
        wrong-commit)
          printf '{"commit":"%040d","headSha":"%040d","confidence":5,"commentCount":0,"runId":"run-2"}\n' 0 0
          exit 0
          ;;
        in-flight)
          # Running until the hook resumes it, completed afterwards.
          if [ ! -e "$MOCK_STATE" ]; then
            exit 3
          fi
          printf '{"commit":"%s","headSha":"%s","confidence":5,"commentCount":0,"runId":"run-3"}\n' \
            "$MOCK_SHA" "$MOCK_SHA"
          exit 0
          ;;
        new-review)
          # No review until the hook starts one, completed afterwards.
          if [ ! -e "$MOCK_STATE" ]; then
            exit 1
          fi
          printf '{"commit":"%s","headSha":"%s","confidence":5,"commentCount":0,"runId":"run-4"}\n' \
            "$MOCK_SHA" "$MOCK_SHA"
          exit 0
          ;;
        review-fails) exit 3 ;;
        status-hangs)
          while :; do sleep 1; done
          ;;
        resume-hangs) exit 3 ;;
      esac
    fi
    if [ "${1:-}" = review ]; then
      case "$MOCK_MODE" in
        in-flight|new-review)
          : >"$MOCK_STATE"
          exit 0
          ;;
        resume-hangs)
          while :; do sleep 1; done
          ;;
      esac
    fi
    exit 1
    ;;
esac

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
hook="$script_dir/pre-push"
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/greptile-pre-push-test.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT INT TERM

mkdir -p "$test_dir/bin" "$test_dir/repo" "$test_dir/tmp"
ln -s "$script_dir/test-pre-push.sh" "$test_dir/bin/greptile"

git -C "$test_dir/repo" init -q
git -C "$test_dir/repo" config user.name Test
git -C "$test_dir/repo" config user.email test@example.com
git -C "$test_dir/repo" commit --allow-empty -qm initial
branch=$(git -C "$test_dir/repo" branch --show-current)
url=https://example.com/greptile/test.git
git -C "$test_dir/repo" remote add origin "$url"
git -C "$test_dir/repo" config "branch.$branch.remote" origin
sha=$(git -C "$test_dir/repo" rev-parse HEAD)
calls="$test_dir/calls"
state="$test_dir/state"
input="refs/heads/$branch $sha refs/heads/$branch 0000000000000000000000000000000000000000"

run_hook() {
  _mode=$1
  _url=$2
  : >"$calls"
  rm -f "$state"
  printf '%s\n' "$input" | (
    cd "$test_dir/repo"
    PATH="$test_dir/bin:$PATH" TMPDIR="$test_dir/tmp" \
      MOCK_CALLS="$calls" MOCK_MODE="$_mode" MOCK_SHA="$sha" MOCK_STATE="$state" \
      GREPTILE_AUTO_REVIEW=1 \
      "$hook" origin "$_url"
  )
}

run_hook completed "$url" >/dev/null 2>&1

# Non-interactive callers cannot accidentally accept a low-confidence review.
if run_hook low-confidence "$url" >"$test_dir/output" 2>&1; then
  echo "expected a low-confidence non-interactive push to be blocked" >&2
  exit 1
fi
grep -q 'review below required confidence' "$test_dir/output"
grep -q 'push blocked' "$test_dir/output"

# The explicit environment bypass still skips the gate entirely.
if ! (GREPTILE_SKIP_REVIEW=1 run_hook low-confidence "$url") >"$test_dir/output" 2>&1; then
  echo "expected GREPTILE_SKIP_REVIEW=1 to bypass the review gate" >&2
  exit 1
fi
grep -q 'GREPTILE_SKIP_REVIEW=1 set' "$test_dir/output"
test ! -s "$calls"

if run_hook wrong-commit "$url" >"$test_dir/output" 2>&1; then
  echo "expected a mismatched status commit to block the push" >&2
  exit 1
fi
grep -q 'review status was for a different commit' "$test_dir/output"

run_hook new-review "$url" >/dev/null 2>&1
grep -q '^review --json$' "$calls"
test "$(grep -c '^review status ' "$calls")" -eq 2

run_hook in-flight "$url" >/dev/null 2>&1
grep -q '^review --resume --json$' "$calls"
test "$(grep -c '^review status ' "$calls")" -eq 2

if run_hook review-fails "$url" >"$test_dir/output" 2>&1; then
  echo "expected a failed review to block the push" >&2
  exit 1
fi
grep -q 'review failed' "$test_dir/output"

if GREPTILE_REVIEW_TIMEOUT_SECONDS=1 run_hook status-hangs "$url" >"$test_dir/output" 2>&1; then
  echo "expected a hanging status check to time out" >&2
  exit 1
fi
grep -q 'review status did not finish within 1 seconds' "$test_dir/output"

if GREPTILE_REVIEW_TIMEOUT_SECONDS=1 run_hook resume-hangs "$url" >"$test_dir/output" 2>&1; then
  echo "expected a hanging resumed review to time out" >&2
  exit 1
fi
grep -q 'review did not finish within 1 seconds' "$test_dir/output"

if run_hook completed https://example.com/greptile/other.git >"$test_dir/output" 2>&1; then
  echo "expected a different push remote to block the push" >&2
  exit 1
fi
grep -q "push target differs from Greptile's review remote" "$test_dir/output"
test ! -s "$calls"

# git passes the hook the remote's push URL, so a configured pushurl must
# match even though it differs from the fetch URL.
pushurl=https://example.com/greptile/push.git
git -C "$test_dir/repo" config remote.origin.pushurl "$pushurl"
run_hook completed "$pushurl" >/dev/null 2>&1
git -C "$test_dir/repo" config --unset remote.origin.pushurl

# A multi-URL remote runs the hook once per URL; each must pass the guard.
second_url=https://example.com/greptile/mirror.git
git -C "$test_dir/repo" remote set-url --add origin "$second_url"
run_hook completed "$second_url" >/dev/null 2>&1
git -C "$test_dir/repo" remote set-url --delete origin "$second_url"

# A chained pre-push that does not forward hook arguments leaves the push
# URL empty; the guard has nothing to compare and must not block.
run_hook completed "" >/dev/null 2>&1

echo "pre-push hook tests passed"
