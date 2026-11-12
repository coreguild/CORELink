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
# status (what a wrong endpoint path answers) must fail. curl and gh are stand-ins here; no network. The stand-in
# curl keeps -F's rule that a ";" ends the value and refuses metadata that is no longer JSON, and the stand-in gh
# hands out release notes with a semicolon in them, as real notes have.
box=$(mktemp -d); trap 'rm -rf "$box"' EXIT
mkdir -p "$box/bin" "$box/scripts" "$box/dist"
cp scripts/curseforge-upload.sh "$box/scripts/"
printf 'v9.9.9\n' > "$box/dist/TAG"; printf 'zip' > "$box/dist/CORELink-9.9.9.zip"
cat > "$box/bin/curl" <<'STUB'
#!/usr/bin/env bash
out=""; url=""; meta=""
while [ $# -gt 0 ]; do case "$1" in
  -o) out=$2; shift ;;
  -F|--form-string)   # curl's rules: -F cuts a value at ";" unless the value comes from a file ("<file")
    if [ "${2#metadata=}" != "$2" ]; then
      meta=${2#metadata=}
      case "$meta" in '<'*) meta=$(cat "${meta#<}") ;; *) [ "$1" = -F ] && meta=${meta%%;*} ;; esac
    fi; shift ;;
  -w|-m|-H) shift ;; -*) ;; *) url=$1 ;; esac; shift; done
if [ -n "$meta" ]; then   # what CurseForge checks: the metadata parses, and the changelog is there
  err=$(printf '%s' "$meta" | python3 -c '
import json, sys
try: m = json.load(sys.stdin)
except Exception: print("Error in field `metadata`: Invalid JSON."); sys.exit()
if not m.get("changelog"): print("Error in field `changelog`: required.")' 2>/dev/null)
  [ -n "$err" ] && { printf '{"errorCode":1002,"errorMessage":"%s"}' "$err" > "$out"; printf 400; exit 0; }
fi
case "$url" in
  */game/versions) [ "$FAKE_VERSIONS" = page ] && { printf '<html>login</html>' > "$out"; printf 200; exit 0; }
                   printf '[{"id":17053,"name":"1.60.1"}]' > "$out"; printf 200 ;;
  */upload-file)   case "$FAKE_STATUS" in exit*) printf 000; exit "${FAKE_STATUS#exit}" ;; esac   # as curl: 000, then its exit code
                   printf '%s' "$FAKE_BODY" > "$out"; printf '%s' "$FAKE_STATUS" ;;
  *)               printf '<html>moved</html>' > "$out"; printf 302 ;;
esac
STUB
cat > "$box/bin/gh" <<'STUB'
#!/usr/bin/env bash
case "${FAKE_NOTES:-}" in
  empty) printf '\r\n' ;;                                          # a web-made release with no description
  long)  head -c 200000 /dev/zero | tr '\0' 'x'; echo ;;         # past one argument's limit on Linux
  *)     echo 'notes; with a semicolon, "quotes" and a backslash \' ;;
esac
STUB
chmod +x "$box/bin/curl" "$box/bin/gh"
upload() {   # upload <expected exit> <status> <body> <expected message>: run an upload against the stand-ins
  local want=$1 out got
  out=$(cd "$box" && PATH="$box/bin:$PATH" FAKE_STATUS=$2 FAKE_BODY=$3 FAKE_VERSIONS=${FAKE_VERSIONS:-} \
        FAKE_NOTES=${FAKE_NOTES:-} CURSEFORGE_API_KEY=fake \
        CURSEFORGE_PROJECT_ID=1 CURSEFORGE_GAME_VERSIONS=1.60.1 scripts/curseforge-upload.sh 2>&1); got=$?
  if [ "$got" -eq "$want" ] && printf '%s' "$out" | grep -q "$4"; then echo "PASS curseforge upload: HTTP $2 '$3' exits $want, says '$4'"
  else echo "FAIL curseforge upload: HTTP $2 '$3' exits $got, expected $want saying '$4':"; printf '%s\n' "$out" | tail -3; fail=1; fi
}
upload 0 200 '{"id":42}'            'uploaded dist/CORELink-9.9.9.zip as file 42'
upload 0 201 '{"id":43}'            'as file 43'
upload 2 302 '<html>moved</html>'   'HTTP 302. The file may still have landed'
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
upload 2 exit7  ''                  'could not connect to CurseForge (curl exit 7); nothing was sent'
upload 2 exit28 ''                  'no answer (curl exit 28). The file may still have landed'
upload 2 503 '<html>busy</html>'    'HTTP 503. The file may still have landed'
FAKE_NOTES=empty upload 0 200 '{"id":44}' 'as file 44'      # a release without notes still sends a changelog
FAKE_NOTES=long  upload 0 200 '{"id":45}' 'as file 45'      # notes longer than one argument may be
FAKE_VERSIONS=page upload 2 200 '{"id":1}' 'could not list game versions (HTTP 200'
exit $fail
