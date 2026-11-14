# Troubleshooting CORELink

Type `/cl` in WoW to check whether CORELink is on and whether it joined the channel. If you need help, type `/cl report` and copy the report from the box it opens. Tell the person helping you which guild sent the message and which guild couldn't see it.

## `/cl` says `NOT CONFIGURED`

Ask your guild master to check for a CORELink line in Guild Information. If they've just added or changed the line, type `/cl reload` to load the updated settings.

## CORELink says the channel password is wrong

Ask the guild masters to compare the CORELink lines in Guild Information. The channel name and password should match in every linked guild. Once your guild master saves the corrected line, type `/cl reload` to try connecting again.

## `/cl` still says `not joined` after login

Press a key or click in the game world, then type `/cl` again. If you still see `not joined`, share the output of `/cl report` so the person helping you can see the last message WoW sent about the channel.

## I can't see messages from another guild

1. Ask someone in the other guild to type `/cl` and check your own status too. Both should say `ON` and `joined`. Use `/cl report` to check that you're both running 0.2.0 or later on the live Forever servers.
2. Ask that player to send a message in guild chat, then send one back to check whether messages travel both ways.
3. If either message is missing, run `/cl report` on both characters. If the sender's report says `lastSend refused`, WoW refused a send. If the receiver's report lists the sending guild under `heard`, check whether the receiver has muted that guild.

## I only see messages from players who have CORELink

Send a guild chat message while CORELink is on. Then ask someone in the other guild to have their courier run `/cl peers` and look for your character's name. The courier is the player whose addon carries messages for guild members without CORELink. If your name isn't listed, the courier can type `/cl hello <FirstName Surname>` with your character's full name to make contact.

## A guild member without CORELink can't see linked messages

Ask them to install CORELink if they want to read linked chat. If your guild master wants members without the addon to see it too, they can try [enabling echo](COMMANDS.md#guild-information-settings) in a test guild first. Echo lets another member's addon re-post linked messages into guild chat.

## My nickname or officer label is missing from my own messages

Type `/cl report` and check the version at the start. If it's older than 0.2.0, install a newer version. If you're already up to date, share the report when asking for help.

## The same message appears twice

If it keeps happening, ask the sender and receiver to run `/cl report`. Share both reports and mention whether your guilds also share chat through a WoW Community.

## WoW says "No player named X is currently playing"

If the notice keeps appearing while you use CORELink, share a report. WoW can show this notice if someone logs off before receiving a whisper or an addon greeting. CORELink hides notices it recognizes as replies to its own greetings.

## CORELink says a linked guild runs a newer CORELink it can't read

Update CORELink. A linked guild sent a message in a newer format than your version reads, so you won't see that guild's messages until you update. You see the notice once per session. It's about another guild's message format, not about a guild member's version.

## Read the report

| Field | What it tells you |
|---|---|
| `proto` | The message format your version reads. `(a linked guild sent a newer one)` after it means a newer format arrived this session; the log has the number. |
| `channel` | A number after `id` means you joined the channel. `id not joined` means you haven't joined. |
| `lastNotice` | The most recent channel notice from WoW. If `NOT_ALLOWED_IN_CHANNEL` keeps appearing, include it when you ask for help. |
| `lastSend` | `ok` means the local send call completed. `refused` means the server reported a refusal. `error` means the call itself failed. |
| `me` | The name CORELink knows for your character. `short:` means it hasn't learned your full name, which can affect nicknames and who carries messages. |
| `heard` | Guild tags heard in the last ten minutes. |
| `relay` | Counts messages you typed and relayed, messages you carried for guild members, and linked messages shown to you. |
| `mirror` | Community connection details. `member=false` means this character isn't a member of the configured Community. |
| `whisper` | Shows the courier and counts known peers, carried messages sent or received, and messages passed on to your guild. |
| `log` | The last 20 debug events. Use `/cl debug on` to also show new events in chat. |

See the [testing guide](../agents/testing.md) for the full in-game checks and the [architecture guide](ARCHITECTURE.md) for how messages travel between guilds.
