#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."

baseline=scripts/lint/comment-baseline.txt
lint=scripts/lint/lint-comments.sh
before_lint_folder() { printf 'scripts/%s' "${1##*/}"; }
update=0
commit=
usage() {
    cat >&2 <<'USAGE'
Usage: lint-comments.sh [--update | --commit <sha>]
Counts the comment lines in each tracked Swift file with scripts/lint/comment-lines.awk, in the working tree, or in
<sha> with the lint and scanner that <sha> holds. Fails when a file has more than scripts/lint/comment-baseline.txt
allows, when the baseline allows more than a file has, or when the baseline rises above its copy at the base
commit: CIEL_COMMENT_BASE, else the merge base with origin/main. A file that git sees as moved since the base keeps
its base count, and --update maps the current baseline with the moves since HEAD. --update writes the counts only
when no count rises. Exit 2: it cannot list or extract the files.
USAGE
    exit 64
}
case "${1:-}" in
"") ;;
--update) update=1 ;;
--commit) commit="${2:-}"; [[ -n "$commit" ]] || usage ;;
*) usage ;;
esac

fail() {
    printf 'lint-comments: %s\n' "$*" >&2
    exit 1
}
broken() {
    printf 'lint-comments: %s\n' "$*" >&2
    exit 2
}

base="${CIEL_COMMENT_BASE:-}"
[[ ! "$base" =~ ^0+$ ]] || base=
no_base="cannot find the merge base with origin/main. Run git fetch origin main (git fetch --unshallow in a shallow clone), or set CIEL_COMMENT_BASE to a commit."
if [[ -z "$base" ]] && ! base="$(git merge-base "${commit:-HEAD}" origin/main 2>/dev/null)"; then
    [[ "$update" == 1 ]] || fail "$no_base"
    base=
    printf 'lint-comments: %s --update compares with the current baseline only.\n' "$no_base" >&2
fi

mkdir -p .build
scratch="$(mktemp -d "$PWD/.build/lint-comments.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
if [[ -n "$commit" ]]; then
    # WARNING: git archive drops the files an export-ignore attribute names, so a temporary index extracts the commit.
    git_dir="$(git rev-parse --absolute-git-dir)" || broken "cannot find the git directory."
    export GIT_DIR="$git_dir" GIT_WORK_TREE="$scratch/tree" GIT_INDEX_FILE="$scratch/index"
    mkdir "$GIT_WORK_TREE"
    { git read-tree "$commit" && git checkout-index -a; } || broken "cannot extract $commit."
    own="$lint"
    [[ -f "$GIT_WORK_TREE/$own" ]] || own="$(before_lint_folder "$lint")"
    [[ -f "$GIT_WORK_TREE/$own" ]] ||
        fail "$commit has no $lint. Rebase it on origin/main, then push again."
    CIEL_COMMENT_BASE="$base" bash "$GIT_WORK_TREE/$own"
    exit
fi

git ls-files -z -- '*.swift' >"$scratch/files" || broken "cannot list the Swift files with git ls-files."
files=()
while IFS= read -r -d '' file; do
    [[ ! -e "$file" ]] || files+=("$file")
