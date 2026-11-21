local _, VS = ...

-- The "Crafting" tab: every recipe this character knows, sorted by profit per craft.

local UI = VS.UI
local Crafting = VS.Crafting

local ROW_HEIGHT = 20
local STALE_DAYS = 2 -- auction prices at least this old are greyed out

-- Columns, anchored from the right edge
local COLUMNS = {
  { key = "profit", header = "Profit", width = 100, right = -8 },
  { key = "revenue", header = "Sells for", width = 140, right = -116 },
  { key = "cost", header = "Cost", width = 100, right = -264 },
  { key = "made", header = "Makes", width = 40, right = -372 },
  { key = "craftable", header = "In bags", width = 50, right = -420 },
  { key = "age", header = "Price age", width = 60, right = -478 },
  { key = "profession", header = "Profession", width = 100, right = -546 },
}
local NAME_RIGHT = -654

local GREY = "|cff808080"
local GREEN, RED = "|cff40ff40", "|cffff5050"

local function Money(value)
  return value and VS.FormatMoney(value) or "?"
end

local function AgeText(days)
  if not days then
    return ""
  end
  local text = days == 0 and "today" or (days .. "d")
  return days >= STALE_DAYS and (GREY .. text .. "|r") or text
end

-- Rows -------------------------------------------------------------------------------------------

local function ShowRowTooltip(row)
  local data = row.data
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  if data.link then
    GameTooltip:SetHyperlink(data.link)
  else
    GameTooltip:SetItemByID(data.output)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(("Reagents for one craft (%s):"):format(Money(data.cost)), 1, 0.82, 0)
  for _, reagent in ipairs(data.reagents) do
    local name = C_Item.GetItemInfo(reagent.itemID) or ("item " .. reagent.itemID)
    local price = reagent.price and ("%s (%s)"):format(VS.FormatMoney(reagent.price * reagent.quantity), reagent.source)
      or (RED .. "no price|r")
    GameTooltip:AddDoubleLine(("   %dx %s"):format(reagent.quantity, name), price, 1, 1, 1, 1, 1, 1)
  end
  if data.revenue then
    GameTooltip:AddDoubleLine(("Sells for (best: %s)"):format(data.via), Money(data.revenue), 1, 0.82, 0, 1, 1, 1)
  else
    GameTooltip:AddLine("No auction or vendor price for the crafted item yet.", 1, 0.5, 0.5)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Click to search the crafted item and its reagents in Auctionator's Shopping tab.", 0.6, 0.8, 1)
  GameTooltip:Show()
end

local function BuildRow(row)
  row.vsBuilt = true
  row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
  row.highlight:SetAllPoints()
  row.highlight:SetColorTexture(1, 1, 1, 0.08)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ROW_HEIGHT - 2, ROW_HEIGHT - 2)
  row.icon:SetPoint("LEFT", 4, 0)
  row.name = UI.Text(row, "GameFontHighlightSmall")
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.name:SetPoint("RIGHT", row, "RIGHT", NAME_RIGHT, 0)
  for _, column in ipairs(COLUMNS) do
    local text = UI.Text(row, "GameFontHighlightSmall", "RIGHT")
    text:SetWidth(column.width)
    text:SetPoint("RIGHT", row, "RIGHT", column.right, 0)
    row[column.key] = text
  end
  row:SetScript("OnClick", function(self)
    if self.data then
      Crafting.SearchReagents(self.data)
    end
  end)
  row:SetScript("OnEnter", function(self)
    if self.data then
      ShowRowTooltip(self)
    end
  end)
  row:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
end

local function InitRow(row, data)
  if not row.vsBuilt then
    BuildRow(row)
  end
  row.data = data
  row.icon:SetTexture(data.icon)
  row.name:SetText(data.link or data.name or ("item " .. data.output))
  row.profession:SetText(GREY .. data.profession .. "|r")
  row.age:SetText(AgeText(data.age))
  row.craftable:SetText(data.craftable > 0 and data.craftable or (GREY .. "0|r"))
  row.made:SetText(data.made == math.floor(data.made) and data.made or ("%.1f"):format(data.made))
  row.cost:SetText(Money(data.cost) .. (data.unpriced > 0 and (RED .. " +?|r") or ""))
  row.revenue:SetText(data.revenue and ("%s %s(%s)|r"):format(VS.FormatMoney(data.revenue), GREY, data.via) or "?")
  if data.profit then
    row.profit:SetText((data.profit >= 0 and GREEN or RED) .. (data.profit < 0 and "-" or "")
      .. VS.FormatMoney(math.abs(data.profit)) .. "|r")
  else
    row.profit:SetText(GREY .. "?|r")
  end
end

-- The tab ----------------------------------------------------------------------------------------

