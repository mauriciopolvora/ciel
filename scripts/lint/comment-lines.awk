# Prints "<file><TAB><line>" for each line of a Swift file that holds comment text. A // comment whose text is a
# directive does not count: WARNING:, swift-format-ignore, color-lint: and swift-tools-version: on line 1 of
# Package.swift. Runs under gawk, mawk, BusyBox awk and the BSD awk of macOS.
function run(s, i, ch,   n) {
    n = 0
    while (substr(s, i + n, 1) == ch) n++
    return n
}

function directive(text) {
    sub(/^[ \t]+/, "", text)
    sub(/[ \t\r]+$/, "", text)
    return text ~ /^WARNING: [^ ]/ || text ~ /^swift-format-ignore(-file)?$/ \
        || text ~ /^swift-format-ignore: [A-Za-z]+(, [A-Za-z]+)*$/ \
        || text ~ /^color-lint: allow until [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9], approved by [^:]+: [^ ]/ \
        || (FNR == 1 && FILENAME ~ /(^|\/)Package\.swift$/ && text ~ /^swift-tools-version:/)
}

# Opens the string or regex literal whose hashes start at i, and returns the index after its opening delimiter.
function open(i,   marks) {
    marks = substr(line, i, run(line, i, "#"))
    if (substr(line, i + length(marks), 1) == "/") {
        mode = "regex"
        close_with = "/" marks
    } else {
        mode = "string"
        escape = "\\" marks
        close_with = (substr(line, i + length(marks), 3) == "\"\"\"" ? "\"\"\"" : "\"") marks
    }
    return i + length(close_with)
}

# Returns the index after the bare /regex/ that starts at i, or 0 when that / is an operator. Under SE-0354 a bare
# regex starts where an expression can start, does not start with a space or tab, holds no unbalanced ) or ] outside
# a [...] class, and ends on its line at an unescaped / outside a class. Thus the / in reduce(1.0, /), f(/, x) and
# x!/2 is an operator. It reads the line as code, where each block comment is blank.
function bare_regex(i,   before, j, ch, parens, brackets) {
    ch = substr(line, i + 1, 1)
    if (ch == "" || index(" \t)]", ch)) return 0
    before = substr(code, 1, i - 1)
    sub(/[ \t]+$/, "", before)
    if (before != "" && before !~ /[=(,:[{;&|^~?<>+*%-]$/ \
        && before !~ /(^|[^A-Za-z0-9_])(return|case|in|try|await|throw|if|guard|while|where|switch)$/) return 0
    parens = 0
    brackets = 0
    for (j = i + 1; j <= n; j++) {
        ch = substr(line, j, 1)
        if (ch == "\\") j++
        else if (ch == "[") {
            brackets++
            if (substr(line, j + 1, 1) == "^") j++
            if (substr(line, j + 1, 1) == "]") j++
        }
        else if (brackets > 0) { if (ch == "]") brackets-- }
        else if (ch == "(") parens++
        else if (ch == ")" && --parens < 0) return 0
        else if (ch == "]") return 0
        else if (ch == "/") return j + 1
    }
    return 0
}

FNR == 1 { mode = "code"; depth = 0; frames = 0 }

{
    line = $0
    code = line
    n = length(line)
    counted = (mode == "block")
    opened = 1
    i = 1
    while (i <= n) {
        two = substr(line, i, 2)
        c = substr(line, i, 1)
        if (mode == "block") {
            if (two == "/*") { depth++; i += 2 }
            else if (two == "*/") {
                depth--
                i += 2
                if (depth == 0) {
                    mode = "code"
                    blank = substr(code, opened, i - opened)
                    gsub(/./, " ", blank)
                    code = substr(code, 1, opened - 1) blank substr(code, i)
                }
            }
            else i++
        } else if (mode == "regex") {
            if (c == "\\") i += 2
            else if (substr(line, i, length(close_with)) == close_with) { mode = "code"; i += length(close_with) }
            else i++
        } else if (mode == "string") {
            if (substr(line, i, length(escape)) == escape) {
                i += length(escape)
                if (substr(line, i, 1) == "(") {
                    frames++
                    parens[frames] = 1
                    saved_close[frames] = close_with
                    saved_escape[frames] = escape
                    mode = "code"
                }
                i++
            } else if (substr(line, i, length(close_with)) == close_with) { mode = "code"; i += length(close_with) }
            else i++
        } else if (two == "//") {
            if (!directive(substr(line, i + 2))) counted = 1
            i = n + 1
        } else if (two == "/*") { mode = "block"; depth = 1; counted = 1; opened = i; i += 2 }
        else if (c == "/" && (end = bare_regex(i))) i = end
        else if (c == "\"") i = open(i)
        else if (c == "#") {
            after = substr(line, i + run(line, i, "#"), 1)
            i = (after == "\"" || after == "/") ? open(i) : i + run(line, i, "#")
        }
        else {
            if (frames > 0 && c == "(") parens[frames]++
            if (frames > 0 && c == ")") {
                parens[frames]--
                if (parens[frames] == 0) {
                    mode = "string"
                    close_with = saved_close[frames]
                    escape = saved_escape[frames]
                    frames--
                }
            }
            i++
        }
    }
    if (counted) print FILENAME "\t" FNR
}
