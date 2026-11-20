local _, VS = ...

-- Buying the current deal, one click per purchase.
--
-- Blizzard requires a real click (hardware event) for purchases, so PlaceBid, StartCommoditiesPurchase
-- and ConfirmCommoditiesPurchase are only ever called from Buy.Click, which the Buy button's OnClick
-- calls. Searches need no click and run on their own.
--
-- Flow for the current deal (the selected row, or the top one):
--   SEARCHING   live search for the item, to get real auctions and today's prices
--   READY       the next purchase is known; the button says what it buys
--     gear:        click -> PlaceBid(auctionID, buyout) -> PURCHASING
--     stackables:  click -> StartCommoditiesPurchase -> QUOTING -> server quotes a total ->
--                  CONFIRM (only if still below vendor value) -> click -> ConfirmCommoditiesPurchase
--   PURCHASING  waiting for the result; the item stays selected while more sell at the same price
-- Once it's sold out at that price (or nothing below vendor price is left, and the deal is removed), the
-- deal that takes its place in the list is selected and searched.
-- "Vendor price" here is the deal's value: what a vendor pays, or what disenchanting is worth when that
-- option is on and it's more (see Disenchant.DealValue).

VS.Buy = {}
local Buy = VS.Buy

local SEARCH_TIMEOUT = 5   -- seconds to wait for search results before sending the search again
local SEARCH_ATTEMPTS = 3  -- searches without an answer before the item counts as no longer on sale
local THROTTLE_WAIT = 2    -- seconds to wait for the server's throttle before searching anyway (not while scanning)
local QUOTE_TIMEOUT = 10
local PURCHASE_TIMEOUT = 8
local THROTTLE_RETRY = 0.25
local DROPPED_RETRY_SCANNING = 1.5 -- seconds before sending a dropped search again while a scan pages

Buy.IDLE, Buy.SEARCHING, Buy.READY = "idle", "searching", "ready"
Buy.QUOTING, Buy.CONFIRM, Buy.PURCHASING = "quoting", "confirm", "purchasing"

