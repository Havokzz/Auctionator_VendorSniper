local _, VS = ...

-- Adds the disenchant value and materials to item tooltips, below Auctionator's Vendor and Auction lines.
-- Auctionator is a dependency, so it loads first and its tooltip hook runs before ours.

local LABEL_COLOR = NORMAL_FONT_COLOR
local DETAIL = { r = 0.8, g = 0.8, b = 0.8 }
local WARNING = ORANGE_FONT_COLOR or CreateColor(1, 0.5, 0.25)

local function MaterialName(itemID)
  local name = (C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)) or C_Item.GetItemInfo(itemID)
  if not name then
    C_Item.RequestLoadItemDataByID(itemID) -- shows on the next tooltip refresh
    return "item " .. itemID
  end
  return name
end

local function Amount(material)
  if material[2] == material[3] then
    return tostring(material[2])
  end
  return ("%d-%d"):format(material[2], material[3])
end

-- What the most likely result is worth after the auction house cut, e.g. "Usually (75%)  46s - 1g15s".
-- Orange when it's less than the average: the rarer results make up the value, so most disenchants are
-- worth less than it says.
local function AddUsualLine(tooltip, value, materials)
  local main = materials[1] -- the most likely material comes first
  local price = VS.Prices.Auction(main[1])
  if not price or main[4] > 0.9 or #materials < 2 then
    return
  end
  local cut = VS.Disenchant.AH_CUT
  local low, high = price * main[2] * cut, price * main[3] * cut
  local text = GetMoneyString(math.floor(low + 0.5), true)
  if high > low then
    text = text .. " - " .. GetMoneyString(math.floor(high + 0.5), true)
  end
  local color = high < value * cut and WARNING or WHITE_FONT_COLOR
  tooltip:AddDoubleLine(("   Usually (%d%%), after the 5%% cut"):format(main[4] * 100), color:WrapTextInColorCode(text),
    DETAIL.r, DETAIL.g, DETAIL.b)
end

local function AddDisenchantLines(tooltip, link)
  if VS.GetSetting("disenchantTooltip") == false then
    return
  end
  local value, materials, unpriced = VS.Disenchant.GetValue(link)
  if not value then
    return
  end
  local valueText = value > 0 and GetMoneyString(value, true) or "?"
  if unpriced and value > 0 then
    valueText = valueText .. " +?"
  end
  tooltip:AddDoubleLine("Disenchant", WHITE_FONT_COLOR:WrapTextInColorCode(valueText),
    LABEL_COLOR.r, LABEL_COLOR.g, LABEL_COLOR.b)
  for _, material in ipairs(materials) do
    local price = VS.Prices.Auction(material[1])
    local chance = material[4] * 100
    local chanceText = chance >= 1 and ("%d%%"):format(chance) or ("%.1f%%"):format(chance)
    tooltip:AddDoubleLine(("   %s  %s %s"):format(chanceText, Amount(material), MaterialName(material[1])),
      price and (GetMoneyString(price, true) .. " each") or "no price",
      DETAIL.r, DETAIL.g, DETAIL.b, DETAIL.r, DETAIL.g, DETAIL.b)
  end
  AddUsualLine(tooltip, value, materials)
end

-- What a merchant charges for the item, when Auctionator has seen it at one (its "Vendor" line is what a
-- merchant pays). Says which is cheaper to buy from: the merchant, or the auction house.
local function AddMerchantPriceLine(tooltip, link)
  if VS.GetSetting("merchantPriceTooltip") == false then
    return
  end
  local itemID = C_Item.GetItemInfoInstant(link)
  local merchant = itemID and VS.Prices.VendorBuy(itemID)
  if not merchant or merchant <= 0 then
    return
  end
  local auction = VS.Prices.Auction(itemID)
  if auction and auction < merchant then
    tooltip:AddDoubleLine("Merchant price", WHITE_FONT_COLOR:WrapTextInColorCode(GetMoneyString(merchant, true)),
      LABEL_COLOR.r, LABEL_COLOR.g, LABEL_COLOR.b)
    tooltip:AddDoubleLine("   Cheaper on the auction house", GetMoneyString(auction, true),
      DETAIL.r, DETAIL.g, DETAIL.b, DETAIL.r, DETAIL.g, DETAIL.b)
  else
    tooltip:AddDoubleLine("Merchant price (cheapest)",
      WHITE_FONT_COLOR:WrapTextInColorCode(GetMoneyString(merchant, true)), LABEL_COLOR.r, LABEL_COLOR.g,
      LABEL_COLOR.b)
  end
