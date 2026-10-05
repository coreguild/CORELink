# WoW API constraints that bit this project

Read before changing anything in the relay, channel or chat code.

1. **Custom channel chat needs a hardware event.** Since patch 8.2.5, `SendChatMessage(..., "CHANNEL", ...)` is
   refused unless the call happens inside a keypress or click. Chat event handlers and `C_Timer` callbacks are
   not hardware events. If you ever send plain channel chat, do it from a post-hook on the chat edit box
   (`hooksecurefunc(ChatFrameNEditBox, "ParseText", ...)`), the way GreenWall does.
2. **Addon messages on channels are blocked on some Classic clients.** Classic 1.13.3 disallowed
   `SendAddonMessage(..., "CHANNEL", ...)`. The Forever client appears to allow them on player-made channels and
   refuses them on standard channels (General, Trade). The result code (`Enum.SendAddonMessageResult`, 0 = ok,
   4 = InvalidChatType, 7 = InvalidChannel) is what `/cl` shows as `last send result`. Keep that visible.
3. **Never swallow send results with `pcall` silently.** Record the result so `/cl` can show it. A silent failure
   cost the team several days.
4. **Channel joins are asynchronous.** `GetChannelName` returns 0 until the server answers; confirm joins from
   `CHAT_MSG_CHANNEL_NOTICE` (`YOU_JOINED` / `YOU_CHANGED`) or re-check later. Never print a failure on the same tick.
5. **Guild Information is read-only for addons** and capped at 500 characters. Give the GM text to paste.
6. **Chat filters, not `GetChatWindowMessages`, decide what shows.** `GetChatWindowMessages` returns message
   groups (`GUILD`, `SAY`); `GetChatWindowChannels` returns channels. `ChatFrame_RemoveChannel` wants a frame
   object, not a name string.
7. **Packet size.** Channel and addon messages are limited to 255 bytes including the prefix. Trim on UTF-8 and
   `|c...|r` / `|H...|h` boundaries; a half link gets the whole message rejected.
8. **Secret values.** On Midnight-era clients chat payloads can be secret inside instances; guard with
   `issecretvalue` and pause relaying when `C_ChatInfo.InChatMessagingLockdown()` is true.
9. **Factions.** Custom channels are faction-bound on Classic clients; cross-faction bridging is not possible.
10. **Interface numbers.** Forever = `16001`. Do not put dotted versions like `12.3.1` in `## Interface:`; use the
    numeric form only.