local state = Buy.IDLE
local target    -- the deal being worked on (an entry of VS.deals)
local offer     -- { kind = "item", auctions = {...} } or { kind = "commodity", quantity, price, value }
local quote     -- total the server quoted for the commodity purchase
local pending   -- the item auction a PlaceBid is waiting on
local moneyBefore -- GetMoney() when the purchase was sent: money leaving is the surest sign it went through
local attempts = 0 -- searches sent for the current target without an answer
local throttledSince
local token = 0 -- every state change invalidates the timers of the previous state
local active = false
local useBuyTab = false -- set once the game blocks our gear purchase: hand gear over to Blizzard's Buy tab
local skipped = {} -- itemID -> true, deals skipped this session
local picked = false -- the target is a row the player clicked (kept even when it isn't the best deal)
local gone = {}    -- auctionID -> true: the server said it's gone, though searches may still list it for a while
local sent = {}    -- item purchases sent and not confirmed yet (see RecordItem)

-- Least profit per item (vendor price minus what we pay for it).
local function MinProfit()
  return math.max(1, VS.GetSetting("minItemProfit"))
end

-- What we may spend now: our money, capped by the session limit.
local function Budget()
  local budget = GetMoney()
  local maxSpend = VS.GetSetting("maxSpend")
  if maxSpend > 0 then
    budget = math.min(budget, maxSpend - VS.session.spent)
  end
  return math.max(0, budget)
end

local function SetState(newState)
  if newState ~= state then
    VS.Debug("buy: %s -> %s%s", state, newState, target and (" (" .. (target.name or target.itemID) .. ")") or "")
  end
  state = newState
  token = token + 1
  VS.Fire("BUY_CHANGED")
end

-- Runs fn after `seconds` unless the state changed in the meantime.
local function After(seconds, fn)
  local current = token
  C_Timer.After(seconds, function()
    if current == token then
      fn()
    end
  end)
end

local function CancelQuote()
  if state == Buy.QUOTING or state == Buy.CONFIRM then
    C_AuctionHouse.CancelCommoditiesPurchase()
  end
end

-- Choosing the deal ------------------------------------------------------------------------------

local Search -- defined below

-- The most profitable deal that isn't skipped.
-- itemID -> what we could spend when its auctions turned out too expensive. Such a deal is passed over
-- until there's more to spend, so the buy flow doesn't stall on a deal it can't afford.
local tooExpensive = {}

local function Eligible(deal, budget)
  return not skipped[deal.itemID] and (deal.price or 0) <= budget
    and not (tooExpensive[deal.itemID] and budget <= tooExpensive[deal.itemID])
end

-- The most profitable deal that isn't skipped and that we can afford.
local function Best()
  local budget = Budget()
  for _, deal in ipairs(VS.deals) do
    if Eligible(deal, budget) then
      return deal
    end
  end
end
Buy.Best = Best

-- Where a deal is in the list (it's sorted by profit), or nil.
local function Position(deal)
  for i, other in ipairs(VS.deals) do
    if other == deal then
      return i
    end
  end
end

-- Moves on to the most profitable deal.
local function Next()
  target, offer, quote, pending = nil, nil, nil, nil
  picked = false
  if not active then
    SetState(Buy.IDLE)
    return
  end
  target = Best()
  if not target then
    SetState(Buy.IDLE)
    return
  end
  attempts = 0
  Search()
end

-- Moves on to the deal at `position` in the list: when the current one sold out at its profit, or left
-- the list, this is the row that took its place (the list moved up, or the old deal sorted lower with what
-- it has left). Below it if that one can't be bought; the best deal if nothing below can. A row the
-- player clicked keeps counting as clicked, so the selection stays where they were working.
local function NextAt(position)
  if not position then
    Next()
    return
  end
  local keepPicked = picked
  target, offer, quote, pending = nil, nil, nil, nil
  if not active then
    SetState(Buy.IDLE)
    return
  end
  local budget = Budget()
  for i = position, #VS.deals do
    if Eligible(VS.deals[i], budget) then
      target = VS.deals[i]
      break
    end
  end
  if not target then
    Next()
    return
  end
  picked = keepPicked
  attempts = 0
  Search()
end

-- Nothing (affordable and) profitable is left for the current deal, so it leaves the list. `reason` says
-- why; it's printed when the player clicked the row, so it never just vanishes from under the cursor.
local function DealGone(reason)
  reason = reason or "nothing below its value is left (someone else bought it, or it was relisted higher)"
  if picked then
    VS.Print("%s: %s - removed from the list.", target.link or target.name, reason)
  else
    VS.Debug("buy: removed %s: %s", target.name or target.itemID, reason)
  end
  local position = Position(target)
  VS.Scan.RemoveDeal(target)
  NextAt(position)
end

-- Stops because of money, without dropping the deal.
local function OutOfBudget()
  if not picked then
    -- the buy flow chose it: pass it over for now and go on with deals we can afford
    VS.Debug("buy: can't afford %s, moving on", target.name or target.itemID)
    tooExpensive[target.itemID] = Budget()
    NextAt(Position(target))
    return
  end
  local maxSpend = VS.GetSetting("maxSpend")
  if maxSpend > 0 and VS.session.spent >= maxSpend then
    VS.Print("max spend for this session reached (%s). Change it with /vsnipe maxspend.", VS.FormatMoney(maxSpend))
  else
    VS.Print("not enough money for %s.", target.link or target.name)
  end
  offer = nil
  SetState(Buy.IDLE)
end

-- Searching --------------------------------------------------------------------------------------

-- No auctions came back. The scan's item key carries details like the item level; if searching with it
-- finds nothing, a plain key for the item ID is tried once.
local function NoResults()
  VS.Debug("buy: no results for %s", target.name or target.itemID)
  if not target.triedPlainKey then
    target.triedPlainKey = true
    local key = target.itemKey
    if key and ((key.itemLevel or 0) > 0 or (key.itemSuffix or 0) > 0) then
      target.searchKey = C_AuctionHouse.MakeItemKey(target.itemID)
      attempts = 0
      Search()
      return
    end
  end
  DealGone("it's no longer on the auction house")
end

-- The search went unanswered: send it again a few times before giving up on the item.
local function SearchTimedOut()
  if attempts < SEARCH_ATTEMPTS then
    VS.Debug("buy: no answer to search %d, sending it again", attempts)
    Search()
  else
    NoResults()
  end
end

function Search()
  if not target then
    SetState(Buy.IDLE)
    return
  end
  if state ~= Buy.SEARCHING then
    throttledSince = nil
  end
  SetState(Buy.SEARCHING)
  -- While a scan pages through the results, the server's throttle is busy almost all the time: each page
  -- is requested the moment the previous one arrives, so polling for "ready" loses that race for seconds.
  -- The client queues a message sent while throttled and sends it after the current page, so search now.
  -- (A dropped message is sent again, see AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED.)
  if not C_AuctionHouse.IsThrottledMessageSystemReady() and not VS.Scan.IsReceiving() then
    throttledSince = throttledSince or GetTime()
    if GetTime() - throttledSince < THROTTLE_WAIT then
      After(THROTTLE_RETRY, Search)
      return
    end
    VS.Debug("buy: still throttled after %ds, searching anyway", THROTTLE_WAIT)
  end
  throttledSince = nil
  attempts = attempts + 1
  target.searchKey = target.searchKey or target.itemKey or C_AuctionHouse.MakeItemKey(target.itemID)
  local sorts = {}
  if not target.stackable then
    sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Buyout, reverseSort = false } }
  end
  local key = target.searchKey
  VS.Debug("buy: search %d for item %d (level %s, suffix %s, %s)", attempts, key.itemID, tostring(key.itemLevel),
    tostring(key.itemSuffix), target.stackable and "stackable" or "gear")
  -- separateOwnerItems: our own auctions come back as rows of their own, so they can be left out
  C_AuctionHouse.SendSearchQuery(key, sorts, true)
  After(SEARCH_TIMEOUT, SearchTimedOut)
