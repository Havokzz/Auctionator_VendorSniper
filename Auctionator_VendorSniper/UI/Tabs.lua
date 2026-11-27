local _, VS = ...

-- Adds our tabs to the auction house window. LibAHTab (shipped with Auctionator) adds tabs without
-- tainting the auction house; if it's missing, a toggle button is used instead.

local UI = VS.UI
local created = false
local ourTabs = {} -- our tab buttons, first one first; the second, and any later LibAHTab tab, follows the first

-- Some add-ons place their own auction house tab by hand, right after Auctionator's tabs, which is where
-- LibAHTab puts ours. These find a shown button, other than ours, sitting on top of one of our tabs.
local MIN_OVERLAP_X = 20 -- pixels; tabs that only touch, or overlap at the edges by design, don't count

-- left, right, top, bottom in screen pixels, so frames with a different scale compare correctly
local function ScreenRect(region)
  local left, right, top, bottom = region:GetLeft(), region:GetRight(), region:GetTop(), region:GetBottom()
  if not (left and right and top and bottom) then
    return nil
  end
  local scale = region:GetEffectiveScale()
  return left * scale, right * scale, top * scale, bottom * scale
end

-- True when `frame` covers `tab`: across more than a few pixels, and most of the tab's height, so a
-- button near the bottom edge of the auction house window that just touches the tab row isn't a tab.
local function Covers(frame, tab)
  local left, right, top, bottom = ScreenRect(frame)
  local tabLeft, tabRight, tabTop, tabBottom = ScreenRect(tab)
  if not (left and tabLeft) then
    return false
  end
  return math.min(right, tabRight) - math.max(left, tabLeft) > MIN_OVERLAP_X
    and math.min(top, tabTop) - math.max(bottom, tabBottom) > (tabTop - tabBottom) / 2
end

-- True when `region` is inside `target` or positioned from it (directly or through other frames).
-- Our tab can't be placed after such a frame: the game refuses circular anchors.
local function DependsOn(region, target, seen)
  if region == target then
    return true
  end
  seen = seen or {}
  if not region or seen[region] then
    return false
  end
  seen[region] = true
  if region.GetParent and DependsOn(region:GetParent(), target, seen) then
    return true
  end
  for i = 1, region.GetNumPoints and region:GetNumPoints() or 0 do
    local _, relativeTo = region:GetPoint(i)
    if relativeTo and DependsOn(relativeTo, target, seen) then
      return true
    end
  end
  return false
end

local function IsOurs(frame)
  for _, tab in ipairs(ourTabs) do
    if frame == tab then
      return true
    end
  end
  return false
end

-- The rightmost shown button covering one of our tabs, searching `depth` levels of `parent`'s children.
local function FindCovering(parent, depth, found)
  for _, child in ipairs({ parent:GetChildren() }) do
    local forbidden = child.IsForbidden and child:IsForbidden()
    if not forbidden and not IsOurs(child) and child:IsShown() then
      if child:IsObjectType("Button") then
        local covers = false
        for _, tab in ipairs(ourTabs) do
          covers = covers or Covers(child, tab)
        end
        if covers and not DependsOn(child, ourTabs[1])
          and (not found or select(2, ScreenRect(child)) > select(2, ScreenRect(found))) then
          found = child
        end
      end
      if depth > 1 then
        found = FindCovering(child, depth - 1, found)
      end
    end
  end
  return found
end

-- Moves our tabs to the right of any tab sitting on top of them, at the same height as before. Only our
-- first tab is moved; tabs LibAHTab placed after ours (often Auctionator's) follow it, and the other
-- add-on's tab stays where it is.
local function AvoidOtherTabs()
  local first = ourTabs[1]
  if not (first and AuctionHouseFrame and AuctionHouseFrame:IsShown() and first:GetTop()) then
    return
  end
  for _ = 1, 5 do -- after moving, another tab may be in the way
    local other = FindCovering(AuctionHouseFrame, 3)
    if not other then
      return
    end
    local points = {}
    for i = 1, first:GetNumPoints() do
      points[i] = { first:GetPoint(i) }
    end
    local _, _, otherTop = ScreenRect(other)
    local _, _, firstTop = ScreenRect(first)
    local yOffset = (firstTop - otherTop) / first:GetEffectiveScale()
    first:ClearAllPoints()
    local ok = pcall(first.SetPoint, first, "TOPLEFT", other, "TOPRIGHT", 3, yOffset)
    if not ok then -- put it back where it was rather than leave it without a position
      first:ClearAllPoints()
      for _, point in ipairs(points) do
        first:SetPoint(unpack(point))
      end
      VS.Debug("tabs: couldn't move our tabs past %s", other:GetName() or "another tab")
      return
    end
    VS.Debug("tabs: %s covered our tabs, moved them after it", other:GetName() or "another tab")
  end
end

-- Other add-ons may add their tab when the auction house opens too, after us.
local function CheckTabs()
  local ok, err = pcall(AvoidOtherTabs)
  if not ok then
    VS.Debug("tabs: couldn't check for other tabs: %s", tostring(err))
  end
end

local function CheckTabsSoon()
  C_Timer.After(0, CheckTabs)
  C_Timer.After(1, CheckTabs)
end

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
    if LibAHTab.GetButton then
      ourTabs = { LibAHTab:GetButton("VendorSniper_Deals"), LibAHTab:GetButton("VendorSniper_Crafting") }
    end
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
  CheckTabsSoon()
end)
