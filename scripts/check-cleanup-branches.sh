#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
here="$PWD"

# WARNING: a hook sets GIT_DIR and other git variables, which would point the scratch repo at the real one.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
mkdir -p .build
scratch="$(mktemp -d "$PWD/.build/check-cleanup-branches.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
work="$scratch/work"
scratch_git() {
    git -C "$work" -c user.name=check -c user.email=check@example.test -c commit.gpgsign=false \
        -c core.hooksPath=/dev/null "$@"
}
commit() {
    printf '%s\n' "$1" >"$work/$1"
    scratch_git add "$1"
    scratch_git commit -q -m "$1"
    scratch_git rev-parse HEAD
}

mkdir "$scratch/bin"
cat >"$scratch/bin/gh" <<'GH'
#!/bin/bash
set -euo pipefail
file= expr=
while [[ $# -gt 0 ]]; do
    case "$1" in
    --state) file="$FIXTURES/pr-$2.json"; shift ;;
    --json) [[ -n "$file" ]] || file="$FIXTURES/repo-$2.json"; shift ;;
    --jq) expr="$2"; shift ;;
    esac
    shift
done
jq -r "$expr" "$file"
GH
chmod +x "$scratch/bin/gh"

git init -q --bare "$scratch/remote.git"
git init -q -b main "$work"
scratch_git remote add origin "$scratch/remote.git"
commit start >/dev/null
scratch_git checkout -q -b feature
feature="$(commit feature)"
scratch_git checkout -q -b stacked
stacked="$(commit stacked)"
scratch_git checkout -q -b done main
commit done-one >/dev/null
done="$(commit done-two)"
scratch_git checkout -q main
scratch_git merge -q --squash done >/dev/null
scratch_git commit -q -m "done (#2)"
scratch_git push -q origin main feature stacked done

mkdir "$scratch/fixtures"
printf '{"url":"https://github.com/owner/repo"}\n' >"$scratch/fixtures/repo-url.json"
printf '{"defaultBranchRef":{"name":"main"}}\n' >"$scratch/fixtures/repo-defaultBranchRef.json"
printf '[{"headRefName":"feature"}]\n' >"$scratch/fixtures/pr-open.json"
cat >"$scratch/fixtures/pr-merged.json" <<JSON
[
  {"headRefName": "done", "headRefOid": "$done", "baseRefName": "main", "isCrossRepository": false},
  {"headRefName": "stacked", "headRefOid": "$stacked", "baseRefName": "feature", "isCrossRepository": false}
]
JSON

want="merged done $done
open feature $feature
unmerged stacked $stacked"
status=0
got="$(cd "$work" && FIXTURES="$scratch/fixtures" PATH="$scratch/bin:$PATH" bash "$here/scripts/cleanup-branches.sh" 2>&1)" ||
    status=$?
if [[ "$status" -ne 0 || "$got" != "$want" ]]; then
    printf 'check-cleanup-branches: exit %s, and a PR merged into feature must leave stacked unmerged. Expected:\n%s\nGot:\n%s\n' \
        "$status" "$want" "$got" >&2
    exit 1
fi
