local _, VS = ...

-- Buying more than one stack from a merchant. The game sells at most one stack per purchase (its own
-- Shift+click box stops at a stack), so right-clicking a stackable merchant item opens a box where any
-- amount can be typed (instead of the game's right-click, which buys one). It's bought in as many purchases as needed, one stack each, a moment apart.
--
-- The amount is capped by what you can afford, the room in your bags (free slots that can hold the item,
-- plus space left on stacks you already have), and the merchant's stock for limited items. Items that
-- cost something other than gold (tokens, currencies) aren't supported.

VS.MerchantBuy = {}
local MerchantBuy = VS.MerchantBuy

local BUY_INTERVAL = 0.2 -- seconds between purchases
local MAX_AMOUNT = 9999
local BAGS = { 0, 1, 2, 3, 4 }

local merchantOpen = false
local buying     -- the purchase under way: { index, link, left, chunk, batch, price, bought }
local popup      -- created on first use
local hooked = {} -- merchant item buttons we've hooked

-- Merchant data ----------------------------------------------------------------------------------

-- name, price (for one purchase of `batch` items), batch, numAvailable (-1 = unlimited), hasExtendedCost
local function ItemInfo(index)
  if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
    local info = C_MerchantFrame.GetItemInfo(index)
    if not info then
      return nil
    end
    return info.name, info.price or 0, math.max(1, info.stackCount or 1), info.numAvailable or -1,
      info.hasExtendedCost
  end
  local name, _, price, stackCount, numAvailable, _, _, extendedCost = GetMerchantItemInfo(index)
  return name, price or 0, math.max(1, stackCount or 1), numAvailable or -1, extendedCost
end

-- The most one purchase can buy (one stack).
local function PerPurchase(index, link)
  local most = GetMerchantItemMaxStack and GetMerchantItemMaxStack(index)
  if not most and link then
    most = select(8, C_Item.GetItemInfo(link))
  end
  return math.max(1, most or 1)
end

-- How many of the item fit in the bags: free slots of bags that can hold it, plus space left on stacks
-- of it the bags already hold.
local function BagRoom(link, itemStack)
  local itemID = C_Item.GetItemInfoInstant(link)
  local family = C_Item.GetItemFamily and C_Item.GetItemFamily(link) or 0
  local room = 0
  for _, bag in ipairs(BAGS) do
    local free, bagType = C_Container.GetContainerNumFreeSlots(bag)
    -- general bags (type 0) hold anything; special bags (quivers, soul bags...) only their own kind
    if free and free > 0 and (bagType == 0 or bit.band(bagType or 0, family or 0) ~= 0) then
      room = room + free * itemStack
    end
    for slot = 1, C_Container.GetContainerNumSlots(bag) do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and info.itemID == itemID and info.stackCount < itemStack then
        room = room + itemStack - info.stackCount
      end
    end
  end
  return room
end

-- What buying `wanted` of merchant item `index` comes to: a plan { name, link, total, cost, chunk, batch,
-- price, limit (why fewer than wanted, or nil) }, or nil and why it can't be bought.
local function Plan(index, wanted)
  local name, price, batch, available, extendedCost = ItemInfo(index)
  local link = GetMerchantItemLink(index)
  if not name or not link then
    return nil, "that item isn't in the merchant's list any more."
  elseif extendedCost then
    return nil, "it costs something other than gold, which this can't buy."
  end
  local perPurchase = PerPurchase(index, link)
  local itemStack = select(8, C_Item.GetItemInfo(link)) or perPurchase
  -- some items are sold in fixed bundles (e.g. 5 at a time): buy whole bundles only
  local chunk = math.max(batch, perPurchase - perPurchase % batch)
  local total, limit = math.floor(wanted / batch) * batch, nil
  if total < wanted then
    limit = ("sold in bundles of %d"):format(batch)
  end
  if available >= 0 and total > available * batch then
    total, limit = available * batch, ("the merchant has only %d"):format(available * batch)
  end
  if price > 0 then
    local affordable = math.floor(GetMoney() / price) * batch
    if total > affordable then
      total, limit = affordable, "that's all you can afford"
    end
  end
  local room = BagRoom(link, itemStack)
  room = room - room % batch
  if total > room then
    total, limit = room, "that's all your bags can hold"
  end
  return {
    name = name, link = link, total = math.max(0, total), cost = math.max(0, total) / batch * price,
    chunk = chunk, batch = batch, price = price, limit = limit,
  }
end

-- Buying -----------------------------------------------------------------------------------------

local events = CreateFrame("Frame")

local function Finish(reason)
  if not buying then
    return
  end
  events:UnregisterEvent("UI_ERROR_MESSAGE")
  local done = buying
  buying = nil
  if done.bought > 0 then
    VS.Print("bought %dx %s for %s%s", done.bought, done.link, VS.FormatMoney(done.bought / done.batch * done.price),
      reason and (" - stopped: " .. reason) or ".")
  elseif reason then
    VS.Print("didn't buy %s: %s", done.link, reason)
  end
end

local function BuyNext()
  if not buying then
    return
  end
  if not merchantOpen then
    Finish("the merchant window closed.")
    return
  end
  if GetMerchantItemLink(buying.index) ~= buying.link then
    Finish("the merchant's list changed.")
    return
  end
  local amount = math.min(buying.chunk, buying.left)
  if amount / buying.batch * buying.price > GetMoney() then
    Finish("not enough money left.")
    return
  end
  BuyMerchantItem(buying.index, amount)
  buying.left = buying.left - amount
  buying.bought = buying.bought + amount
  if buying.left <= 0 then
    Finish()
    return
  end
  local current = buying
  C_Timer.After(BUY_INTERVAL, function()
    if buying == current then
      BuyNext()
    end
  end)
end

function MerchantBuy.Buy(index, wanted)
  if buying then
    VS.Print("still buying the last order.")
    return
  end
  local plan, err = Plan(index, wanted)
  if not plan then
    VS.Print("can't buy that: %s", err)
    return
  end
  if plan.total <= 0 then
    VS.Print("can't buy any %s: %s.", plan.link, plan.limit or "nothing to buy")
    return
  end
  buying = { index = index, link = plan.link, left = plan.total, chunk = plan.chunk, batch = plan.batch,
    price = plan.price, bought = 0 }
  events:RegisterEvent("UI_ERROR_MESSAGE") -- bags full, not enough money, merchant out of stock...
  BuyNext() -- the first purchase right away, from the click
end

-- The "Buy how many?" box -------------------------------------------------------------------------

local function UpdatePopup()
  local wanted = tonumber(popup.amount:GetText()) or 0
  local plan, err = Plan(popup.index, wanted)
  if not plan then
    popup.summary:SetText("|cffff5050" .. err .. "|r")
    popup.buy:Disable()
    return
  end
  local text
  if wanted <= 0 then
    text = "Type how many to buy."
  else
    local purchases = math.ceil(plan.total / plan.chunk)
    text = ("%d for %s (%d purchase%s)"):format(plan.total, VS.FormatMoney(plan.cost), purchases,
      purchases == 1 and "" or "s")
    if plan.limit and plan.total < wanted then
      text = text .. "\n|cffffd200Only " .. plan.total .. ": " .. plan.limit .. ".|r"
    end
  end
  popup.summary:SetText(text)
  popup.buy:SetEnabled(plan.total > 0)
end

local function BuyFromPopup()
  local wanted = tonumber(popup.amount:GetText()) or 0
  local index = popup.index
  popup:Hide()
  if wanted > 0 then
    MerchantBuy.Buy(index, wanted)
  end
end

local function CreatePopup()
  local UI = VS.UI
  popup = CreateFrame("Frame", "VendorSniperMerchantBuy", UIParent, "BasicFrameTemplateWithInset")
  popup:SetSize(280, 140)
  popup:SetFrameStrata("DIALOG")
  popup:EnableMouse(true)
  table.insert(UISpecialFrames, "VendorSniperMerchantBuy") -- Escape closes it

  local title = popup.TitleText or UI.Text(popup, "GameFontNormal", "CENTER")
  if not popup.TitleText then
    title:SetPoint("TOP", 0, -5)
  end
  title:SetText("Buy several stacks")

  popup.icon = popup:CreateTexture(nil, "ARTWORK")
  popup.icon:SetSize(28, 28)
  popup.icon:SetPoint("TOPLEFT", 14, -32)
  popup.name = UI.Text(popup, "GameFontHighlight")
  popup.name:SetPoint("LEFT", popup.icon, "RIGHT", 8, 0)
  popup.name:SetPoint("RIGHT", popup, "RIGHT", -14, 0)

  local label = UI.Text(popup, "GameFontNormal")
  label:SetPoint("TOPLEFT", popup.icon, "BOTTOMLEFT", 0, -12)
  label:SetText("How many:")
  popup.amount = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
  popup.amount:SetSize(70, 20)
  popup.amount:SetPoint("LEFT", label, "RIGHT", 12, 0)
  popup.amount:SetNumeric(true)
  popup.amount:SetMaxLetters(#tostring(MAX_AMOUNT))
  popup.amount:SetAutoFocus(true)
  popup.amount:SetScript("OnTextChanged", UpdatePopup)
  popup.amount:SetScript("OnEnterPressed", function()
    if popup.buy:IsEnabled() then
      BuyFromPopup()
    end
  end)
  popup.amount:SetScript("OnEscapePressed", function()
    popup:Hide()
  end)

  popup.summary = UI.Text(popup, "GameFontHighlightSmall")
  popup.summary:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -10)
  popup.summary:SetPoint("RIGHT", popup, "RIGHT", -14, 0)
  popup.summary:SetWordWrap(true)

  popup.buy = UI.Button(popup, "Buy", 100, 22)
  popup.buy:SetPoint("BOTTOMRIGHT", popup, "BOTTOM", -4, 10)
  popup.buy:SetScript("OnClick", BuyFromPopup)
  local cancel = UI.Button(popup, "Cancel", 100, 22)
  cancel:SetPoint("BOTTOMLEFT", popup, "BOTTOM", 4, 10)
  cancel:SetScript("OnClick", function()
    popup:Hide()
  end)
end

function MerchantBuy.Open(index)
  local link = GetMerchantItemLink(index)
  if not link then
    return
  end
  if not popup then
    CreatePopup()
  end
  popup.index = index
  popup.icon:SetTexture(C_Item.GetItemIconByID(link))
  popup.name:SetText(link)
  popup:ClearAllPoints()
  if MerchantFrame and MerchantFrame:IsShown() then
    popup:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 4, 0)
  else
    popup:SetPoint("CENTER")
  end
  popup:Show()
  -- start at one stack
  local perPurchase = PerPurchase(index, link)
  popup.amount:SetText(tostring(perPurchase))
  popup.amount:HighlightText()
  popup.amount:SetFocus()
  UpdatePopup()
