# Architecture

How the code is organised and how one line travels through it. Read this before changing anything in
`CORELink/`.

## What the game allows, and the design that follows

Measured on live WoW: Forever on 2026-11-08:

| The game | So CORELink |
|---|---|
| A custom chat channel is shared by every realm, and its text is readable by addons | uses one hidden channel as the broadcast path, with no realm bookkeeping |
| Addon messages on a custom channel are refused by the server | never sends addon messages on the channel |
| Chat text can be sent only from inside the player's own keypress | posts a player's own lines from the chat send hooks, and nothing else |
| Guild addon messages reach guildmates on every realm | uses them for presence, nicknames, and fanning out a line a 0.2.0 client carried to us |
| A whisper addon message to a player who logged off prints "No player named ..." on the sender's screen | sends no whispers from 0.2.1; 0.2.0 carried lines with them, and those are still read |
| Community text reaches addons sealed | mirrors into the community for humans to read, and shows posts by channel name |

One transport out:

1. **An addon user's own line** goes into the hidden channel as packed text from the chat send hooks, inside
   their keypress. Every addon user in every guild reads it.
2. **A line from a member without the addon** is not bridged. Nobody else's client can post it into the
   channel, and from 0.2.1 the addon sends no whispers. Everyone who takes part needs the addon.

One more path in, for as long as some guild runs 0.2.0: that version's courier whispers a line from a member
without the addon to one peer in each other guild. A 0.2.1 client that receives one shows it and fans it out
to its guildmates over the guild addon channel.

## The files

The game loads the files in the order the TOC lists them. Every file begins with `local _, NS = ...`: the game
hands each file the same private table, and a file puts on it whatever later files need. A file copies off
`NS` at load time only what earlier files defined (`tests/load-order.lua` checks it); anything else it reaches
as `NS.Name()` when called.

| File | What it owns |
|---|---|
| `Core.lua` | Constants, the shared tables (`seen`, `heard`, the registries), small helpers (`Print`, `Debug`, `Hash`, `Truncate`, `IsMe`, `GetTag`, `RankNickPrefix`). |
| `Channel.lua` | The hidden chat channel: join, hide, notices and refusals, `SendChannelText`. Owns `NS.conn`. |
| `Club.lua` | The Blizzard Community: resolving the `club=` token, its channels, keeping them subscribed, post authors. Owns `NS.club`. |
| `GuildInfo.lua` | The `CORELink:` line in Guild Info: parse it, build it, clear it when a guild has none, the copy box. |
| `Roster.lua` | Our guild's members: ranks, our own full name, nicknames, presence, the guild addon channel dispatcher. Owns `NS.addonUsers`. |
| `Echo.lua` | Re-posting linked guilds' lines into plain guild chat for members without the addon (ECHO claims). |
| `Display.lua` | Drawing another guild's line in guild chat; the dedupe between relay and community copies; the officer colour filter. |
| `Whisper.lua` | Reading what 0.2.0 clients whisper: peers, the `WB` handler and its fan-out, the whisper packet dispatcher. Sends no whisper. Owns `NS.peers`. |
| `Relay.lua` | Our own typed line out as channel text, every packet in (`ShowPacket`), reading a guildmate's LINE fan-out. |
| `Mirror.lua` | Posting typed guild lines into the community and showing its posts in guild chat. Owns `NS.mirror`. |
| `Hooks.lua` | The chat send hooks, the one place the addon runs inside the player's keypress. |
| `Events.lua` | The event frame, saved variables, login, message dispatch, the housekeeping ticker, `StatusLine`. |
| `Report.lua` | `/cl report`, `/cl guilds`, `/cl peers`. |
| `Commands.lua` | Every other `/cl` command, one function each, the dispatcher, the help line built from the command table. |

Limits, enforced by `tests/run.sh`: a file is at most 400 lines, a function at most 40, a line at most 120.
A function does one thing its name states and fits on a screen.

## Registries

Four tables on `NS` let a file add behaviour without the file that dispatches knowing about it:

| Registry | Filled by | Read by |
|---|---|---|
| `NS.events[event]` | any file, before or after `Events.lua` loads | `Events.lua` registers each key with the game as it is set and calls the handler |
| `NS.guildPackets[cmd]` | `Roster`, `Echo`, `Relay` | `Roster.lua` when a GUILD addon message arrives |
| `NS.whisperPackets[cmd]` | `Whisper` | `Whisper.lua` when a WHISPER addon message arrives |
| `NS.commands[name]` | `Commands`, `Report` | the `/cl` dispatcher in `Commands.lua`; the help line is built from the keys |

To add a `/cl` command, add `NS.commands.name = function(arg) ... end`. To handle a new packet on the guild
addon channel, add `NS.guildPackets.NAME = function(rest, sender) ... end`. To listen for a game event, add
`NS.events.EVENT_NAME = function(...) ... end`. Nothing else changes.

## Shared state

Defined in `Core.lua`, used everywhere:

| Table | Key -> value | Why |
|---|---|---|
| `NS.db` | the saved variables (`CORELinkDB`, per character) | settings, nicknames, mutes, saved peers; nil until ADDON_LOADED |
| `NS.seen` | packet id -> time | a line already relayed or read: do not do it again |
| `NS.displayed` | packet id -> time | already shown in guild chat |
| `NS.heard` | guild tag -> time | guilds whose lines reached us in the last 10 minutes, by any path |
| `NS.authorClass`, `authorOfficer`, `authorNick`, `authorSeen` | author -> what packets told us | community posts carry none of it |

Each feature file owns its own state and exposes it for `/cl report`: `NS.conn` (channel diagnostics),
`NS.club` (stream state), `NS.mirror` (mirror counters and hooks), `NS.peers`, `NS.addonUsers` (guildmates
seen running the addon), `NS.relayStats`, `NS.whisperStats`, `NS.echoStats`.

## The life of a line

A member of guild MAIN types "hello" in guild chat.

**If the author runs the addon:**

1. **`Hooks.lua`** sees the send inside the author's keypress and calls `Relay.lua`, `RelayTyped`.
2. **`RelayTyped`** hashes the tag, author and text into an id, packs `CL4~id~MAIN~Author~CLASS~flags~nick~hello`,
   and `Channel.lua`, `SendChannelText` posts it into the hidden channel as text. One send, every realm.
3. **`Events.lua`, `CHAT_MSG_CHANNEL`** on every addon user's client hands the text to `Relay.lua`,
   `OnLinkMessage`, which calls `ShowPacket`. MAIN clients note the author as an addon user and show nothing,
   since they saw the line natively. Other guilds' clients note the author as a live peer of MAIN and show
   `[MAIN] [Author]: (Rank Nick) hello` in every chat window with Guild chat, class and officer coloured
   (`Display.lua`), unless the same author was just shown from the community (`CrossSeen`).
4. **`Echo.lua`, `MaybeEcho`**: with `echo=on`, one client in each receiving guild claims the id over the guild
   addon channel (ECHO) and re-posts the line as real guild chat for members without the addon.
5. **`Mirror.lua`** also posts the typed line into the community from the same keypress.

**If the author does not run the addon:**

1. Every MAIN client sees the line natively (`CHAT_MSG_GUILD`, `Relay.lua`, `OnGuildMessage`). A 0.2.1
   client does nothing with it: the line stays in MAIN.
2. **A 0.2.0 client** that is MAIN's courier (the alphabetically first MAIN member it has seen running the
   addon, any version, in the last six minutes) waits a short back-off and, if no copy of the line appeared on
   the channel, whispers `WB~<packet>` to the freshest live peer of every other guild. When that first member
   runs 0.2.1, no MAIN client carries.
3. **The peer** (`whisperPackets.WB`) accepts it if the sender is a known peer or the guild has been heard on
   the channel, shows it with `ShowPacket`, and sends `LINE~<packet>` once to its own guild over the guild addon
   channel. Every guildmate's client shows it (`guildPackets.LINE`). Nothing is carried onward.

## Packets

Addon messages carry the prefix `CORELink`; fields are separated by `~`.

