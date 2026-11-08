# Troubleshooting

Start with `/cl report`. It prints one line and opens it in a copy box; paste it to whoever is helping.

## Symptoms

| Symptom | Cause | What to do |
|---|---|---|
| "not configured" after login | No `CORELink:` line in Guild Info, or it could not be read yet | The guild master pastes the line (`/cl publish` shows it); members `/cl reload` |
| "could not join ...: wrong channel password" | This guild's line differs from the other guilds' | GM re-publishes with `/cl publish`, members `/cl reload` |
| Status says "not joined" long after login | Joining a channel needs a keypress or click after login | Press any key or click in the world, then `/cl` again |
| We only see guild X when player Y is online | Y is the only member of X with the addon on your realm | X needs an addon user online on your realm, or `guilds=` for the whisper bridge; `/cl guilds` shows `NOT reaching <realm>` |
| Two players cannot see each other even in a plain `/join test` channel | They are on different realms | Expected: custom channels are per realm. See Realms below |
| Lines from one guild never arrive | `reach` in `/cl report` shows which realms each guild is heard on | Fix realm coverage; if the guild is heard on your realm and still not shown, share the report |
| Nickname or officer tag missing on your own lines | Older build on WoW: Forever surnames | Update to 0.1.1 or later |
| A line shows twice | Two clients relayed it inside the same back-off window, or a community copy was not matched | Rare and harmless; if it repeats, share `/cl report` from both clients |
| "No player named X is currently playing" in chat | A whisper greeting reached someone who just logged off | Hidden by the addon when it is about a greeting of ours; otherwise it was a chat whisper of yours |

## Reading `/cl report`

* `channel <name> id <n>`: joined. `id not joined`: see the keypress row above and `lastNotice`.
* `lastNotice`: the game's last answer about the channel. `NOT_ALLOWED_IN_CHANNEL` once, right after joining,
  is a send that beat the join and is harmless; repeated, it means the character may not speak there.
* `lastSend 0`: the last packet was accepted. Anything else and the addon prints a warning once a minute.
* `heard`: guild tags seen on the channel in the last 10 minutes. `reach`: the same per realm, including what
  your guildmates on other realms hear.
* `mirror ...`: the community. `member=false` means this character is not in it. `hooks=editbox+send` is normal.
* `whisper courier=true`: this client runs the who rounds for its guild on this realm. `peers=N` live peers.
* `bridge elsewhere=true`: your guild has addon users on another realm, so lines can cross through them.
* `log:` the last 20 events. `/cl debug on` echoes them live.

## Realms

Forever has several realms and custom chat channels do not cross them. A guild's lines reach a realm only
while something carries them there:

* a guildmate of the origin guild running the addon on that realm (the relay channel),
* a member of any linked guild with addon users on both realms (the cross-realm bridge),
* a whisper from the courier to a known addon user on that realm (the whisper bridge, needs `guilds=`),
* the community, which everyone can read in a chat tab regardless of realm.

Names are unique across Forever realms. A whisper to a plain `First Surname` reaches any realm, `/who` sees
every realm, and no name ever carries a `-Realm` suffix. The only way to learn someone's realm is to ask them:
`/run print(GetRealmName())` on their client.

## Testing the whisper bridge

Needs one player on another realm with the addon installed. No guild or setup on their side.

1. `/cl hello First Surname` with their exact name.
2. `/cl peers` a few seconds later. "seen Ns ago" on their entry: whisper addon messages cross realms.
3. If they also join your channel (`/cl setup` with the same channel on their side), type a line in your guild
   chat. Their `/cl report` should show `recv=1` and `bridge resent=1`.

For the who round, add a guild that exists on another realm to `guilds=`, then `/cl who`, wait ten seconds, and
`/cl guilds`. The last lines show each guild's online count from that round.
