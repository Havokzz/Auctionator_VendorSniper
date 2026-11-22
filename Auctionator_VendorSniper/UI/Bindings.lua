local _, VS = ...

-- Key bindings, set in the game's Options > Keybindings > Vendor Sniper (declared in Bindings.xml). Buy and Skip
-- do what clicking their buttons on the Vendor Deals tab does, and only while it's open; Scan works while
-- the auction house is open. A key press counts as a click for the game's purchase rules, so Buy can buy:
-- like the button, it only reads before the purchase call (see Buy.Click).

BINDING_NAME_VENDORSNIPER_BUY = "Buy the current deal"
BINDING_NAME_VENDORSNIPER_SKIP = "Skip the current deal"
BINDING_NAME_VENDORSNIPER_SCAN = "Scan, or stop the scan"

local function Press(key)
  local buttons = VS.UI.dealsButtons
  local button = buttons and buttons[key]
  if not (button and button:IsVisible()) then
    VS.Print("open the Vendor Deals tab in the auction house to use this key.")
    return
  end
  if button:IsEnabled() then
    button:GetScript("OnClick")(button, "LeftButton", false)
  end
end

function VendorSniper_KeyBuy()
  Press("buy")
end

function VendorSniper_KeySkip()
  Press("skip")
end

function VendorSniper_KeyScan()
  VS.Scan.Toggle()
end
