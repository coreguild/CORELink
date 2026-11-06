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
| `scripts/package.sh` | Builds `dist/CORELink-<version>.zip`, stamping `VERSION` (default `dev`) into the TOCs, after running tests. |
| `scripts/release.sh` | `rc` / `final` / `site`: tags, GitHub pre-release or release, and the public download page on `gh-pages`. Run by the **release** workflow button in the Actions tab, or locally. |
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
2. Put the `CORELink` folder in `World of Warcraft/_forever_/Interface/AddOns/`.
3. Log in. If your Guild Information contains a `CORELink:` line, you are done.

## Quick start (guild master, once per guild)

```
/cl setup <channel> <password> [tag]      e.g.  /cl setup CORELink7100 pw1 MAIN
```

A copy box shows the Guild Info line. Paste it into Guild Information and save.
Every co-guild uses the same channel and password and a different tag.
Members pick the settings up automatically within a minute of logging in.

Guild Info line format: `CORELink: <channel> <password|-> [tag|-] [officerRankCutoff] [club=<community>] [echo=on] [guilds=<name>, <name>]`
(`guilds=` must be last; names may contain spaces.)

To mirror chat into a Blizzard Community: create a **World of Warcraft community** (not a Battle.net one; those
show account names instead of characters and are the only kind that crosses factions), give it a short name that
no other community of yours uses, append `club=<short name>` (or the full name without spaces, e.g.
`club=CoreTest2`, or the numeric id) to every co-guild's line, and share the invite link. Then add one channel to
the community per guild, named after that guild's tag, with `CORELink` in the channel description (Settings >
Add Channel). Other channels of the community are left alone. Members read linked guilds in their guild chat;
they do not need the community in a chat tab.

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
| `/cl guilds` | all | Which guild tags were heard on the link in the last 10 minutes, and on which realms (yours, plus what your guildmates on other realms hear). Flags guilds not reaching your realm. |
| `/cl nickname <name>` or `clear` | all | Your nickname, shown to your guild and linked guilds. |
| `/cl nicknames on/off`, `/cl classcolor on/off`, `/cl officer on/off` | all | Display toggles (this client only). |
| `/cl officercolor [RRGGBB|reset]` | all | Officer text colour; no argument opens the colour picker. |
| `/cl window <n>` | all | Force bridged lines into chat window n; no argument = windows with Guild chat. |
| `/cl mirror on/off`, `read off`, `post off`, `hide off` | all | Post your typed guild lines into the community named by `club=`, and show the community's lines in guild chat. Default both on. `hide off` shows the raw community channel lines again if you keep the community in a chat tab. |
| `/cl whisper on/off` | all | Whether this client takes part in the whisper bridge (courier duty and relaying whispered lines). Default on. |
| `/cl who` | all | Run the directory round now: ask who is online in each guild of `guilds=` and greet new names. Only the courier queries. |
| `/cl peers` | all | List known peers (other guilds' addon users), their realm, guild, and whether they answered. |
| `/cl hello <First Surname-Realm>` | all | Greet one addon user of another guild directly. Seeds a peer when `/who` cannot see their realm, and is the smallest test of whispers crossing realms: they appear in `/cl peers` once they answer. |
| `/cl echo on/off` | all | Whether this client may be the one that re-posts other guilds' lines into real guild chat (needs `echo=on` on the Guild Info line). Default on. |
| `/cl bridge on/off` | all | Whether this client forwards other guilds' lines to guildmates on other realms and re-sends forwards into its realm. Default on. |
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
* **Realms.** Custom channels are per realm. Guild chat crosses realms, the relay channel does not, so a guild's
  lines reach a realm only while that guild has an addon user online on that realm. Clients tell their guild
  (over the guild addon channel, which does cross realms) which guilds they hear on their realm; `/cl guilds`
  merges that and warns when a linked guild has no relay on yours.
* **Community mirror (optional).** If the Guild Info line carries `club=<community>`, each addon user's own
  guild lines are also posted into that Blizzard Community from inside the keypress that sent them (community
  sends are refused from timers and event handlers, so relayed lines cannot be mirrored). In a World of Warcraft
  community the post is `[TAG] text`, since the community shows the character as the author; in a Battle.net
  community it is `[TAG] Name (nick): text`, since that kind shows account names. Both the chat edit box and
  `SendChatMessage` are hooked, so `/g text`, macros and other addons' guild sends are mirrored too. Everyone,
  with or without the addon, can also read the community in a chat tab; it crosses realms and keeps history.
  An officer's post carries their rank and nickname in the text, `(Rank Nick) text`, so every reader sees it.
  Each guild posts into the community channel named after its tag, so readers get the tag from the channel and
  the character from the member record, and lines from other guilds show in your guild chat windows as
  `[TAG] [Character Name]: (Rank Nick) text`, the same shape as relayed lines, with the class colour from the
  member record and the officer colour from the relay when this character has been heard there, otherwise from
  the community role (make your officers Moderators of the community to get the colour across realms). A guild
  without a channel of its own posts `[TAG] (Rank Nick) text` into General and shows as
  `[Character Name]: [TAG] (Rank Nick) text`. The game hands addons community text as a sealed value it can draw but not read,
  so your own guild's posts are recognised by the author's guild roster entry, and a line that also arrived on
  the relay channel is dropped when the same author was shown there within five seconds. The raw community
  channel copy is hidden so nothing reads twice, and the community stream is loaded before every post and
  reloaded after a community error, since posting fails until it is loaded.
  `/cl mirror off` opts a client out; `/cl mirror read off`, `post off` or `hide off` for one piece.
* **Guild-chat echo (optional, per guild).** With `echo=on` on the Guild Info line, one addon user re-posts each
  other-guild line that arrived readable (relay or bridge; community text cannot be read) as a real guild message,
  `[TAG] Name (Rank Nick): text`, so members without the addon see linked guilds in plain guild chat. The first
  client to claim a line over the guild addon channel posts it, after the same random back-off as the relay.
  Addon users hide the echoed copy (they already saw the coloured line) and never relay, carry or mirror it.
  Echoed lines count as real guild chat for everyone: logs, mobile apps and other addons see them.
* **Whisper bridge (optional, per guild).** For guilds that share no realm with yours, so neither the relay
  channel nor the guild bridge can reach them. `guilds=Trois Royaume, Deux` on the Guild Info line names the
  collective. On each realm your guild's courier (the alphabetically first guildmate running the addon there; every
  client computes the same answer) asks the server who is online in each listed guild, learns which realms they
  are on, greets a few of them over whisper addon messages, and keeps the ones that answer as peers. A player
  without the addon never answers and is skipped. Peers share their peer lists, so one good contact teaches the
  rest, and peers are saved between sessions. When a line is heard on your realm, the courier whispers it to one
  peer on every realm that nothing else reaches (no addon user of the origin guild there, no guildmate of yours
  there); that peer drops it into its own realm's channel, where it shows like any relayed line, readable, with
  colours, and eligible for the echo. Nothing needs a keypress. `/cl guilds` lists each guild's online members
  per realm from the last round; `/cl peers` lists peers; `/cl who` runs a round now; `/cl hello <name>` greets one
  player by hand when the directory cannot find them.
