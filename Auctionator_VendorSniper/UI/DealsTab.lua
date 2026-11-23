local _, VS = ...

-- The "Vendor Deals" tab: scan controls, the list of deals, and the Buy / Skip buttons.

local UI = VS.UI
local Scan, Buy = VS.Scan, VS.Buy

local ROW_HEIGHT = 20

-- Columns, anchored from the right edge: { key, header, width, rightOffset }
local COLUMNS = {
  { key = "totalProfit", header = "Total profit", width = 140, right = -8 },
  { key = "profit", header = "Profit per item", width = 110, right = -156 },
  { key = "risk", header = "Risk", width = 44, right = -274 },
  { key = "value", header = "Worth", width = 110, right = -326 },
  { key = "price", header = "Cheapest", width = 110, right = -444 },
  { key = "onSale", header = "On sale", width = 60, right = -562 },
}
local NAME_RIGHT = -630

-- The orders the "Sort" dropdown offers (keys of Scan.SORTS). The buy flow works down the list in this order.
local SORTS = {
  { key = "profit", text = "Profit per item", tooltip = "Biggest profit per item first." },
  { key = "roi", text = "Return on gold", tooltip = "Most profit for the gold spent first (profit divided by"
    .. " price): a 2s item making 6c comes before a 20s item making 7c. Best when your gold, or your max spend,"
    .. " runs out before the deals do." },
  { key = "risk", text = "Lowest risk", tooltip = "Lowest disenchant risk first, then by profit per item."
    .. " Vendor deals have no risk, so they come first." },
}

local GREY, GREEN, YELLOW, RED = "|cff808080", "|cff40ff40", "|cffffd100", "|cffff5050"

-- Disenchant risk --------------------------------------------------------------------------------
--
-- A disenchant deal's risk is the chance that disenchanting one is worth less than its price (see
-- Disenchant.GetOutcomes). Vendor deals have none: a vendor always pays the same.

local LOW_RISK, HIGH_RISK = 0.20, 0.50

-- Whole percentages, except near 0 and 100: a 0.5% risk reads 0.5%, not 1%, and 99.5% not 100%.
local function Percent(chance)
  if (chance > 0 and chance < 0.0095) or (chance > 0.9905 and chance < 1) then
    return ("%.1f%%"):format(chance * 100)
  end
  return ("%d%%"):format(math.floor(chance * 100 + 0.5))
end

local function RiskText(chance)
  local color = chance < LOW_RISK and GREEN or (chance <= HIGH_RISK and YELLOW or RED)
  return color .. Percent(chance) .. "|r"
end

local function MaterialName(itemID)
  local name = (C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)) or C_Item.GetItemInfo(itemID)
  return name or ("item " .. itemID)
end

-- The chance that buying all `units` of what one click buys loses money overall. Worked out once per
-- deal, price and amount, since it adds up every combination of results.
local function RiskForAll(deal)
  local cost = deal.value * deal.buyUnits - deal.totalProfit
  local key = deal.buyUnits .. ":" .. cost
  if deal.riskForAllKey ~= key then
    deal.riskForAllKey = key
    deal.riskForAll = VS.Disenchant.LossChanceMany(deal.outcomes, deal.buyUnits, cost)
  end
  return deal.riskForAll
end

local function AddRiskLines(deal)
  local outcomes = deal.outcomes
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(("Disenchanting one bought for %s gives:"):format(VS.FormatMoney(deal.price)), 1, 0.82, 0)
  for i = #outcomes, 1, -1 do -- best first
    local outcome = outcomes[i]
    local chance = outcome.chance * 100
    local chanceText = chance >= 1 and ("%.4g%%"):format(chance) or ("%.1f%%"):format(chance)
    GameTooltip:AddDoubleLine(("   %s  %d %s"):format(chanceText, outcome.amount, MaterialName(outcome.itemID)),
      (outcome.value < deal.price and RED or GREEN) .. VS.FormatMoney(outcome.value) .. "|r", 0.8, 0.8, 0.8)
  end
  GameTooltip:AddLine("   (after the 5% auction house cut; green = more than you pay)", 0.6, 0.6, 0.6)
  GameTooltip:AddDoubleLine("Chance of a loss on one", RiskText(deal.risk), 1, 1, 1)
  if deal.buyUnits and deal.buyUnits > 1 and deal.totalProfit then
    GameTooltip:AddDoubleLine(("Chance of a loss on all %d"):format(deal.buyUnits), RiskText(RiskForAll(deal)), 1, 1, 1)
  end
  GameTooltip:AddLine(("3 times in 4 one is worth at least %s; on average %s."):format(
    VS.FormatMoney(VS.Disenchant.AtLeast(outcomes, 0.75)), VS.FormatMoney(deal.value)), 0.8, 0.8, 0.8, true)
