#!/usr/bin/env bash
# scripts/curseforge-upload.sh must refuse bad arguments and must not pass silently when a deliberate check or
# upload has no key: those exits are what turn the Actions buttons red. Nothing here talks to CurseForge.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
expect() {   # expect <exit code> <args...>: run the script without a key and compare the exit code
  local want=$1; shift
  local got; env -u CURSEFORGE_API_KEY -u CURSEFORGE_PROJECT_ID scripts/curseforge-upload.sh "$@" > /dev/null 2>&1; got=$?
  if [ "$got" -eq "$want" ]; then echo "PASS curseforge args: '$*' exits $want"
  else echo "FAIL curseforge args: '$*' exits $got, expected $want"; fail=1; fi
}
expect 0                              # a release run without the key skips quietly
expect 0 --dry-run
expect 2 --check                      # a deliberate check without the key goes red
expect 2 --tag v0.2.0                 # so does a deliberate upload
expect 2 --tag v0.2.1-rc1 --dry-run
expect 2 --tag                        # no value
expect 2 --tag nope                   # not a release tag
expect 2 --tag 'v0.2.0; rm -rf /'     # nothing but a tag gets through
expect 2 --check --tag v0.2.0         # one or the other
expect 2 --bogus
exit $fail
