local _, VS = ...

-- The addon's page in the game's options (Esc > Options > AddOns), also opened by /vsnipe options.
-- Every setting is here; the Vendor Deals tab's checkboxes change the same settings and stay in sync.

local UI = VS.UI

local TITLE = "Auctionator: Vendor Sniper & Crafting"

-- canvas is what the options window shows; it scrolls `panel`, which holds the controls, once they're
-- taller than the window. The named frames are needed by Blizzard's scroll frame template.
local canvas = CreateFrame("Frame")
canvas:Hide()
local scroll = CreateFrame("ScrollFrame", "AuctionatorVendorSniperOptionsScroll", canvas,
  "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 0, -4)
scroll:SetPoint("BOTTOMRIGHT", -28, 4) -- room for the scroll bar, which sits just right of the frame
local panel = CreateFrame("Frame", nil, scroll)
panel:SetSize(600, 1)
scroll:SetScrollChild(panel)
scroll:SetScript("OnSizeChanged", function(_, width)
  panel:SetWidth(width)
end)

local refreshers = {} -- functions that show each control's current value
local y = -16         -- where the next control goes

local function Gap(height)
  y = y - height
end

local function Header(text)
  Gap(8)
  local header = UI.Text(panel, "GameFontNormal")
  header:SetPoint("TOPLEFT", 16, y)
  header:SetText(text)
  local line = panel:CreateTexture(nil, "ARTWORK")
  line:SetColorTexture(1, 0.82, 0, 0.25)
  line:SetHeight(1)
  line:SetPoint("LEFT", header, "RIGHT", 8, 0)
  line:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
  Gap(24)
end

local function Description(anchor, text)
  local description = UI.Text(panel, "GameFontDisableSmall")
  description:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -3)
  description:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
  description:SetWordWrap(true)
  description:SetText(text)
end