end

-- Rows -------------------------------------------------------------------------------------------

local function BuildRow(row)
  row.vsBuilt = true
  row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
  row.highlight:SetAllPoints()
  row.highlight:SetColorTexture(1, 1, 1, 0.08)
  row.selected = row:CreateTexture(nil, "BACKGROUND")
  row.selected:SetAllPoints()
  row.selected:SetColorTexture(1, 0.82, 0, 0.18)

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
    if self.deal then
      Buy.Select(self.deal)
    end
  end)
  row:SetScript("OnEnter", function(self)
    if not self.deal then
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.deal.link then
      GameTooltip:SetHyperlink(self.deal.link)
    else
      GameTooltip:SetItemByID(self.deal.itemID)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("Vendor sell price: %s each"):format(VS.FormatMoney(self.deal.sellPrice)), 1, 1, 1)
    if self.deal.via == "disenchant" then
      GameTooltip:AddLine(("Disenchant value: %s each, after the 5%% auction house cut (used here)"):format(
        VS.FormatMoney(self.deal.value)), 1, 1, 1)
    end
    GameTooltip:AddLine(("Cheapest on the auction house: %s each"):format(VS.FormatMoney(self.deal.price)), 1, 1, 1)
    if self.deal.totalProfit then
      GameTooltip:AddLine(("One click buys %d for a total profit of %s."):format(self.deal.buyUnits or 0,
        VS.FormatMoney(self.deal.totalProfit)), 1, 1, 1)
    else
      GameTooltip:AddLine("The total profit shows once the item has been checked (when it's next to buy).", 0.7, 0.7, 0.7)
    end
    if self.deal.outcomes then
      AddRiskLines(self.deal)
    end
    GameTooltip:AddLine("Click to buy this one next.", 0.6, 0.8, 1)
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
end

local function UpdateSelection(row)
  local _, target = Buy.GetState()
  row.selected:SetShown(row.deal ~= nil and row.deal == target)
end

local function InitRow(row, deal)
  if not row.vsBuilt then
    BuildRow(row)
  end
  row.deal = deal
  row.icon:SetTexture(deal.icon)
  row.name:SetText(deal.link or deal.name)
  row.onSale:SetText(deal.onSale)
  row.price:SetText(VS.FormatMoney(deal.price))
  row.value:SetText(VS.FormatMoney(deal.value) .. (deal.via == "disenchant" and " |cffa335eeDE|r" or ""))
  row.profit:SetText("|cff40ff40" .. VS.FormatMoney(deal.profit) .. "|r")
  row.risk:SetText(deal.risk and RiskText(deal.risk) or (GREY .. "-|r"))
  -- known once the item has been checked: what one click buys
  if deal.totalProfit then
    row.totalProfit:SetText(("|cff40ff40%s|r |cff808080(%d)|r"):format(VS.FormatMoney(deal.totalProfit), deal.buyUnits or 0))
  else
    row.totalProfit:SetText("|cff808080?|r")
  end
  UpdateSelection(row)
end

-- Texts ------------------------------------------------------------------------------------------

local Number = BreakUpLargeNumbers or tostring

