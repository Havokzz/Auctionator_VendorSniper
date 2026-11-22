local _, VS = ...

-- Scanning the auction house for items selling below vendor price.
--
-- This uses a summary scan: an empty Browse search, paged until the server has sent everything. It lists
-- every item on sale once, with its cheapest price per unit (minPrice) and how many are on sale. It has
-- no cooldown, unlike the full "replicate" scan (one per 15 minutes). The cheapest price is all we need:
-- if any auction of an item is below vendor price, the cheapest one is. How many units are cheap enough
-- is only known once the item is searched, which the Buy flow does before every purchase anyway.
--
-- Our Scan button starts *Auctionator's* summary scan, so Auctionator stores the prices too; we read the
-- same Browse results. That function is Auctionator-internal (not its official API), so it's guarded: if
-- it's missing or errors, we page through the results ourselves. When Auctionator's own Full Scan button
-- starts a summary scan, a hook notices and we read that one as well.
--
-- Steps and their share of the progress bar, roughly their share of the time (receiving takes most of a
-- minute; the vendor prices mostly load while the pages arrive, so the rest takes about a second):
--   scanning  0-95%    the server sends the items in pages of 500 (the auction house must stay open)
--   loading   95-99%   vendor prices of items the client hasn't cached yet
--   finding   99-100%  deals

VS.Scan = {}
local Scan = VS.Scan
local ItemData = VS.ItemData

local LOAD_TIMEOUT = 60    -- seconds to wait for item data (vendor prices) before skipping the rest
local STALL_TIMEOUT = 30   -- seconds without a new page before the scan is given up
local NUDGE_AFTER = 4      -- seconds without a new page before the next page is asked for again
local THROTTLE_RETRY = 0.25
local SLICE_MS = 6         -- milliseconds of work per frame, so the game doesn't freeze
local DEFAULT_EXPECTED = 20000 -- browse results a first scan expects (gear has one per item level and suffix)

Scan.IDLE, Scan.SCANNING, Scan.LOADING, Scan.EVALUATING = "idle", "scanning", "loading", "evaluating"

local state = Scan.IDLE
local scanId = 0
local startedAt = 0      -- GetTime() when the scan started
local lastPageAt = 0     -- GetTime() of the last page of results
local lastNudgeAt = 0    -- GetTime() the next page was last asked for again (see Nudge)
local Nudge -- defined below
local driver             -- "auctionator" when Auctionator pages through the results, "self" when we do
local done, total = 0, 0 -- progress within the current step
local hooked = false
local loadBatch -- the vendor prices being loaded (ItemData batch)
local removedAt = {} -- itemID -> GetTime() the buy flow found nothing left to buy
local live    -- the scan whose pages are arriving (see NewScan)
local lastScan -- the last complete scan, rechecked when a setting changes what counts as a deal
local NewScan -- defined below

VS.deals = {}
VS.dealsScannedAt = nil

local events = CreateFrame("Frame")

local function SetState(newState, newDone, newTotal)
  state = newState
  done, total = newDone or 0, newTotal or 0
  VS.Fire("SCAN_CHANGED")
end

-- Progress -----------------------------------------------------------------------------------------

function Scan.IsBusy()
  return state ~= Scan.IDLE
end

-- True while the server is still sending pages: searches would compete with them for the throttle.
function Scan.IsReceiving()
  return state == Scan.SCANNING
end

-- state, overall progress 0-1, done and total within the current step, seconds since the scan started
function Scan.GetProgress()
  if state == Scan.LOADING then
    local loaded, all = ItemData.GetProgress(loadBatch)
    done, total = loaded or 0, all or 0
  end
  local step = total > 0 and math.min(1, done / total) or 0
  local overall = 0
  if state == Scan.SCANNING then
    overall = 0.95 * math.min(step, 0.98) -- the result count is an estimate from the last scan
  elseif state == Scan.LOADING then
    overall = 0.95 + 0.04 * step
  elseif state == Scan.EVALUATING then
    overall = 0.99 + 0.01 * step
  end
  return state, overall, done, total, state == Scan.IDLE and 0 or GetTime() - startedAt
end

-- Auctionator ------------------------------------------------------------------------------------

local function AuctionatorScanFrame()
  local frame = AuctionatorIncrementalScanFrame
  if frame and type(frame.InitiateScan) == "function" then
    return frame
  end
end

