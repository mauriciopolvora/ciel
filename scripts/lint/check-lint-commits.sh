#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# WARNING: a hook sets GIT_DIR and other git variables, which would point the scratch repo at the real one.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
mkdir -p .build
scratch="$(mktemp -d "$PWD/.build/check-lint-commits.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
failures=0
repo="$scratch/repo"
mkdir -p "$repo/scripts"
cp scripts/check-commits.sh "$repo/scripts/"
scratch_git() {
    git -C "$repo" -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"
}
commit() {
    local author="$1" message="$2"
    GIT_AUTHOR_NAME=author GIT_AUTHOR_EMAIL="$author" GIT_COMMITTER_NAME=author GIT_COMMITTER_EMAIL="$author" \
        scratch_git commit -q --allow-empty -m "$message"
    scratch_git rev-parse HEAD
}
expect() {
    local want="$1" name="$2" output status=0
    shift 2
    output="$(cd "$repo" && bash scripts/check-commits.sh "$@" 2>&1)" || status=$?
    if [[ "$status" -ne "$want" ]]; then
        printf 'FAIL %s: exit %s, expected %s. Output:\n%s\n' "$name" "$status" "$want" "$output"
        failures=$((failures + 1))
    fi
}

scratch_git init -q
person=person@example.test
dependabot='49699333+dependabot[bot]@users.noreply.github.com'
root="$(commit "$person" "chore: start")"
clean="$(commit "$person" "fix(scripts): a plain commit")"
expect 0 "a commit with no trailers" "$root..$clean"
coauthor="$(commit "$person" $'feat: pair work\n\nCo-authored-by: Other <other@example.test>')"
expect 1 "a Co-authored-by trailer" "$clean..$coauthor"
signed="$(commit "$person" $'fix: signed\n\nSigned-off-by: Person <person@example.test>')"
expect 1 "a Signed-off-by from a person" "$coauthor..$signed"
lower="$(commit "$person" $'fix: body\n\nSome text.\nco-authored-by: other')"
expect 1 "a co-authored-by line inside the body" "$signed..$lower"
bot="$(commit "$dependabot" $'chore(deps): bump x\n\nSigned-off-by: dependabot[bot] <support@github.com>')"
expect 0 "the Dependabot Signed-off-by" "$lower..$bot"
bot_extra="$(commit "$dependabot" $'chore(deps): bump y\n\nSigned-off-by: dependabot[bot] <support@github.com>\nChange-Id: 1')"
expect 1 "a Dependabot commit with another trailer" "$bot..$bot_extra"
fake="$(commit "$person" $'chore(deps): bump z\n\nSigned-off-by: dependabot[bot] <support@github.com>')"
expect 1 "the Dependabot Signed-off-by from another author" "$bot_extra..$fake"
expect 1 "a range with one bad commit" "$root..$fake"
scratch_git update-ref refs/remotes/origin/main "$fake"
after="$(commit "$person" "fix: after the remote")"
expect 0 "commits that a remote has are skipped" --not --remotes --not "$after"
expect 1 "a range with no remote skip" "$after"

if [[ "$failures" -gt 0 ]]; then
    printf 'check-lint-commits: %s cases failed\n' "$failures" >&2
    exit 1
fi
