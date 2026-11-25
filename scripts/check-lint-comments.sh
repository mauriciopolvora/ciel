#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
here="$PWD"
mkdir -p .build
scratch="$(mktemp -d "$here/.build/check-lint-comments.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

awks=()
for candidate in awk gawk mawk "busybox awk"; do
    if $candidate 'BEGIN { exit 0 }' 2>/dev/null; then awks+=("$candidate"); fi
done

failed=0
expect() {
    local file="$scratch/$1" want="$2" got candidate
    cat >"$file"
    for candidate in "${awks[@]}"; do
        got="$($candidate -f scripts/comment-lines.awk "$file" | cut -f2 | tr '\n' ' ' | sed 's/ $//')"
        if [[ "$got" != "$want" ]]; then
            printf 'check-lint-comments: %s under %s counts lines "%s", expected "%s"\n' "$1" "$candidate" "$got" "$want" >&2
            failed=1
        fi
    done
}

expect plain.swift "1 2 3" <<'EOF'
// a comment
/// a doc comment
let x = 1 // a trailing comment
let y = 2
EOF
expect strings.swift "3" <<'EOF'
let url = "https://example.test"
let quoted = "a \"//\" b \\"
let after = "\\" // counted
EOF
expect raw.swift "4" <<'EOF'
let a = #"say "hi" https://example.test"#
let b = ##"a "# // still inside"##
let c = #"a\"# + "//"
let d = #"a\"# // counted
EOF
expect interpolation.swift "4" <<'EOF'
let a = "\(f("//"))"
let b = "\(g((1), "/*", h("\(i("//"))")))"
let c = #"\#(j("//")) \(not) //"#
let d = "\(k)" // counted
EOF
expect multiline.swift "5 9" <<'EOF'
let a = """
    // not a comment
    "quoted" and \(f("""
    """)) /* still a string */
    """ // counted after the closing delimiter
let b = #"""
    """ is not the end
    // not a comment
    """# + "x" // counted
EOF
expect regex.swift "3" <<'EOF'
let a = #/https://example[.]test/#
let b = ##/a/# // still inside/##
let c = #/\/#/# // counted
let d = #/
    https://example.test
    /#
