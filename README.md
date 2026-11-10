# CORELink

CORELink lets multiple guilds share guild chat in World of Warcraft: Forever.

## Install CORELink

1. Open the [CORELink download page](https://coreguild.github.io/CORELink/) and download the stable ZIP.
2. Unzip the download and move the `CORELink` folder into `World of Warcraft/_forever_/Interface/AddOns/`. If you're updating, replace the old `CORELink` folder.
3. Start WoW, or type `/reload` if you're already logged in.
4. Type `/cl` in chat. When the addon is ready, the status shows `ON` and `joined` next to the channel name.

CORELink reads its settings from Guild Information. If `/cl` still says `NOT CONFIGURED` after login, ask your guild master to check the CORELink line in Guild Information. If they've just updated it, type `/cl reload` to read it again.

Use version 0.2.0 or later on the live Forever servers. To check which version you have, type `/cl report` and look at the start of the report.

## Link your guild

Each guild master adds one CORELink line to their own guild's Guild Information. Before you start, agree on a channel name and password with the other guild masters. Use the same name and password in every guild. Both must be single words, and the channel name should be hard to guess.

Give each guild a different tag of up to eight characters. The tag appears in brackets before the player's name. Here's a message from CORE Deux using the tag `DEUX`.

```text
[DEUX] [Tanner Ashvale]: anyone up for a dungeon run?
```

1. Run `/cl setup <channel> <password> <tag>` with your guild's values. For example, `/cl setup corelink7100 hearth CORE`.
2. Copy the line the addon shows you. Paste it on its own line in Guild Information and save.
3. Ask someone in another linked guild to send a guild chat message. Check that you can see their message with their guild's tag, then send one back.

For example, CORE and CORE Deux might use the following lines. Each guild saves only its own line.

**CORE**

```text
CORELink: corelink7100 hearth CORE 1 guilds=CORE Deux
```

**CORE Deux**

```text
CORELink: corelink7100 hearth DEUX 1 guilds=CORE
```

The `1` means ranks 0 and 1 are shown as officers. Rank 0 is the guild master. Increase that number if more ranks should be shown as officers. To help CORELink find guilds it hasn't heard from yet, you can add `guilds=` to the line before saving it. List the other guilds by their exact names, separate them with commas, and put the list last.

Members who are already online can type `/cl reload` after you save the line. See the [Guild Information settings](docs/COMMANDS.md#guild-information-settings) for the full format and options such as mirroring into a WoW Community.

## Who can read linked chat?

Members with CORELink can see messages from linked guilds in their guild chat window. A member without CORELink can still have their own messages carried by another addon user in their guild, but will not see the linked guild's messages themselves.

## Get help

If chat isn't coming through, start with the [troubleshooting guide](docs/TROUBLESHOOTING.md). If you need to ask for help, type `/cl report` and share the report from the copy box. It includes your addon version and connection status.

See the [command reference](docs/COMMANDS.md) for commands to check linked guilds, set a nickname, mute a guild, or turn CORELink off.

## Contribute

Start with the [contribution guide](CONTRIBUTING.md). The [development guide](docs/DEVELOPMENT.md) covers local setup, tests, and releases. See the [architecture guide](docs/ARCHITECTURE.md) for how the addon relays messages.