local function Checkbox(setting, label, description)
  local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  check:SetSize(26, 26)
  check:SetPoint("TOPLEFT", 20, y)
  local text = UI.Text(panel, "GameFontHighlight")
  text:SetPoint("LEFT", check, "RIGHT", 4, 1)
  text:SetText(label)
  Description(text, description)
  check:SetScript("OnClick", function(self)
    VS.SetSetting(setting, self:GetChecked() and true or false)
  end)
  refreshers[#refreshers + 1] = function()
    check:SetChecked(VS.GetSetting(setting) and true or false)
  end
  Gap(40)
end

-- An amount of money: typed like 50c, 1s50c or 2g; saved on Enter or when leaving the box.
local function MoneyField(setting, label, description, minimum)
  local text = UI.Text(panel, "GameFontHighlight")
  text:SetPoint("TOPLEFT", 26, y - 4)
  text:SetText(label)
  local edit = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
  edit:SetSize(100, 20)
  edit:SetPoint("LEFT", text, "RIGHT", 14, 0)
  edit:SetAutoFocus(false)
  edit:SetMaxLetters(16)
  Description(text, description)

  local function Show()
    edit:SetText(VS.MoneyInputText(VS.GetSetting(setting)))
    edit:SetCursorPosition(0)
  end
  local function Save()
    local value = VS.ParseMoney(edit:GetText())
    if not value then
      VS.Print("couldn't read \"%s\" as an amount. Examples: 50c, 1s50c, 2g.", edit:GetText())
    else
      value = math.max(minimum, value)
      if value ~= VS.GetSetting(setting) then
        VS.SetSetting(setting, value)
      end
    end
    Show()
  end
  edit:SetScript("OnEnterPressed", function(self)
    self:ClearFocus() -- saves, through OnEditFocusLost
  end)
  edit:SetScript("OnEditFocusLost", Save)
  edit:SetScript("OnEscapePressed", function(self)
    Show() -- back to the saved value
    self:ClearFocus()
  end)
  refreshers[#refreshers + 1] = function()
    if not edit:HasFocus() then
      Show()
    end
  end
  Gap(40)
end

-- A whole percentage from 0 to 100; saved on Enter or when leaving the box.
local function PercentField(setting, label, description)
  local text = UI.Text(panel, "GameFontHighlight")
  text:SetPoint("TOPLEFT", 26, y - 4)
  text:SetText(label)
  local edit = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
  edit:SetSize(50, 20)
  edit:SetPoint("LEFT", text, "RIGHT", 14, 0)
  edit:SetAutoFocus(false)
  edit:SetMaxLetters(4)
  local sign = UI.Text(panel, "GameFontHighlight")
  sign:SetPoint("LEFT", edit, "RIGHT", 4, 0)
  sign:SetText("%")
  Description(text, description)

  local function Show()
    edit:SetText(tostring(VS.GetSetting(setting)))
    edit:SetCursorPosition(0)
  end
  local function Save()
    local value = tonumber((edit:GetText():gsub("%%", "")))
    if not value then
      VS.Print("couldn't read \"%s\" as a percentage from 0 to 100.", edit:GetText())
    else
      value = math.max(0, math.min(100, math.floor(value + 0.5)))
      if value ~= VS.GetSetting(setting) then
        VS.SetSetting(setting, value)
      end
    end
    Show()
  end
  edit:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
  end)
  edit:SetScript("OnEditFocusLost", Save)
  edit:SetScript("OnEscapePressed", function(self)
    Show()
    self:ClearFocus()
  end)
  refreshers[#refreshers + 1] = function()
    if not edit:HasFocus() then
      Show()
    end
  end
  Gap(40)
end

-- Layout -------------------------------------------------------------------------------------------

local title = UI.Text(panel, "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, y)
title:SetText(TITLE)
Gap(22)
local subtitle = UI.Text(panel, "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", 16, y)
subtitle:SetText("An unofficial companion add-on for Auctionator. The Vendor Deals and Crafting tabs are in the"
  .. " auction house window. Key bindings for Buy, Skip and Scan are under Keybindings > Vendor Sniper.")
Gap(18)

Header("Vendor Deals")
MoneyField("minItemProfit", "Minimum profit per item",
  "Deals that earn less than this per item aren't listed or bought.", 1)
MoneyField("maxSpend", "Max spend per session",
  "Buying stops after spending this much until you log out or reload. 0 = no limit.", 0)
Checkbox("includeDisenchant", "Include disenchant value",
  "Gear also counts as a deal when disenchanting it is worth more than its price (shown as DE).")
PercentField("maxDisenchantRisk", "Max disenchant risk",
  "Disenchant deals more likely than this to lose money on one item aren't listed or bought (most gear gives"
  .. " dust most of the time; essences and shards make up the average). 100% = no limit.")
Checkbox("sellToVendor", "Sell bought items to vendors",
  "Items the Buy button buys are sold automatically at the next merchant. Gear bought to disenchant isn't.")

Header("Merchants")
Checkbox("sellJunk", "Sell junk automatically",
  "Grey (poor quality) items in your bags are sold whenever you open a merchant.")
Checkbox("merchantBulkBuy", "Right-click to buy any amount",
  "Right-clicking a stackable item at a merchant asks how many to buy, beyond one stack.")

Header("Tooltips")
Checkbox("disenchantTooltip", "Disenchant value",
  "Gear tooltips show what disenchanting it is worth, with each material, its chance and its price.")
Checkbox("merchantPriceTooltip", "Merchant price",
  "Items sold by merchants show what a merchant charges (Auctionator's Vendor line is what a merchant pays you),"
  .. " and whether the auction house is cheaper.")
Checkbox("itemCounts", "Item counts on your characters",
  "Item tooltips show how many each character has in bags, bank and mail, as of their last login.")

Header("Professions")
Checkbox("professionProfits", "Profit in the profession window",
  "Each recipe shows its profit (green) or loss (red); enchants show what their materials cost.")
Checkbox("recipeTooltips", "Recipe profit before you learn it",
  "Tooltips at the trainer and on recipe items (Pattern:, Plans:, Recipe: and so on) show what the craft"
  .. " sells for, what its reagents cost and the profit. Open the profession window once so the addon"
  .. " learns its recipes.")
Checkbox("altClickDisenchant", "Alt+click to disenchant",
  "Alt+click a bag item that can be disenchanted to disenchant it (needs Enchanting, not in combat).")

Header("Troubleshooting")
Checkbox("debug", "Step-by-step trace in chat",
  "Prints what scanning, buying and Alt+click disenchanting do, to help find problems.")

panel:SetHeight(16 - y) -- the scroll range: everything above plus a margin

local function Refresh()
  for _, refresh in ipairs(refreshers) do
    refresh()
  end
end
canvas:SetScript("OnShow", Refresh)
VS.On("SETTINGS_CHANGED", function()
  if canvas:IsVisible() then
    Refresh()
  end
end)

-- Registering --------------------------------------------------------------------------------------

local category
if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
  category = Settings.RegisterCanvasLayoutCategory(canvas, TITLE)
  Settings.RegisterAddOnCategory(category)
end

function VS.OpenOptions()
  if not category then
    VS.Print("the game's options window isn't available. Type /vsnipe for the commands.")
    return
  end
  if InCombatLockdown() then
    VS.Print("the options can't open during combat.")
    return
  end
  Settings.OpenToCategory(category:GetID())
end