-- Whether the server has sent every page. Auctionator queues its query, so its own check (which knows
-- whether the query went out yet) is used while it pages.
local function HasFullResults()
  if driver == "auctionator" and Auctionator and Auctionator.AH and Auctionator.AH.HasFullBrowseResults then
    local ok, full = pcall(Auctionator.AH.HasFullBrowseResults)
    if ok then
      return full
    end
  end
  return C_AuctionHouse.HasFullBrowseResults()
end

-- Starting a scan --------------------------------------------------------------------------------

-- The events read while pages arrive.
local SCAN_EVENTS = {
  "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED",
  "AUCTION_HOUSE_BROWSE_RESULTS_ADDED",
  "ITEM_DATA_LOAD_RESULT",
  "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
  "AUCTION_HOUSE_SHOW_ERROR", -- DatabaseError came right before pages stopped, during purchases
}

local function ListenWhileScanning(on)
  for _, event in ipairs(SCAN_EVENTS) do
    if on then
      VS.SafeRegister(events, event)
    elseif events:IsEventRegistered(event) then
      events:UnregisterEvent(event)
    end
  end
end

local function Stop(message, ...)
  scanId = scanId + 1
  live = nil
  ListenWhileScanning(false)
  SetState(Scan.IDLE)
  if message then
    VS.Print(message, ...)
  end
end

local function BeginScanning(by, newDriver)
  scanId = scanId + 1
  local id = scanId
  driver = newDriver
  startedAt, lastPageAt, lastNudgeAt = GetTime(), GetTime(), 0
  ListenWhileScanning(true)
  live = NewScan()
  VS.deals, VS.dealsByItem, lastScan = {}, nil, nil
  VS.Fire("DEALS_CHANGED", true)
  SetState(Scan.SCANNING, 0, VendorSniperDB.lastScanResults or DEFAULT_EXPECTED)
  VS.Print("scan started%s. Keep the auction house open until it reaches 95%%.", by and (" by " .. by) or "")
  local function CheckStall()
    if id ~= scanId or state ~= Scan.SCANNING then
      return
    end
    if GetTime() - lastPageAt >= STALL_TIMEOUT then
      Stop("scan stopped: the server sent nothing for %d seconds.", STALL_TIMEOUT)
      return
    end
    if GetTime() - lastPageAt >= NUDGE_AFTER and GetTime() - lastNudgeAt >= NUDGE_AFTER then
      Nudge(id, "no page for " .. math.floor(GetTime() - lastPageAt) .. "s")
    end
    C_Timer.After(1, CheckStall)
  end
  C_Timer.After(1, CheckStall)
end

-- Our own paging, used only when Auctionator's scan can't be started.
local function SendOwnQuery(id)
  if id ~= scanId then
    return
  end
  if not C_AuctionHouse.IsThrottledMessageSystemReady() then
    C_Timer.After(THROTTLE_RETRY, function() SendOwnQuery(id) end)
    return
  end
  C_AuctionHouse.SendBrowseQuery({ searchString = "", sorts = {}, filters = {}, itemClassFilters = {} })
end

local function RequestMore(id)
  if id ~= scanId or state ~= Scan.SCANNING then
    return
  end
  if not C_AuctionHouse.IsThrottledMessageSystemReady() then
    C_Timer.After(THROTTLE_RETRY, function() RequestMore(id) end)
    return
  end
  C_AuctionHouse.RequestMoreBrowseResults()
end

-- Asks for the next page again when none came for a while. Searches and purchases made during a scan share
-- the game's small queue of auction house messages with the page requests; when the queue is full the game
-- drops one (AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED), and if that was a page request nobody asks again:
-- Auctionator only asks for the next page when the previous one arrives. When the page arrives, Auctionator
-- reads it as usual and carries on paging.
Nudge = function(id, why)
  if id ~= scanId or state ~= Scan.SCANNING or done == 0 or HasFullResults() then
    return -- no first page yet (that query is still queued), or nothing more to ask for
  end
  lastNudgeAt = GetTime()
  VS.Debug("scan: asking for the next page again (%s)", why)
  RequestMore(id)
end

-- Auctionator's frame is created the first time the auction house opens, so this is retried until it exists.
local function HookAuctionator()
  local frame = AuctionatorScanFrame()
  if hooked or not frame then
    return
  end
  hooked = true
  hooksecurefunc(frame, "InitiateScan", function(self)
    -- our own Start is already scanning by the time it calls this, so only Auctionator's button gets here
    if state == Scan.IDLE and self.doingFullScan then
      BeginScanning("Auctionator", "auctionator")
    end
  end)
end

