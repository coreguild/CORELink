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

# The upload believes a file id in CurseForge's answer and nothing else: a redirect or a page with a 2xx/3xx
# status (what a wrong endpoint path answers) must fail. curl and gh are stand-ins here; no network.
box=$(mktemp -d); trap 'rm -rf "$box"' EXIT
mkdir -p "$box/bin" "$box/scripts" "$box/dist"
cp scripts/curseforge-upload.sh "$box/scripts/"
printf 'v9.9.9\n' > "$box/dist/TAG"; printf 'zip' > "$box/dist/CORELink-9.9.9.zip"
cat > "$box/bin/curl" <<'STUB'
#!/usr/bin/env bash
out=""; url=""
while [ $# -gt 0 ]; do case "$1" in -o) out=$2; shift ;; -w|-m|-H|-F) shift ;; -*) ;; *) url=$1 ;; esac; shift; done
case "$url" in
  */game/versions) [ "$FAKE_VERSIONS" = page ] && { printf '<html>login</html>' > "$out"; printf 200; exit 0; }
                   printf '[{"id":17053,"name":"1.60.1"}]' > "$out"; printf 200 ;;
  */upload-file)   [ "$FAKE_STATUS" = exit28 ] && exit 28
                   printf '%s' "$FAKE_BODY" > "$out"; printf '%s' "$FAKE_STATUS" ;;
  *)               printf '<html>moved</html>' > "$out"; printf 302 ;;
esac
STUB
printf '#!/usr/bin/env bash\necho "notes"\n' > "$box/bin/gh"; chmod +x "$box/bin/curl" "$box/bin/gh"
upload() {   # upload <expected exit> <status> <body> <expected message>: run an upload against the stand-ins
  local want=$1 out got
  out=$(cd "$box" && PATH="$box/bin:$PATH" FAKE_STATUS=$2 FAKE_BODY=$3 FAKE_VERSIONS=${FAKE_VERSIONS:-} CURSEFORGE_API_KEY=fake \
        CURSEFORGE_PROJECT_ID=1 CURSEFORGE_GAME_VERSIONS=1.60.1 scripts/curseforge-upload.sh 2>&1); got=$?
  if [ "$got" -eq "$want" ] && printf '%s' "$out" | grep -q "$4"; then echo "PASS curseforge upload: HTTP $2 '$3' exits $want, says '$4'"
  else echo "FAIL curseforge upload: HTTP $2 '$3' exits $got, expected $want saying '$4':"; printf '%s\n' "$out" | tail -3; fail=1; fi
}
upload 0 200 '{"id":42}'            'uploaded dist/CORELink-9.9.9.zip as file 42'
upload 0 201 '{"id":43}'            'as file 43'
upload 2 302 '<html>moved</html>'   'HTTP 302 (000 = no answer). The file may still have landed'
upload 2 200 '<html>ok</html>'      'no file id in the answer; nothing is listed'
upload 2 400 '{"errorMessage":"x"}' 'HTTP 400; nothing is listed'
upload 2 400 '<html>x-api-token: fake</html>' 'the answer was not JSON'
upload 2 400 '{"errorMessage":"API token is malformed. Token provided: fake."}' 'Token provided: <key>'
# whatever the answer, the key (fake here) never reaches the output
for body in '<html>x-api-token: fake</html>' '{"errorMessage":"Token provided: fake."}' '{"id":"fake"}'; do
  out=$(cd "$box" && PATH="$box/bin:$PATH" FAKE_STATUS=400 FAKE_BODY=$body FAKE_VERSIONS= CURSEFORGE_API_KEY=fake \
        CURSEFORGE_PROJECT_ID=1 CURSEFORGE_GAME_VERSIONS=1.60.1 scripts/curseforge-upload.sh 2>&1) || true
  if printf '%s' "$out" | grep -q fake; then echo "FAIL curseforge upload: the key reached the output for '$body'"; fail=1
  else echo "PASS curseforge upload: the key stays out of the output for '$body'"; fi
done
upload 2 exit28 ''                  'HTTP 000 (000 = no answer)'
FAKE_VERSIONS=page upload 2 200 '{"id":1}' 'could not list game versions (HTTP 200'
exit $fail
