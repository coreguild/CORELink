# Architecture

How the code is organised and how one line travels through it. Read this before changing anything in
`CORELink/`.

## The files

The game loads the files in the order the TOC lists them. Every file begins with `local _, NS = ...`: the game
hands each file the same private table, and a file puts on it whatever later files need. A file may read from
`NS` at load time only what earlier files defined; anything else it looks up when the game delivers the event.

| File | Lines | What it owns |
|---|---|---|
| `Core.lua` | ~200 | Constants, the shared tables (`seen`, `heard`, queues, registries), small helpers (`Print`, `Debug`, `Hash`, `Trim`, `IsMe`, `GetTag`). |
| `Channel.lua` | ~150 | The hidden chat channel: join, hide, notices, the one-per-second sender for both queues, the presence beacon. |
| `GuildInfo.lua` | ~140 | The `CORELink:` line in Guild Info: parse it, build it, the copy box. |
| `Roster.lua` | ~150 | Our guild's members: ranks, officers, nicknames, the guild addon channel dispatcher, HEARD reports. |
| `Display.lua` | ~100 | Drawing another guild's line in guild chat; the dedupe between relay and community copies; the officer colour filter. |
| `Bridge.lua` | ~60 | Cross-realm bridge through our own guild (BRIDGE packets). |
| `Echo.lua` | ~50 | Re-posting linked guilds' lines into plain guild chat for members without the addon (ECHO claims). |
| `Whisper.lua` | ~280 | The whisper bridge: courier election, who rounds, greetings, peers, routing (HELLO, PEER, DIR, WB). |
| `Relay.lua` | ~115 | Guild lines out to the channel, channel packets in to guild chat. |
| `Club.lua` | ~190 | The Blizzard Community: resolving the `club=` token, its channels, keeping them subscribed, post authors. |
| `Mirror.lua` | ~220 | Posting typed guild lines into the community and showing its posts in guild chat. |
| `Events.lua` | ~135 | The event frame, saved variables, login, addon-message dispatch, the housekeeping ticker. |
| `Report.lua` | ~180 | `/cl report`, `/cl guilds`, `/cl peers`. |
| `Commands.lua` | ~250 | Every other `/cl` command, one function each, and the dispatcher. |

Limits, enforced by `tests/run.sh`: a file is under 400 lines, a function under 40, a line under 120.
A function does one thing its name states and fits on a screen.

## Registries

Four tables on `NS` let a file add behaviour without the file that dispatches knowing about it:

| Registry | Filled by | Read by |
|---|---|---|
| `NS.events[event]` | any file | `Events.lua` registers each key with the game and calls the handler |
| `NS.guildPackets[cmd]` | `Roster`, `Bridge`, `Echo` | `Roster.lua` when a GUILD addon message arrives |
| `NS.whisperPackets[cmd]` | `Whisper` | `Whisper.lua` when a WHISPER addon message arrives |
| `NS.commands[name]` | `Commands`, `Report` | the `/cl` dispatcher in `Commands.lua` |

To add a `/cl` command, add `NS.commands.name = function(arg) ... end`. To handle a new packet on the guild
addon channel, add `NS.guildPackets.NAME = function(rest, sender) ... end`. To listen for a game event, add
`NS.events.EVENT_NAME = function(...) ... end`. Nothing else changes.

## Shared state

Defined in `Core.lua`, used everywhere:

| Table | Key -> value | Why |
|---|---|---|
| `NS.db` | the saved variables (`CORELinkDB`) | settings, nicknames, mutes, saved peers; nil until ADDON_LOADED |
| `NS.seen` | packet id -> time | a packet already on our realm's channel: do not relay or re-send it |
| `NS.pending` | packet id -> true | a random back-off is deciding whether we relay it |
| `NS.displayed` | packet id -> time | already shown in guild chat |
| `NS.heard` | guild tag -> time | guilds heard on our realm in the last 10 minutes |
| `NS.heardRealms` | tag -> realm -> time | where each guild is heard, ours and what guildmates report |
| `NS.guildRealms` | realm -> time | realms our own guild has addon users on |
| `NS.sendQueue`, `NS.whisperQueue` | packets waiting | drained one per second by `Channel.lua` |
| `NS.authorClass`, `authorOfficer`, `authorNick`, `authorSeen` | author -> what relay packets told us | community posts carry none of it |