function Scan.Start()
  if state ~= Scan.IDLE then
    VS.Print("a scan is already running.")
    return
  end
  if not (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
    VS.Print("open the auction house first.")
    return
  end

  HookAuctionator()
  local frame = AuctionatorScanFrame()
  if frame and frame.doingFullScan then
    BeginScanning("Auctionator", "auctionator") -- it's already paging; read the same results
    return
  end
  BeginScanning(nil, frame and "auctionator" or "self")
  if not (frame and pcall(frame.InitiateScan, frame)) then
    driver = "self"
    SendOwnQuery(scanId)
  end
end

-- Finding deals ----------------------------------------------------------------------------------
--
-- Deals show up while the pages arrive: each item is checked as soon as its vendor price is known (most
-- are cached; the rest are requested and checked when they load). Once every page is in, the complete
-- results are checked again from scratch. Deal objects are kept per item ID across both passes, so the
-- deal the Buy button is working on stays the same object.

local function SortDeals(deals)
  table.sort(deals, function(a, b)
    if a.profit ~= b.profit then
      return a.profit > b.profit
    end
    return a.itemID < b.itemID
  end)
end

local publishPending = false

NewScan = function()
  local scan = {
    items = {},   -- itemID -> { itemKey, price = cheapest per unit, onSale }
    order = {},   -- itemIDs in first-seen order
    waiting = {}, -- itemID -> true while its vendor price loads
    deals = {},   -- itemID -> deal
    startedAt = startedAt,
  }
  -- Disenchant materials are priced from this scan's own results, not Auctionator's saved prices:
  -- Auctionator only saves the new prices after the scan ends, so until then it has older ones. A
  -- material that isn't on sale (or hasn't arrived yet) counts as unpriced, so a value is never too high.
  function scan.priceOf(itemID)
    local item = scan.items[itemID]
    return item and item.price or nil
  end
  return scan
end

