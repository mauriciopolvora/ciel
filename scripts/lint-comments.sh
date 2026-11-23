#!/bin/bash
# Usage: lint-comments.sh [--update | --commit <sha>]. Counts the comment lines in each Swift file that git tracks with
# scripts/comment-lines.awk, in the working tree, or in <sha> with the lint and scanner that <sha> holds. Fails when a
# file has more than scripts/comment-baseline.txt allows, when the baseline allows more than a file has, or when the
# baseline rises above its copy at the base commit: CIEL_COMMENT_BASE, else the merge base with origin/main. Exits 2
# when it cannot list or extract the files. --update writes the counts to the baseline only when no count is above the
# current baseline or the base baseline. Else it exits 1 and does not change the file. When it finds no merge base, it
# compares with the current baseline only.
set -euo pipefail
cd "$(dirname "$0")/.."

baseline=scripts/comment-baseline.txt
update=0
commit=
case "${1:-}" in
"") ;;
--update) update=1 ;;
--commit) commit="${2:?Usage: lint-comments.sh --commit <sha>}" ;;
*) printf 'Usage: lint-comments.sh [--update | --commit <sha>]\n' >&2; exit 64 ;;
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
    # The commit's own lint and scanner judge it, so a change in the working tree cannot make it pass. A temporary index
    # extracts every file of the commit, since git archive drops the files that an export-ignore attribute names. The
    # child runs in the extracted tree, so the git directory must be absolute.
    git_dir="$(git rev-parse --absolute-git-dir)" || broken "cannot find the git directory."
    export GIT_DIR="$git_dir" GIT_WORK_TREE="$scratch/tree" GIT_INDEX_FILE="$scratch/index"
    mkdir "$GIT_WORK_TREE"
    { git read-tree "$commit" && git checkout-index -a; } || broken "cannot extract $commit."
    [[ -f "$GIT_WORK_TREE/scripts/lint-comments.sh" ]] ||
        fail "$commit has no scripts/lint-comments.sh. Rebase it on origin/main, then push again."
    CIEL_COMMENT_BASE="$base" bash "$GIT_WORK_TREE/scripts/lint-comments.sh"
    exit
fi

git ls-files -z -- '*.swift' >"$scratch/files" || broken "cannot list the Swift files with git ls-files."
files=()
while IFS= read -r -d '' file; do
    # A file deleted from the working tree but not from the index has no comments.
    [[ ! -e "$file" ]] || files+=("$file")
done <"$scratch/files"
[[ ${#files[@]} -gt 0 ]] || broken "found no Swift files with git ls-files."
awk -f scripts/comment-lines.awk "${files[@]}" >"$scratch/lines"

# Prints nothing for a valid baseline: one "<count> <path>" row per path, with a count above 0.
validate() {
    awk -v name="$1" '
        !/^[1-9][0-9]* [^ ]/ { print name ":" NR ": expected <count> <path>, with a count above 0"; next }
        { path = substr($0, index($0, " ") + 1); if (path in seen) print name ":" NR ": " path " is listed again" }
        { seen[path] = 1 }
    ' "$2"
}
: >"$scratch/previous"
has_previous=0
if [[ -n "$base" ]]; then
    git cat-file -e "$base^{commit}" 2>/dev/null ||
        fail "cannot read the base commit $base. Fetch it with git fetch --unshallow, or check out with fetch-depth: 0."
fi
if [[ -n "$base" ]] && git cat-file -e "$base:$baseline" 2>/dev/null; then
    has_previous=1
    git show "$base:$baseline" >"$scratch/previous"
    errors="$(validate "$base:$baseline" "$scratch/previous")"
    [[ -z "$errors" ]] || fail "$errors"$'\n'"Fix the baseline at the base commit, or set CIEL_COMMENT_BASE to a commit with a valid one."
fi

cp "$baseline" "$scratch/stored" 2>/dev/null || : >"$scratch/stored"
errors="$(validate "$baseline" "$scratch/stored")"
if [[ "$update" == 1 ]]; then
    # A missing or malformed baseline sets no limit, so --update can write it again. The base baseline still applies.
    has_current=0
    [[ ! -f "$baseline" || -n "$errors" ]] || has_current=1
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
[[ -z "$errors" ]] || fail "$errors"$'\n'"Run bash scripts/lint-comments.sh --update to write it again."

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
                report(file ": " (count[file] + 0) " comment lines, and " baseline " still allows " allowed[file] ". Run bash scripts/lint-comments.sh --update to lower it.")
            if (has_previous && allowed[file] > before[file] + 0)
                report(baseline ": raises " file " from " (before[file] + 0) " to " allowed[file] " comment lines. The baseline only shrinks: delete the comment, or put a fact about code we cannot change on a // WARNING: line.")
        }
        exit failed
    }
' which=lines "$scratch/lines" which=stored "$scratch/stored" which=previous has_previous="$has_previous" "$scratch/previous"