end

-- Right-click on merchant items ----------------------------------------------------------------------

-- Whether a right-click on merchant item `index` opens the box: stackable items that cost gold, on the
-- merchant's own tab. Everything else keeps the game's right-click (buy one).
local function OpensBox(index)
  if VS.GetSetting("merchantBulkBuy") == false then
    return false
  end
  if MerchantFrame and MerchantFrame.selectedTab and MerchantFrame.selectedTab ~= 1 then
    return false -- the buyback tab
  end
  local name, _, _, _, extendedCost = ItemInfo(index)
  local link = GetMerchantItemLink(index)
  return name ~= nil and link ~= nil and not extendedCost and PerPurchase(index, link) > 1
end

-- The game's right-click buys one item at once, and a hook only runs after that. So the buttons' click
-- handler is wrapped: a plain right-click on a stackable item opens the box instead, and every other click
-- (left-click, drag, Shift/Ctrl clicks, the buyback tab) goes to the game's own handler unchanged.
local function HookButtons()
  for i = 1, (MERCHANT_ITEMS_PER_PAGE or 10) + 2 do
    local button = _G["MerchantItem" .. i .. "ItemButton"]
    if button and not hooked[button] then
      hooked[button] = true
      local original = button:GetScript("OnClick")
      button:SetScript("OnClick", function(self, mouseButton, ...)
        if mouseButton == "RightButton" and not IsShiftKeyDown() and not IsControlKeyDown()
          and not IsAltKeyDown() and OpensBox(self:GetID()) then
          MerchantBuy.Open(self:GetID())
          return
        end
        if original then
          return original(self, mouseButton, ...)
        end
      end)
    end
  end
