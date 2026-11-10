# Troubleshooting

Start with `/cl report`. It prints one line and opens it in a copy box; paste it to whoever is helping.

## Symptoms

| Symptom | Cause | What to do |
|---|---|---|
| "not configured" after login | No `CORELink:` line in Guild Info, or it could not be read yet | The guild master pastes the line (`/cl publish` shows it); members `/cl reload` |
| "could not join ...: wrong channel password" | This guild's line differs from the other guilds' | GM re-publishes with `/cl publish`, members `/cl reload` |
| Status says "not joined" long after login | Joining a channel needs a keypress or click after login | Press any key or click in the world, then `/cl` again |
| We only see guild X's lines from players who have the addon | Lines from X's members without the addon are carried by X's courier, who needs a peer in your guild | Someone in your guild has to have said something in guild chat since logging in, so X's courier knows them; `/cl peers` on X's side lists who it can whisper to |
| "the server refused your line on <channel>" | The server rejected a send on the channel | Share `/cl report`; `lastSend refused` and the log say when. Linked guilds did not get that line |
| Lines from one guild never arrive | `heard` in `/cl report` lists the guilds whose lines reached you in the last 10 minutes | If the guild is missing, its members' clients are not posting (wrong channel or password, or refused); if it is listed and nothing shows, share the report |
| Nothing arrives from any guild, `/cl report` says `lastSend refused` | Version before 0.2.0: the server refuses what it sends | Everyone updates to 0.2.0 or later; `/cl report` starts with the version |
| A guildmate without the addon (or with `/cl off`) sees nothing from other guilds | Expected: only addon users read the channel | Their own lines still reach the other guilds. For them to read, the GM adds `echo=on` to the Guild Info line (new in 0.2.0, test it first) |
| Nickname or officer tag missing on your own lines | Older build on WoW: Forever surnames | Update to 0.2.0 or later |
| A line shows twice | Two clients relayed it inside the same back-off window, or a community copy was not matched | Rare and harmless; if it repeats, share `/cl report` from both clients |
| "No player named X is currently playing" in chat | A whisper greeting reached someone who just logged off | Hidden by the addon when it is about a greeting of ours; otherwise it was a chat whisper of yours |

## Reading `/cl report`

* `channel <name> id <n>`: joined. `id not joined`: see the keypress row above and `lastNotice`.
* `lastNotice`: the game's last answer about the channel. `NOT_ALLOWED_IN_CHANNEL` once, right after joining,
  is a send that beat the join and is harmless; repeated, it means the character may not speak there.
* `lastSend ok`: the last line was accepted by the client. `refused`: the server rejected it (the addon says so
  once per 10 minutes). `error`: the send call itself failed; the log says why.
* `me`: your name as the addon knows it. On Forever it must be `First Surname`; `short:` means the roster has
  not been read yet, and nicknames and courier duty may be off until it is.
* `heard`: guild tags whose lines reached you in the last 10 minutes, by any path.
* `relay typed=N carried=N shown=N`: your own lines posted, guildmates' lines you carried as courier, other
  guilds' lines shown.
* `mirror ...`: the community. `member=false` means this character is not in it. `hooks=editbox+send` is normal.
* `whisper courier=me`: this client carries guildmates' lines; otherwise the courier's name. `peers=N` live
  peers, `sent=N` lines carried, `recv=N` carried lines received, `fanned=N` passed to your guild.
* `log:` the last 20 events. `/cl debug on` echoes them live.

## Realms

Realms do not matter to CORELink on Forever. The hidden channel is shared by every realm, guild addon messages
and whispers cross them, names are unique across them, and no name ever carries a `-Realm` suffix. The only
thing a realm changes is where you can trade and group. The only way to learn someone's realm is to ask:
`/run print(GetRealmName())` on their client.

What the server does refuse, on every realm, is an addon message sent on a custom channel. CORELink therefore
sends your own lines as plain text from your keypress, and has the courier whisper the lines of members
without the addon. See [ARCHITECTURE.md](ARCHITECTURE.md).

## Testing with two guilds

Two characters in two guilds, both with the addon and the same channel and password, different tags.

1. Type a line in guild A. Within a second it shows in B as `[TAGA] [Name]: text`. `/cl report` on A: `relay
   typed=1`, `lastSend ok`.
2. `/cl peers` on B lists A's character as a live peer. `/cl guilds` on B lists TAGA.
3. Have a member of A without the addon type a line (or log A's character out and use a second one without the
   addon). Within two seconds it shows in B. `/cl report` on A's courier: `carried=1`; on B: `recv=1 fanned=1`.
4. `/cl hello First Surname` greets one addon user by hand; `/cl peers` shows the answer a few seconds later.