end

-- The merchant price goes right under Auctionator's Vendor and Auction lines, above other add-ons' lines
-- (Price History & Trends adds its own after Auctionator's, and loads before us): it's added when
-- Auctionator's tooltip function runs. merchantShown[tooltip] = { link, time } stops the item tooltip hook
-- below from adding it again in the same frame; that hook adds it when Auctionator's function didn't run.
local merchantShown = setmetatable({}, { __mode = "k" })

local function OnAuctionatorTooltip(tooltip, link)
  if not link or not tooltip or tooltip:IsForbidden() or not tooltip.AddDoubleLine then
    return
  end
  local ok, err = pcall(AddMerchantPriceLine, tooltip, link)
  if ok then
    merchantShown[tooltip] = { link = link, time = GetTime() }
  else
    VS.Debug("tooltip error: %s", tostring(err))
  end
end

if Auctionator and Auctionator.Tooltip and Auctionator.Tooltip.ShowTipWithPricing then
  hooksecurefunc(Auctionator.Tooltip, "ShowTipWithPricing", OnAuctionatorTooltip)
end

local function ShownByAuctionator(tooltip, link)
  local shown = merchantShown[tooltip]
  merchantShown[tooltip] = nil
  return shown ~= nil and shown.time == GetTime()
    and C_Item.GetItemInfoInstant(shown.link) == C_Item.GetItemInfoInstant(link)
end

-- "Will be sold to a vendor" for items the Buy button bought with Sell to vendor on.
local function AddSellLine(tooltip, link)
  local itemID = C_Item.GetItemInfoInstant(link)
  local count = itemID and VS.AutoSell.MarkedCount(itemID) or 0
  if count > 0 then
    tooltip:AddLine(("VendorSniper: %d will be sold at the next vendor%s"):format(count,
      VS.AutoSell.IsOn() and "" or " (Sell to vendor is off)"), 0.4, 0.8, 1)
  end
end

-- Recipe profit ----------------------------------------------------------------------------------
-- At the trainer and on recipe items ("Pattern: Runecloth Bag"): what a craft sells for, what its
-- reagents cost and the profit, from the recipes saved when the profession window was opened.

local GREEN_TEXT, RED_TEXT = CreateColor(0.25, 1, 0.25), CreateColor(1, 0.31, 0.31)

local VIA_TEXT = {
  AH = "auction house, after the 5% cut",
  vendor = "vendor",
  disenchant = "disenchanted, after the 5% cut",
}

local function AddRecipeLines(tooltip, recipeID, recipe)
  if not recipe.output then
    -- enchants make no item: only what the materials cost
    local cost, unpriced = 0, false
    for _, reagent in ipairs(recipe.reagents) do
      local price = VS.Prices.Cheapest(reagent.itemID)
      cost = cost + (price or 0) * reagent.quantity
      unpriced = unpriced or not price
    end
    if #recipe.reagents > 0 then
      tooltip:AddDoubleLine("Materials cost", WHITE_FONT_COLOR:WrapTextInColorCode(
        (cost > 0 and GetMoneyString(cost, true) or "?") .. (unpriced and cost > 0 and " +?" or "")),
        LABEL_COLOR.r, LABEL_COLOR.g, LABEL_COLOR.b)
    end
    return
  end
  local row = VS.Crafting.Evaluate(recipeID, recipe)
  local profitText = "?"
  if row.profit then
    local color = row.profit >= 0 and GREEN_TEXT or RED_TEXT
    profitText = color:WrapTextInColorCode((row.profit >= 0 and "+" or "-")
      .. GetMoneyString(math.abs(row.profit), true))
  end
  tooltip:AddDoubleLine("Crafting profit", profitText, LABEL_COLOR.r, LABEL_COLOR.g, LABEL_COLOR.b)
  local items = ""
  if row.made ~= 1 then
    items = (row.made == math.floor(row.made) and row.made or ("%.1f"):format(row.made)) .. " items, "
  end
  tooltip:AddDoubleLine(("   Sells for (%s%s)"):format(items, row.via and VIA_TEXT[row.via] or "no price"),
    row.revenue and GetMoneyString(row.revenue, true) or "?",
    DETAIL.r, DETAIL.g, DETAIL.b, DETAIL.r, DETAIL.g, DETAIL.b)
  tooltip:AddDoubleLine("   Reagents", (row.cost > 0 and GetMoneyString(row.cost, true) or "?")
    .. (row.unpriced > 0 and row.cost > 0 and " +?" or ""), DETAIL.r, DETAIL.g, DETAIL.b, DETAIL.r, DETAIL.g, DETAIL.b)
end

-- Recipe items: the recipe they teach is the name after "Pattern: ", "Plans: ", "Recipe: " and so on.
local function AddRecipeItemLines(tooltip, link)
  if VS.GetSetting("recipeTooltips") == false then
    return
  end
  local itemID, _, _, _, _, classID = C_Item.GetItemInfoInstant(link)
  if not itemID or classID ~= Enum.ItemClass.Recipe then
    return
  end
  local name = (C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)) or C_Item.GetItemInfo(link)
  local taught = name and name:match("^.-:%s*(.+)$")
  local recipeID, recipe = VS.Recipes.FindByName(taught or name or "")
  if recipe then
    AddRecipeLines(tooltip, recipeID, recipe)
  end
