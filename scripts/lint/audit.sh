#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
scanner="${OSV_SCANNER:-osv-scanner}"
mkdir -p .build
report="$(mktemp "$PWD/.build/audit.XXXXXX")"
trap 'rm -f "$report"' EXIT

status=0
"$scanner" scan source --format json \
    -L Package.resolved \
    -L site/bun.lock \
    -L requirements.txt:scripts/release/dmg-requirements.txt >"$report" || status=$?
if [[ $status -ne 0 && $status -ne 1 ]]; then
    printf 'audit.sh: osv-scanner exited %d, so the audit did not run.\n' "$status" >&2
    exit 2
fi

high="$(jq -r '
  [.results[]?.packages[]? | . as $p | .groups[]?
    | . as $g
    | select(
        ((.max_severity // "") | tonumber? // 0) >= 7
        or any($p.vulnerabilities[]? | select(.id as $id | $g.ids | index($id));
          (.database_specific.severity // "" | ascii_upcase) | . == "HIGH" or . == "CRITICAL"))
    | "\($p.package.ecosystem) \($p.package.name) \($p.package.version): \($g.ids | join(", ")) (CVSS \($g.max_severity // "unknown"))"]
  | unique[]' "$report")"
if [[ -n "$high" ]]; then
    printf 'audit.sh: high or critical advisories:\n%s\n' "$high" >&2
    exit 1
fi
printf 'audit: no high or critical advisory\n'
