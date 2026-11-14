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
| Guild addon messages reach guildmates on every realm | uses them for presence, nicknames, and fanning a carried line out to the guild |
| Whisper addon messages reach any player by plain `First Surname`, from a timer | uses them for lines nobody's keypress can post: the courier carries them |
| Community text reaches addons sealed | mirrors into the community for humans to read, and shows posts by channel name |

Two transports, chosen by who typed the line:

1. **An addon user's own line** goes into the hidden channel as packed text from the chat send hooks, inside
   their keypress. Every addon user in every guild reads it.
2. **A line from a member without the addon** is carried by the guild's courier: whispered to one peer in each
   other guild, who shows it and fans it out to their guildmates over the guild addon channel.

## The files

The game loads the files in the order the TOC lists them. Every file begins with `local _, NS = ...`: the game
hands each file the same private table, and a file puts on it whatever later files need. A file copies off
`NS` at load time only what earlier files defined (`tests/load-order.lua` checks it); anything else it reaches
as `NS.Name()` when called.

| File | What it owns |
|---|---|
| `Core.lua` | Constants, the shared tables (`seen`, `heard`, the whisper queue, the registries), small helpers (`Print`, `Debug`, `Hash`, `Truncate`, `IsMe`, `GetTag`, `RankNickPrefix`). |
| `Channel.lua` | The hidden chat channel: join, hide, notices and refusals, `SendChannelText`, the whisper queue drain. Owns `NS.conn`. |
| `Club.lua` | The Blizzard Community: resolving the `club=` token, its channels, keeping them subscribed, post authors. Owns `NS.club`. |
| `GuildInfo.lua` | The `CORELink:` line in Guild Info: parse it, build it, clear it when a guild has none, the copy box. |
| `Roster.lua` | Our guild's members: ranks, our own full name, nicknames, presence, the guild addon channel dispatcher. Owns `NS.addonUsers`. |
| `Echo.lua` | Re-posting linked guilds' lines into plain guild chat for members without the addon (ECHO claims). |
| `Display.lua` | Drawing another guild's line in guild chat; the dedupe between relay and community copies; the officer colour filter. |
| `Whisper.lua` | The courier election, peers, greetings, the optional who round, carrying lines (HELLO, PEER, DIR, WB). Owns `NS.peers`. |
| `Relay.lua` | Our own typed line out as channel text, the courier's carry of a guildmate's line, every packet in (`ShowPacket`), the LINE fan-out. |
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
| `NS.seen` | packet id -> time | a line already relayed, read, carried or fanned: do not do it again |
| `NS.pending` | packet id -> true | the courier's back-off is deciding whether to carry it |
| `NS.displayed` | packet id -> time | already shown in guild chat |
| `NS.heard` | guild tag -> time | guilds whose lines reached us in the last 10 minutes, by any path |
| `NS.whisperQueue` | whispers waiting | drained a few per second by `Channel.lua` |
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

1. Every MAIN client sees the line natively (`CHAT_MSG_GUILD`, `Relay.lua`, `OnGuildMessage`). Only the courier
   acts: the alphabetically first MAIN member seen running the addon in the last six minutes (`Whisper.lua`,
   `Courier`). It waits a short back-off, and if no copy of the line appeared on the channel meanwhile, packs it.
2. **`Whisper.lua`, `WhisperOut`** whispers `WB~<packet>` to the freshest live peer of every other guild.
3. **The peer** (`whisperPackets.WB`) accepts it if the sender is a known peer or the guild has been heard on
   the channel, shows it with `ShowPacket`, and sends `LINE~<packet>` once to its own guild over the guild addon
   channel. Every guildmate's client shows it (`guildPackets.LINE`). Nothing is carried onward.

## Packets

Addon messages carry the prefix `CORELink`; fields are separated by `~`.

| Where | Packet | Meaning |
|---|---|---|
| hidden channel, as text | `CL4~id~tag~author~class~flags~nick~text` | an addon user's own guild line (`flags` = `O<rank>` for officers) |
| guild | `PRESENT~version` | I run the addon (elects the courier); every two minutes and at login. A version newer than the reader's own produces the update notice |
| guild | `NICK~name`, `NREQ` | nickname, request for nicknames |
| guild | `LINE~<CL4 packet>` | a carried line fanned out to guildmates |
| guild | `ECHO~id` | this client is echoing that line |
| whisper | `HELLO~tag~realm~guild`, `PEER~tag~realm~guild` | greeting and answer between addon users of different guilds |
| whisper | `DIR~name@realm@tag@guild;...` | gossip: peers worth greeting |
| whisper | `WB~<CL4 packet>` | a carried line |

Changing the CL4 field order or separator is a protocol change: bump the version and keep old versions
readable.

## Peers and the courier

A peer is an addon user of another guild. Clients learn them from ordinary traffic: the author of every line
on the channel is one. A HELLO/PEER exchange adds one by hand (`/cl hello`), gossip (DIR) suggests more, and
with `guilds=` on the Guild Info line the courier runs a silent `/who` per listed guild and greets a few members,
for a guild nobody has heard from yet. Peers are saved between sessions; one that never answered is never
whispered to. The courier pings its peers every ten minutes to keep them fresh.

## Things the game will not let us do

Collected in `agents/wow-api-gotchas.md`. The ones that shape this design: addons cannot write Guild Info;
chat text needs a keypress and addon packets are refused on channels; community sends work only inside a
keypress and community text arrives sealed; chat is paused in instanced lockdown.
