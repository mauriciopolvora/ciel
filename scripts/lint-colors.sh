#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

tokens=Sources/Ciel/DesignSystem.swift
files=()
while IFS= read -r file; do files+=("$file"); done < <(find Sources -name '*.swift' ! -path "$tokens" | sort)

awk -v tokens="$tokens" -v today="$(date +%Y-%m-%d)" '
BEGIN {
    use_token = "use a Theme token from " tokens ", and add one there if none fits."
    named = "white|black|gray|lightGray|darkGray|red|green|blue|cyan|yellow|magenta|orange|purple|brown"
    systems = "system(Red|Orange|Yellow|Green|Mint|Teal|Cyan|Blue|Indigo|Purple|Pink|Brown|Gray)|[a-z]*[sS]ystemFill"
    semantic = "(control|selected|unemphasized|alternate|alternating|window|header|disabled|secondary|tertiary" \
        "|quaternary|quinary|placeholder|keyboardFocus|findHighlight|underPage|text|label|link|separator|grid" \
        "|highlight|shadow|knob|scrollBar)[A-Za-z]*Color"

    rule[++rules] = "NSColor(\\.[a-z]|\\()[A-Za-z]*"
    fix[rules] = use_token
    rule[++rules] = "CGColor(\\.[a-z]|\\(|Create)[A-Za-z]*"
    fix[rules] = use_token
    rule[++rules] = "set(Fill|Stroke)Color\\((red|gray):"
    fix[rules] = use_token
    rule[++rules] = "\\.init\\((white|red|hue|srgbRed|displayP3Red|calibrated[A-Za-z]*|device[A-Za-z]*|generic[A-Za-z]*" \
        "|named|cgColor|ciColor|catalogName|colorSpace|patternImage):"
    fix[rules] = use_token
    rule[++rules] = "(^|[^]A-Za-z0-9_?!)])\\.(" systems "|" semantic "|" named ")([^A-Za-z0-9_]|$)"
    fix[rules] = use_token
    rule[++rules] = "\\.cgColor"
    fix[rules] = "use Theme.cg(token, in: view) from " tokens ", which resolves the color in the view appearance."
    rule[++rules] = "NSTextField\\((labelWithString|wrappingLabelWithString|labelWithAttributedString):"
    fix[rules] = "use Theme.label from " tokens ", which sets a Theme text color."
    rule[++rules] = "NSSwitch\\(|NSButton\\(checkboxWithTitle:"
    fix[rules] = "use MonochromeSwitch from " tokens ", which draws without the system accent color."
    rule[++rules] = "orderFrontStandardAboutPanel"
    fix[rules] = "use AboutController, which draws the About window with Theme colors."

    split("31 28 31 30 31 30 31 31 30 31 30 31", month_days, " ")

    exception = "// color-lint: allow until [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9], approved by [^:]+: [^ ].*"
}
function real_date(date,    year, month, day, last) {
    year = substr(date, 1, 4) + 0
    month = substr(date, 6, 2) + 0
    day = substr(date, 9, 2) + 0
    if (month < 1 || month > 12 || day < 1) return 0
    last = month_days[month]
    if (month == 2 && (year % 4 == 0 && year % 100 != 0 || year % 400 == 0)) last = 29
    return day <= last
}
function report(message) {
    printf "%s:%d: %s\n", FILENAME, FNR, message
    failed = 1
}
{
    code = $0
    allowed = 0
    marker = index(code, "// color-lint:")
    if (marker > 0) {
        note = substr(code, marker)
        if (note !~ "^" exception "$") {
            report("malformed color-lint exception. Write // color-lint: allow until YYYY-MM-DD, approved by <human>: <reason>.")
            next
        }
        until = substr(note, length("// color-lint: allow until ") + 1, 10)
        if (!real_date(until)) {
            report("color-lint exception date " until " is not a calendar date. Write YYYY-MM-DD.")
            next
        }
        if (until < today) {
            report("color-lint exception expired on " until ". Fix the color, or get a human to approve a new date.")
            next
        }
        allowed = 1
        code = substr(code, 1, marker - 1)
    }
    sub(/\/\/.*/, "", code)
    gsub(/(NS|CG)Color\.clear/, "", code)
    gsub(/weight: *\.black/, "", code)
    for (i = 1; i <= rules; i++) {
        if (match(code, rule[i])) {
            shown = substr(code, RSTART, RLENGTH)
            gsub(/^[^.A-Za-z]+|[^A-Za-z0-9_]+$/, "", shown)
            if (!allowed) report(shown " bypasses the theme. Fix: " fix[i])
            next
        }
    }
    if (allowed) report("unused color-lint exception. Remove it.")
}
END { exit failed }
' "${files[@]}"
