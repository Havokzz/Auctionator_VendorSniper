local addonName, VS = ...

-- Shared namespace, saved settings, a tiny internal event bus, money helpers and the slash command.

VS.name = addonName
VS.callerID = addonName -- identifies us to Auctionator's API

local DEFAULTS = {
  minItemProfit = 1, -- copper each item must earn at least (vendor price minus what we pay)
  maxSpend = 0,      -- copper per session, 0 = no limit
  sellToVendor = false, -- mark purchases and sell them at the next merchant
  includeDisenchant = false, -- gear also counts as a deal when disenchanting it is worth more than the price
  altClickDisenchant = true, -- Alt+click a bag item to disenchant it
  sellJunk = false,          -- sell grey items at every merchant
  merchantBulkBuy = true,    -- right-click a stackable merchant item to buy any amount
  itemCounts = true,         -- item tooltips show how many each of your characters has
  disenchantTooltip = true,  -- gear tooltips show the disenchant value and materials
  professionProfits = true,  -- profit or loss next to each recipe in the profession window
}

VS.session = { spent = 0, vendorValue = 0, purchases = 0 }

-- Output -----------------------------------------------------------------------------------------

function VS.Print(text, ...)
  if select("#", ...) > 0 then
    text = text:format(...)
  end
  print("|cff33ff99VendorSniper|r: " .. text)
end

-- Step-by-step trace, on with /vsnipe debug.
function VS.Debug(text, ...)
  if VendorSniperDB and VendorSniperDB.debug then
    if select("#", ...) > 0 then
      text = text:format(...)
    end
    print("|cff888888VendorSniper debug:|r " .. text)
  end
end

-- Internal events --------------------------------------------------------------------------------

local listeners = {}

function VS.On(name, fn)
  listeners[name] = listeners[name] or {}
  table.insert(listeners[name], fn)
end

function VS.Fire(name, ...)
  for _, fn in ipairs(listeners[name] or {}) do
    local ok, err = pcall(fn, ...)
    if not ok then
      geterrorhandler()(err)
    end
  end
end

-- Registers a game event without erroring when the client doesn't know it (event names differ
-- slightly between game versions). Returns true if registered.
function VS.SafeRegister(frame, event)
  return (pcall(frame.RegisterEvent, frame, event))
end

-- Money ------------------------------------------------------------------------------------------

function VS.FormatMoney(copper)
  copper = math.floor((copper or 0) + 0.5)
  local negative = copper < 0
  copper = math.abs(copper)
  local text
  if GetMoneyString then
    text = GetMoneyString(copper, true)
  else
    text = GetCoinTextureString(copper)
  end
  return negative and ("-" .. text) or text
end

-- Copper as text that ParseMoney reads back, e.g. "1g20s5c", "50c", "0c".
function VS.MoneyInputText(copper)
  copper = math.max(0, math.floor((copper or 0) + 0.5))
  local gold, silver, rest = math.floor(copper / 10000), math.floor(copper % 10000 / 100), copper % 100
  local text = (gold > 0 and (gold .. "g") or "") .. (silver > 0 and (silver .. "s") or "")
    .. (rest > 0 and (rest .. "c") or "")
  return text ~= "" and text or "0c"
end

-- Accepts "1g20s5c", "50s", "3g", or a plain number (copper). Returns copper or nil.
function VS.ParseMoney(text)
  if not text then
    return nil
  end
  -- accepts "50c", "50 copper", "1s50c", "1.5s", "2g 30s", or plain copper ("50")
  text = text:lower():gsub("%s+", ""):gsub("gold", "g"):gsub("silver", "s"):gsub("copper", "c")
  if text == "" then
    return nil
  end
  if text:match("^%d+$") then
    return tonumber(text)
  end
  local total, matched = 0, false
  for amount, unit in text:gmatch("([%d%.]+)([gsc])") do
    amount = tonumber(amount)
    if not amount then
      return nil
    end
    matched = true
    if unit == "g" then
      total = total + amount * 10000
    elseif unit == "s" then
      total = total + amount * 100
    else
      total = total + amount
    end
  end
  -- reject leftovers like "5x"
  if not matched or text:gsub("[%d%.]+[gsc]", "") ~= "" then
    return nil
  end
  return math.floor(total + 0.5)
end

-- Auctionator ------------------------------------------------------------------------------------

function VS.HasAuctionator()
  return Auctionator ~= nil and Auctionator.API ~= nil and Auctionator.API.v1 ~= nil
end

-- Settings & slash command -----------------------------------------------------------------------

