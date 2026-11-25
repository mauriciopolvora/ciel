#!/usr/bin/env bash
set -euo pipefail

usage="usage: scripts/cleanup-branches.sh [--delete] [remote]
Lists each branch on the remote as merged, orphaned, open or unmerged.
With --delete, deletes the merged and orphaned branches. It never deletes an unmerged branch or one with an open PR."

delete=0
remote=origin
for arg in "$@"; do
  case $arg in
    --delete) delete=1 ;;
    -h | --help) echo "$usage"; exit 0 ;;
    -*) echo "$usage" >&2; exit 64 ;;
    *) remote=$arg ;;
  esac
done

limit=1000
url=$(git remote get-url "$remote")
if [ "$(git remote get-url --push --all "$remote")" != "$url" ]; then
  echo "cleanup-branches: $remote pushes to a different URL than it fetches from, or to more than one, so a delete could hit a different repo" >&2
  exit 1
fi
repo=$(gh repo view "$url" --json url --jq .url)
repo=${repo#https://}
default=$(gh repo view "$repo" --json defaultBranchRef --jq .defaultBranchRef.name)
git fetch -q --prune "$remote"
base=refs/remotes/$remote/$default
git rev-parse -q --verify "$base^{commit}" >/dev/null || { echo "cleanup-branches: $base does not exist, so nothing can be checked against it" >&2; exit 1; }
open=$(gh pr list --repo "$repo" --state open --limit "$limit" --json headRefName --jq '.[].headRefName')
newlines=${open//[!$'\n']/}
if [ -n "$open" ] && [ $((${#newlines} + 1)) -ge "$limit" ]; then
  echo "cleanup-branches: $repo has $limit or more open PRs, so this script cannot see them all" >&2
  exit 1
fi
merged=$(gh pr list --repo "$repo" --state merged --limit "$limit" --json headRefName,headRefOid,isCrossRepository --jq '.[] | select(.isCrossRepository | not) | "\(.headRefName) \(.headRefOid)"')

has_line() { [[ $'\n'$2$'\n' == *$'\n'"$1"$'\n'* ]]; }

classify() {
  local branch=$1 tip=$2 cherry merges
  if has_line "$branch" "$open"; then
    echo open
  elif has_line "$branch $tip" "$merged" || git merge-base --is-ancestor "$tip" "$base"; then
    echo merged
  else
    cherry=$(git cherry "$base" "$tip") || return 1
    merges=$(git rev-list --merges "$base..$tip") || return 1
    if [ -n "$merges" ] || [[ $'\n'$cherry == *$'\n+'* ]]; then echo unmerged; else echo orphaned; fi
  fi
}

doomed=()
while read -r branch; do
  [ "$branch" = "$default" ] && continue
  tip=$(git rev-parse "refs/remotes/$remote/$branch")
  kind=$(classify "$branch" "$tip")
  echo "$kind $branch $tip"
  [[ $kind = merged || $kind = orphaned ]] && doomed+=("$branch $tip")
done < <(git for-each-ref --format='%(refname:lstrip=3)' "refs/remotes/$remote" | grep -vx HEAD)

[ "$delete" = 1 ] || exit 0
status=0
for entry in ${doomed[@]+"${doomed[@]}"}; do
  branch=${entry% *}
  tip=${entry##* }
  if git push -q --force-with-lease="refs/heads/$branch:$tip" "$remote" ":refs/heads/$branch"; then
    echo "deleted $branch"
  else
    echo "kept $branch: it is no longer at $tip on $remote" >&2
    status=1
  fi
done
git fetch -q --prune "$remote"
exit $status
