local _, VS = ...

-- Adds the disenchant value and materials to item tooltips, below Auctionator's Vendor and Auction lines.
-- Auctionator is a dependency, so it loads first and its tooltip hook runs before ours.

local LABEL_COLOR = NORMAL_FONT_COLOR
local DETAIL = { r = 0.8, g = 0.8, b = 0.8 }

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
    local ok, err = pcall(AddDisenchantLines, tooltip, link)
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
