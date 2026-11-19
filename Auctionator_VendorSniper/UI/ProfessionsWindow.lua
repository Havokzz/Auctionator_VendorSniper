local _, VS = ...

-- Shows each recipe's profit (green) or loss (red) at the right edge of its row in Blizzard's profession
-- window, with the same numbers as the Crafting tab. "?" means a price is missing. Recipes that make no
-- item (enchants) show what their materials cost instead, in grey.
-- The window is Blizzard_Professions, loaded on demand, so the hook is installed the first time it opens.

local Crafting, Recipes = VS.Crafting, VS.Recipes

local GREEN, RED, GREY = "|cff40ff40", "|cffff5050", "|cff808080"

local hooked = false
local cache = {} -- recipeID -> text ("" when there's nothing to show)

-- What the materials of a recipe cost at their cheapest source, or nil if one has no price.
local function MaterialCost(recipe)
  local cost = 0
  for _, reagent in ipairs(recipe.reagents) do
    local price = VS.Prices.Cheapest(reagent.itemID)
    if not price then
      return nil
    end
    cost = cost + price * reagent.quantity
  end
  return cost
end

local function ProfitText(recipeID)
  local text = cache[recipeID]
  if text then
    return text
  end
  text = ""
  local recipe = Recipes.ReadRecipe(recipeID, true)
  if recipe and not recipe.output then
    if #recipe.reagents > 0 then
      local cost = MaterialCost(recipe)
      text = GREY .. (cost and ("-" .. VS.FormatMoney(cost)) or "?") .. "|r"
    end
  elseif recipe then
    local row = Crafting.Evaluate(recipeID, recipe)
    if row.profit == nil then
      text = GREY .. "?|r"
    elseif row.profit >= 0 then
      text = GREEN .. "+" .. VS.FormatMoney(row.profit) .. "|r"
    else
      text = RED .. "-" .. VS.FormatMoney(-row.profit) .. "|r"
    end
  end
  cache[recipeID] = text
  return text
end

-- Shortens the recipe name (Blizzard's Label, which ends in "..." when cut) so it and the "[7]" craftable
-- count after it end before our text. Returns false if the row has no position yet.
local GAP = 6
local function FitLabel(frame)
  local label, ours = frame.Label, frame.vsProfit
  local text = ours and ours:GetText()
  if not label or not label.SetWidth or not text or text == "" then
    return true
  end
  local right, left = frame:GetRight(), label:GetLeft()
  if not right or not left then
    return false
  end
  local room = right - 6 - ours:GetStringWidth() - GAP - left
  local count = frame.Count
  if count and count:IsShown() and (count:GetText() or "") ~= "" then
    room = room - count:GetStringWidth() - 4
  end
  local full = label.GetUnboundedStringWidth and label:GetUnboundedStringWidth() or label:GetStringWidth()
  if room > 30 and full > room then
    label:SetWordWrap(false) -- one line, cut with "..."
    label:SetWidth(room)
  end
  return true
end

-- "Enchant Bracer - Minor Agility" -> "Bracer - Minor Agility": the category already says it's an enchant.
-- Blizzard sets the full name again whenever it sets up the row, so this runs every time.
local function ShortenName(frame)
  local label = frame.Label
  local name = label and label.GetText and label:GetText()
  local short = name and name:match("^Enchant (.+)$")
  if not short then
    return
  end
  local width = label:GetWidth()
  label:SetText(short)
  -- Blizzard sized the label for the full name; shrink it so the "[7]" count after it doesn't leave a gap
  local needed = label.GetUnboundedStringWidth and label:GetUnboundedStringWidth() or label:GetStringWidth()
  if needed and needed > 0 and (not width or width <= 0 or needed < width) then
    label:SetWidth(needed + 1)
  end
end

local function Decorate(frame, elementData, extra)
  if frame == VS then -- called with the owner first
    frame, elementData = elementData, extra
  end
  if type(frame) ~= "table" or not frame.CreateFontString then
    return
  end
  local node = elementData or (frame.GetElementData and frame:GetElementData())
  local data = node and node.GetData and node:GetData()
  local recipeInfo = data and data.recipeInfo
  if not recipeInfo then
    if frame.vsProfit then
      frame.vsProfit:SetText("")
    end
    return
  end
  if not frame.vsProfit then
    frame.vsProfit = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.vsProfit:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
    frame.vsProfit:SetJustifyH("RIGHT")
  end
  local ok, text = pcall(ProfitText, recipeInfo.recipeID)
  frame.vsProfit:SetText(ok and text or "")
  ShortenName(frame)
  if not FitLabel(frame) then
    C_Timer.After(0, function() -- the row isn't placed yet: try once it is
      FitLabel(frame)
    end)
  end
end

local function RecipeScrollBox()
  local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
  return page and page.RecipeList and page.RecipeList.ScrollBox
end

local function RefreshAll()
  wipe(cache)
  local scrollBox = RecipeScrollBox()
  if scrollBox and scrollBox:IsVisible() then
    scrollBox:ForEachFrame(Decorate)
  end
end

local function Hook()
  local scrollBox = RecipeScrollBox()
  if hooked or not scrollBox then
    return
  end
  hooked = true
  if ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
    -- runs for every row Blizzard sets up (scrolling, filtering, opening a category), after Blizzard's own setup
    ScrollUtil.AddInitializedFrameCallback(scrollBox, Decorate, VS, true)
  else
    hooksecurefunc(scrollBox, "Update", function(self)
      self:ForEachFrame(Decorate)
    end)
  end
end

local events = CreateFrame("Frame")
VS.SafeRegister(events, "TRADE_SKILL_SHOW")
events:SetScript("OnEvent", function()
  local ok, err = pcall(Hook)
  if not ok then
    VS.Debug("profession window hook failed: %s", tostring(err))
  end
  VS.Crafting.LoadItems()
  RefreshAll()
end)

-- prices or item data changed: recalculate the visible rows
local function RefreshSoon()
  C_Timer.After(0.2, RefreshAll)
end
VS.On("RECIPES_CHANGED", function()
  VS.Crafting.LoadItems()
  RefreshSoon()
end)
VS.On("CRAFTING_CHANGED", RefreshSoon)
VS.On("SCAN_DONE", RefreshSoon)