Each feature file owns its own state and exposes it for `/cl report`: `NS.conn` (channel diagnostics),
`NS.mirror`, `NS.peers`, `NS.bridgeStats`, `NS.echoStats`, `NS.whisperStats`, `NS.courierSeen`.

## The life of a line

A member of guild MAIN types "hello" in guild chat. On every MAIN client with the addon:

1. **`Relay.lua`, `OnGuildMessage`** (event `CHAT_MSG_GUILD`). The line is hashed with the tag and author into
   an id. The author's own client relays at once; every other client waits 0.3 to 1.5 seconds and relays only
   if `NS.seen[id]` is still empty. Relaying means queueing `CL4~id~MAIN~Author~CLASS~flags~nick~hello` in
   `NS.sendQueue`.
2. **`Channel.lua`, the sender ticker.** One packet per second goes out as an addon message on the hidden
   channel. Addon messages need no keypress.
3. **`Events.lua`, `CHAT_MSG_ADDON`.** On every client in the channel, on that realm, the packet arrives and is
   handed to `Relay.lua`, `OnLinkMessage`.
4. **`OnLinkMessage`** notes the id in `NS.seen` and the tag in `NS.heard`, then:
   * **`Bridge.lua`, `ForwardToGuild`**: if this client's guild has members on other realms, forward the packet
     to them over the guild addon channel (BRIDGE). A guildmate there re-sends it into their realm's channel
     after the same back-off, unless it already arrived (`OnBridgeReceived`).
   * **`Whisper.lua`, `WhisperOut`**: if this client is its guild's courier, whisper the packet (WB) to one
     known peer on every realm nothing else reaches. The peer re-sends it there, the same way.
   * If the tag is our own guild, or muted, stop.
   * **`Display.lua`, `Display`**: print `[MAIN] [Author]: (Rank Nick) hello` in every chat window with Guild
     chat, class and officer coloured, unless the same author was just shown from the community
     (`CrossSeen`).
   * **`Echo.lua`, `MaybeEcho`**: with `echo=on`, one client claims the id over the guild addon channel (ECHO)
     and re-posts the line as real guild chat for members without the addon. Addon users hide that copy.
5. **`Mirror.lua`** runs separately, inside the author's keypress: the chat send hooks post the typed line into
   the community named by `club=`. Other guilds' clients see community posts arrive (`CLUB_MESSAGE_ADDED`),
   read the tag from the channel name, and `Display` them, deduplicated against step 4 by author and time.

## Packets

All packets are addon messages with prefix `CORELink`, fields separated by `~`.

| Channel | Packet | Meaning |
|---|---|---|
| hidden channel | `CL4~id~tag~author~class~flags~nick~text` | a guild line (`flags` = `O<rank>` for officers; empty `text` = presence beacon) |
| guild | `HEARD~realm~tag1,tag2` | which guilds this guildmate hears on its realm (also elects the courier) |
| guild | `NICK~name`, `NREQ` | nickname, request for nicknames |
| guild | `BRIDGE~<CL4 packet>` | a foreign line for guildmates on other realms |
| guild | `ECHO~id` | this client is echoing that line |
| whisper | `HELLO~tag~realm~guild`, `PEER~tag~realm~guild` | greeting and answer between addon users of different guilds |
| whisper | `DIR~name@realm@tag@guild;...` | gossip: peers worth greeting |
| whisper | `WB~<CL4 packet>` | a line for a realm nothing else reaches |

Protocols CL1 to CL3 from earlier builds are still read. Changing the CL4 field order or separator is a
protocol change: bump the version and keep old versions readable.

## Realms

Custom channels are per realm; guild addon messages and whispers cross realms. On Forever a `First Surname` is
unique across realms, `/who` returns every realm's players but no realm names, and only a client knows its own
realm (`GetNormalizedRealmName`). So realms are learned from what clients say about themselves: HEARD reports
from guildmates, PEER answers from other guilds' addon users. Nothing reads a realm off a name.

## Things the game will not let us do

Collected in `agents/wow-api-gotchas.md`. The ones that shape this design: addons cannot write Guild Info;
chat on a custom channel needs a keypress but addon messages do not; community sends work only inside a
keypress; community text reaches addons sealed; chat is paused in instanced lockdown.
