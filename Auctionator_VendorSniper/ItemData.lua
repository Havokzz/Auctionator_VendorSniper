local _, VS = ...

-- Item info the client loads lazily: vendor sell price and stack size. GetItemInfo returns nil for an
-- item the client hasn't cached yet, so a batch of items is requested and waited for. Several batches
-- can run at once (the scan's and the crafting tab's).

VS.ItemData = {}
local ItemData = VS.ItemData

local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local RequestLoad = (C_Item and C_Item.RequestLoadItemDataByID) or function() end

local REREQUEST_SECONDS = 3

-- sellPrice (copper per unit), maxStack, or nil while the client hasn't loaded the item.
-- `item` is an itemID, item link or item string.
function ItemData.GetSellInfo(item)
  local _, _, _, _, _, _, _, maxStack, _, _, sellPrice = GetItemInfo(item)
  if sellPrice == nil then
    return nil
  end
  return sellPrice, maxStack or 1
end

local events = CreateFrame("Frame")
local batches = {} -- running batches -> true

local function Finish(batch)
  if not batches[batch] then
    return
  end
  batches[batch] = nil
  if next(batches) == nil then
    events:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
  end
  batch.onDone(batch.waiting)
end

local function Loaded(batch, itemID)
  if batch.pending[itemID] then
    batch.pending[itemID] = nil
    batch.waiting = batch.waiting - 1
  end
end

events:SetScript("OnEvent", function(_, _, itemID)
  local finished = {}
  for batch in pairs(batches) do
    Loaded(batch, itemID)
    if batch.waiting <= 0 then
      finished[#finished + 1] = batch
    end
  end
  for _, batch in ipairs(finished) do
    Finish(batch)
  end
end)

-- Loads the given itemIDs, then calls onDone(missing) with the number that never loaded within
-- timeoutSeconds. Returns the batch, for GetProgress and Cancel.
function ItemData.LoadMany(itemIDs, timeoutSeconds, onDone)
  local batch = { pending = {}, waiting = 0, onDone = onDone }
  for _, itemID in ipairs(itemIDs) do
    if not batch.pending[itemID] and ItemData.GetSellInfo(itemID) == nil then
      batch.pending[itemID] = true
      batch.waiting = batch.waiting + 1
    end
  end
  batch.total = batch.waiting
  batches[batch] = true
  if batch.waiting == 0 then
    Finish(batch)
    return batch
  end
  events:RegisterEvent("ITEM_DATA_LOAD_RESULT")
  for itemID in pairs(batch.pending) do
    RequestLoad(itemID)
  end
  local started = GetTime()
  local function Tick()
    if not batches[batch] then
      return
    end
    -- the event isn't always delivered, so look at what loaded in the meantime
    for itemID in pairs(batch.pending) do
      if ItemData.GetSellInfo(itemID) ~= nil then
        Loaded(batch, itemID)
      end
    end
    if batch.waiting <= 0 or GetTime() - started >= timeoutSeconds then
      Finish(batch)
      return
    end
    for itemID in pairs(batch.pending) do
      RequestLoad(itemID)
    end
    C_Timer.After(REREQUEST_SECONDS, Tick)
  end
  C_Timer.After(REREQUEST_SECONDS, Tick)
  return batch
end

-- Items loaded so far and in all for a batch, or nil once it's finished.
function ItemData.GetProgress(batch)
  if batch and batches[batch] then
    return math.max(0, batch.total - batch.waiting), batch.total
  end
end

-- Abandons a batch; its onDone never runs.
function ItemData.Cancel(batch)
  if batch then
    batches[batch] = nil
  end
end
