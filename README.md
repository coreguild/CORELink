# CORELink

Bridges guild chat between co-guilds in World of Warcraft: Forever. Members of linked guilds see each other's
guild chat as `[TAG] [Name]: message`, with class-coloured names, officer highlighting and optional nicknames.
Nothing to configure for members: the guild master pastes one line into Guild Info and every client picks it up.

## Download

* Stable: https://core-wow-community.github.io/CORELink/latest/CORELink.zip
* Release candidate: https://core-wow-community.github.io/CORELink/rc/CORELink.zip
* Both, with install steps and release notes: https://core-wow-community.github.io/CORELink/

## Players

1. Download the stable zip.
2. Put the `CORELink` folder in `World of Warcraft/_forever_/Interface/AddOns/`.
3. Log in. If your Guild Information contains a `CORELink:` line, you are done. `/cl` shows the status.

## Guild masters (once per guild)

```
/cl setup <channel> <password> [tag]      e.g.  /cl setup CORELink7100 pw1 MAIN
```

A copy box shows the Guild Info line. Paste it into Guild Information and save. Every co-guild uses the same
channel and password and a different tag. Members pick the settings up within a minute of logging in.

The line can carry three optional features, all explained in [docs/COMMANDS.md](docs/COMMANDS.md):
`club=` mirrors chat into a Blizzard Community, `echo=on` re-posts linked guilds' lines into plain guild chat for
members without the addon, and `guilds=` names the co-guilds so lines reach realms your guild is not on.

## How it works

* Members' clients join a hidden custom channel and keep it out of every chat tab.
* A guild line is packed as a small packet and sent on that channel. One client relays each line: the author's
  own at once, anyone else after a short random wait if nobody did, so members without the addon are bridged too.
* Receivers drop duplicates by the packet id, ignore their own guild, and print the line in every chat window
  that has Guild chat enabled.
* Custom channels are per realm. Lines reach other realms three ways: through a guildmate on that realm (guild
  addon messages cross realms), through a whisper to a known addon user there, or through the community.
* In chat lockdown (instanced content on Midnight-era clients) relaying pauses.

The full picture, file by file, is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Commands

| Command | Does |
|---|---|
| `/cl` | Status and the command list. |
| `/cl guilds` | Which guilds are on the link, on which realms, and which ones do not reach yours. |
| `/cl report` | One pasteable diagnostic line. Paste it when asking for help. |
| `/cl nickname <name>` | Your nickname, shown to your guild and linked guilds. |
| `/cl mute <tag>` / `unmute` | Silence a linked guild on this client. |
| `/cl reload` | Re-read Guild Info and rejoin the channel. |

Every command, with who may run it: [docs/COMMANDS.md](docs/COMMANDS.md).

## More

* Something not working: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
* Working on the addon, tests, releases: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)
* How the code is organised: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
