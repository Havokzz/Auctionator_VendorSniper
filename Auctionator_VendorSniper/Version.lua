local addonName, VS = ...

-- Update notice. Add-ons can't reach the internet, so a newer release can only be learned from other
-- players: each copy tells its guild and group which version it runs, in hidden add-on messages, and
-- says so in chat (once a session) when someone runs a newer one. A newer version heard in the last
-- week is mentioned again at login, since one may not be heard every session.
-- A copy run straight from the source has no version number ("@project-version@") and stays silent.

local PREFIX = "VSniperVersion"
local MIN_GAP = 30                  -- seconds between two announcements on one channel
local REMIND_FOR = 7 * 24 * 60 * 60 -- how long a newer version heard is mentioned at login
local CHANNELS = { GUILD = true, PARTY = true, RAID = true, INSTANCE_CHAT = true }

-- "1.0.2", "v1.0.2" or "1.1" -> { 1, 0, 2 }. Anything else is nil, so an odd message changes nothing.
local function Parse(text)
  if type(text) ~= "string" or #text > 20 then
    return nil
  end
  local major, minor, patch = text:match("^v?(%d+)%.(%d+)%.(%d+)$")
  if not major then
    major, minor = text:match("^v?(%d+)%.(%d+)$")
    patch = "0"
  end
  if not major or #major > 3 or #minor > 3 or #patch > 3 then
    return nil
  end
  return { tonumber(major), tonumber(minor), tonumber(patch) }
end

local function Newer(a, b)
  for i = 1, 3 do
    if a[i] ~= b[i] then
      return a[i] > b[i]
    end
  end
  return false
end

local function Text(version)
  return table.concat(version, ".")
end

local mine = Parse(C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")
  or GetAddOnMetadata and GetAddOnMetadata(addonName, "Version"))
VS.version = mine and Text(mine) or nil

-- Saying it --------------------------------------------------------------------------------------

local told = false

local function Tell(version)
  if not told then
    told = true
    VS.Print("version %s is available (you have %s). Update it from CurseForge.", Text(version), VS.version)
  end
end

local function Remember(version)
  local saved = VendorSniperDB.newerVersion
  local known = saved and Parse(saved.version)
  if not known or not Newer(known, version) then
    VendorSniperDB.newerVersion = { version = Text(version), heardAt = time() }
  end
end

-- Announcing ours --------------------------------------------------------------------------------

local lastSent, waiting, replyDue = {}, {}, {}

local function Announce(channel)
  if waiting[channel] then
    return
  end
  local wait = lastSent[channel] and lastSent[channel] + MIN_GAP - GetTime() or 0
  if wait > 0 then
    waiting[channel] = true
    C_Timer.After(wait, function()
      waiting[channel] = nil
      Announce(channel)
    end)
    return
  end
  lastSent[channel] = GetTime()
  pcall(C_ChatInfo.SendAddonMessage, PREFIX, VS.version, channel)
end

local function AnnounceToGroup()
  if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
    Announce("INSTANCE_CHAT")
  end
  if IsInRaid(LE_PARTY_CATEGORY_HOME) then
    Announce("RAID")
  elseif IsInGroup(LE_PARTY_CATEGORY_HOME) then
    Announce("PARTY")
  end
end

-- Someone on `channel` runs an older copy: tell them ours after a few seconds, unless another player
-- with at least our version answers first (so a big guild doesn't answer all at once).
local function ReplyLater(channel)
  if replyDue[channel] then
    return
  end
  replyDue[channel] = true
  C_Timer.After(2 + math.random() * 5, function()
    if replyDue[channel] then
      replyDue[channel] = nil
      Announce(channel)
    end
  end)
end

-- Listening --------------------------------------------------------------------------------------

local function Heard(text, channel)
  local theirs = Parse(text)
  if not theirs or not CHANNELS[channel] then
    return
  end
  if Newer(mine, theirs) then
    ReplyLater(channel)
    return
  end
  replyDue[channel] = nil -- they run at least our version, so no answer is needed from us
  if Newer(theirs, mine) then
    Remember(theirs)
    Tell(theirs)
  end
end

local function AtLogin()
  local saved = VendorSniperDB.newerVersion
  local known = saved and Parse(saved.version)
  if known and Newer(known, mine) and time() - (tonumber(saved.heardAt) or 0) < REMIND_FOR then
    Tell(known)
  else
    VendorSniperDB.newerVersion = nil -- updated since, or not heard of lately
  end
  if IsInGuild() then
    Announce("GUILD")
  end
  AnnounceToGroup()
end

if not mine then
  return
end

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

local groupSize = 0
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:SetScript("OnEvent", function(_, event, ...)
  if event == "CHAT_MSG_ADDON" then
    local prefix, text, channel = ...
    if prefix == PREFIX then
      Heard(text, channel)
    end
  elseif event == "PLAYER_LOGIN" then
    groupSize = GetNumGroupMembers()
    C_Timer.After(10, AtLogin) -- after the loading screen, so the notice isn't lost in the login chatter
  else
    local size = GetNumGroupMembers()
    if size > groupSize then
      AnnounceToGroup() -- someone joined: they may run another version
    end
    groupSize = size
  end
end)