end

-- Shows the live cheapest price in the list.
-- Shows what a live check found: the cheapest price (and so the profit per item), and how many units one
-- click buys with their total profit (nil = not known until the item is checked again).
local function UpdateTarget(price, units, totalProfit)
  if price then
    target.price, target.profit = price, target.value - price
  end
  target.buyUnits, target.totalProfit = units, totalProfit
  VS.Scan.UpdateDeal(target)
end

-- Units and total profit of the item auctions still on offer.
local function ItemTotals(auctions)
  local units, total = 0, 0
  for _, auction in ipairs(auctions) do
    units = units + auction.quantity
    total = total + auction.profit
  end
  return units, total
end

local function ReadCommodities()
  attempts = 0
  local itemID, worth = target.itemID, target.value
  local budget, minProfit = Budget(), MinProfit()
  local quantity, cost, budgetLimited = 0, 0, false
  local first = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, 1)
  local cheapest = first and not first.containsOwnerItem and first.unitPrice or nil
  for index = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) do
    local result = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, index)
    -- sorted by unit price; the server always sells the cheapest units first, so stop at the first
    -- row that isn't cheap enough or is our own
    if not result or worth - result.unitPrice < minProfit or result.containsOwnerItem then
      break
    end
    local affordable = math.min(result.quantity, math.floor((budget - cost) / result.unitPrice))
    if affordable < result.quantity then
      budgetLimited = true
    end
    if affordable <= 0 then
      break
    end
    quantity = quantity + affordable
    cost = cost + affordable * result.unitPrice
    if budgetLimited then
      break
    end
  end
  local value = quantity * worth
  VS.Debug("buy: %d units below vendor price for %s%s", quantity, VS.FormatMoney(cost),
    budgetLimited and " (limited by money)" or "")
  if quantity == 0 then
    if budgetLimited then
      UpdateTarget(cheapest)
      OutOfBudget()
    elseif first and first.containsOwnerItem then
      DealGone("the cheapest units are your own auctions")
    else
      DealGone()
    end
    return
  end
  offer = { kind = "commodity", quantity = quantity, price = cost, value = value }
  UpdateTarget(cheapest, quantity, value - cost)
  -- the list showed an older price (e.g. before we bought its cheapest units): if another deal is better
  -- now, check that one instead
  if not picked and Best() ~= target then
    Next()
    return
  end
  SetState(Buy.READY)
end