local function AddResult(scan, result)
  local key = result.itemKey
  local itemID = key and key.itemID
  -- battle pets have no vendor price
  if not itemID or (key.battlePetSpeciesID or 0) ~= 0 or not result.minPrice or result.minPrice <= 0
    or (result.totalQuantity or 0) <= 0 then
    return nil
  end
  local item = scan.items[itemID]
  if not item then
    scan.items[itemID] = { itemKey = key, price = result.minPrice, onSale = result.totalQuantity }
    scan.order[#scan.order + 1] = itemID
  else
    item.onSale = item.onSale + result.totalQuantity
    if result.minPrice < item.price then
      item.price, item.itemKey = result.minPrice, key
    end
  end
  return itemID
end

-- Creates, updates or drops the deal for one item. False while its vendor price isn't loaded.
-- An item's value is its vendor price, or its disenchant value when that option is on and it's higher.
local function CheckItem(scan, itemID, minProfit)
  local value, via, sellPrice, maxStack = VS.Disenchant.DealValue(itemID, scan.priceOf)
  local known = scan.deals[itemID]
  local materials = VS.Disenchant.GetMaterials(itemID) or (known and known.materials)
  if not value then
    -- The item's data can leave the client's cache during or after the scan (it holds only so many items).
    -- Its vendor price and what it disenchants into never change, so a deal that kept them is valued again
    -- at this scan's prices. (Keeping its old value would leave one priced from the first pages only.)
    if not known or not known.sellPrice then
      return false
    end
    sellPrice = known.sellPrice
    value, via = VS.Disenchant.WorthOf(sellPrice, materials, scan.priceOf)
  end
  local item = scan.items[itemID]
  -- every possible disenchant result: gives the risk of a loss. Above the "Max disenchant risk" option, the
  -- item counts at its vendor price instead.
  local outcomes
  if via == "disenchant" then
    outcomes = VS.Disenchant.GetOutcomes(materials, scan.priceOf)
    if outcomes and VS.Disenchant.TooRisky(outcomes, item.price) then
      value, via, outcomes = sellPrice, "vendor", nil
    end
  end
  -- found sold out after this scan started: its results are older than that, so leave it out
  if value - item.price < minProfit or (removedAt[itemID] or 0) >= scan.startedAt then
    scan.deals[itemID] = nil
    return true
  end
  local deal = known
  if not deal then
    deal = VS.dealsByItem and VS.dealsByItem[itemID] or { itemID = itemID }
    scan.deals[itemID] = deal
  end
  local name, link, quality = C_Item.GetItemInfo(itemID)
  deal.itemKey = item.itemKey
  deal.name = name or deal.name or ("item:" .. itemID)
  deal.link = link or deal.link
  deal.quality = quality
  deal.icon = C_Item.GetItemIconByID(itemID)
  deal.sellPrice = sellPrice           -- what a vendor pays
  deal.materials = materials           -- what it disenchants into (Disenchant.GetMaterials), or nil
  if maxStack then
    deal.stackable = maxStack > 1
  end
  if deal.price ~= item.price or deal.value ~= value then
    deal.buyUnits, deal.totalProfit = nil, nil -- from a check at another price or value: out of date
  end
  deal.value, deal.via = value, via    -- what one is worth, and how ("vendor" / "disenchant")
  deal.price = item.price              -- cheapest price per item
  deal.onSale = item.onSale            -- items on sale in all, at any price
  deal.profit = value - item.price     -- per item, at the cheapest price
  deal.outcomes = outcomes             -- disenchant deals: every possible result (Disenchant.GetOutcomes)
  deal.risk = outcomes and VS.Disenchant.LossChance(outcomes, item.price) or nil -- chance one is a loss
  deal.riskForAllKey = nil             -- the list's tooltip works out the risk for all units again
  return true
end

-- Shows the scan's current deals in the list. replaced = the buy flow should start over from the top deal.
local function Publish(scan, replaced)
  local deals = {}
  for _, deal in pairs(scan.deals) do
    deals[#deals + 1] = deal
  end
  SortDeals(deals)
  VS.deals = deals
  VS.dealsByItem = scan.deals
  VS.Fire("DEALS_CHANGED", replaced)
end

-- At most twice a second while pages arrive.
local function PublishSoon(id)
  if publishPending then
    return
  end
  publishPending = true
  C_Timer.After(0.5, function()
    publishPending = false
    if id == scanId and live then
      Publish(live)
    end
  end)
end

-- A page of results arrived while scanning.
local function AddPage(results)
  local minProfit = math.max(1, VS.GetSetting("minItemProfit"))
  for _, result in ipairs(results) do
    local itemID = AddResult(live, result)
    if itemID and not live.waiting[itemID] and not CheckItem(live, itemID, minProfit) then
      live.waiting[itemID] = true
      C_Item.RequestLoadItemDataByID(itemID)
    end
  end
  PublishSoon(scanId)
end

-- The final pass over the complete results.
local function Evaluate(id, scan, missing)
  local order = scan.order
  SetState(Scan.EVALUATING, 0, #order)
  local minProfit = math.max(1, VS.GetSetting("minItemProfit"))
  local position = 0
  local function Step()
    if id ~= scanId then
      return
    end
    local deadline = debugprofilestop() + SLICE_MS
    while position < #order do
      position = position + 1
      CheckItem(scan, order[position], minProfit)
      if debugprofilestop() > deadline then
        break
      end
    end
    done = position
    VS.Fire("SCAN_CHANGED")
    if position < #order then
      C_Timer.After(0, Step)
      return
    end
    Publish(scan)
    lastScan = scan
    VS.dealsScannedAt = time()
    local seconds = GetTime() - startedAt
    SetState(Scan.IDLE)
    VS.Print("scan done in %ds: %d items on sale, %d of them below vendor price.", seconds, #order, #VS.deals)
    VS.Fire("SCAN_DONE") -- Auctionator has new prices too
    if missing > 0 then
      VS.Print("%d items never loaded their vendor price and were skipped.", missing)
    end
  end
  Step()
end

-- Every page has arrived: rebuild from the complete results, load the missing vendor prices, check all.
local function ReadResults()
  local id = scanId
  ListenWhileScanning(false)
  local scan = NewScan()
  scan.deals = live and live.deals or {} -- keeps the deals shown so far, and their objects
  live = nil
  local results = C_AuctionHouse.GetBrowseResults()
  for _, result in ipairs(results) do
    AddResult(scan, result)
  end
  if #results > 0 then
    -- the next scan's progress estimate: it counts browse results as they arrive, not items
    VendorSniperDB.lastScanResults = #results
  end
  -- drop deals for items no longer in the results
  for itemID in pairs(scan.deals) do
    if not scan.items[itemID] then
      scan.deals[itemID] = nil
    end
  end
  -- everything needed is copied out; the auction house may close from here on
  SetState(Scan.LOADING)
  loadBatch = ItemData.LoadMany(scan.order, LOAD_TIMEOUT, function(missing)
    if id == scanId then
      Evaluate(id, scan, missing)
    end
  end)
end

-- Deal list maintenance (used by the buy flow) ---------------------------------------------------

function Scan.RemoveDeal(deal)
  removedAt[deal.itemID] = GetTime()
  if VS.dealsByItem and VS.dealsByItem[deal.itemID] == deal then
    VS.dealsByItem[deal.itemID] = nil
  end
  for i, other in ipairs(VS.deals) do
    if other == deal then
      table.remove(VS.deals, i)
      VS.Fire("DEALS_CHANGED")
      return
    end
  end
end

-- The buy flow checked the item live: its price is newer than the scan's, so a recheck keeps it.
function Scan.UpdateDeal(deal)
  local item = lastScan and lastScan.items[deal.itemID]
  if item and deal.price then
    item.price = deal.price
  end
  SortDeals(VS.deals)
  VS.Fire("DEALS_CHANGED")
end

-- A new minimum profit, or turning disenchant values on or off, applies to the list right away: every item
-- of the last scan is checked again. While a scan runs, its final pass uses the new setting anyway.
VS.On("SETTINGS_CHANGED", function(key)
  if key ~= "minItemProfit" and key ~= "includeDisenchant" and key ~= "maxDisenchantRisk" then
    return
  end
  if state ~= Scan.IDLE then
    return
  end
  if not lastScan then
    if key == "includeDisenchant" then
      VS.Print("disenchant values count from the next scan.")
    end
    return
  end
  local scan, before = lastScan, #VS.deals
  local minProfit = math.max(1, VS.GetSetting("minItemProfit"))
  -- items whose data left the client's cache can't be checked yet: load them, then check them again
  local unloaded = {}
  for _, itemID in ipairs(scan.order) do
    if not CheckItem(scan, itemID, minProfit) then
      unloaded[#unloaded + 1] = itemID
    end
  end
  Publish(scan, true) -- the buy flow starts over from the best deal
  local function Report()
    if #VS.deals ~= before then
      VS.Print("the list now has %d deal%s (was %d).", #VS.deals, #VS.deals == 1 and "" or "s", before)
    end
  end
  if #unloaded == 0 then
    Report()
    return
  end
  ItemData.LoadMany(unloaded, LOAD_TIMEOUT, function(missing)
    if scan ~= lastScan then
      return -- a new scan replaced it
    end
    local current = math.max(1, VS.GetSetting("minItemProfit"))
    for _, itemID in ipairs(unloaded) do
      CheckItem(scan, itemID, current)
    end
    Publish(scan)
    Report()
  end)
end)

-- Events -----------------------------------------------------------------------------------------

events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:RegisterEvent("AUCTION_HOUSE_CLOSED")
events:SetScript("OnEvent", function(_, event, ...)
  if event == "AUCTION_HOUSE_SHOW" then
    HookAuctionator()
    C_Timer.After(0, HookAuctionator) -- in case Auctionator creates its frame after us
  elseif event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
    if state ~= Scan.SCANNING then
      return
    end
    lastPageAt = GetTime()
    if event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
      local added = ...
      if type(added) == "table" then
        done = done + #added
        AddPage(added)
      end
    else
      -- the first page, or the whole list sent again: start the preview over, keeping the deal objects
      local results = C_AuctionHouse.GetBrowseResults()
      done = #results
      local deals = live.deals
      live = NewScan()
      live.deals = deals
      AddPage(results)
    end
    VS.Fire("SCAN_CHANGED")
    if HasFullResults() then
      ReadResults()
    elseif driver == "self" then
      RequestMore(scanId)
    end
  elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" or event == "AUCTION_HOUSE_SHOW_ERROR" then
    -- maybe the page request was dropped or failed: ask again shortly, unless a page arrives first
    local id, droppedAt = scanId, GetTime()
    local why = event == "AUCTION_HOUSE_SHOW_ERROR" and ("auction house error " .. tostring((...)))
      or "a message was dropped"
    VS.Debug("scan: %s", why)
    C_Timer.After(0.5, function()
      if lastPageAt < droppedAt then
        Nudge(id, why)
      end
    end)
  elseif event == "ITEM_DATA_LOAD_RESULT" then
    local itemID = ...
    if live and live.waiting[itemID] and live.items[itemID]
      and CheckItem(live, itemID, math.max(1, VS.GetSetting("minItemProfit"))) then
      live.waiting[itemID] = nil
      PublishSoon(scanId)
    end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    if state == Scan.SCANNING then
      Stop("scan stopped: the auction house was closed before every page arrived. Scan again any time - there's no cooldown.")
    elseif state ~= Scan.IDLE then
      VS.Print("the auction house closed, but the results were already in - the deals will be ready next time you open it.")
    end
  end
end)