| Where | Packet | Meaning |
|---|---|---|
| hidden channel, as text | `CL4~id~tag~author~class~flags~nick~text` | an addon user's own guild line (`flags` = `O<rank>` for officers) |
| guild | `PRESENT~version` | I run the addon (0.2.0 elects its courier from it); every two minutes and at login |
| guild | `NICK~name`, `NREQ` | nickname, request for nicknames |
| guild | `LINE~<CL4 packet>` | a line carried to us by a 0.2.0 client, fanned out to guildmates |
| guild | `ECHO~id` | this client is echoing that line |
| whisper, read only | `WB~<CL4 packet>` | a line carried by a 0.2.0 courier: shown and fanned out |
| whisper, ignored | `HELLO~tag~realm~guild`, `PEER~tag~realm~guild` | 0.2.0's greeting and answer between addon users of different guilds |
| whisper, ignored | `DIR~name@realm@tag@guild;...` | 0.2.0's gossip: peers worth greeting |

From 0.2.1 the addon sends none of the four whisper packets. 0.2.0 clients still send all four.

These formats cannot change while a release that reads them is still supported: see the next section.

## Frozen formats

0.2.0 is released and those clients will never change. What they read and write is frozen:

* the addon message prefix `CORELink`;
* the channel line `CL4~id~tag~author~class~flags~nick~text`: exactly `CL4`, seven fields, text takes the rest.
  0.2.0 drops any other version, so a `CL5` line is a line 0.2.0 players never see;
* the line id, `NS.Hash(tag .. author .. msg)`: both sides must compute the same id or duplicates get through;
* the whisper packets `HELLO~tag~realm~guild`, `PEER~tag~realm~guild`, `DIR~name@realm@tag@guild;...`, `WB~<packet>`.
  From 0.2.1 the addon no longer sends any of them. It still reads `WB`, and it drops `HELLO`, `PEER` and `DIR`
  without an answer. 0.2.0 clients still send all four, so the formats stay frozen;
* the guild packets `PRESENT~version`, `NICK~name`, `NREQ`, `LINE~<packet>`, `ECHO~id`;
* the echoed guild chat line `[TAG] Name (Rank Nick): text`: 0.2.0 recognises an echo by `[TAG] ...: ` at the
  start, to hide it and to keep its courier from carrying it back out;
* the Guild Info line `CORELink: <channel> <password|-> [tag|-] [officerRank] [club=..] [echo=on] [guilds=a, b]`.
  From 0.2.1 `guilds=` is parsed and written back by `/cl publish` but does nothing;
* the saved variables `CORELinkDB` as 0.2.0 wrote them.

New data never goes inside an existing format. It travels in:

* a new packet kind whose name is letters only and does not start with an existing kind's name. 0.2.0 reads
  the leading letters as the kind and ignores a kind it does not know, but it reads `NICK2~x` as `NICK` with
  the name `2x`;
* a new `key=value` field on the Guild Info line, after the four positional fields (`-` for no tag, then the
  officer rank) and before `guilds=`. 0.2.0 takes the third and fourth words as tag and rank whatever they are:
  it reads `CORELink: chan pw echo=on` as the tag `echo=on`. `/cl publish` always writes all four.

`tests/compat.sh` holds this: it loads the addon from the baseline tag and from the working tree into fake
clients, two guilds with one of each, and passes lines, greetings, settings and saved variables between them.
It also holds that the working copy sends no whisper in any of its scenarios.
The baseline (`BASELINE` in that script, `v0.2.0`) is the oldest release that must keep working, not the
previous release. Changing a frozen format means dropping that release: a decision for a human, made by
raising `BASELINE`.

## Peers

A peer is an addon user of another guild. A client learns one from the author of a line on the channel
(`NS.NotePeer`). Peers are saved in `CORELinkDB.peers` and forgotten a week after they were last heard; peers
saved by 0.2.0 load as they are. From 0.2.1 the peer table has one use: a `WB` is accepted when its sender is
a known peer, or when its guild tag was heard in the last ten minutes. `/cl peers` lists the table.

0.2.0 also elected a courier per guild, greeted players (HELLO, PEER), passed peers on (DIR) and, with
`guilds=` on the Guild Info line, ran `/who` queries to find them. 0.2.1 removed all of that with the whispers.

## Things the game will not let us do

Collected in `agents/wow-api-gotchas.md`. The ones that shape this design: addons cannot write Guild Info;
chat text needs a keypress and addon packets are refused on channels; a whisper to a player who logged off
prints an error on the sender's screen; community sends work only inside a
keypress and community text arrives sealed; chat is paused in instanced lockdown.