local function ShowItemOffer()
  local cheapest
  for _, auction in ipairs(offer.auctions) do
    local unitPrice = math.floor(auction.price / auction.quantity)
    cheapest = math.min(cheapest or unitPrice, unitPrice)
  end
  UpdateTarget(cheapest, ItemTotals(offer.auctions))
  if not picked and Best() ~= target then
    Next() -- another deal is better at today's prices
    return
  end
  SetState(Buy.READY)
end

local function ReadItems(itemKey)
  attempts = 0
  local count = C_AuctionHouse.GetNumItemSearchResults(itemKey)
  local budget, minProfit = Budget(), MinProfit()
  local auctions, budgetLimited = {}, false
  local bidOnly, own = 0, 0 -- auctions below its value that can't be bought outright: bid only, or our own
  for index = 1, count do
    local result = C_AuctionHouse.GetItemSearchResultInfo(itemKey, index)
    local cheap = result and (result.buyoutAmount or result.bidAmount or math.huge) < target.value
    if cheap and result.containsOwnerItem then
      own = own + 1
    elseif cheap and not (result.buyoutAmount and result.buyoutAmount > 0) then
      bidOnly = bidOnly + 1 -- the scan's cheapest price can be a bid
    end
    if result and result.auctionID and not gone[result.auctionID]
      and not (sent[result.auctionID] and not sent[result.auctionID].unanswered)
      and result.buyoutAmount and result.buyoutAmount > 0
      and not result.containsOwnerItem then
      -- worth per item: the deal's value from the scan. Its disenchant value is priced from the scan's own
      -- results; Auctionator's saved prices can be older than that while a scan is being saved.
      local worth, via = target.value, target.via
      local _, maxStack = VS.ItemData.GetSellInfo(result.itemLink or target.itemID)
      -- one auction can't hold more than a stack: a bigger quantity counts identical auctions grouped in one
      -- row, and buying (PlaceBid) gets one of them
      local quantity = math.min(result.quantity or 1, maxStack or 1)
      local value = worth * quantity
      if value - result.buyoutAmount >= minProfit * quantity then
        if result.buyoutAmount > budget then
          budgetLimited = true
        else
          auctions[#auctions + 1] = {
            auctionID = result.auctionID,
            price = result.buyoutAmount,
            quantity = quantity,
            value = value,
            profit = value - result.buyoutAmount,
            via = via,
            link = result.itemLink,
          }
        end
      end
    end
  end
  VS.Debug("buy: %d auctions found, %d below vendor price, %d bid only, %d own%s", count, #auctions, bidOnly, own,
    budgetLimited and ", some too expensive" or "")
  if #auctions == 0 then
    if budgetLimited then
      OutOfBudget()
    elseif bidOnly > 0 then
      DealGone(("the auction%s below its value %s no buyout, only a bid (bid in Blizzard's Buy tab)"):format(
        bidOnly == 1 and "" or "s", bidOnly == 1 and "has" or "have"))
    elseif own > 0 then
      DealGone("the auctions below its value are your own")
    else
      DealGone()
    end
    return
  end
  table.sort(auctions, function(a, b) return a.profit > b.profit end)
  offer = { kind = "item", auctions = auctions }
  ShowItemOffer()
end

-- Purchases --------------------------------------------------------------------------------------

local SETTLE_SECONDS = 0.8 -- after a purchase, the gold has left the bags by then

local function Record(itemID, link, price, quantity, worth, ordered, via)
  local value = worth * quantity
  local session = VS.session
  session.spent = session.spent + price
  session.vendorValue = session.vendorValue + value
  session.purchases = session.purchases + 1
  VS.Print("bought %dx %s for %s (%s value %s, profit %s)%s.", quantity, link, VS.FormatMoney(price),
    via == "disenchant" and "disenchant" or "vendor", VS.FormatMoney(value), VS.FormatMoney(value - price),
    ordered and ordered ~= quantity and (" - %d were ordered"):format(ordered) or "")
  VS.Fire("SESSION_CHANGED")
  VS.Fire("PURCHASED", itemID, quantity, via)
end