EOF
expect bare-regex.swift "2 4 5 6 9 11 13" <<'EOF'
let quote = /"/
let answer = 42 // counted
let slash = /\//
let half = total / 2 // counted
let ratio = a/b // counted
let both = /a\/b/.wholeMatch(in: s) ?? x / 2 // counted
let list = [/a/, try /b/, f(/c/), y ?? /d"/]
let block = s.map { /"/ }
if s.contains(/^\/\//) { return /"/ } // counted
let spaced = / x / 2
let mixed = a /b // counted
let path = "a/b" + x / y
let url = x.matches(/https:\/\/[a-z]+/) // counted
EOF
expect operator-slash.swift "1 2 3 4 5" <<'EOF'
let ratio = [2.0, 4.0].reduce(1.0, /) // Divide by each entry
let a = f(/, x) // counted
let b = [/] // counted
let c = g(/x) // counted
let d = s.contains(/(a)\)\//) // counted
let e = s.matches(/(a|b)\/\//)
let f = s.matches(/(a)/) + [/b/]
EOF
expect regex-class.swift "1 2 3 4" <<'EOF'
let delimiter = /[)"]+/ // counted
// counted
let nested = /[a-z&&[^)"]]/ // counted
let first = /[]"(]/ // counted
let x = 1
EOF
expect regex-start.swift "1 2 3 4 5" <<'EOF'
let quotient = numerator!/2 // counted
let pattern = /,"/ // counted
// counted
let ops = [/, y] // counted
let q = f(/, "x") // counted
let x = 1
EOF
expect block-then-regex.swift "1 2 3 4 5 6 7" <<'EOF'
let r = /* existing */ /"/
let x = 42 // counted
/* a
*/ /"/
let y = 1 // counted
return /* a */ /"/ + 1
let z = 2 // counted
EOF
expect blocks.swift "1 2 3 4 5 7" <<'EOF'
/* a /* nested */ still
inside

*/ let x = 1
let y = 2 /* trailing */
let z = 3
/** doc */
EOF
expect warning.swift "2 3 4 6" <<'EOF'
// WARNING: an outside constraint
/* WARNING: a block is not exempt */
/// WARNING: a doc comment is not exempt
// WARNING:
// WARNING: a """ does not open a string
let s = "//" // counted
EOF
expect directives.swift "4 5 6 8 9" <<'EOF'
// swift-format-ignore
// swift-format-ignore-file
// swift-format-ignore: NeverForceUnwrap, NeverUseForceTry
// swift-format-ignore please
// swift-format-ignore: two words
// color-lint: allow it
let c = NSColor.red // color-lint: allow until 2026-12-31, approved by the operator: a pending fix
// swift-tools-version: 6.0
#if DEBUG // counted
#endif
EOF
mkdir "$scratch/package"
expect package/Package.swift "2" <<'EOF'
// swift-tools-version: 6.0
// swift-tools-version: 6.0
EOF

# WARNING: a pre-push hook exports these, and they would point the scratch repository at this one.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
repo="$scratch/repo"
scratch_git() {
    git -C "$repo" -c user.name=check -c user.email=check@example.test -c commit.gpgsign=false \
        -c core.excludesFile=/dev/null -c core.hooksPath=/dev/null "$@"
}
lint() {
    local want_status="$1" want_text="$2" output status=0
    shift 2
    output="$(cd "$repo" && CIEL_COMMENT_BASE="$base" bash scripts/lint-comments.sh "$@" 2>&1)" || status=$?
    if [[ "$status" != "$want_status" || "$output" != *"$want_text"* ]]; then
        printf 'check-lint-comments: lint %s exited %s, expected %s with "%s". Output:\n%s\n' \
            "$*" "$status" "$want_status" "$want_text" "$output" >&2
        failed=1
    fi
}
mkdir -p "$repo/Sources" "$repo/Tests" "$repo/scripts"
cp scripts/lint-comments.sh scripts/comment-lines.awk "$repo/scripts"
printf '// swift-tools-version: 6.0\n' >"$repo/Package.swift"
printf '// one\nlet x = 1\n' >"$repo/Sources/With Space.swift"
printf 'let y = 2\n' >"$repo/Tests/Test.swift"
scratch_git init -q
scratch_git commit -q --allow-empty -m empty
base="$(scratch_git rev-parse HEAD)"
scratch_git add -A
lint 0 "" --update
lint 0 ""
printf '1 Sources/With Space.swift\n1 Sources/With Space.swift\n' >"$repo/scripts/comment-baseline.txt"
lint 1 "is listed again"
lint 1 "lint-comments.sh --update"
printf 'one Sources/With Space.swift\n' >"$repo/scripts/comment-baseline.txt"
lint 1 "expected <count> <path>"
lint 0 "" --update
printf '// two\n' >>"$repo/Sources/With Space.swift"
lint 1 "Sources/With Space.swift:3"
lint 1 "raises Sources/With Space.swift from 1 to 2" --update
printf '2 Sources/With Space.swift\n' >"$repo/scripts/comment-baseline.txt"
lint 0 ""
scratch_git add -A
scratch_git commit -q -m baseline
base="$(scratch_git rev-parse HEAD)"
unchanged_baseline() {
    if ! scratch_git diff --quiet HEAD -- scripts/comment-baseline.txt; then
        printf 'check-lint-comments: %s changed the baseline:\n%s\n' "$1" "$(scratch_git diff HEAD)" >&2
        failed=1
    fi
}
printf 'let x = 1\n// two\n' >"$repo/Sources/With Space.swift"
lint 0 "" --update
scratch_git commit -q -am "one comment less"
printf '// one\nlet x = 1\n// two\n' >"$repo/Sources/With Space.swift"
lint 1 "raises Sources/With Space.swift from 1 to 2" --update
unchanged_baseline "an --update above the current baseline"
lint 1 "2 comment lines, and scripts/comment-baseline.txt allows 1"
scratch_git reset -q --hard "$base"
scratch_git mv "Sources/With Space.swift" Sources/Moved.swift
lint 0 "" --update
if [[ "$(cat "$repo/scripts/comment-baseline.txt")" != "2 Sources/Moved.swift" ]]; then
    printf 'check-lint-comments: --update after git mv wrote:\n%s\n' "$(cat "$repo/scripts/comment-baseline.txt")" >&2
    failed=1
fi
lint 0 ""
scratch_git checkout -q -- scripts/comment-baseline.txt
printf '// three\n' >>"$repo/Sources/Moved.swift"
lint 1 "raises Sources/Moved.swift from 2 to 3" --update
unchanged_baseline "an --update above the baseline after git mv"
scratch_git reset -q --hard "$base"
scratch_git mv "Sources/With Space.swift" Sources/Moved.swift
printf '2 Sources/Moved.swift\n' >"$repo/scripts/comment-baseline.txt"
lint 0 ""
lint 0 "" --update
scratch_git commit -q -am "move"
lint 0 "" --commit HEAD
printf '// three\n' >>"$repo/Sources/Moved.swift"
printf '3 Sources/Moved.swift\n' >"$repo/scripts/comment-baseline.txt"
lint 1 "raises Sources/Moved.swift from 2 to 3"
lint 1 "raises Sources/Moved.swift from 2 to 3" --update
scratch_git commit -q -am "move and comment"
lint 1 "raises Sources/Moved.swift from 2 to 3" --commit HEAD
scratch_git reset -q --hard "$base"
printf '// three\n' >>"$repo/Sources/With Space.swift"
lint 1 "raises Sources/With Space.swift from 2 to 3" --update
unchanged_baseline "an --update above the base baseline"
lint 0 "" --commit HEAD
scratch_git checkout -q -- scripts/comment-baseline.txt
scratch_git commit -q -am "over the baseline"
lint 1 "3 comment lines" --commit HEAD
{ printf '/three/ { next }\n'; cat scripts/comment-lines.awk; } >"$repo/scripts/comment-lines.awk"
lint 0 ""
lint 1 "3 comment lines" --commit HEAD
GIT_DIR=.git lint 1 "3 comment lines" --commit HEAD
printf 'Sources/** export-ignore\n' >"$repo/.git/info/attributes"
lint 1 "3 comment lines" --commit HEAD
rm "$repo/.git/info/attributes"
mkdir "$repo/scripts/dmg"
printf '// deep\n' >"$repo/scripts/dmg/Deep.swift"
scratch_git add scripts/dmg/Deep.swift
lint 1 "scripts/dmg/Deep.swift: 1 comment lines"
lint 1 "raises scripts/dmg/Deep.swift from 0 to 1" --update
scratch_git rm -qf scripts/dmg/Deep.swift
scratch_git checkout -q -- scripts/comment-baseline.txt
cp "$repo/.git/index" "$scratch/index"
printf 'not an index' >"$repo/.git/index"
lint 2 "cannot list the Swift files"
cp "$scratch/index" "$repo/.git/index"
scratch_git rm -q scripts/lint-comments.sh
scratch_git commit -q -m "no lint"
cp scripts/lint-comments.sh "$repo/scripts"
lint 1 "has no scripts/lint-comments.sh" --commit HEAD
base=0000000000000000000000000000000000000000
lint 1 "merge base with origin/main"
cp scripts/comment-lines.awk "$repo/scripts"
lint 1 "compares with the current baseline only" --update
lint 1 "raises Sources/With Space.swift from 2 to 3" --update
unchanged_baseline "an --update without a merge base"
base=1111111111111111111111111111111111111111
lint 1 "git fetch --unshallow"

exit "$failed"