local function ProfessionsText()
  local parts = {}
  for name, profession in pairs(VS.Recipes.GetProfessions()) do
    local count = 0
    for _ in pairs(profession.recipes) do
      count = count + 1
    end
    parts[#parts + 1] = ("%s: %d recipes (%s)"):format(name, count, UI.TimeAgo(time() - profession.updated))
  end
  table.sort(parts)
  if #parts == 0 then
    return nil
  end
  return table.concat(parts, "   |   ")
end

function UI.CreateCraftingTab(parent)
  local panel = CreateFrame("Frame", "VendorSniperCraftingTab", parent)
  UI.AnchorInAuctionHouse(panel)

  -- top bar (starts right of the character portrait)
  -- Update prices: the same summary scan as Vendor Deals. It sends Auctionator a fresh price for every
  -- item on sale, crafted items and reagents alike; the list recalculates when it finishes (SCAN_DONE).
  local updateButton = UI.Button(panel, "Update prices", 130, 24)
  updateButton:SetPoint("TOPRIGHT", -8, -4)
  updateButton:SetScript("OnClick", function()
    VS.Scan.Start()
  end)
  updateButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText("Update prices")
    GameTooltip:AddLine("Scans the whole auction house (a few seconds, no cooldown) so Auctionator has today's"
      .. " prices for every crafted item and reagent. Keep the auction house open until it reaches 95%.", 1, 1, 1, true)
    if VS.dealsScannedAt then
      GameTooltip:AddLine("Last scan: " .. UI.TimeAgo(time() - VS.dealsScannedAt), 0.6, 0.8, 1)
    end
    GameTooltip:Show()
  end)
  updateButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  local professionsText = UI.Text(panel, "GameFontNormal")
  professionsText:SetPoint("TOPLEFT", 58, -10)
  professionsText:SetPoint("RIGHT", updateButton, "LEFT", -10, 0)

  local function RefreshUpdateButton()
    if VS.Scan.IsBusy() then
      local _, overall = VS.Scan.GetProgress()
      updateButton:SetText(("Updating %d%%"):format(overall * 100))
      updateButton:SetEnabled(false)
    else
      updateButton:SetText("Update prices")
      updateButton:SetEnabled(true)
    end
  end

  -- column headers
  local headerName = UI.Text(panel, "GameFontNormalSmall")
  headerName:SetPoint("TOPLEFT", 30, -38)
  headerName:SetText("Crafted item")
  for _, column in ipairs(COLUMNS) do
    local header = UI.Text(panel, "GameFontNormalSmall", "RIGHT")
    header:SetWidth(column.width)
    header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", column.right - 20, -38)
    header:SetText(column.header)
  end

  -- list
  local listArea = CreateFrame("Frame", nil, panel)
  listArea:SetPoint("TOPLEFT", 0, -54)
  listArea:SetPoint("BOTTOMRIGHT", -20, 34)
  UI.Background(listArea, 0, 0, 0, 0.3)

  local scrollBox = CreateFrame("Frame", nil, panel, "WowScrollBoxList")
  scrollBox:SetAllPoints(listArea)
  local scrollBar = CreateFrame("EventFrame", nil, panel, "MinimalScrollBar")
  scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
  scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)
  local view = CreateScrollBoxListLinearView()
  view:SetElementExtent(ROW_HEIGHT)
  view:SetElementInitializer("Button", InitRow)
  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

  local emptyText = UI.Text(listArea, "GameFontDisable", "CENTER")
  emptyText:SetPoint("CENTER")
  emptyText:SetText("Open each of your profession windows once, so the addon can learn your recipes.")

  -- bottom bar
  local hint = UI.Text(panel, "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", 4, 12)
  hint:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
  hint:SetText("Prices come from Auctionator's last scan (Update prices scans again). Sells for = the best of"
    .. " auction house (after the 5% cut), vendor, or disenchanting. Click a row to search it and its reagents.")

  local function Refresh()
    local text = ProfessionsText()
    professionsText:SetText(text or "No recipes yet")
    local rows = text and Crafting.GetRows() or {}
    scrollBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants.RetainScrollPosition)
    emptyText:SetShown(#rows == 0)
  end

  -- several events can come at once; recalculate once
  local refreshPending = false
  local function RefreshSoon()
    if refreshPending or not panel:IsShown() then
      return
    end
    refreshPending = true
    C_Timer.After(0.2, function()
      refreshPending = false
      if panel:IsShown() then
        Refresh()
      end
    end)
  end

  VS.On("RECIPES_CHANGED", function()
    if panel:IsShown() then
      Crafting.LoadItems()
      RefreshSoon()
    end
  end)
  VS.On("CRAFTING_CHANGED", RefreshSoon)
  VS.On("SCAN_DONE", RefreshSoon)
  VS.On("SCAN_CHANGED", function()
    if panel:IsShown() then
      RefreshUpdateButton()
    end
  end)

  panel:RegisterEvent("BAG_UPDATE_DELAYED")
  panel:SetScript("OnEvent", RefreshSoon)

  panel:SetScript("OnShow", function()
    RefreshUpdateButton()
    Crafting.LoadItems()
    Refresh()
  end)

  panel:Hide()
  return panel
end
