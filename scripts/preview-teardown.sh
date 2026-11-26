#!/usr/bin/env bash
set -euo pipefail

usage="usage: scripts/preview-teardown.sh <pr number>
Deletes the previews and the head branch of a closed PR. Does nothing when the PR is open.
Needs GH_TOKEN and GITHUB_REPOSITORY. PREVIEW_PROVIDERS lists the preview providers of the repo, from: vercel convex.
PREVIEW_KEEP_BRANCHES lists the long-lived branches (for example staging) that keep their previews and stay.
It deletes the Vercel previews made while the PR was open, and those of a PR commit made up to 2 minutes after the
close (a push that reaches Vercel late). Convex has no commit sha and makes its preview during the build, so it deletes
each Convex preview of the branch made up to 45 minutes (the longest Vercel build) after the close.
vercel needs VERCEL_TOKEN, VERCEL_PROJECT_ID and VERCEL_TEAM_ID. convex needs CONVEX_TEAM_TOKEN and CONVEX_PROJECT_ID."

[ $# -eq 1 ] && [[ $1 =~ ^[0-9]+$ ]] || { echo "$usage" >&2; exit 64; }
pr=$1
repo=${GITHUB_REPOSITORY:?set GITHUB_REPOSITORY to owner/name}
remote=${PREVIEW_TEARDOWN_REMOTE:-https://github.com/$repo.git}
vercel_api=${VERCEL_API:-https://api.vercel.com}
convex_api=${CONVEX_API:-https://api.convex.dev}

bearer() {
  printf 'Authorization: Bearer %s\n' "${!1}"
}

need() {
  local name
  for name in "$@"; do
    [ -n "${!name:-}" ] || { echo "preview-teardown: $name is not set, so the previews of PR #$pr stay up" >&2; exit 1; }
  done
}

counted() {
  labels+=("$1")
  deleted[$1]=0
}

target() {
  targets+=("$1"$'\x1f'"$2"$'\x1f'"$3"$'\x1f'"$4"$'\x1f'"$5")
}

list_vercel() {
  need VERCEL_TOKEN VERCEL_PROJECT_ID VERCEL_TEAM_ID
  local page ids id until=
  counted Vercel
  while :; do
    page=$(curl -fsS -m 30 -H @<(bearer VERCEL_TOKEN) -G "$vercel_api/v6/deployments" \
      --data-urlencode "projectId=$VERCEL_PROJECT_ID" --data-urlencode "teamId=$VERCEL_TEAM_ID" \
      --data-urlencode target=preview --data-urlencode limit=100 --data-urlencode "branch=$branch" \
      ${until:+--data-urlencode "until=$until"})
    ids=$(jq -r --arg owner "${repo%%/*}" --arg name "${repo#*/}" --arg branch "$branch" --arg commits "$commits" --argjson opened "$opened_ms" --argjson closed "$closed_ms" --argjson grace "$grace_ms" '($commits | split("\n")) as $mine | .deployments[] | select(.meta.githubCommitOrg == $owner and .meta.githubCommitRepo == $name and .meta.githubCommitRef == $branch and .target != "production") | if (.created | type) == "number" then select((.created >= $opened and .created <= $closed) or (.created <= $grace and (.meta.githubCommitSha | IN($mine[])))) | .uid else error("Vercel gave no number for created") end' <<<"$page")
    for id in $ids; do
      target Vercel VERCEL_TOKEN DELETE "$vercel_api/v13/deployments/$id?teamId=$VERCEL_TEAM_ID" "$id"
    done
    until=$(jq -r '.pagination.next // empty' <<<"$page")
    [ -n "$until" ] || break
  done
}

list_convex() {
  need CONVEX_TEAM_TOKEN CONVEX_PROJECT_ID
  local list names name
  counted Convex
  list=$(curl -fsS -m 30 -H @<(bearer CONVEX_TEAM_TOKEN) "$convex_api/v1/projects/$CONVEX_PROJECT_ID/list_deployments")
  names=$(jq -r --arg branch "$branch" --argjson closed "$late_ms" '.[] | select(.deploymentType == "preview" and .previewIdentifier == $branch) | if (.createTime | type) == "number" then select(.createTime <= $closed) | .name else error("Convex gave no number for createTime") end' <<<"$list")
  for name in $names; do
    target Convex CONVEX_TEAM_TOKEN POST "$convex_api/v1/deployments/$name/delete" "$name"
  done
}

remove() {
  local code
  unchanged
  code=$(curl -sS -m 30 -o /dev/null -w '%{http_code}' -H @<(bearer "$1") -X "$2" "$3")
  case $code in
    2??) echo "deleted the $4 of $branch"; removed=1 ;;
    404) echo "the $4 of $branch is already gone"; removed=0 ;;
    *) echo "preview-teardown: HTTP $code from $2 $3" >&2; exit 1 ;;
  esac
}

unused() {
  local open head base
  open=$(gh api --paginate -X GET "repos/$repo/pulls" -f state=open -f per_page=100 --jq '.[] | [.head.ref, .base.ref] | join("\u001f")')
  while IFS=$'\x1f' read -r head base; do
    [ "$head" != "$branch" ] || keep "an open PR has $branch as its head"
    [ "$base" != "$branch" ] || keep "an open PR has $branch as its base"
  done <<<"$open"
}

tip_now() {
  git ls-remote "$remote" "refs/heads/$branch" | awk -v ref="refs/heads/$branch" '$2 == ref { print $1 }'
}

deleted_since_reopen() {
  gh api --paginate -X GET "repos/$repo/issues/$pr/events" -f per_page=100 --jq '.[] | select(.event == "head_ref_deleted" or .event == "reopened") | .event' | awk '$1 == "reopened" { n = 0 } $1 == "head_ref_deleted" { n++ } END { print n + 0 }'
}

unchanged() {
  local now now_deletes
  now=$(tip_now)
  [ "$now" = "$tip" ] || keep "$branch changed while the teardown ran"
  if [ -n "$tip" ]; then
    now_deletes=$(deleted_since_reopen)
    [ "$now_deletes" = "$deletes" ] || keep "$branch was deleted while the teardown ran"
  fi
  unused
}

keep() {
  echo "preview-teardown: $1, so PR #$pr keeps its previews and its branch"
  exit 0
}

live=$(gh api "repos/$repo/pulls/$pr" --jq '[.state, .head.repo.full_name // "", .head.ref, .head.sha, .base.repo.default_branch, .created_at, .closed_at // ""] | join("\u001f")')
IFS=$'\x1f' read -r state head_repo branch sha default created_at closed_at <<<"$live"
[ "$state" = closed ] || keep "PR #$pr is $state"
[ "$head_repo" = "$repo" ] || keep "the head branch is ${head_repo:-a deleted fork}:$branch, not a branch of $repo"
[ "$branch" != "$default" ] || keep "the head branch $branch is the default branch"
unused
for long_lived in ${PREVIEW_KEEP_BRANCHES:-}; do
  [ "$long_lived" != "$branch" ] || keep "$branch is in PREVIEW_KEEP_BRANCHES"
done
opened_ms=$(($(date -u -d "$created_at" +%s) * 1000))
closed_ms=$((($(date -u -d "${closed_at:?PR #$pr has no closed_at}" +%s) + 1) * 1000 - 1))
grace_ms=$((closed_ms + 2 * 60 * 1000))
late_ms=$((closed_ms + 45 * 60 * 1000))
commits=$(gh api --paginate -X GET "repos/$repo/pulls/$pr/commits" -f per_page=100 --jq '.[].sha')
deletes=$(deleted_since_reopen)
tip=$(tip_now)
[ -z "$tip" ] || [ "$tip" = "$sha" ] || keep "$branch moved to $tip after PR #$pr closed at $sha"
if [ -n "$tip" ]; then
  path=$(jq -rn --arg branch "$branch" '$branch | @uri')
  protected=$(gh api "repos/$repo/branches/$path" --jq .protected)
  rules=$(gh api --paginate -X GET "repos/$repo/rules/branches/$path" -f per_page=100 --jq '.[] | select(.type == "deletion") | .type' | wc -l)
  [ "$protected" = false ] && [ "$rules" = 0 ] || keep "$branch is protected or a ruleset blocks its deletion"
  [ "$deletes" = 0 ] || keep "$branch came back after it was deleted once"
fi

targets=()
labels=()
declare -A deleted=()
for provider in ${PREVIEW_PROVIDERS:-}; do
  case $provider in
    vercel) list_vercel ;;
    convex) list_convex ;;
    *) echo "preview-teardown: no teardown for the provider $provider. Add a list_$provider function." >&2; exit 1 ;;
  esac
done
for item in "${targets[@]}"; do
  IFS=$'\x1f' read -r provider token method url name <<<"$item"
  remove "$token" "$method" "$url" "$provider preview $name"
  deleted[$provider]=$((deleted[$provider] + removed))
done
for provider in "${labels[@]}"; do
  echo "preview-teardown: deleted ${deleted[$provider]} $provider previews of $branch"
done

if [ -z "$tip" ]; then
  echo "preview-teardown: $branch is already gone"
else
  unchanged
  git push -q --force-with-lease="refs/heads/$branch:$sha" "$remote" ":refs/heads/$branch"
  echo "deleted the branch $branch"
fi