-- Records a purchase from the gold that actually left the bags, not from what was ordered: the server may
-- sell fewer units than asked for. `expected` = { itemID, link, price, quantity, worth (per item), via,
-- commodity, money }.
local function RecordPurchase(expected)
  C_Timer.After(SETTLE_SECONDS, function()
    local paid = expected.money - GetMoney()
    local price, quantity = expected.price, expected.quantity
    if paid > 0 then
      if expected.commodity then
        local unitPrice = expected.price / expected.quantity
        quantity = math.max(1, math.min(expected.quantity, math.floor(paid / unitPrice + 0.5)))
        price = paid
      elseif paid >= expected.price * 0.5 and paid <= expected.price * 1.5 then
        price = paid
      end
    end
    VS.Debug("purchase settled: paid %s, expected %s for %d", VS.FormatMoney(math.max(0, paid)),
      VS.FormatMoney(expected.price), expected.quantity)
    Record(expected.itemID, expected.link, price, quantity, expected.worth,
      expected.commodity and expected.quantity or nil, expected.via)
  end)
end

-- Item purchases sent but not confirmed yet: auctionID -> { itemID, link, price, quantity, worth, via }.
-- A purchase can be confirmed seconds after an error that turned out to be about something else (Forever
-- sends DatabaseError while a scan is paging, then completes the purchase), or after we stopped waiting
-- for it, so each one is recorded whenever its confirmation arrives. (`sent` is declared at the top.)

