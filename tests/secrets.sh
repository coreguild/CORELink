#!/usr/bin/env bash
# Secrets stay out of logs: no script or workflow may trace itself, run curl verbosely, print a secret-bearing
# variable, or put the CurseForge key on a command line. The key reaches curl through a header file only.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0
bad() { echo "FAIL secrets: $1"; fail=1; }
files=$(ls scripts/*.sh .github/workflows/*.yml)
grep -nE '^\s*set -x|bash -x|sh -x' $files && bad "a script traces itself (set -x)" || true
grep -nE 'curl[^|]*\s-(v|-verbose|-trace)' $files && bad "curl runs verbosely" || true
grep -nE '(echo|printf|cat)[^|]*\$\{?CURSEFORGE_API_KEY' $files | grep -v "> \"\$HDR\"" && bad "a script prints the API key" || true
grep -nE -- '-H "x-api-token' $files && bad "the API key is on a curl command line" || true
grep -nE 'secrets\.' .github/workflows/*.yml | grep -vE 'CURSEFORGE_API_KEY: \$\{\{ secrets\.CURSEFORGE_API_KEY \}\}' && bad "a workflow uses a secret outside the CurseForge step env" || true
n=$(grep -c 'secrets.CURSEFORGE_API_KEY' .github/workflows/release.yml); [ "$n" -eq 1 ] || bad "the API key is wired into $n steps, expected 1"
[ $fail -eq 0 ] && echo "secrets ok: no tracing, no verbose curl, key only in a header file for one step"
exit $fail
