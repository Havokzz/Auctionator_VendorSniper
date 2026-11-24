local _, VS = ...

-- Profit of every recipe this character knows, from Auctionator's prices.
--   cost    = sum of reagents at their cheapest source (auction house, or a vendor if it sells them)
--   revenue = items made x the best way to sell one: auction house (minus the 5% cut), a vendor, or
--             disenchanting it and selling the materials (minus the 5% cut)
--   profit  = revenue - cost

VS.Crafting = {}
local Crafting = VS.Crafting

local AH_CUT = 0.95
local LOAD_TIMEOUT = 20

local loadBatch

-- Item IDs used by the recipes, so their names and vendor prices can be loaded.
local function AllItemIDs()
  local ids, seen = {}, {}
  local function Add(itemID)
    if itemID and not seen[itemID] then
      seen[itemID] = true
      ids[#ids + 1] = itemID
    end
  end
  for _, profession in pairs(VS.Recipes.GetProfessions()) do
    for _, recipe in pairs(profession.recipes) do
      Add(recipe.output)
      for _, reagent in ipairs(recipe.reagents) do
        Add(reagent.itemID)
      end
    end
  end
  return ids
end

-- Loads every item the recipes use, then fires CRAFTING_CHANGED so the tab recalculates.
function Crafting.LoadItems()
  if loadBatch then
    return
  end
  loadBatch = VS.ItemData.LoadMany(AllItemIDs(), LOAD_TIMEOUT, function()
    loadBatch = nil
    VS.Fire("CRAFTING_CHANGED")
  end)
end

-- How many times the recipe can be made from what's in the bags (and bank, where the client knows it).
local function CraftableFromBags(recipe)
  local count
  for _, reagent in ipairs(recipe.reagents) do
    local have = C_Item.GetItemCount(reagent.itemID, true) or 0
    local times = math.floor(have / reagent.quantity)
    count = math.min(count or times, times)
  end
  return count or 0
end

-- The best way to sell one crafted item: value, "AH" / "vendor" / "disenchant", and the auction house
-- price before the 5% cut (nil when it sells to a vendor, which takes no cut).
local function BestSale(itemID)
  local best, via, listed = nil, nil, nil
  local auction = VS.Prices.Auction(itemID)
  if auction then
    best, via, listed = math.floor(auction * AH_CUT), "AH", auction
  end
  local sellPrice = VS.ItemData.GetSellInfo(itemID)
  if sellPrice and sellPrice > 0 and (not best or sellPrice > best) then
    best, via, listed = sellPrice, "vendor", nil
  end
  local disenchant = VS.Disenchant.GetValue(itemID)
  if disenchant and disenchant > 0 and (not best or disenchant * AH_CUT > best) then
    best, via, listed = math.floor(disenchant * AH_CUT), "disenchant", disenchant
  end
  return best, via, listed
end

-- Cost, sale value and profit of one recipe: { recipeID, profession, name, icon, output, link, made, cost,
-- unpriced, revenue, listed, via, profit, age, craftable, reagents = { {itemID, quantity, price, source} } }.
-- listed is what everything one craft makes sells for on the auction house before the 5% cut (nil when
-- it's sold to a vendor).
-- profit is nil when a price is missing.
function Crafting.Evaluate(recipeID, recipe, professionName)
  local cost, unpriced, reagents = 0, 0, {}
  for _, reagent in ipairs(recipe.reagents) do
    local price, source = VS.Prices.Cheapest(reagent.itemID)
    reagents[#reagents + 1] = { itemID = reagent.itemID, quantity = reagent.quantity, price = price, source = source }
    if price then
      cost = cost + price * reagent.quantity
    else
      unpriced = unpriced + 1
    end
  end
  local sale, via, listed = BestSale(recipe.output)
  local revenue = sale and math.floor(sale * recipe.made) or nil
  local name, link, quality = C_Item.GetItemInfo(recipe.output)
  return {
    recipeID = recipeID,
    profession = professionName,
    name = name or recipe.name,
    icon = C_Item.GetItemIconByID(recipe.output) or recipe.icon,
    output = recipe.output,
    link = link,
    quality = quality,
    made = recipe.made,
    cost = cost,
    unpriced = unpriced,
    revenue = revenue,
    listed = revenue and listed and math.floor(listed * recipe.made) or nil,
    via = via,
    profit = revenue and unpriced == 0 and (revenue - cost) or nil,
    age = via == "AH" and VS.Prices.AgeDays(recipe.output) or nil,
    craftable = CraftableFromBags(recipe),
    reagents = reagents,
  }
end

-- One row per recipe this character knows (see Evaluate), sorted by profit, unknown profits last.
function Crafting.GetRows()
  local rows = {}
  for professionName, profession in pairs(VS.Recipes.GetProfessions()) do
    for recipeID, recipe in pairs(profession.recipes) do
      rows[#rows + 1] = Crafting.Evaluate(recipeID, recipe, professionName)
    end
  end
  table.sort(rows, function(a, b)
    if (a.profit ~= nil) ~= (b.profit ~= nil) then
      return a.profit ~= nil
    end
    if a.profit and a.profit ~= b.profit then
      return a.profit > b.profit
    end
    return (a.name or "") < (b.name or "")
  end)
  return rows
end

-- Opens Auctionator's Shopping tab with a search for the crafted item and the recipe's reagents (the auction
-- house must be open). The crafted item comes first, so its competition shows at the top.
function Crafting.SearchReagents(row, times)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not (api and api.MultiSearchAdvanced) then
    VS.Print("Auctionator's search isn't available.")
    return
  end
  local terms = {}
  local product = C_Item.GetItemInfo(row.output) or row.name
  if product then
    terms[1] = { searchString = product, isExact = true }
  end
  for _, reagent in ipairs(row.reagents) do
    local name = C_Item.GetItemInfo(reagent.itemID)
    if name and reagent.source ~= "vendor" then
      terms[#terms + 1] = { searchString = name, isExact = true, quantity = reagent.quantity * (times or 1) }
    end
  end
  if #terms == 0 then
    VS.Print("nothing to search for: the items haven't loaded yet.")
    return
  end
  local ok, err = pcall(api.MultiSearchAdvanced, VS.callerID, terms)
  if not ok then
    VS.Print("Auctionator's search failed: %s", tostring(err))
  end
end
