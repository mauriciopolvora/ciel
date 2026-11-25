#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."

# WARNING: a hook sets GIT_DIR and other git variables, which would point the scratch repo at the real one.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
[[ -x node_modules/.bin/tsrs && -d site/node_modules ]] ||
    { echo "check-lint-types: node_modules is missing. Run bun install here and in site/." >&2; exit 1; }
mkdir -p .build
scratch="$(mktemp -d "$PWD/.build/check-lint-types.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
failures=0

git ls-files -z -- 'tsconfig*.json' oxlint.config.ts site scripts/lint .agents/skills >"$scratch/listed"
tar -cf "$scratch/repo.tar" --null -T "$scratch/listed"

expect() {
    local want="$1" name="$2" text="$3" root="$scratch/repo" output status=0
    rm -rf "$root" && mkdir "$root" && tar -xf "$scratch/repo.tar" -C "$root"
    ln -s "$PWD/node_modules" "$root/node_modules"
    ln -s "$PWD/site/node_modules" "$root/site/node_modules"
    git -C "$root" init -q && git -C "$root" add -A
    git -C "$root" -c user.name=check -c user.email=check@example.com commit -qm base
    git -C "$root" update-ref refs/remotes/origin/main HEAD
    (cd "$root" && eval "$4") ||
        { printf 'check-lint-types: %s: the command that breaks the copy failed.\n' "$name" >&2; exit 1; }
    output="$(cd "$root" && env -u CI ${5:-} node scripts/lint/check-types.mjs 2>&1)" || status=$?
    if [[ "$status" -ne "$want" || "$output" != *"$text"* ]]; then
        printf 'FAIL %s: exit %s, expected %s with "%s". Output:\n%s\n' "$name" "$status" "$want" "$text" "$output"
        failures=$((failures + 1))
    fi
}

error='const typed: number = "text"; export { typed };'
expect 0 "the current code" "" ":"
expect 1 "a new type error" "check-docs.mjs has 1 type errors, and scripts/lint/type-baseline.txt allows 0" \
    "printf '%s\n' '$error' >>scripts/lint/check-docs.mjs"
expect 1 "a type error in the browser project" "site.js has 50 type errors" \
    "printf '%s\n' 'const late = 1; late.unref();' >>site/public/assets/site.js"
expect 1 "a type error in the JXA project" "window-frame.js has 1 type errors" \
    "printf '%s\n' 'Application(\"Finder\");' >>.agents/skills/verify-ciel/scripts/window-frame.js"
expect 1 "a count above the errors" "Lower its count to 49" \
    "sed -i.bak 's/^49 /50 /' scripts/lint/type-baseline.txt"
expect 1 "a count raised over main" "The baseline only shrinks" \
    "printf '%s\n' '$error' >>scripts/lint/check-docs.mjs && printf '1 scripts/lint/check-docs.mjs\n' >>scripts/lint/type-baseline.txt"
expect 1 "a line at 0" "expected <count> <path>" "printf '0 scripts/lint/check-docs.mjs\n' >>scripts/lint/type-baseline.txt"
expect 1 "a path listed twice" "is listed again" "tail -1 scripts/lint/type-baseline.txt >>scripts/lint/type-baseline.txt"
expect 1 "CI with no main" "cannot find the merge base" "git update-ref -d refs/remotes/origin/main" CI=1

if [[ "$failures" -gt 0 ]]; then
    printf 'check-lint-types: %s cases failed\n' "$failures" >&2
    exit 1
fi
echo "check-lint-types: all cases pass"
