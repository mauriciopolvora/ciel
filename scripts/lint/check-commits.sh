#!/usr/bin/env bash
set -euo pipefail

dependabot='49699333+dependabot[bot]@users.noreply.github.com'
commits=$(git rev-list "$@")
bad=0
for commit in $commits; do
  trailers=$(git -c trailer.separators=: log -1 --format='%(trailers:only,unfold)' "$commit")
  coauthors=$(git log -1 --format=%B "$commit" | grep -i '^co-authored-by:' || true)
  if [ "$(git log -1 --format=%ae "$commit")" = "$dependabot" ]; then
    trailers=$(printf '%s\n' "$trailers" | grep -vxF 'Signed-off-by: dependabot[bot] <support@github.com>' || true)
  fi
  found=$(printf '%s\n%s\n' "$trailers" "$coauthors" | grep -v '^$' | sort -u || true)
  [ -z "$found" ] && continue
  echo "check-commits: $(git log -1 --format='%h %s' "$commit") has trailer or Co-authored-by lines:" >&2
  printf '%s\n' "$found" | sed 's/^/  /' >&2
  bad=1
done
if [ "$bad" = 1 ]; then
  echo "check-commits: reword each commit above without its trailer lines." >&2
  exit 1
fi