local function ScanStatusText()
  local state, _, done, total, seconds = Scan.GetProgress()
  if state == Scan.SCANNING then
    return ("Step 1/3: receiving items %s (%ds) - keep the AH open"):format(Number(done), seconds)
  elseif state == Scan.LOADING then
    return ("Step 2/3: loading vendor prices %s / %s items"):format(Number(done), Number(total))
  elseif state == Scan.EVALUATING then
    return ("Step 3/3: finding deals %s / %s items"):format(Number(done), Number(total))
  end
  if VS.dealsScannedAt and VS.dealsStoppedAt then
    return ("Scan stopped at %d%% %s: %d deals so far"):format(VS.dealsStoppedAt * 100,
      UI.TimeAgo(time() - VS.dealsScannedAt), #VS.deals)
  elseif VS.dealsScannedAt then
    return ("Last scan %s: %d deals"):format(UI.TimeAgo(time() - VS.dealsScannedAt), #VS.deals)
  end
  return "No scan yet"
end

-- Text and enabled state of the Buy button.
-- True when nothing is left to buy (no deals, or only skipped ones): the Buy button scans instead.
local function NothingToBuy()
  local state, target = Buy.GetState()
  if state ~= Buy.IDLE or target then
    return false
  end
  for _, deal in ipairs(VS.deals) do
    if not Buy.IsSkipped(deal.itemID) then
      return false
    end
  end
  return true
end

local function BuyButtonState()
  local state, target, offer, quote = Buy.GetState()
  local name = target and target.name or ""
  if NothingToBuy() then
    if Scan.IsBusy() then
      return "No deals yet - scanning...", false
    end
    return "Nothing to buy - Scan", true
  end
  if state == Buy.IDLE and not target and not Buy.Best() then
    return "Not enough money for any deal", false
  elseif state == Buy.IDLE then
    return "Start buying", true
  elseif state == Buy.SEARCHING then
    return ("Checking %s..."):format(name), false
  elseif state == Buy.READY and offer.kind == "item" and Buy.UsesBuyTab() then
    return ("Open %s in the Buy tab  (%s, +%s)"):format(name, VS.FormatMoney(offer.auctions[1].price),
      VS.FormatMoney(offer.auctions[1].profit)), true
  elseif state == Buy.READY and offer.kind == "item" then
    local auction = offer.auctions[1]
    local count = auction.quantity > 1 and (auction.quantity .. "x ") or ""
    local risk = auction.risk and (", " .. Percent(auction.risk) .. " risk") or ""
    return ("Buy %s%s for %s  (+%s%s)"):format(count, name, VS.FormatMoney(auction.price), VS.FormatMoney(auction.profit),
      risk), true
  elseif state == Buy.READY then
    return ("Buy %dx %s for %s  (+%s)"):format(offer.quantity, name, VS.FormatMoney(offer.price),
      VS.FormatMoney(offer.value - offer.price)), true
  elseif state == Buy.QUOTING then
    return "Getting the server's price...", false
  elseif state == Buy.CONFIRM then
    return ("Confirm %dx for %s  (+%s)"):format(offer.quantity, VS.FormatMoney(quote), VS.FormatMoney(offer.value - quote)), true
  elseif state == Buy.PURCHASING then
    return "Buying...", false
  end
  return "", false
end

-- Two lines, so large amounts fit beside the buttons.
local function SessionText()
  local session = VS.session
  local profit = session.vendorValue - session.spent
  return ("Session: %d bought, spent %s\nProfit: %s%s|r"):format(session.purchases, VS.FormatMoney(session.spent),
    profit < 0 and RED or GREEN, VS.FormatMoney(profit))
end

-- The tab ----------------------------------------------------------------------------------------

function UI.CreateDealsTab(parent)
  local panel = CreateFrame("Frame", "VendorSniperDealsTab", parent)
  UI.AnchorInAuctionHouse(panel)

  -- top bar (starts right of the character portrait in the auction house's top-left corner)
  local scanButton = UI.Button(panel, "Scan", 130, 24)
  scanButton:SetPoint("TOPLEFT", 58, -4)
  scanButton:SetScript("OnClick", function()
    Scan.Toggle()
  end)
  scanButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    if Scan.IsReceiving() then
      GameTooltip:AddLine("Stop the scan")
      GameTooltip:AddLine("The deals found so far stay in the list. Scan again for the rest.", 1, 1, 1, true)
    else
      GameTooltip:AddLine("Scan")
      GameTooltip:AddLine("Scans the whole auction house for deals (no cooldown). Click again while it runs to stop"
        .. " it.", 1, 1, 1, true)
    end
    GameTooltip:AddLine("Key bindings: Options > Keybindings > Vendor Sniper.", 0.6, 0.8, 1, true)
    GameTooltip:Show()
  end)
  scanButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  local scanStatus = UI.Text(panel, "GameFontNormal")
  scanStatus:SetPoint("LEFT", scanButton, "RIGHT", 10, 0)
  scanStatus:SetPoint("RIGHT", panel, "RIGHT", -8, 0)

  -- options row, below the scan bar
  local function Checkbox(label, setting, tooltip, anchorTo)
    local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    if anchorTo then
      check:SetPoint("LEFT", anchorTo, "RIGHT", 16, 0)
    else
      check:SetPoint("TOPLEFT", 54, -30)
    end
    local text = UI.Text(panel, "GameFontHighlightSmall")
    text:SetPoint("LEFT", check, "RIGHT", 2, 0)
    text:SetText(label)
    check:SetChecked(VS.GetSetting(setting))
    -- the options page changes the same setting
    VS.On("SETTINGS_CHANGED", function(key)
      if key == setting then
        check:SetChecked(VS.GetSetting(setting) and true or false)
      end
    end)
    check:SetScript("OnClick", function(self)
      VS.SetSetting(setting, self:GetChecked() and true or false)
    end)
    check:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
      GameTooltip:AddLine(label)
      for _, line in ipairs(tooltip) do
        GameTooltip:AddLine(line[1], line[2] or 1, line[3] or 1, line[4] or 1, true)
      end
      GameTooltip:Show()
    end)
    check:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    return check, text
  end

  -- "Sell to vendor": mark what we buy and sell it at the next merchant
  local _, sellLabel = Checkbox("Sell to vendor", "sellToVendor", {
    { "Items bought while this is checked are marked, and sold automatically the next time you open a merchant"
      .. " (collect them from the mailbox first). Only the units you bought are sold." },
    { "Gear bought for its disenchant value isn't marked.", 0.7, 0.7, 0.7 },
    { "/vsnipe clearsell forgets the marks.", 0.6, 0.8, 1 },
  })
  -- "Include disenchant value": gear also counts when disenchanting it is worth more than its price
  local _, disenchantLabel = Checkbox("Include disenchant value", "includeDisenchant", {
    { "Gear also counts as a deal when disenchanting it is worth more than its price. The profit is the"
      .. " expected value of the materials at Auctionator's prices, minus the 5% auction house cut, minus the"
      .. " price." },
    { "Such deals show DE in the Worth column. You need Enchanting (or an enchanter) to turn them into"
      .. " materials, and the materials still have to be sold.", 0.7, 0.7, 0.7 },
    { "The Risk column shows how often disenchanting one is worth less than its price. Max risk, on this"
      .. " row, leaves out the riskiest.", 0.7, 0.7, 0.7 },
  }, sellLabel)

  -- "Sort": the list's order, which is also the order the Buy button buys in
  local sortLabel = UI.Text(panel, "GameFontNormalSmall")
  sortLabel:SetPoint("LEFT", disenchantLabel, "RIGHT", 20, 0)
  sortLabel:SetText("Sort:")
  local sortDropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
  sortDropdown:SetWidth(130)
  sortDropdown:SetPoint("LEFT", sortLabel, "RIGHT", 6, 0)
  sortDropdown:SetupMenu(function(_, root)
    for _, sort in ipairs(SORTS) do
      local option = root:CreateRadio(sort.text, function()
        return VS.GetSetting("dealSort") == sort.key
      end, function()
        if VS.GetSetting("dealSort") ~= sort.key then
          VS.SetSetting("dealSort", sort.key)
        end
      end)
      option:SetTooltip(function(tooltip)
        GameTooltip_SetTitle(tooltip, sort.text)
        GameTooltip_AddNormalLine(tooltip, sort.tooltip)
        GameTooltip_AddInstructionLine(tooltip, "The Buy button buys in the list's order.")
      end)
    end
  end)
  VS.On("SETTINGS_CHANGED", function(key)
    if key == "dealSort" then
      sortDropdown:GenerateMenu() -- shows the new choice
    end
  end)

  -- A text that turns into an edit box when clicked: type a value, Enter saves it, Escape cancels.
  -- opts: font and hoverFont of the text, side ("LEFT" or "RIGHT": where the box lines up with the text),
  -- label (beside the box), boxWidth, current() = the box's starting text, save(text) = true when it was
  -- saved (false keeps the box open), tooltip(), called to fill the GameTooltip.
  local function ClickToEdit(text, opts)
    local edit = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    edit:SetSize(opts.boxWidth, 20)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(16)
    edit:Hide()
    local label = UI.Text(panel, "GameFontNormalSmall", opts.side)
    label:SetText(opts.label)
    label:Hide()
    if opts.side == "RIGHT" then
      edit:SetPoint("RIGHT", text, "RIGHT", 0, 0)
      label:SetPoint("RIGHT", edit, "LEFT", -8, 0)
    else
      label:SetPoint("LEFT", text, "LEFT", 0, 0)
      edit:SetPoint("LEFT", label, "RIGHT", 12, 0) -- the box's border reaches 5 px left of it
    end
    local button = CreateFrame("Button", nil, panel)
    button:SetAllPoints(text)
    local control = { editing = false }
    local function StopEditing()
      control.editing = false
      edit:ClearFocus()
      edit:Hide()
      label:Hide()
      text:Show()
    end
    edit:SetScript("OnEnterPressed", function(self)
      if opts.save(self:GetText()) then
        StopEditing()
      else
        self:HighlightText()
      end
    end)
    edit:SetScript("OnEscapePressed", StopEditing)
    edit:SetScript("OnEditFocusLost", StopEditing)
    button:SetScript("OnClick", function()
      control.editing = true
      text:Hide()
      label:Show()
      edit:SetText(opts.current())
      edit:Show()
      edit:SetFocus()
      edit:HighlightText()
    end)
    button:SetScript("OnEnter", function(self)
      text:SetFontObject(opts.hoverFont)
      GameTooltip:SetOwner(self, opts.side == "RIGHT" and "ANCHOR_BOTTOMLEFT" or "ANCHOR_BOTTOMRIGHT")
      opts.tooltip()
      GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
      text:SetFontObject(opts.font)
      GameTooltip:Hide()
    end)
    return control
  end

  -- minimum profit per item: type an amount (50c, 1s50c, 2g)
  local minProfitText = UI.Text(panel, "GameFontDisableSmall", "RIGHT")
  minProfitText:SetPoint("TOPRIGHT", -8, -36)
  ClickToEdit(minProfitText, {
    font = "GameFontDisableSmall", hoverFont = "GameFontHighlightSmall", side = "RIGHT", boxWidth = 90,
    label = "Min profit per item (e.g. 50c, 1s50c):",
    current = function()
      return VS.MoneyInputText(VS.GetSetting("minItemProfit"))
    end,
    save = function(input)
      local value = VS.ParseMoney(input)
      if not value then
        VS.Print("couldn't read \"%s\" as an amount. Examples: 50c, 1s50c, 2g.", input)
        return false
      end
      VS.SetSetting("minItemProfit", math.max(1, value))
      VS.Print("minimum profit per item: %s", VS.FormatMoney(math.max(1, value)))
      return true
    end,
    tooltip = function()
      GameTooltip:AddLine("Minimum profit per item")
      GameTooltip:AddLine("Click to change it. Deals earning less per item than this aren't listed or bought.",
        1, 1, 1, true)
      GameTooltip:AddLine("Max spend per session: /vsnipe maxspend, or in the options. Buying stops after"
        .. " spending this much until you log out or reload.", 0.6, 0.8, 1, true)
    end,
  })

  -- max disenchant risk, after the Sort dropdown: type a percentage
  local maxRiskText = UI.Text(panel, "GameFontHighlightSmall")
  maxRiskText:SetPoint("LEFT", sortDropdown, "RIGHT", 16, 0)
  local maxRisk = ClickToEdit(maxRiskText, {
    font = "GameFontHighlightSmall", hoverFont = "GameFontNormalSmall", side = "LEFT", boxWidth = 40,
    label = "Max risk % (100 = off):",
    current = function()
      return tostring(VS.GetSetting("maxDisenchantRisk"))
    end,
    save = function(input)
      local value = input:lower():find("off") and 100 or tonumber((input:gsub("%%", "")))
      if not value then
        VS.Print("couldn't read \"%s\" as a percentage. Examples: 30, 50%%, off.", input)
        return false
      end
      value = math.max(0, math.min(100, math.floor(value + 0.5)))
      VS.SetSetting("maxDisenchantRisk", value)
      VS.Print("max disenchant risk: %s", value < 100 and (value .. "% chance of a loss per item") or "off")
      return true
    end,
    tooltip = function()
      GameTooltip:AddLine("Max disenchant risk")
      GameTooltip:AddLine("Click to change it. Disenchant deals more likely than this to lose money on one item"
        .. " (the Risk column) aren't listed or bought. 100% = off.", 1, 1, 1, true)
      GameTooltip:AddLine("Most gear gives dust most of the time, and the rarer essences and shards make up the"
        .. " average, so a deal that profits on average can still lose on most single items.", 0.8, 0.8, 0.8, true)
      if not VS.GetSetting("includeDisenchant") then
        GameTooltip:AddLine("Only applies while \"Include disenchant value\" is on.", 1, 0.5, 0.25, true)
      end
    end,
  })

  -- column headers
  local headerName = UI.Text(panel, "GameFontNormalSmall")
  headerName:SetPoint("TOPLEFT", 30, -60)
  headerName:SetText("Item")
  for _, column in ipairs(COLUMNS) do
    local header = UI.Text(panel, "GameFontNormalSmall", "RIGHT")
    header:SetWidth(column.width)
    -- the list's scroll bar takes 20 px on the right
    header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", column.right - 20, -60)
    header:SetText(column.header)
    if column.key == "risk" then
      local hover = CreateFrame("Frame", nil, panel)
      hover:SetAllPoints(header)
      hover:EnableMouse(true)
      hover:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Disenchant risk")
        GameTooltip:AddLine("The chance that disenchanting one item bought at the cheapest price gives materials"
          .. " worth less than you paid. Most gear gives dust most of the time, and the rarer essences and shards"
          .. " make up the average, so a profit on average can still be a loss most times.", 1, 1, 1, true)
        GameTooltip:AddLine(("Green under %d%%, yellow up to %d%%, red above. Vendor deals have no risk (-)."):format(
          LOW_RISK * 100, HIGH_RISK * 100), 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine("Buying several evens it out: hover a deal to see the risk for all of them. Set a"
          .. " limit with Max risk above the list.", 0.6, 0.8, 1, true)
        GameTooltip:Show()
      end)
      hover:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)
    end
  end

  -- list
  local listArea = CreateFrame("Frame", nil, panel)
  listArea:SetPoint("TOPLEFT", 0, -76)
  listArea:SetPoint("BOTTOMRIGHT", -20, 74)
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

  -- bottom bar
  local targetText = UI.Text(panel, "GameFontHighlightSmall")
  targetText:SetPoint("BOTTOMLEFT", 4, 50)
  targetText:SetPoint("RIGHT", panel, "RIGHT", -8, 0)

  local buyButton = UI.Button(panel, "", 400, 32)
  buyButton:SetPoint("BOTTOMLEFT", 4, 10)
  buyButton:SetScript("OnClick", function()
    -- a real click: purchases are allowed here. Only reads come before Buy.Click, which must make the
    -- purchase call before anything else.
    if NothingToBuy() then
      Scan.Start()
    else
      Buy.Click()
    end
  end)
  local skipButton = UI.Button(panel, "Skip", 80, 32)
  skipButton:SetPoint("LEFT", buyButton, "RIGHT", 8, 0)
  skipButton:SetScript("OnClick", function()
    Buy.Skip()
  end)
  UI.dealsButtons = { buy = buyButton, skip = skipButton } -- for the key bindings (UI/Bindings.lua)
  -- as tall as the buttons, beside them: room for two lines (see SessionText)
  local sessionText = UI.Text(panel, "GameFontHighlightSmall", "RIGHT")
  sessionText:SetPoint("TOPLEFT", skipButton, "TOPRIGHT", 12, 0)
  sessionText:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 10)
  sessionText:SetJustifyV("MIDDLE")
  sessionText:SetWordWrap(true)

  -- updates
  -- The deal being bought moves when its live check changes what the list is sorted by. If its row was on
  -- screen, the list follows it, so a clicked row doesn't jump away from under the cursor.
  local function RefreshList()
    local _, target = Buy.GetState()
    local followed = target and scrollBox.FindFrame and scrollBox:FindFrame(target) ~= nil
    local copy, targetIndex = {}, nil
    for i, deal in ipairs(VS.deals) do
      copy[i] = deal
      if deal == target then
        targetIndex = i
      end
    end
    scrollBox:SetDataProvider(CreateDataProvider(copy), ScrollBoxConstants.RetainScrollPosition)
    if followed and targetIndex and not scrollBox:FindFrame(target) and scrollBox.ScrollToElementDataIndex then
      scrollBox:ScrollToElementDataIndex(targetIndex, ScrollBoxConstants.AlignNearest or 0.5)
    end
  end

  local function RefreshStatus()
    scanStatus:SetText(ScanStatusText())
    local _, overall = Scan.GetProgress()
    if Scan.IsReceiving() then
      scanButton:SetText(("Stop (%d%%)"):format(overall * 100))
      scanButton:SetEnabled(true)
    elseif Scan.IsBusy() then
      scanButton:SetText(("Scanning %d%%"):format(overall * 100))
      scanButton:SetEnabled(false)
    else
      scanButton:SetText("Scan")
      scanButton:SetEnabled(true)
    end
    if #VS.deals > 0 then
      emptyText:Hide()
    else
      if Scan.IsBusy() then
        emptyText:SetText("Scanning - the deals will appear here when the scan is done.")
      elseif VS.dealsScannedAt then
        emptyText:SetText(VS.GetSetting("includeDisenchant") and "No auctions below vendor or disenchant value right now."
          or "No auctions below vendor price right now.")
      else
        emptyText:SetText("Click Scan to find auctions selling below vendor price.")
      end
      emptyText:Show()
    end
    local maxSpend, riskLimit = VS.GetSetting("maxSpend"), VS.GetSetting("maxDisenchantRisk")
    -- short: the Sort dropdown and Max risk share the row
    minProfitText:SetText(("Min profit: %s%s"):format(VS.FormatMoney(VS.GetSetting("minItemProfit")),
      maxSpend > 0 and ("  |  Max spend: " .. VS.FormatMoney(maxSpend)) or ""))
    maxRiskText:SetText(("Max risk: %d%%"):format(riskLimit))
    maxRiskText:SetShown(not maxRisk.editing)
  end

  local function RefreshBuy()
    local text, enabled = BuyButtonState()
    buyButton:SetText(text)
    buyButton:SetEnabled(enabled)
    local state, target = Buy.GetState()
    skipButton:SetEnabled(target ~= nil and state ~= Buy.PURCHASING)
    if target then
      targetText:SetText(("Now: %s - cheapest %s, %s %s, profit %s per item%s"):format(
        target.link or target.name, VS.FormatMoney(target.price),
        target.via == "disenchant" and "disenchant value" or "vendor price", VS.FormatMoney(target.value),
        VS.FormatMoney(target.profit), target.risk and (", risk of a loss " .. RiskText(target.risk)) or ""))
    else
      targetText:SetText("")
    end
    scrollBox:ForEachFrame(UpdateSelection)
  end

  local function RefreshSession()
    sessionText:SetText(SessionText())
  end

  VS.On("DEALS_CHANGED", function()
    if panel:IsShown() then
      RefreshList()
      RefreshStatus()
    end
  end)
  VS.On("SCAN_CHANGED", function()
    if panel:IsShown() then
      RefreshStatus()
      RefreshBuy()
    end
  end)
  VS.On("SETTINGS_CHANGED", function()
    if panel:IsShown() then
      RefreshStatus()
    end
  end)
  VS.On("BUY_CHANGED", function()
    if panel:IsShown() then
      RefreshBuy()
    end
  end)
  VS.On("SESSION_CHANGED", RefreshSession)

  local elapsed = 0
  panel:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed >= (Scan.IsBusy() and 0.25 or 1) then
      elapsed = 0
      RefreshStatus() -- scan progress, cooldown countdown
    end
  end)
  panel:SetScript("OnShow", function()
    RefreshList()
    RefreshStatus()
    RefreshSession()
    Buy.SetActive(true)
    RefreshBuy()
  end)
  panel:SetScript("OnHide", function()
    Buy.SetActive(false)
  end)

  panel:Hide()
  return panel
end
