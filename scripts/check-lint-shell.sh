#!/bin/bash
# Proves that lint-shell.sh fails each bash -n or sh -n call, and that check-syntax.sh checks every file it gets.
set -euo pipefail
cd "$(dirname "$0")/.."
# A hook sets GIT_DIR and other git variables. Unset them, so the scratch repo below never writes to the real one.
unset $(git rev-parse --local-env-vars)
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

passing=(
    'bash scripts/check-syntax.sh scripts/*.sh .githooks/pre-push'
    '    # bash -n a b in a comment line'
    'bash -x a b'
    'bash a.sh'
    'sh -c "echo hi"'
    'ssh -n host true'
    'find . -name "*.sh" -print'
    'echo tool.sh -n'
    'bash scripts/test.sh --name x'
    'set -o pipefail'
)
failing=(
    'bash -n "$script"'
    'bash -n a b'
    'bash -n scripts/*.sh'
    'bash -n "$@"'
    'bash -n "$f" >/dev/null invalid.sh'
    'bash -n "$f" 01-invalid.sh'
    'bash 2>/dev/null -n a.sh b.sh'
    'bash -O extglob -n a.sh b.sh'
    'bash -o errexit -n a.sh b.sh'
    'bash --noprofile -n a.sh b.sh'
    '/bin/bash -n a b'
    '"/bin/bash" "-n" a.sh b.sh'
    'sh -n a b'
    'bash -en a b'
    'bash -e -n a b'
    'bash -n &>/dev/null a.sh b.sh'
    'LC_ALL="C" bash -n a.sh b.sh'
    'echo ok; bash -n a b'
    'out="$(bash -n a.sh b.sh)"'
    'for f in *.sh; do bash -n "$f"; done'
    'bash -o noexec a.sh b.sh'
    'sh -o noexec a b'
    '"$BASH" -n a.sh b.sh'
    '${BASH} -n a b'
)
passing_yml='jobs:\n  a:\n    steps:\n      - run: bash scripts/check-syntax.sh scripts/*.sh\n'
failing_yml=(
    'jobs:\n  a:\n    steps:\n      - run: bash -n a b\n'
    'jobs:\n  a:\n    steps:\n      - run: "bash \\"-n\\" a.sh b.sh"\n'
    "jobs:\n  a:\n    steps:\n      - run: 'bash -n \"\$f\"'\n"
    'jobs:\n  a:\n    steps:\n      - run: | # check\n          bash -n scripts/*.sh\n'
)

failed=0
expect() {
    local want="$1" got=0 output
    shift
    output="$("$@" 2>&1)" || got=$?
    if [[ "$got" != "$want" ]]; then
        echo "$* exited $got, expected $want" >&2
        [[ -n "$output" ]] && echo "$output" >&2
        failed=1
    fi
}

printf '%s\n' "${passing[@]}" > "$scratch/pass.sh"
expect 0 bash scripts/lint-shell.sh "$scratch/pass.sh"
printf "$passing_yml" > "$scratch/pass.yml"
expect 0 bash scripts/lint-shell.sh "$scratch/pass.yml"
for index in "${!failing[@]}"; do
    printf '%s\n' "${failing[$index]}" > "$scratch/fail$index.sh"
    expect 1 bash scripts/lint-shell.sh "$scratch/fail$index.sh"
done
for index in "${!failing_yml[@]}"; do
    printf "${failing_yml[$index]}" > "$scratch/fail$index.yml"
    expect 1 bash scripts/lint-shell.sh "$scratch/fail$index.yml"
done
expect 2 bash scripts/lint-shell.sh "$scratch/missing.sh"
expect 0 bash scripts/lint-shell.sh scripts/check-syntax.sh

repo="$scratch/repo"
mkdir -p "$repo/scripts" "$repo/site" "$repo/.github/workflows" "$repo/.githooks"
cp scripts/lint-shell.sh scripts/check-syntax.sh "$repo/scripts/"
printf 'echo ok\n' > "$repo/site/ação.sh"
git -C "$repo" init -q
# -f adds a file that a global ignore rule matches.
git -C "$repo" add -f -A
expect 0 bash "$repo/scripts/lint-shell.sh"
for tracked in site/tool.sh .github/workflows/test.yaml .githooks/pre-commit .agents/skills/x/scripts/run.sh; do
    mkdir -p "$repo/$(dirname "$tracked")"
    printf 'bash -n a.sh b.sh\n' > "$repo/$tracked"
    git -C "$repo" add -f "$tracked"
    expect 1 bash "$repo/scripts/lint-shell.sh"
    git -C "$repo" rm -qf "$tracked"
done
printf 'bash -n a.sh b.sh\n' > "$scratch/input=bad.sh"
expect 1 bash -c 'cd "$1" && bash "$2" input=bad.sh </dev/null' _ "$scratch" "$PWD/scripts/lint-shell.sh"

printf 'echo ok\n' > "$scratch/good.sh"
printf 'if then\n' > "$scratch/bad.sh"
expect 0 bash scripts/check-syntax.sh "$scratch/good.sh" "$scratch/good.sh"
expect 2 bash scripts/check-syntax.sh "$scratch/good.sh" "$scratch/bad.sh"
expect 2 bash scripts/check-syntax.sh
printf 'if then\n' > "$scratch/-s"
expect 2 bash -c 'cd "$1" && bash "$2" -s </dev/null' _ "$scratch" "$PWD/scripts/check-syntax.sh"
exit "$failed"
