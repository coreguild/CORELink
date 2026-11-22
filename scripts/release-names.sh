#!/usr/bin/env bash
# Names derived from a release tag. Sourced by scripts/release.sh and scripts/curseforge-upload.sh, and by
# tests/release-names.sh; it only defines functions.
#
# A build carries the version of its tag without the "v": v0.3.0 is stamped 0.3.0 and ships as
# CORELink-0.3.0.zip; the candidate v0.3.0-rc1 is stamped 0.3.0-rc1 and ships as CORELink-0.3.0-rc1.zip (#19).
# Candidates cut before that (up to v0.2.0-rc3) were stamped with the bare version, and their GitHub release
# asset is CORELink-0.2.0.zip: whoever fetches a candidate's asset tries both names, the current one first.

stamp_of() { printf '%s\n' "${1#v}"; }                       # v0.3.0-rc1 -> 0.3.0-rc1 ; v0.3.0 -> 0.3.0
asset_names() {                                              # the zip names a tag's release may carry, one a line
  local stamp=${1#v}
  printf 'CORELink-%s.zip\n' "$stamp"
  case "$stamp" in *-rc*) printf 'CORELink-%s.zip\n' "${stamp%-rc*}" ;; esac
}
asset_stamp() { local s=${1#CORELink-}; printf '%s\n' "${s%.zip}"; }   # CORELink-0.3.0-rc1.zip -> 0.3.0-rc1
fetch_asset() {   # fetch_asset <tag> <dir>: download the zip of the tag's GitHub release into <dir>, print its name
  local n
  for n in $(asset_names "$1"); do
    if gh release download "$1" --pattern "$n" --dir "$2" >/dev/null 2>&1 && [ -f "$2/$n" ]; then
      echo "$n"; return 0
    fi
  done
  return 1
}