end

-- "Right-click to buy any amount" on merchant item tooltips
if GameTooltip.SetMerchantItem then
  hooksecurefunc(GameTooltip, "SetMerchantItem", function(tooltip, index)
    if OpensBox(index) then
      tooltip:AddLine("Right-click to buy any amount", 0.4, 0.8, 1)
      tooltip:Show()
    end
  end)
end

-- Events -------------------------------------------------------------------------------------------

events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_CLOSED")
VS.SafeRegister(events, "ADDON_ACTION_BLOCKED")
VS.SafeRegister(events, "ADDON_ACTION_FORBIDDEN")
events:SetScript("OnEvent", function(_, event, arg1, arg2)
  if event == "MERCHANT_SHOW" then
    merchantOpen = true
    HookButtons()
  elseif event == "MERCHANT_CLOSED" then
    merchantOpen = false
    if popup then
      popup:Hide()
    end
    Finish("the merchant window closed.")
  elseif event == "UI_ERROR_MESSAGE" then
    -- arg2 = the message: the game refused a purchase (bags full, not enough money, sold out...)
    Finish(tostring(arg2))
  elseif (event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN") and arg1 == VS.name
    and tostring(arg2):find("BuyMerchantItem") then
    Finish("the game doesn't let addons make more than one purchase per click here.")
  end
end)
