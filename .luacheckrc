-- luacheck configuration for CORELink (WoW addon, game Lua is 5.1)
std = "lua51"
max_line_length = false            -- style only; we keep lines readable by review, not by tool
codes = true
ignore = { "212", "581" }          -- WoW callbacks have fixed signatures; style-only rewrite hints
-- Globals this addon legitimately creates
globals = {
  "CORELinkDB",
  "SLASH_CORELINK1", "SLASH_CORELINK2",
  "SlashCmdList",
  "StaticPopupDialogs",
  "ColorPickerFrame",              -- legacy picker API is configured by assigning fields
}
-- WoW API and UI globals the addon reads. Keep this list honest: if the game lacks one of these,
-- the code must guard it with `if X then`; luacheck only proves we spelled it right.
read_globals = {
  -- frames / UI
  "CreateFrame", "UIParent", "DEFAULT_CHAT_FRAME", "NUM_CHAT_WINDOWS", "ChatTypeInfo", "RAID_CLASS_COLORS",
  "ChatFrame_AddMessageEventFilter", "ChatFrame_RemoveChannel", "StaticPopup_Show", "C_AddOns", "GetAddOnMetadata",
  "GetChatWindowMessages", "GetChatWindowChannels", "ChatFrame1EditBox", "ChatEdit_ParseText", "hooksecurefunc",
  -- chat / channels
  "SendChatMessage", "SendAddonMessage", "JoinChannelByName", "JoinTemporaryChannel", "LeaveChannelByName",
  "GetChannelName", "GetChannelList", "C_ChatInfo",
  -- guild / player
  "GetGuildInfo", "GetGuildInfoText", "IsInGuild", "GetNumGuildMembers", "GetGuildRosterInfo", "GuildRoster",
  "C_GuildInfo", "UnitName", "UnitClass", "UnitFullName", "Ambiguate", "GetPlayerInfoByGUID",
  -- misc
  "C_Timer", "GetTime", "date", "wipe", "issecretvalue", "strsplit", "unpack",
}
files["tests/harness.lua"] = {
  std = "+lua53",                 -- harness runs on the host Lua, defines the mocks as globals
  allow_defined_top = true,
  ignore = { "1.." },             -- setting mocks as globals is the point of the harness
}
