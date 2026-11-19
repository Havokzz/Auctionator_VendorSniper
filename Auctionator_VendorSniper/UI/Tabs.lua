local _, VS = ...

-- Adds our tabs to the auction house window. LibAHTab (shipped with Auctionator) adds tabs without
-- tainting the auction house; if it's missing, a toggle button is used instead.

local UI = VS.UI
local created = false

local function CreateFallbackToggle(dealsTab)
  UI.Background(dealsTab, 0.05, 0.05, 0.05, 0.97)
  dealsTab:SetFrameLevel(AuctionHouseFrame:GetFrameLevel() + 20)
  local toggle = UI.Button(AuctionHouseFrame, "Vendor Deals", 110, 22)
  toggle:SetPoint("TOPRIGHT", AuctionHouseFrame, "TOPRIGHT", -30, -2)
  toggle:SetScript("OnClick", function()
    dealsTab:SetShown(not dealsTab:IsShown())
  end)
  VS.Print("LibAHTab wasn't found, so Vendor Deals opens from a button at the top of the auction house instead of a tab.")
end

local function CreateTabs()
  if created or not AuctionHouseFrame then
    return
  end
  created = true
  local dealsTab = UI.CreateDealsTab(AuctionHouseFrame)
  local craftingTab = UI.CreateCraftingTab(AuctionHouseFrame)

  local LibAHTab = LibStub and LibStub("LibAHTab-1-0", true)
  if LibAHTab then
    LibAHTab:CreateTab("VendorSniper_Deals", dealsTab, "Vendor Deals", "Vendor Sniper: Vendor Deals")
    LibAHTab:CreateTab("VendorSniper_Crafting", craftingTab, "Crafting", "Vendor Sniper: Crafting Profits")
  else
    CreateFallbackToggle(dealsTab)
  end
end

local events = CreateFrame("Frame")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:SetScript("OnEvent", function()
  local ok, err = pcall(CreateTabs)
  if not ok then
    VS.Print("couldn't add the auction house tabs: %s", tostring(err))
  end
end)