-- Records a confirmed item purchase. False if it was already recorded (or isn't ours).
local function RecordItem(auctionID)
  local purchase = sent[auctionID]
  if not purchase then
    return false
  end
  sent[auctionID] = nil
  gone[auctionID] = true -- searches can list it for a while yet
  Record(purchase.itemID, purchase.link, purchase.price, purchase.quantity, purchase.worth, nil, purchase.via)
  return true
end

local function SentCount()
  local count = 0
  for _, purchase in pairs(sent) do
    if not purchase.unanswered then
      count = count + 1
    end
  end
  return count
end

local function WaitForPurchase(link)
  SetState(Buy.PURCHASING)
  After(PURCHASE_TIMEOUT, function()
    VS.Print("no answer to the purchase of %s after %d seconds - checking the auctions again.",
      link or target.link or target.name, PURCHASE_TIMEOUT)
    -- Usually it didn't happen (the auction is still listed), so it may be offered again. It's still
    -- recorded if a confirmation does arrive.
    if pending and sent[pending.auctionID] then
      sent[pending.auctionID].unanswered = true
    end
    pending = nil
    Search()
  end)
end

-- Opens Blizzard's own Buy tab on the item, where its Buyout button does the purchase.
local function OpenInBuyTab(deal)
  local ok, err = pcall(function()
    local buyTab = AuctionHouseFrame.BuyTab or AuctionHouseFrameBuyTab
    if buyTab then
      buyTab:Click()
    end
    AuctionHouseFrame:SelectBrowseResult({ itemKey = deal.itemKey or C_AuctionHouse.MakeItemKey(deal.itemID),
      minPrice = deal.price or 0 })
  end)
  if not ok then
    VS.Print("couldn't open the Buy tab: %s", tostring(err))
  end
end

-- Called by the Buy button's OnClick. Never call this from anything that isn't a click.
-- The purchase call comes first, before any of our own bookkeeping or interface updates, the same way
-- Auctionator's buy buttons do it (Forever blocked our PlaceBid when it came after them).
function Buy.Click()
  if state == Buy.READY and offer and offer.kind == "item" and useBuyTab then
    OpenInBuyTab(target)
  elseif state == Buy.READY and offer and offer.kind == "item" then
    local auction = offer.auctions[1]
    if auction.price > Budget() then
      OutOfBudget()
      return
    end
    local money = GetMoney()
    C_AuctionHouse.PlaceBid(auction.auctionID, auction.price) -- PlaceBid with the buyout price buys it outright
    pending, moneyBefore = auction, money
    sent[auction.auctionID] = { itemID = target.itemID, link = auction.link or target.link or target.name,
      price = auction.price, quantity = auction.quantity, worth = math.floor(auction.value / auction.quantity),
      via = auction.via }
    VS.Debug("buy: PlaceBid(auction %s, %s)", tostring(auction.auctionID), VS.FormatMoney(auction.price))
    WaitForPurchase(auction.link)
  elseif state == Buy.READY and offer and offer.kind == "commodity" then
    if offer.price > Budget() then
      OutOfBudget()
      return
    end
    C_AuctionHouse.StartCommoditiesPurchase(target.itemID, offer.quantity)
    quote = nil
    VS.Debug("buy: StartCommoditiesPurchase(%d, %d)", target.itemID, offer.quantity)
    SetState(Buy.QUOTING)
    After(QUOTE_TIMEOUT, function()
      CancelQuote()
      Search()
    end)
  elseif state == Buy.CONFIRM and offer and quote then
    local money = GetMoney()
    C_AuctionHouse.ConfirmCommoditiesPurchase(target.itemID, offer.quantity)
    moneyBefore = money
    VS.Debug("buy: ConfirmCommoditiesPurchase(%d, %d)", target.itemID, offer.quantity)
    WaitForPurchase()
  elseif state == Buy.IDLE then
    Next()
  end
end

-- Skips the current deal for the rest of the session.
function Buy.Skip()
  if not target then
    return
  end
  CancelQuote()
  skipped[target.itemID] = true
  Next()
end

-- Works on a specific deal (a clicked row).
function Buy.Select(deal)
  CancelQuote()
  skipped[deal.itemID] = nil
  target, offer, quote, pending = deal, nil, nil, nil
  picked = true
  attempts, throttledSince = 0, nil -- searches sent for the previous deal don't count against this one
  if active then
    Search()
  else
    SetState(Buy.IDLE)
  end
end

-- The deals tab tells us when it is visible; searches only run while it is.
function Buy.SetActive(isActive)
  if active == isActive then
    return
  end
  active = isActive
  if active then
    if state == Buy.IDLE then
      if target then
        Search()
      else
        Next()
      end
    end
  else
    CancelQuote()
    target, offer, quote, pending = nil, nil, nil, nil
    SetState(Buy.IDLE)
  end
end

function Buy.GetState()
  return state, target, offer, quote
end

-- True once gear purchases go through Blizzard's Buy tab (the game blocked ours).
function Buy.UsesBuyTab()
  return useBuyTab
end

function Buy.IsSkipped(itemID)
  return skipped[itemID] == true
end

-- Events -----------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
for _, event in ipairs({
  "COMMODITY_SEARCH_RESULTS_UPDATED",
  "ITEM_SEARCH_RESULTS_UPDATED",
  "COMMODITY_PRICE_UPDATED",
  "COMMODITY_PRICE_UNAVAILABLE",
  "COMMODITY_PURCHASE_SUCCEEDED",
  "COMMODITY_PURCHASE_FAILED",
  "AUCTION_HOUSE_PURCHASE_COMPLETED",
  "AUCTION_HOUSE_SHOW_ERROR",
  "UI_ERROR_MESSAGE",
  "AUCTION_HOUSE_CLOSED",
  "PLAYER_MONEY",
  "ADDON_ACTION_BLOCKED",
  "ADDON_ACTION_FORBIDDEN",
  "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED",
}) do
  VS.SafeRegister(events, event)
end

-- Auction house errors (Enum.AuctionHouseError). Only these mean the purchase failed; others, like
-- DatabaseError (10) while a scan pages, came right before purchases that completed.
local AuctionError = Enum and Enum.AuctionHouseError or {}
local NOT_ENOUGH_MONEY = AuctionError.NotEnoughMoney or 0
local SOLD_ERRORS = {} -- the auction is gone or can't be bought by us
for _, name in ipairs({ "ItemNotFound", "ItemNotAvailable", "HigherBid", "BidOwn", "DoubleBid" }) do
  if AuctionError[name] then
    SOLD_ERRORS[AuctionError[name]] = true
  end
end
local ERROR_NAMES = {}
for name, code in pairs(AuctionError) do
  ERROR_NAMES[code] = name
end

-- The purchase went through: count it and move on to the next auction or search again.
-- After a purchase the item stays selected while more are on sale at the same price. Once it's sold out at
-- that price, the deal that takes its place in the list is selected (see NextAt).
local function RemoveOffered(auctionID)
  for i, auction in ipairs(offer.auctions) do
    if auction.auctionID == auctionID then
      table.remove(offer.auctions, i)
      return
    end
  end
end

local function ItemBought()
  local position = Position(target)
  local boughtAt = math.floor(pending.price / pending.quantity)
  RecordItem(pending.auctionID)
  RemoveOffered(pending.auctionID)
  pending = nil
  local cheapest
  for _, auction in ipairs(offer.auctions) do
    cheapest = math.min(cheapest or auction.price, math.floor(auction.price / auction.quantity))
  end
  if cheapest and cheapest <= boughtAt then
    ShowItemOffer() -- more at the same price: the same profit, so it stays selected and in its place
    return
  end
  -- Sold out at this profit. Its row shows what's left (sorting lower) or leaves the list, and the deal
  -- that takes its place is selected.
  if cheapest then
    local units, total = ItemTotals(offer.auctions)
    UpdateTarget(cheapest, units, total)
  else
    VS.Scan.RemoveDeal(target) -- every auction below its value was bought
  end
  NextAt(position)
end

-- Every unit below its value was bought in one go, so the deal leaves the list and the one that takes its
-- place is selected. Units listed later show up in the next scan.
local function CommodityBought()
  RecordPurchase({ itemID = target.itemID, link = target.link or target.name, price = quote or offer.price,
    quantity = offer.quantity, worth = target.value, via = target.via, commodity = true, money = moneyBefore })
  local position = Position(target)
  VS.Scan.RemoveDeal(target)
  NextAt(position)
end

events:SetScript("OnEvent", function(_, event, ...)
  if event ~= "PLAYER_MONEY" and event ~= "UI_ERROR_MESSAGE" then
    VS.Debug("event %s %s", event, tostring((...)))
  end
  if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
    local addon, func = ...
    -- only purchase calls are ours to handle here (selling to vendors has its own handler)
    if addon ~= VS.name or not tostring(func):find("Bid") and not tostring(func):find("Commodit") then
      return
    end
    VS.Print("the game blocked %s, so this purchase didn't happen.", tostring(func))
    if target and offer and offer.kind == "item" then
      useBuyTab = true
      VS.Print("from now on the Buy button opens gear in Blizzard's Buy tab - click Buyout there, then come back.")
      OpenInBuyTab(target)
    end
    if pending then
      sent[pending.auctionID] = nil
    end
    pending = nil
    if target then
      Search()
    end
    return
  end
  if event == "AUCTION_HOUSE_CLOSED" then
    Buy.SetActive(false)
    return
  end
  if event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
    -- the client's queue was full and dropped a message, maybe our search: send it again shortly. It
    -- doesn't count as an unanswered search.
    -- While a scan pages, wait longer: resending every quarter second kept the queue full, which can drop
    -- the scan's own page requests.
    if state == Buy.SEARCHING then
      attempts = math.max(0, attempts - 1)
      After(VS.Scan.IsReceiving() and DROPPED_RETRY_SCANNING or THROTTLE_RETRY, Search)
    end
    return
  end
  if event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
    local auctionID = ...
    if state == Buy.PURCHASING and pending and pending.auctionID == auctionID then
      ItemBought()
    elseif RecordItem(auctionID) and state == Buy.READY and offer and offer.kind == "item" then
      -- a purchase confirmed after we stopped waiting for it: don't offer that auction again
      RemoveOffered(auctionID)
      if #offer.auctions > 0 then
        ShowItemOffer()
      else
        Search()
      end
    end
    return
  end
  if not target then
    return
  end

  if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    local itemID = ...
    if state ~= Buy.SEARCHING or itemID ~= target.itemID then
      return
    end
    -- the event also fires while a search restarts with no rows yet; wait for the real ones
    if C_AuctionHouse.GetNumCommoditySearchResults(itemID) == 0 then
      if C_AuctionHouse.HasFullCommoditySearchResults and C_AuctionHouse.HasFullCommoditySearchResults(itemID) then
        DealGone()
      end
      return
    end
    target.stackable = true
    ReadCommodities()

  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    local itemKey = ...
    if state ~= Buy.SEARCHING or not itemKey or itemKey.itemID ~= target.itemID then
      return
    end
    if C_AuctionHouse.GetNumItemSearchResults(itemKey) == 0 then
      if C_AuctionHouse.HasFullItemSearchResults and C_AuctionHouse.HasFullItemSearchResults(itemKey) then
        NoResults()
      end
      return
    end
    target.stackable = false
    ReadItems(itemKey)

  elseif event == "COMMODITY_PRICE_UPDATED" then
    if state ~= Buy.QUOTING then
      return
    end
    local _, totalPrice = ...
    if totalPrice and totalPrice <= offer.value - MinProfit() * offer.quantity and totalPrice <= Budget() then
      quote = totalPrice
      offer.price = totalPrice
      SetState(Buy.CONFIRM)
    else
      VS.Print("%s: the price went up to %s, no longer profitable - skipped this purchase.",
        target.link or target.name, VS.FormatMoney(totalPrice or 0))
      CancelQuote()
      Search()
    end

  elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
    if state == Buy.QUOTING then
      CancelQuote()
      Search()
    end

  elseif event == "PLAYER_MONEY" then
    -- the surest sign a purchase went through, whatever the auction house's own events are called
    if state == Buy.PURCHASING and moneyBefore then
      local paid = moneyBefore - GetMoney()
      VS.Debug("money changed by %s while buying", VS.FormatMoney(math.abs(paid)))
      -- only when this is the one item purchase waiting: an earlier one may be what was just paid for
      if offer and offer.kind == "item" and pending and paid >= pending.price and SentCount() == 1 then
        ItemBought()
      elseif offer and offer.kind == "commodity" and paid > 0 and paid >= (quote or offer.price) * 0.5 then
        CommodityBought()
      end
    end

  elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
    if state == Buy.PURCHASING and offer and offer.kind == "commodity" then
      CommodityBought()
    end

  elseif event == "COMMODITY_PURCHASE_FAILED" then
    if state == Buy.PURCHASING then
      VS.Print("purchase of %s failed.", target.link or target.name)
      Search()
    end

  elseif event == "AUCTION_HOUSE_SHOW_ERROR" or event == "UI_ERROR_MESSAGE" then
    if state ~= Buy.PURCHASING then
      return
    end
    local code = event == "AUCTION_HOUSE_SHOW_ERROR" and (...) or nil
    local message = event == "UI_ERROR_MESSAGE" and select(2, ...) or nil
    VS.Debug("error while buying: %s", tostring(message or ERROR_NAMES[code] or code))
    -- commodities: COMMODITY_PURCHASE_FAILED or the timeout decide
    if not (offer and offer.kind == "item" and pending) then
      return
    end
    if code == NOT_ENOUGH_MONEY then
      sent[pending.auctionID], pending = nil, nil
      OutOfBudget()
    elseif code and SOLD_ERRORS[code] then
      -- someone bought it first. Don't offer it again; move on to the item's other auctions, or drop the
      -- item from the list when none are left.
      gone[pending.auctionID], sent[pending.auctionID] = true, nil
      VS.Print("%s is no longer for sale.", pending.link or target.link or target.name)
      RemoveOffered(pending.auctionID)
      pending = nil
      if #offer.auctions > 0 then
        ShowItemOffer()
      else
        DealGone("someone else bought it first")
      end
    end
    -- Any other error (DatabaseError, IsBusy...) isn't taken as a failure: on Forever the purchase usually
    -- completes a few seconds later. AUCTION_HOUSE_PURCHASE_COMPLETED or the purchase timeout moves on.
  end
end)

-- A new scan replaced the list: start over from its top deal, unless a purchase is under way.
-- Otherwise, start as soon as deals arrive, even while the scan is still receiving pages: the best deal so
-- far is checked, and after every purchase the best one at that moment is picked.
VS.On("DEALS_CHANGED", function(replaced)
  if not active then
    return
  end
  if replaced and (state == Buy.IDLE or state == Buy.SEARCHING or state == Buy.READY) then
    Next()
  elseif state == Buy.IDLE and not target and #VS.deals > 0 then
    Next()
  end
end)

VS.On("SCAN_CHANGED", function()
  if active and state == Buy.IDLE and not target and #VS.deals > 0 then
    Next()
  end
end)
