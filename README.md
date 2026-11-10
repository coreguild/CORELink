# CORELink

Links the guild chat of two or more guilds in World of Warcraft: Forever. When someone in a linked guild types
in guild chat, members of the other guilds see it in their own guild chat with that guild's tag in front:

```
[EMBER] [Tanner Ashvale]: anyone up for a dungeon run?
```

Guilds on different realms link the same way as guilds on one realm.

Download: https://coreguild.github.io/CORELink/

## Players: install it

1. Download the stable zip from the page above and unzip it. You get a folder named `CORELink`.
2. Move that folder into `World of Warcraft/_forever_/Interface/AddOns/`. If an older `CORELink` folder is
   there, replace it.
3. Start the game, or type `/reload` if you were already logged in.
4. Type `/cl`. It should say `ON`, name your guild's tag and channel, and say `joined`.

That is all. The addon reads its settings from your guild's Guild Information, so there is nothing to configure.
If `/cl` says `NOT CONFIGURED`, your guild master has not added the line yet (see below).

Three things worth knowing:

* Lines from other guilds show in whatever chat window shows your guild chat, with the other guild's tag in
  front. Names are class-coloured and officers are highlighted.
* Guildmates who do not have the addon are still heard by the other guilds: the addon carries their lines for
  them. They do not see the other guilds' lines unless your guild master turns echo on (see below).
* Everyone must be on version 0.2.0 or later. Older versions do not work on the live Forever servers. `/cl report`
  shows your version in its first words.

If lines are not coming through, see [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md). The one-line report from
`/cl report` is what to paste when asking for help.

## Guild masters: link your guild

Every linked guild has one line in its Guild Information. Agree these with the other guild masters:

* a **channel name** and a **password**, the same for every linked guild (one word each, no spaces; pick a
  channel name nobody would guess, because the channel is shared by every realm);
* a **tag** for each guild, up to 8 characters, different for every guild. It shows in front of your guild's
  lines in the other guilds' chat.

Then put this on its own line in your Guild Information, with your guild's values:

```
CORELink: <channel> <password> <TAG> 1 guilds=<Other Guild>, <Another Guild>
```

* The `1` is the officer rank cutoff: ranks 0 to 1 (guild master and the next rank) are shown as officers. Raise
  it if more of your ranks are officers.
* `guilds=` lists the other linked guilds by their exact names, comma separated, always last on the line. It
  helps the addon find a guild it has not heard from yet.

Example for two guilds, CORE and Ember Watch, sharing channel `corelink7100` and password `hearth`:

```
CORELink: corelink7100 hearth CORE 1 guilds=Ember Watch
CORELink: corelink7100 hearth EMBER 1 guilds=CORE
```

Save Guild Information. Members pick the line up within a minute of logging in, or at once with `/cl reload`.
You can also type `/cl setup <channel> <password> <TAG>` in game and copy the line it shows.

Two optional additions to the line, both explained in [docs/COMMANDS.md](docs/COMMANDS.md):

* `echo=on`: one addon user in your guild re-posts the other guilds' lines as plain guild chat, so guildmates
  without the addon can read them too. New in 0.2.0 and not yet proven on the live servers; try it in a test
  guild first.
* `club=<community>`: also mirror the chat into a Blizzard Community. Docs to come.

## Commands

| Command | Does |
|---|---|
| `/cl` | Status and the command list. |
| `/cl report` | One pasteable line for asking for help. |
| `/cl guilds` | Which linked guilds have been heard in the last 10 minutes. |
| `/cl nickname <name>` | A nickname shown to your guild and the linked guilds. |
| `/cl mute <tag>` / `/cl unmute <tag>` | Silence or restore one linked guild on this client. |
| `/cl off` / `/cl on` | Switch the addon off or on for this character. |
| `/cl reload` | Re-read Guild Information now. |

Every command, with who may run it: [docs/COMMANDS.md](docs/COMMANDS.md).

## How it works, in short

Every member's client sits in a hidden chat channel shared by all the linked guilds. When you type a guild line,
your own client posts a copy into that channel, and every addon user in the other guilds shows it. A line from a
guildmate without the addon is carried for them by one addon user in your guild. The longer version, file by
file, is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## More

* Something not working: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
* Working on the addon, tests, releases: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)
