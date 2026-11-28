#!/bin/bash
set -euo pipefail
if [[ $# -ne 0 || -z "${GITHUB_TOKEN:-}" || -z "${GITHUB_ENV:-}" ]]; then
    printf 'Usage: GITHUB_TOKEN=<job token> bash scripts/git-auth.sh\nIn a GitHub Actions job, makes each later git call to https://github.com/ send the job token.\nSwiftPM clones then count against the token, not against the anonymous limit of the runner.\n' >&2
    exit 64
fi
credentials="$(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 | tr -d '\n')"
echo "::add-mask::$credentials"
{
    echo GIT_CONFIG_COUNT=1
    echo GIT_CONFIG_KEY_0=http.https://github.com/.extraheader
    echo "GIT_CONFIG_VALUE_0=AUTHORIZATION: basic $credentials"
} >>"$GITHUB_ENV"
