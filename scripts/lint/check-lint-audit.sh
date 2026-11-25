#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."

mkdir -p .build
scratch="$(mktemp -d "$PWD/.build/check-lint-audit.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT
failures=0

cat >"$scratch/osv-scanner" <<'EOF'
#!/bin/bash
cat "$STUB_REPORT"
exit "$STUB_STATUS"
EOF
chmod +x "$scratch/osv-scanner"

expect() {
    local want="$1" name="$2" status_from_scanner="$3" report="$4" output status=0
    printf '%s\n' "$report" >"$scratch/report.json"
    output="$(OSV_SCANNER="$scratch/osv-scanner" STUB_REPORT="$scratch/report.json" STUB_STATUS="$status_from_scanner" \
        bash scripts/lint/audit.sh 2>&1)" || status=$?
    if [[ "$status" -ne "$want" ]]; then
        printf 'FAIL %s: exit %s, expected %s. Audit output:\n%s\n' "$name" "$status" "$want" "$output"
        failures=$((failures + 1))
    fi
}

finding() {
    local max="$1" severity="$2"
    printf '{"results":[{"packages":[{"package":{"name":"pkg","version":"1.0.0","ecosystem":"PyPI"},"vulnerabilities":[{"id":"GHSA-xxxx-xxxx-xxxx","database_specific":%s}],"groups":[{"ids":["GHSA-xxxx-xxxx-xxxx"],"max_severity":"%s"}]}]}]}' "$severity" "$max"
}

expect 0 "no advisories" 0 '{"results":[]}'
expect 0 "a CVSS 6.9 advisory" 1 "$(finding 6.9 '{"severity":"MODERATE"}')"
expect 0 "a LOW advisory with no score" 1 "$(finding '' '{"severity":"LOW"}')"
expect 1 "a CVSS 7.0 advisory" 1 "$(finding 7.0 null)"
expect 1 "a CVSS 9.8 advisory" 1 "$(finding 9.8 null)"
expect 1 "a HIGH advisory with no score" 1 "$(finding '' '{"severity":"HIGH"}')"
expect 1 "a critical advisory in lower case" 1 "$(finding '' '{"severity":"critical"}')"
expect 2 "a scanner error" 127 '{}'
expect 2 "no packages found" 128 '{}'

if [[ "$failures" -gt 0 ]]; then
    printf 'check-lint-audit: %s cases failed\n' "$failures" >&2
    exit 1
fi