done <"$scratch/files"
[[ ${#files[@]} -gt 0 ]] || broken "found no Swift files with git ls-files."
awk -f scripts/lint/comment-lines.awk "${files[@]}" >"$scratch/lines"

validate() {
    awk -v name="$1" '
        !/^[1-9][0-9]* [^ ]/ { print name ":" NR ": expected <count> <path>, with a count above 0"; next }
        { path = substr($0, index($0, " ") + 1); if (path in seen) print name ":" NR ": " path " is listed again" }
        { seen[path] = 1 }
    ' "$2"
}
: >"$scratch/previous"
has_previous=0
apply_moves_since() {
    git diff -z -M --name-status --diff-filter=R "$1" -- '*.swift' >"$scratch/renames" ||
        broken "cannot list the files moved since $1 with git diff."
    : >"$scratch/moves"
    while IFS= read -r -d '' _ && IFS= read -r -d '' from && IFS= read -r -d '' to; do
        printf '%s\t%s\n' "$from" "$to" >>"$scratch/moves"
    done <"$scratch/renames"
    awk -F '\t' 'which == "moves" { to[$1] = $2; next }
        { space = index($0, " "); path = substr($0, space + 1) }
        { print (path in to) ? substr($0, 1, space) to[path] : $0 }' \
        which=moves "$scratch/moves" which=rows "$2" >"$scratch/moved"
    mv "$scratch/moved" "$2"
}
if [[ -n "$base" ]]; then
    git cat-file -e "$base^{commit}" 2>/dev/null ||
        fail "cannot read the base commit $base. Fetch it with git fetch --unshallow, or check out with fetch-depth: 0."
fi
base_baseline="$baseline"
[[ -z "$base" ]] || git cat-file -e "$base:$base_baseline" 2>/dev/null ||
    base_baseline="$(before_lint_folder "$baseline")"
if [[ -n "$base" ]] && git cat-file -e "$base:$base_baseline" 2>/dev/null; then
    has_previous=1
    git show "$base:$base_baseline" >"$scratch/previous"
    errors="$(validate "$base:$base_baseline" "$scratch/previous")"
    [[ -z "$errors" ]] || fail "$errors"$'\n'"Fix the baseline at the base commit, or set CIEL_COMMENT_BASE to a commit with a valid one."
    apply_moves_since "$base" "$scratch/previous"
fi

cp "$baseline" "$scratch/stored" 2>/dev/null || : >"$scratch/stored"
errors="$(validate "$baseline" "$scratch/stored")"
if [[ "$update" == 1 ]]; then
    has_current=0
    [[ ! -f "$baseline" || -n "$errors" ]] || has_current=1
    ! git rev-parse -q --verify HEAD >/dev/null || apply_moves_since HEAD "$scratch/stored"
    awk -F '\t' '{ if (!($1 in count)) order[++files] = $1; count[$1]++ }
        END { for (f = 1; f <= files; f++) print count[order[f]], order[f] }' "$scratch/lines" >"$scratch/proposed"
    awk -v baseline="$baseline" '
        function path() { return substr($0, index($0, " ") + 1) }
        which == "proposed" { proposed[++rows] = path(); count[path()] = $1 + 0 }
        which == "stored" { current[path()] = $1 + 0 }
        which == "previous" { before[path()] = $1 + 0 }
        END {
            for (r = 1; r <= rows; r++) {
                file = proposed[r]
                limit = -1
                if (has_current) limit = current[file] + 0
                if (has_previous && (limit < 0 || before[file] + 0 < limit)) limit = before[file] + 0
                if (limit >= 0 && count[file] > limit) {
                    print "lint-comments: --update raises " file " from " limit " to " count[file] " comment lines, above the current baseline or the base baseline. The baseline only shrinks: delete the comment, or put a fact about code we cannot change on a // WARNING: line." > "/dev/stderr"
                    failed = 1
                }
            }
            if (failed) print "lint-comments: --update did not change " baseline "." > "/dev/stderr"
            exit failed
        }
    ' which=proposed "$scratch/proposed" which=stored has_current="$has_current" "$scratch/stored" \
        which=previous has_previous="$has_previous" "$scratch/previous" || exit 1
    mv "$scratch/proposed" "$baseline"
    cp "$baseline" "$scratch/stored"
    errors=
fi
[[ -z "$errors" ]] || fail "$errors"$'\n'"Run bash scripts/lint/lint-comments.sh --update to write it again."

awk -v baseline="$baseline" '
    function report(message) { print message > "/dev/stderr"; failed = 1 }
    function path() { return substr($0, index($0, " ") + 1) }
    which == "lines" {
        tab = index($0, "\t")
        file = substr($0, 1, tab - 1)
        if (!(file in count)) order[++files] = file
        count[file]++
        where[file] = where[file] "\n    " file ":" substr($0, tab + 1)
    }
    which == "stored" { allowed[path()] = $1 + 0; stored[++rows] = path() }
    which == "previous" { before[path()] = $1 + 0 }
    END {
        for (f = 1; f <= files; f++) {
            file = order[f]
            if (count[file] > allowed[file] + 0)
                report(file ": " count[file] " comment lines, and " baseline " allows " (allowed[file] + 0) ". Say it with a name, a type or a test instead. Put a fact about code we cannot change on a // WARNING: line." where[file])
        }
        for (r = 1; r <= rows; r++) {
            file = stored[r]
            if (count[file] + 0 < allowed[file])
                report(file ": " (count[file] + 0) " comment lines, and " baseline " still allows " allowed[file] ". Run bash scripts/lint/lint-comments.sh --update to lower it.")
            if (has_previous && allowed[file] > before[file] + 0)
                report(baseline ": raises " file " from " (before[file] + 0) " to " allowed[file] " comment lines. The baseline only shrinks: delete the comment, or put a fact about code we cannot change on a // WARNING: line.")
        }
        exit failed
    }
' which=lines "$scratch/lines" which=stored "$scratch/stored" which=previous has_previous="$has_previous" "$scratch/previous"