* **Cross-realm bridge.** A client that hears another guild's line on its realm forwards it to its own guild over
  the guild addon channel (which crosses realms); a guildmate on another realm re-sends it into that realm's
  channel if it has not arrived there. Any guild with addon users on two realms therefore bridges every linked
  guild across them. Loops and duplicates are prevented by the per-message id memory and the same short random
  wait the relay uses. `/cl bridge off` opts a client out.

## Troubleshooting

| Symptom | Cause | What to do |
|---|---|---|
| We only see guild X when player Y is online | Y is the only member of X with the addon on your realm | X needs an addon user online on your realm; `/cl guilds` shows `NOT reaching <realm>` |
| Two players can't see each other even in a plain `/join test` channel | They are on different realms (`/run print(GetRealmName())`) | Expected; see Realms above |
| Lines from one guild never arrive | `/cl report` on the receiving client: `reach` shows which realms each guild is heard on | Fix realm coverage; if the guild is heard on your realm and still not shown, share the report |
| "could not join ...: wrong channel password" | Guild Info line differs from the other guilds' | GM re-publishes with `/cl publish`, members `/cl reload` |
| Nickname or officer tag missing on your own lines | Older build on WoW: Forever surnames | Update to 0.1.1 or later |

Protocols CL1-CL3 from earlier test builds are still accepted on receive.

