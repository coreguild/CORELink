# CORELink

Bridges guild chat between co-guilds in World of Warcraft: Forever (GreenWall-style).
Members of linked guilds see each other's guild chat as `[TAG] [Name]: message`, with
class-coloured names, officer highlighting and optional nicknames.

Repository layout:

| Path | What it is |
|---|---|
| `CORELink/` | The addon. This folder is what goes into `Interface/AddOns/`. |
| `tests/` | Mock WoW API harness. `tests/run.sh` syntax-checks and runs it without the game. |
| `scripts/install-local.sh` | Symlinks the addon into your WoW client so edits are live after `/reload`. |
| `scripts/package.sh` | Builds `dist/CORELink-<version>.zip` from the TOC version, after running tests. |
| `scripts/release.sh` | `rc` / `final` / `site`: tags, GitHub pre-release or release, and the public download page on `gh-pages`. |
| `site/` | Template and stylesheet for the download page. Rendered by `scripts/release.sh`, never edited on `gh-pages` by hand. |
| `scripts/check-game-version.sh` | Compares the TOC `## Interface:` numbers with the live client version from Blizzard's version server. CI runs it on every PR and every 6 hours. |
| `agents/` | Rules for humans and AI agents working in this repo (branching, testing, WoW API gotchas). |
| `skills/` | Agent skills: step-by-step procedures for starting a branch, testing, installing and releasing. |

## Download

* Stable: https://core-wow-community.github.io/CORELink/latest/CORELink.zip
* Release candidate (guild leads testing the next version): https://core-wow-community.github.io/CORELink/rc/CORELink.zip
* Landing page with both and install steps: https://core-wow-community.github.io/CORELink/

## Quick start (players)

1. Download the stable zip above.
2. Put the `CORELink` folder in `World of Warcraft/_classic_beta_/Interface/AddOns/`.
3. Log in. If your Guild Information contains a `CORELink:` line, you are done.

## Quick start (guild master, once per guild)

```
/cl setup <channel> <password> [tag]      e.g.  /cl setup CORELink7100 pw1 MAIN
```

A copy box shows the Guild Info line. Paste it into Guild Information and save.
Every co-guild uses the same channel and password and a different tag.
Members pick the settings up automatically within a minute of logging in.

Guild Info line format: `CORELink: <channel> <password|-> [tag|-] [officerRankCutoff]`

## Commands

| Command | Who | Does |
|---|---|---|
| `/cl` | all | Status: on/off, tag, channel, joined, config source, last send result. |
| `/cl setup <channel> <password> [tag]` | GM | Configure and show the Guild Info line. |
| `/cl channel <name>`, `/cl password <pw>`, `/cl tag <tag>` | GM | Change one setting locally, then `/cl publish`. |
| `/cl publish` | GM | Show the Guild Info line again. |
| `/cl officerrank <n>` | GM | Ranks 0..n count as officers (0 = GM). Shared via the Guild Info line. |
| `/cl reload` | GM | Re-read Guild Info now. |
| `/cl clear`, `/cl on`, `/cl off` | GM | Clear settings, enable, disable. |
| `/cl mute <tag>`, `/cl unmute <tag>` | GM | Silence a linked guild. |
| `/cl guilds` | all | Which guild tags were heard on the link in the last 10 minutes. |
| `/cl nickname <name>` or `clear` | all | Your nickname, shown to your guild and linked guilds. |
| `/cl nicknames on/off`, `/cl classcolor on/off`, `/cl officer on/off` | all | Display toggles (this client only). |
| `/cl officercolor [RRGGBB|reset]` | all | Officer text colour; no argument opens the colour picker. |
| `/cl window <n>` | all | Force bridged lines into chat window n; no argument = windows with Guild chat. |
| `/cl report` | all | One pasteable line: version, channel and id, last send result, lockdown, queue, guilds heard, table sizes, and the last 20 debug events. Paste it when asking for help. |
| `/cl debug on/off` | all | Echo debug events to chat as they happen. Events are always kept for `/cl report`. |

## How it works

* Members' clients join a hidden custom channel named in Guild Info and remove it from all chat tabs.
* A guild message is packed as `CL4~id~tag~author~class~flags~nick~message` and sent on that channel.
  The author's own client relays immediately; others wait a random 0.3-1.5 s and relay only if nobody did, so
  members without the addon are bridged too.
* Receivers de-duplicate on the hash id, ignore their own guild tag, and print the line in every chat window
  that has Guild chat enabled.
* Nicknames travel over the guild addon-message channel (`NICK`, `NREQ`).
* In chat-messaging lockdown (instanced content on Midnight-era clients) relaying pauses.

Protocols CL1-CL3 from earlier test builds are still accepted on receive.

## How a change gets to players

The short version: edit on a branch, open a pull request, the robots check it, a human merges it, then a
release candidate goes to a few testers before everyone gets it.

1. **Nobody edits `main` directly.** You make a branch (`feat/my-idea`), change the addon, and open a pull request.
2. **The checks run.** GitHub runs the tests and confirms the addon still matches the current game client. A pull
   request cannot be merged until both are green. No reviewer sign-off is required, but the PR must say what players
   will see and how it was tested.
3. **Merge.** Whoever merges uses the squash button. `main` is now the next version, but nobody is running it yet.
4. **Release candidate.** `scripts/release.sh rc` tags it `v0.2.0-rc1`, publishes a GitHub pre-release, and puts the
   zip on the RC link: https://core-wow-community.github.io/CORELink/rc/CORELink.zip. Guild leads run it for a day
   on two clients in two guilds, with one person still on the old stable version to prove they can still talk.
   Problems go back to step 1, and the next candidate is `rc2`.
5. **Release.** `scripts/release.sh final` tags the same code `v0.2.0`, publishes it as the latest release, and moves
   the stable link to it: https://core-wow-community.github.io/CORELink/latest/CORELink.zip. Announce it to both
   guilds with the CHANGELOG entry. Everyone should run the same version.

The zip that testers ran in step 4 is byte for byte the one players get in step 5; only the tag changes.
Every build also stays available at `v/CORELink-<version>.zip` if someone needs to go back.

## Development

```
scripts/install-local.sh            # link CORELink/ into the beta client (macOS default path), then /reload in game
tests/run.sh                        # syntax check + luacheck + mock harness (brew install lua luacheck)
scripts/package.sh                  # tests + dist/CORELink-<version>.zip
```

New here? Start with `ONBOARDING.md`. Read `CONTRIBUTING.md` for the branch and release workflow, and `agents/` if you are an AI agent (or using one).
