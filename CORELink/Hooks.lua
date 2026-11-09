-- CORELink/Hooks.lua: the chat send hooks, the one place where the addon runs inside the player's keypress.
-- A guild line typed in the edit box, or sent by "/g", a macro or another addon, is relayed into the hidden
-- channel as text (Relay.lua) and mirrored into the community (Mirror.lua) from here, because both kinds of
-- send are refused by the game outside a keypress.
-- Provides NS.InstallHooks, NS.OnTypedGuildLine.
local _, NS = ...
local issecret = NS.issecret

function NS.OnTypedGuildLine(text)
  NS.RelayTyped(text)
  NS.MirrorTypedLine(text)
end

-- Typed in a chat box whose type is already Guild.
local function OnEditBoxParseText(editBox, send)
  if send ~= 1 or not editBox or not editBox.GetAttribute then return end
  if editBox:GetAttribute("chatType") ~= "GUILD" then return end
  local text = editBox:GetText()
  if type(text) ~= "string" or not text:match("%S") or text:sub(1, 1) == "/" then return end
  NS.OnTypedGuildLine(text)
end

-- Any guild send: "/g text" typed in another chat type, macros, other addons. Our own echo and channel sends
-- come through here too and are not guild lines.
local function OnSendChatMessage(msg, chatType)
  if NS.echoStats.active then return end
  if type(chatType) ~= "string" or issecret(chatType) or chatType:upper() ~= "GUILD" then return end
  if type(msg) ~= "string" or issecret(msg) or not msg:match("%S") then return end
  NS.OnTypedGuildLine(msg)
end

function NS.InstallHooks()
  local mirror = NS.mirror
  if mirror.hooks ~= "not installed" then return end
  local got = {}
  if ChatFrame1EditBox and ChatFrame1EditBox.ParseText then
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
      local eb = _G["ChatFrame" .. i .. "EditBox"]
      if eb and eb.ParseText then hooksecurefunc(eb, "ParseText", OnEditBoxParseText); got.editbox = true end
    end
  elseif ChatEdit_ParseText then
    hooksecurefunc("ChatEdit_ParseText", OnEditBoxParseText); got.editbox = true
  end
  if SendChatMessage then hooksecurefunc("SendChatMessage", OnSendChatMessage); got.send = true end
  if C_ChatInfo and C_ChatInfo.SendChatMessage then
    hooksecurefunc(C_ChatInfo, "SendChatMessage", OnSendChatMessage); got.send = true
  end
  mirror.hooks = (got.editbox and got.send and "editbox+send") or (got.editbox and "editbox") or (got.send and "send")
    or "FAILED (no chat hooks)"
end
