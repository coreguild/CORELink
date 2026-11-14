# CORELink commands and settings

Type `/cl` in WoW to see whether CORELink is on, whether it joined the chat channel, and which commands you can run. Guild masters can also change the settings their guild uses to connect.

## Check your connection

| Command | What it does |
|---|---|
| `/cl` | Shows whether CORELink is on, your guild tag, which channel you are connected to, where your settings came from, and which commands you can run. |
| `/cl guilds` | Lists guilds heard in the last 10 minutes. It also shows who is carrying chat for your guild and any online counts from the latest guild lookup. |
| `/cl report` | Opens a copy box with your addon version, connection status, and recent events. Share it when asking for help. |
| `/cl reload` | Re-reads Guild Information and tries to connect to the channel again. |

## Mute a guild, set a nickname, or turn CORELink off

| Command | What it does |
|---|---|
| `/cl on` | Turns CORELink on for this character. |
| `/cl off` | Turns CORELink off for this character. If your guild uses echo, you can still see messages another member re-posts into guild chat. |
| `/cl mute <tag>` | Hides messages from the linked guild with that tag on your client. |
| `/cl unmute <tag>` | Shows messages from the linked guild with that tag again on your client. |
| `/cl nickname <name>` | Sets the nickname shown to your guild and linked guilds. |
| `/cl nickname clear` | Clears your nickname. |

## Change how chat looks on your client

| Command | What it does |
|---|---|
| `/cl nicknames on/off` | Shows or hides other people's nicknames. |
| `/cl classcolor on/off` | Turns class colours for player names on or off. |
| `/cl officer on/off` | Turns highlighting for officers' messages on or off. |
| `/cl officercolor [RRGGBB\|reset]` | Sets the colour for officers' messages or restores the default. Type `/cl officercolor` on its own to open the colour picker. |
| `/cl window <n>` | Shows linked messages in the chat window you specify. Type `/cl window` on its own to show them in windows that already display guild chat. |

## Help relay messages

The courier is the addon user who carries messages from guildmates without CORELink. A peer is an addon user in another linked guild.

| Command | What it does |
|---|---|
| `/cl whisper on/off` | Controls whether your client can act as courier and pass along messages it receives from another courier. This is on by default. |
| `/cl echo on/off` | Controls whether your client can re-post linked messages into guild chat. This is on by default and only takes effect if your guild master adds `echo=on` to the CORELink line. |
| `/cl peers` | Lists known peers, their guilds and tags, and when CORELink last heard from them. |
| `/cl who` | Looks up who is online in each guild listed in `guilds=` and contacts new names. Only the courier runs the lookup. |
| `/cl hello <First Surname>` | Contacts an addon user in another guild by character name. They appear in `/cl peers` once they answer. |

## Control Community mirroring

| Command | What it does |
|---|---|
| `/cl mirror on/off` | Turns both reading and posting on or off for the Community configured with `club=`. Both are on by default. |
| `/cl mirror read on/off` | Shows or hides the Community's messages in guild chat. |
| `/cl mirror post on/off` | Starts or stops posting the guild messages you type to the Community. |
| `/cl mirror hide on/off` | Hides or shows the original Community messages in any chat tab where you added that channel. |

## Show debug messages

| Command | What it does |
|---|---|
| `/cl debug on/off` | Shows or hides debug messages in chat. Recent events still appear in `/cl report`. |

## Guild master commands

These commands change settings on your client. To share the settings with your guild, run `/cl publish` and paste the line it shows into Guild Information.

| Command | What it does |
|---|---|
| `/cl setup <channel> <password> [tag]` | Sets up CORELink on your client and shows the line to paste into Guild Information. Use `-` for no password. |
| `/cl publish` | Shows the current CORELink line again. |
| `/cl channel <name>` | Changes the channel name on your client. |
| `/cl password <password>` | Changes the channel password on your client. |
| `/cl tag <tag>` | Changes the guild tag on your client. |
| `/cl officerrank <n>` | Treats ranks 0 through `n` as officers when displaying chat. Rank 0 is the guild master. |
| `/cl clear` | Clears the connection settings on your client. |

## Guild Information settings

See [Link your guild](../README.md#link-your-guild) for a setup example. The square brackets below mark optional fields. Leave the brackets out of the line you paste into Guild Information.

```text
CORELink: <channel> <password|-> [tag|-] [officerRankCutoff] [club=<community>] [echo=on] [guilds=<name>, <name>]
```

- Use the same channel and password for all linked guilds. Use `-` in the password position if the channel has no password.
- Give each guild a distinct tag of up to eight characters. Use `-` or omit the tag to let CORELink make one from the guild name.
- The officer rank cutoff defaults to 1, so ranks 0 and 1 are shown as officers.
- Add `echo=on` if you want one addon user to re-post linked messages into guild chat for members without CORELink. Try this in a test guild before using it on the live Forever servers.
- Add `guilds=` followed by the other guilds' exact names, separated by commas, to help CORELink find guilds it hasn't heard from. Put this setting last so guild names can contain spaces.

### Mirror chat into a WoW Community

1. Create a World of Warcraft Community and give it a unique short name. Share its invite link with the members who need access.
2. Add `club=<short name>` to each guild's CORELink line before `guilds=`, if present. You can also use the Community's numeric ID or its full name without spaces.
3. In the Community settings, add one channel per linked guild. Name each channel after its guild tag and put `CORELink` in the channel description.

Members can read linked messages in guild chat without adding the Community channel to a chat tab.