end

-- The trainer's tooltip for a service: its ID is the recipe's (a recipe is the spell the trainer teaches).
local function OnAnyTooltip(tooltip, data)
  if VS.GetSetting("recipeTooltips") == false or tooltip:IsForbidden() or not tooltip.GetProcessingTooltipInfo then
    return
  end
  local info = tooltip:GetProcessingTooltipInfo()
  if not info or info.getterName ~= "GetTrainerService" then
    return
  end
  local ok, err = pcall(function()
    local recipe, recipeID
    if data and data.id then
      recipeID = data.id
      recipe = VS.Recipes.Find(recipeID)
    end
    local index = info.getterArgs and info.getterArgs[1]
    if not recipe and index then
      recipeID, recipe = VS.Recipes.FindByName(GetTrainerServiceInfo(index) or "")
    end
    if recipe then
      AddRecipeLines(tooltip, recipeID, recipe)
    end
  end)
  if not ok then
    VS.Debug("trainer tooltip error: %s", tostring(err))
  end
end

if TooltipDataProcessor and TooltipDataProcessor.AllTypes then
  TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, OnAnyTooltip)
end

-- Item tooltips ----------------------------------------------------------------------------------

local function ShouldHandle(tooltip)
  if tooltip == GameTooltip or tooltip == ItemRefTooltip then
    return true
  end
  return not tooltip:IsForbidden() and (tooltip:GetName() or ""):match("^ShoppingTooltip") == nil
    and tooltip.AddDoubleLine ~= nil
end

local function OnItemTooltip(tooltip)
  if not ShouldHandle(tooltip) then
    return
  end
  local link
  if TooltipUtil and TooltipUtil.GetDisplayedItem then
    link = select(2, TooltipUtil.GetDisplayedItem(tooltip))
  elseif tooltip.GetItem then
    link = select(2, tooltip:GetItem())
  end
  if link then
    local ok, err = true, nil
    if not ShownByAuctionator(tooltip, link) then
      ok, err = pcall(AddMerchantPriceLine, tooltip, link)
      if not ok then
        VS.Debug("tooltip error: %s", tostring(err))
      end
    end
    ok, err = pcall(AddDisenchantLines, tooltip, link)
    if not ok then
      VS.Debug("tooltip error: %s", tostring(err))
    end
    ok, err = pcall(AddRecipeItemLines, tooltip, link)
    if not ok then
      VS.Debug("tooltip error: %s", tostring(err))
    end
    ok, err = pcall(AddSellLine, tooltip, link)
    if not ok then
      VS.Debug("tooltip error: %s", tostring(err))
    end
    ok, err = pcall(VS.Inventory.AddTooltipLines, tooltip, link)
    if not ok then
      VS.Debug("tooltip error: %s", tostring(err))
    end
  end
end

if TooltipDataProcessor and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
else
  GameTooltip:HookScript("OnTooltipSetItem", OnItemTooltip)
  ItemRefTooltip:HookScript("OnTooltipSetItem", OnItemTooltip)
end
