local _, VS = ...

-- The addon's page in the game's options (Esc > Options > AddOns), also opened by /vsnipe options.
-- Every setting is here; the Vendor Deals tab's checkboxes change the same settings and stay in sync.

local UI = VS.UI

local TITLE = "Auctionator: Vendor Sniper & Crafting"

local panel = CreateFrame("Frame")
panel:Hide()
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

-- Layout -------------------------------------------------------------------------------------------

local title = UI.Text(panel, "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, y)
title:SetText(TITLE)
Gap(22)
local subtitle = UI.Text(panel, "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", 16, y)
subtitle:SetText("An unofficial companion add-on for Auctionator. The Vendor Deals and Crafting tabs are in the"
  .. " auction house window.")
Gap(18)

Header("Vendor Deals")
MoneyField("minItemProfit", "Minimum profit per item",
  "Deals that earn less than this per item aren't listed or bought.", 1)
MoneyField("maxSpend", "Max spend per session",
  "Buying stops after spending this much until you log out or reload. 0 = no limit.", 0)
Checkbox("includeDisenchant", "Include disenchant value",
  "Gear also counts as a deal when disenchanting it is worth more than its price (shown as DE).")
Checkbox("sellToVendor", "Sell bought items to vendors",
  "Items the Buy button buys are sold automatically at the next merchant. Gear bought to disenchant isn't.")

Header("Merchants")
Checkbox("sellJunk", "Sell junk automatically",
  "Grey (poor quality) items in your bags are sold whenever you open a merchant.")
Checkbox("merchantBulkBuy", "Right-click to buy any amount",
  "Right-clicking a stackable item at a merchant asks how many to buy, beyond one stack.")

Header("Tooltips")
Checkbox("itemCounts", "Item counts on your characters",
  "Item tooltips show how many each character has in bags, bank and mail, as of their last login.")

Header("Disenchanting")
Checkbox("altClickDisenchant", "Alt+click to disenchant",
  "Alt+click a bag item that can be disenchanted to disenchant it (needs Enchanting, not in combat).")

Header("Troubleshooting")
Checkbox("debug", "Step-by-step trace in chat",
  "Prints what scanning, buying and Alt+click disenchanting do, to help find problems.")

local function Refresh()
  for _, refresh in ipairs(refreshers) do
    refresh()
  end
end
panel:SetScript("OnShow", Refresh)
VS.On("SETTINGS_CHANGED", function()
  if panel:IsShown() then
    Refresh()
  end
end)

-- Registering --------------------------------------------------------------------------------------

local category
if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
  category = Settings.RegisterCanvasLayoutCategory(panel, TITLE)
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
