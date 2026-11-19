local _, VS = ...

-- Remembers how many of each item every character has, so item tooltips can show the counts on alts.
-- Saved per character in VendorSniperDB.characters["Name-Realm"]:
--   class = "MAGE", inventory = { bags = { [itemID] = count }, bank = {...}, mail = {...} }
-- Bags are read whenever they change. The bank and mailbox can only be read while they're open, so those
-- counts are from the character's last visit.

VS.Inventory = {}
local Inventory = VS.Inventory

local KINDS = { "bags", "bank", "mail" }

local bankOpen = false
local mailOpen = false -- the inbox only lists mail while the mailbox is open

local function CharacterData()
  VendorSniperDB.characters = VendorSniperDB.characters or {}
  local key = VS.Recipes.CharacterKey()
  local data = VendorSniperDB.characters[key]
  if not data then
    data = { professions = {} }
    VendorSniperDB.characters[key] = data
  end
  data.inventory = data.inventory or {}
  return data
end

-- Container IDs ------------------------------------------------------------------------------------

local function BagIDs()
  local ids = {}
  for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
    ids[#ids + 1] = bag
  end
  return ids
end

local function BankIDs()
  local ids = { (Enum.BagIndex and Enum.BagIndex.Bank) or -1 }
  local first = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) + 1
  for bag = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do
    ids[#ids + 1] = bag
  end
  if Enum.BagIndex and Enum.BagIndex.Reagentbank then
    ids[#ids + 1] = Enum.BagIndex.Reagentbank
  end
  return ids
end

local function CountContainers(ids)
  local counts = {}
  for _, bag in ipairs(ids) do
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID then
        counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
      end
    end
  end
  return counts
end

-- Recording --------------------------------------------------------------------------------------------

local function RecordBags()
  local data = CharacterData()
  data.class = select(2, UnitClass("player"))
  data.inventory.bags = CountContainers(BagIDs())
end

local function RecordBank()
  if bankOpen then
    CharacterData().inventory.bank = CountContainers(BankIDs())
  end
end

local function RecordMail()
  local counts = {}
  for mail = 1, GetInboxNumItems() do
    for attachment = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
      local _, itemID, _, count = GetInboxItem(mail, attachment)
      if itemID then
        counts[itemID] = (counts[itemID] or 0) + (count or 1)
      end
    end
  end
  CharacterData().inventory.mail = counts
end

-- Bag changes come in bursts: record once they settle.
local pending = false
local function RecordSoon()
  if pending then
    return
  end
  pending = true
  C_Timer.After(0.5, function()
    pending = false
    if not VendorSniperDB then
      return -- saved settings not loaded yet
    end
    RecordBags()
    RecordBank()
  end)
end

local function SetBankOpen(open)
  bankOpen = open
  if open then
    RecordSoon()
  end
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
  "PLAYERBANKSLOTS_CHANGED", "PLAYERREAGENTBANKSLOTS_CHANGED", "MAIL_SHOW", "MAIL_CLOSED", "MAIL_INBOX_UPDATE",
  "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" }) do
  VS.SafeRegister(events, event)
end
events:SetScript("OnEvent", function(_, event, interaction)
  if event == "BANKFRAME_OPENED" then
    SetBankOpen(true)
  elseif event == "BANKFRAME_CLOSED" then
    SetBankOpen(false)
  elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
    local banker = Enum.PlayerInteractionType and Enum.PlayerInteractionType.Banker
    if banker and interaction == banker then
      SetBankOpen(event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    end
  elseif event == "MAIL_SHOW" or event == "MAIL_CLOSED" then
    mailOpen = event == "MAIL_SHOW"
  elseif event == "MAIL_INBOX_UPDATE" then
    if not mailOpen or not VendorSniperDB then
      return
    end
    local ok, err = pcall(RecordMail)
    if not ok then
      VS.Debug("mail count failed: %s", tostring(err))
    end
  else
    RecordSoon()
  end
end)

-- Tooltip -------------------------------------------------------------------------------------------------

local function ClassColor(class)
  local color = class and ((C_ClassColor and C_ClassColor.GetClassColor(class)) or RAID_CLASS_COLORS[class])
  return color or HIGHLIGHT_FONT_COLOR
end

-- Adds a line per character holding the item ("Name   12 (bags 10, bank 2)"), and a total when several do.
function Inventory.AddTooltipLines(tooltip, link)
  if VS.GetSetting("itemCounts") == false then
    return
  end
  local itemID = C_Item.GetItemInfoInstant(link)
  if not itemID or not VendorSniperDB.characters then
    return
  end
  local me = VS.Recipes.CharacterKey()
  local myRealm = me:match("%-(.*)$")
  local rows, total = {}, 0
  for key, data in pairs(VendorSniperDB.characters) do
    local inventory = data.inventory
    if inventory then
      local count, parts = 0, {}
      for _, kind in ipairs(KINDS) do
        local n = inventory[kind] and inventory[kind][itemID]
        if n and n > 0 then
          count = count + n
          parts[#parts + 1] = kind .. " " .. n
        end
      end
      if count > 0 then
        local name, realm = key:match("^(.-)%-(.*)$")
        rows[#rows + 1] = {
          name = (realm == myRealm) and name or key,
          mine = key == me,
          class = data.class,
          count = count,
          detail = table.concat(parts, ", "),
        }
        total = total + count
      end
    end
  end
  if #rows == 0 then
    return
  end
  table.sort(rows, function(a, b)
    if a.mine ~= b.mine then
      return a.mine
    end
    return a.name < b.name
  end)
  for _, row in ipairs(rows) do
    local color = ClassColor(row.class)
    tooltip:AddDoubleLine(row.name, ("%d |cffaaaaaa(%s)|r"):format(row.count, row.detail),
      color.r, color.g, color.b, 1, 1, 1)
  end
  if #rows > 1 then
    tooltip:AddDoubleLine("Total", tostring(total), NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b,
      1, 1, 1)
  end
end