## How a change gets to players

Branch, pull request, CI, merge, then two buttons: release candidate, release. Nobody edits a version
number or a changelog; the release button computes the version from the existing tags and builds the notes from
the commits merged since the last release.

```
feat/x ──PR──▶ main ──[release: rc]──▶ v0.2.0-rc1 (pre-release, rc/CORELink.zip)
                 │                          │ testers run it for a day
                 │                          ▼
                 └──[release: final]──▶ v0.2.0 (latest, latest/CORELink.zip)
```

1. **Branch.** `git switch -c feat/<name> main` (`fix/`, `docs/`, `chore/` for other kinds). One change per branch.
   Commit subjects use Conventional Commits (`feat(scope): ...`, `fix: ...`); the changelog is generated from them
   and grouped into Features, Bug Fixes and so on, each line linking its commit. See `CONTRIBUTING.md`.

2. **Pull request into `main`.** The template asks for feature notes (player-facing behaviour, commands, Guild Info
   and wire-protocol impact) and how it was tested. CI runs two required checks on every PR:
   * `tests`: `luac -p`, `luacheck` against the WoW globals in `.luacheckrc`, the mock-API harness in
     `tests/harness.lua`, the TOCs still carry `@project-version@`, and a build stamps a version correctly.
   * `game-version`: `scripts/check-game-version.sh` fetches the live client build from
     `https://us.version.battle.net/<product>/versions` (product in `tests/game-product.txt`), derives the interface
     number (`1.60.1` -> `16001`) and fails if either TOC's `## Interface:` lacks it. It also runs every 6 hours and
     opens an issue when a game patch moves ahead of us.
   The `protect-main` ruleset blocks merging until both are green and the branch is up to date with `main`. No
   approval is required; the gameplay-impact review in `agents/review-checklist.md` is posted as a comment.

3. **Merge.** A person clicks the button; agents never merge. Merge commits are the only method enabled, so the
   branch's full history lands on `main`; the branch is deleted automatically.

4. **Release candidate.** GitHub -> Actions -> **release** -> **Run workflow** -> `rc`. The job checks out `main`,
   re-runs the checks, works out the version (`bump` = `auto`: continue an open candidate series as `rcN+1`,
   otherwise patch-bump the last release and start `rc1`; choose `minor` or `major` to start a bigger version),
   stamps it into the TOCs inside the zip, creates tag `v<ver>-rcN`, publishes a GitHub pre-release whose body is the
   changelog section for that tag (commits since the previous rc or release, grouped by type), and pushes
   `rc/CORELink.zip`, `v/CORELink-<ver>.zip`, `notes/<tag>.md`, an updated `CHANGELOG.md` and the re-rendered
   page, which shows the same section under each channel, to the `gh-pages` branch. GitHub Pages serves that branch publicly at
   https://core-wow-community.github.io/CORELink/ even though the source is private. Testers run the RC for a day
   on two clients in two guilds, with one client left on the previous stable to prove the protocol still
   interoperates. Fixes go through normal PRs; press `rc` again for `rcN+1`.

5. **Release.** The same button with `final`. It refuses unless an rc tag points at the current `main` (the
   `no_rc` box exists for a small hotfix that touches neither the relay path nor the protocol). It tags `v<ver>`,
   publishes the GitHub release as latest with the same zip, and updates `latest/CORELink.zip` and the page.
   Everyone in every linked guild should run the same version.

Permanent download URLs: `latest/CORELink.zip` (stable), `rc/CORELink.zip` (candidate), `v/CORELink-<ver>.zip`
(every build), `channels.json` (`{"stable","rc","updated"}` for bots). Only the release job writes to `gh-pages`.
`scripts/release.sh --dry-run rc` shows what the next press would do without doing it.

## Development

```
scripts/install-local.sh            # link CORELink/ into the Forever client (macOS default path), then /reload in game
tests/run.sh                        # syntax check + luacheck + mock harness (brew install lua luacheck)
scripts/package.sh                  # tests + dist/CORELink-<version>.zip
```

New here? Start with `ONBOARDING.md`. Read `CONTRIBUTING.md` for the branch and release workflow, and `agents/` if you are an AI agent (or using one).