function VS.GetSetting(key)
  return VendorSniperDB[key]
end

function VS.SetSetting(key, value)
  VendorSniperDB[key] = value
  VS.Fire("SETTINGS_CHANGED", key, value)
end

local function PrintHelp()
  VS.Print("commands (all settings are also in Options > AddOns, or /vsnipe options):")
  print("  /vsnipe options             - open this addon's options")
  print(("  /vsnipe minprofit <amount>  - least profit per item, e.g. 5s or 1g (now %s)")
    :format(VS.FormatMoney(VS.GetSetting("minItemProfit"))))
  local maxSpend = VS.GetSetting("maxSpend")
  print(("  /vsnipe maxspend <amount>   - stop buying after spending this much per session, 0 = off (now %s)")
    :format(maxSpend > 0 and VS.FormatMoney(maxSpend) or "off"))
  print("  /vsnipe scan                - scan the auction house (it must be open)")
  print("  /vsnipe session             - what you bought this session")
  print("  /vsnipe clearsell           - forget which bought items are waiting to be sold to a vendor")
  print(("  /vsnipe altde               - Alt+click a bag item to disenchant it, on or off (now %s)")
    :format(VS.GetSetting("altClickDisenchant") and "on" or "off"))
  print("  /vsnipe debug               - turn the step-by-step trace in chat on or off")
end

SLASH_VENDORSNIPER1 = "/vsnipe"
SLASH_VENDORSNIPER2 = "/vendorsniper"
SlashCmdList.VENDORSNIPER = function(input)
  local command, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
  command = command:lower()
  if command == "minprofit" or command == "min" or command == "profit" then
    local value = VS.ParseMoney(rest)
    if not value then
      VS.Print("couldn't read \"%s\" as an amount. Examples: /vsnipe minprofit 50c, /vsnipe minprofit 1s50c,"
        .. " /vsnipe minprofit 2g", rest)
      return
    end
    VS.SetSetting("minItemProfit", math.max(1, value))
    VS.Print("minimum profit per item: %s", VS.FormatMoney(math.max(1, value)))
  elseif command == "maxspend" then
    local value = VS.ParseMoney(rest)
    if not value then
      VS.Print("usage: /vsnipe maxspend 100g  (0 turns it off)")
      return
    end
    VS.SetSetting("maxSpend", value)
    VS.Print("max spend per session: %s", value > 0 and VS.FormatMoney(value) or "off")
  elseif command == "debug" then
    VendorSniperDB.debug = not VendorSniperDB.debug
    VS.Print("debug trace %s.", VendorSniperDB.debug and "on" or "off")
  elseif command == "scan" then
    VS.Scan.Start()
  elseif command == "options" or command == "config" or command == "settings" then
    VS.OpenOptions()
  elseif command == "altde" then
    VS.SetSetting("altClickDisenchant", not VS.GetSetting("altClickDisenchant"))
    VS.Print("Alt+click to disenchant %s.", VS.GetSetting("altClickDisenchant") and "on" or "off")
  elseif command == "clearsell" then
    local count = VS.AutoSell.ClearMarks()
    VS.Print("forgot the vendor marks of %d item%s.", count, count == 1 and "" or "s")
  elseif command == "session" then
    local s = VS.session
    VS.Print("%d purchases, spent %s, worth %s, profit %s", s.purchases, VS.FormatMoney(s.spent),
      VS.FormatMoney(s.vendorValue), VS.FormatMoney(s.vendorValue - s.spent))
  else
    PrintHelp()
  end
end

-- Startup ----------------------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
  if name ~= addonName then
    return
  end
  self:UnregisterEvent("ADDON_LOADED")
  VendorSniperDB = VendorSniperDB or {}
  for key, value in pairs(DEFAULTS) do
    if VendorSniperDB[key] == nil then
      VendorSniperDB[key] = value
    end
  end
  VendorSniperDB.minProfit, VendorSniperDB.lastOwnScan = nil, nil -- replaced in 0.2.0
  VendorSniperDB.auctionPrices, VendorSniperDB.vendorPrices = nil, nil -- briefly saved by 0.4.0, Auctionator has them
  VendorSniperDB.log = nil -- a troubleshooting log saved by test builds before 1.0.2
  VendorSniperDB.lastScanCount = nil -- items in the last scan, replaced by lastScanResults after 1.0.2
  if not VS.HasAuctionator() then
    VS.Print("Auctionator's API was not found - prices and shared scans won't work.")
  end
  VS.Fire("LOADED")
end)
