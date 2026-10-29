#!/usr/bin/env bash
# Usage: scripts/ci-wait.sh [branch] [outdir]
# Waits for the GitHub Actions run of the current HEAD commit on <branch>, then prints the
# result and copies that branch's renders + logs from the ci-output branch into <outdir>.
set -u
BR="${1:-$(git rev-parse --abbrev-ref HEAD)}"
OUTDIR="${2:-/tmp/ci-$(echo "$BR" | tr '/' '-')}"
SHA=$(git rev-parse HEAD)
REPO=Bogadin/cat-island
gh_() { env -u GH_TOKEN gh "$@"; }
echo "Waiting for CI of $SHA on $BR ..."
RUN=""
for i in $(seq 1 60); do
  RUN=$(gh_ run list -R $REPO --branch "$BR" --limit 10 --json databaseId,headSha -q ".[] | select(.headSha==\"$SHA\") | .databaseId" 2>/dev/null | head -1)
  [ -n "$RUN" ] && break
  sleep 10
done
[ -z "$RUN" ] && { echo "No run found for $SHA"; exit 2; }
echo "Run $RUN: https://github.com/$REPO/actions/runs/$RUN"
while true; do
  ST=$(gh_ run view "$RUN" -R $REPO --json status,conclusion -q '.status+" "+.conclusion' 2>/dev/null)
  case "$ST" in completed*) break;; esac
  sleep 20
done
echo "Run finished: $ST"
sleep 20  # let the ci-output push land
D="branches/$(echo "$BR" | tr '/' '-')"
for i in 1 2 3 4 5 6; do
  git fetch -q origin ci-output:refs/remotes/origin/ci-output 2>/dev/null
  if git show "origin/ci-output:$D/logs/status.txt" 2>/dev/null | grep -q "$SHA"; then break; fi
  sleep 15
done
rm -rf "$OUTDIR" && mkdir -p "$OUTDIR"
git archive origin/ci-output "$D" 2>/dev/null | tar x -C "$OUTDIR" --strip-components=2 2>/dev/null
echo "----- status"; cat "$OUTDIR/logs/status.txt" 2>/dev/null
echo "----- compile errors (device build)"; head -60 "$OUTDIR/logs/ipa-errors.txt" 2>/dev/null
echo "----- test/compile errors (simulator)"; head -80 "$OUTDIR/logs/test-errors.txt" 2>/dev/null
echo "----- test summary"; grep -E "Executed|\*\* TEST" "$OUTDIR/logs/test-digest.txt" 2>/dev/null | tail -5
echo "----- failed tests"; grep -E "failed|error:" "$OUTDIR/logs/test-digest.txt" 2>/dev/null | head -20
echo "----- renders in $OUTDIR/renders:"; (cd "$OUTDIR/renders" 2>/dev/null && find . -name '*.png' | sort | head -80)
