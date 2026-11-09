# CORELink

Bridges guild chat between co-guilds in World of Warcraft: Forever. Members of linked guilds see each other's
guild chat as `[TAG] [Name]: message`, with class-coloured names, officer highlighting and optional nicknames.
Nothing to configure for members: the guild master pastes one line into Guild Info and every client picks it up.

## Download

* Stable: https://coreguild.github.io/CORELink/latest/CORELink.zip
* Release candidate: https://coreguild.github.io/CORELink/rc/CORELink.zip
* Both, with install steps and release notes: https://coreguild.github.io/CORELink/

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
members without the addon, and `guilds=` names the co-guilds so a guild nobody has heard from yet still gets
found.

## How it works

* Members' clients join a hidden chat channel, shared by every realm, and keep it out of every chat tab.
* When you type a guild line, your own client posts a packed copy into that channel in the same keypress.
  Every addon user in every linked guild reads it, drops duplicates, ignores their own guild, and prints it in
  the chat windows that show Guild chat.
* A line from a guildmate who does not have the addon cannot be posted by anyone else's keypress, so your
  guild's courier (one addon user, chosen the same way by every client) whispers it to one addon user in each
  other guild, who passes it to their guildmates.
* With `echo=on`, one addon user per guild re-posts linked guilds' lines as plain guild chat, so members
  without the addon see them too. With `club=`, lines are also mirrored into a community everyone can read.
* In chat lockdown (instanced content) relaying pauses.

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
