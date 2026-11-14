# Commands and the Guild Info line

## The Guild Info line

```
CORELink: <channel> <password|-> [tag|-] [officerRankCutoff] [club=<community>] [echo=on] [guilds=<name>, <name>]
```

* `channel`, `password`: the hidden chat channel every co-guild shares. `-` for no password.
* `tag`: how this guild is labelled, up to 8 characters. `-` or nothing: the first six letters of the guild name.
* `officerRankCutoff`: ranks 0 to n count as officers (0 = guild master). Default 1.
* `club=`: a Blizzard Community to mirror into (see below).
* `echo=on`: one addon user re-posts other guilds' lines into plain guild chat for members without the addon.
* `guilds=`: the co-guilds by name, comma separated, always last on the line because names contain spaces.
  Optional: addon users of other guilds are found from their own lines on the channel; this list lets the courier
  look up a guild nobody has heard from yet. See [ARCHITECTURE.md](ARCHITECTURE.md).

`/cl setup` writes the line for you and `/cl publish` shows it again. Addons cannot write Guild Info, so the
guild master pastes it by hand. The line is at most 500 characters, which is far more than it needs.

### Mirroring into a community

Create a **World of Warcraft community** (not a Battle.net one; those show account names instead of characters
and are the only kind that crosses factions), give it a short name that no other community of yours uses, append
`club=<short name>` (or the full name without spaces, e.g. `club=CoreTest2`, or the numeric id) to every
co-guild's line, and share the invite link. Then add one channel to the community per guild, named after that
guild's tag, with `CORELink` in the channel description (Settings > Add Channel). Other channels of the community
are left alone. Members read linked guilds in their guild chat; they do not need the community in a chat tab.

## All commands

| Command | Who | Does |
|---|---|---|
| `/cl` | all | Status: on/off, tag, channel, joined, config source, last send result, and the command list. |
| `/cl setup <channel> <password> [tag]` | GM | Configure and show the Guild Info line. |
| `/cl channel <name>`, `/cl password <pw>`, `/cl tag <tag>` | GM | Change one setting locally, then `/cl publish`. |
| `/cl publish` | GM | Show the Guild Info line again. |
| `/cl officerrank <n>` | GM | Ranks 0..n count as officers (0 = GM). Shared via the Guild Info line. |
| `/cl clear` | GM | Clear this client's settings. |
| `/cl reload` | all | Re-read Guild Info now and retry the channel. |
| `/cl on`, `/cl off` | all | Enable or disable this client. |
| `/cl mute <tag>`, `/cl unmute <tag>` | all | Silence a linked guild on this client. |
| `/cl guilds` | all | Which guild tags were heard on the link in the last 10 minutes, how many of their addon users you could whisper to, who your guild's courier is, and each `guilds=` guild's online count from the last who round. |
| `/cl nickname <name>` or `clear` | all | Your nickname, shown to your guild and linked guilds. |
| `/cl nicknames on/off`, `/cl classcolor on/off`, `/cl officer on/off` | all | Display toggles (this client only). |
| `/cl officercolor [RRGGBB\|reset]` | all | Officer text colour; no argument opens the colour picker. |
| `/cl window <n>` | all | Force bridged lines into chat window n; no argument = windows with Guild chat. |
| `/cl mirror on/off`, `read off`, `post off`, `hide off` | all | Post your typed guild lines into the community named by `club=`, and show the community's lines in guild chat. Default both on. `hide off` shows the raw community channel lines again if you keep the community in a chat tab. |
| `/cl echo on/off` | all | Whether this client may be the one that re-posts other guilds' lines into real guild chat (needs `echo=on` on the Guild Info line). Default on. |
| `/cl whisper on/off` | all | Whether this client carries lines as courier and passes on carried lines it receives. Default on. |
| `/cl who` | all | Run the who round now: ask who is online in each `guilds=` guild and greet new names. Only your guild's courier runs it; anyone else is told `<name> is the courier for this guild; only the courier runs /cl who.` |
| `/cl peers` | all | Known peers (other guilds' addon users), their tag and guild, and when they were last heard from. |
| `/cl hello <First Surname>` | all | Greet one addon user of another guild directly, on any realm (Forever names are unique across realms and need no realm suffix). They appear in `/cl peers` once they answer. |
| `/cl report` | all | One pasteable line: version, channel and id, last send result, lockdown, your full name as the addon knows it, guilds heard, mirror, relay, whisper and echo counters, and the last 20 debug events. |
| `/cl debug on/off` | all | Echo debug events to chat as they happen. Events are always kept for `/cl report`. |
