local _, VS = ...

-- Sells what the Buy button bought, the next time a merchant window opens.
--
-- With the "Sell to vendor" setting on, every purchase is marked: VendorSniperDB.toSell["Name-Realm"][itemID]
-- = how many units are still to be sold. Purchases arrive by mail, so they're sold once they're in the bags.
-- Only as many units as were bought get sold, so copies the player already had are left alone. A stack
-- holding more than what's marked (bought units that merged with the player's own) is left alone too:
-- splitting stacks isn't worth the risk, and the rest stays marked for when it's possible.
--
-- With "Sell junk" on, grey (poor quality) items in the bags are sold at every merchant too.

VS.AutoSell = {}
local AutoSell = VS.AutoSell

local SELL_BATCH = 10      -- items sold at once
local SELL_INTERVAL = 0.2 -- seconds between batches, so the merchant keeps up
local BAGS = { 0, 1, 2, 3, 4 }

local merchantOpen = false
local selling = false
local blocked = false -- the game refused our selling call: stop until the next merchant visit

local function Marked(create)
  VendorSniperDB.toSell = VendorSniperDB.toSell or {}
  local key = VS.Recipes.CharacterKey()
  local marked = VendorSniperDB.toSell[key]
  if not marked and create then
    marked = {}
    VendorSniperDB.toSell[key] = marked
  end
  return marked
end

function AutoSell.IsOn()
  return VS.GetSetting("sellToVendor") == true
end

-- Units of the item still to be sold by this character (0 if none).
function AutoSell.MarkedCount(itemID)
  local marked = Marked(false)
  return marked and marked[itemID] or 0
end

function AutoSell.Mark(itemID, quantity)
  local marked = Marked(true)
  marked[itemID] = (marked[itemID] or 0) + quantity
end

-- Forgets every mark of this character; returns how many items were marked.
function AutoSell.ClearMarks()
  local marked = Marked(false)
  local count = 0
  for _ in pairs(marked or {}) do
    count = count + 1
  end
  if marked then
    wipe(marked)
  end
  return count
end

local function Unmark(itemID, quantity)
  local marked = Marked(false)
  if marked and marked[itemID] then
    marked[itemID] = marked[itemID] - quantity
    if marked[itemID] <= 0 then
      marked[itemID] = nil
    end
  end
end

local function SellsJunk()
  return VS.GetSetting("sellJunk") == true
end

-- The next bag slot to sell: bag, slot, itemID, count, link, isJunk. Marked purchases (stacks no bigger
-- than what's marked) and, with Sell junk on, grey items. Skips locked items, items vendors don't buy, and
-- slots in `sent` (already sold this visit, possibly not gone from the bag yet).
local function NextSale(sent)
  local marked = AutoSell.IsOn() and Marked(false) or nil
  if marked and next(marked) == nil then
    marked = nil
  end
  local junk = SellsJunk()
  if not marked and not junk then
    return nil
  end
  for _, bag in ipairs(BAGS) do
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID and not info.isLocked and not info.hasNoValue and not sent[bag * 1000 + slot] then
        local left = marked and marked[info.itemID]
        if left and info.stackCount <= left then
          return bag, slot, info.itemID, info.stackCount, info.hyperlink, false
        elseif junk and info.quality == Enum.ItemQuality.Poor then
          return bag, slot, info.itemID, info.stackCount, info.hyperlink, true
        end
      end
    end
  end
end

local function SellAll()
  if selling then
    return
  end
  selling = true
  local sold, earned, junkSold, junkEarned = 0, 0, 0, 0
  local sent = {} -- bag * 1000 + slot of every slot sold this visit
  local function Finish()
    selling = false
    if sold > 0 then
      VS.Print("sold %d marked item%s to the vendor for %s.", sold, sold == 1 and "" or "s", VS.FormatMoney(earned))
    end
    if junkSold > 0 then
      VS.Print("sold %d junk item%s for %s.", junkSold, junkSold == 1 and "" or "s", VS.FormatMoney(junkEarned))
    end
  end
  local function Step()
    for _ = 1, SELL_BATCH do
      if not merchantOpen or blocked then
        Finish()
        return
      end
      local bag, slot, itemID, count, link, isJunk = NextSale(sent)
      if not bag then
        Finish()
        return
      end
      sent[bag * 1000 + slot] = true
      C_Container.UseContainerItem(bag, slot) -- at an open merchant this sells the item
      if blocked then -- the game refused it (reported by the event handler below): nothing was sold
        Finish()
        return
      end
      local sellPrice = VS.ItemData.GetSellInfo(itemID) or 0
      if isJunk then
        junkSold = junkSold + count
        junkEarned = junkEarned + sellPrice * count
      else
        Unmark(itemID, count)
        sold = sold + count
        earned = earned + sellPrice * count
      end
      VS.Debug("sold %dx %s", count, link or itemID)
    end
    C_Timer.After(SELL_INTERVAL, Step)
  end
  Step()
end

-- Purchases made by the Buy button. Gear bought for its disenchant value is meant for disenchanting, so
-- it isn't marked: a vendor would pay less than what it cost.
VS.On("PURCHASED", function(itemID, quantity, via)
  if AutoSell.IsOn() and via ~= "disenchant" and itemID and quantity and quantity > 0 then
    AutoSell.Mark(itemID, quantity)
  end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_CLOSED")
VS.SafeRegister(events, "ADDON_ACTION_BLOCKED")
VS.SafeRegister(events, "ADDON_ACTION_FORBIDDEN")
events:SetScript("OnEvent", function(_, event, addon, func)
  if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
    -- only while selling: Alt+click disenchanting also uses UseContainerItem, and reports its own blocks
    if addon == VS.name and selling and tostring(func):find("UseContainerItem") then
      blocked = true -- SellAll sees this right after its call and stops, leaving that item marked
      VS.Print("the game doesn't allow addons to sell items automatically here. Your bought items stay marked"
        .. " - sell them by right-clicking them at the vendor, or /vsnipe clearsell.")
    end
    return
  end
  if event == "MERCHANT_SHOW" then
    merchantOpen = true
    blocked = false
    if AutoSell.IsOn() or SellsJunk() then
      -- give the merchant window a moment to finish opening
      C_Timer.After(0.3, function()
        local ok, err = pcall(SellAll)
        if not ok then
          selling = false
          VS.Print("selling marked items failed: %s", tostring(err))
        end
      end)
    end
  else
    merchantOpen = false
  end
end)
