local _, VS = ...

-- Learns the recipes of each profession when its window is opened. Forever uses the retail profession API
-- (C_TradeSkillUI), which only has recipe data while the window is open, so what was seen is saved per
-- character: VendorSniperDB.characters["Name-Realm"].professions[professionName] =
--   { updated = time(), recipes = { [recipeID] = { name, icon, output, made, reagents = { {itemID, quantity} } } } }
-- Recipes without an item to sell (most enchants) are left out.

VS.Recipes = {}
local Recipes = VS.Recipes

local C = C_TradeSkillUI

function Recipes.CharacterKey()
  local name, realm = UnitFullName("player")
  return ("%s-%s"):format(name or "?", realm or GetRealmName() or "?")
end

local function CharacterData(create)
  VendorSniperDB.characters = VendorSniperDB.characters or {}
  local key = Recipes.CharacterKey()
  local data = VendorSniperDB.characters[key]
  if not data and create then
    data = { professions = {} }
    VendorSniperDB.characters[key] = data
  end
  return data
end

-- This character's professions: name -> { updated, recipes }.
function Recipes.GetProfessions()
  local data = CharacterData(false)
  return data and data.professions or {}
end

-- A window showing someone else's recipes (a linked profession, a guild member's, an NPC's) isn't ours.
local function IsOwnWindow()
  return not ((C.IsTradeSkillLinked and C.IsTradeSkillLinked()) or (C.IsTradeSkillGuild and C.IsTradeSkillGuild())
    or (C.IsNPCCrafting and C.IsNPCCrafting()))
end

-- A recipe as saved (see the top of this file), read from the open profession window; nil if it isn't
-- learned, or makes no item (unless withoutItem is true: then such recipes, like enchants, have output nil).
local function ReadRecipe(recipeID, withoutItem)
  local info = C.GetRecipeInfo(recipeID)
  if not info or not info.learned or info.isDummyRecipe then
    return nil
  end
  local schematic = C.GetRecipeSchematic(recipeID, false)
  if not schematic or not (schematic.outputItemID or withoutItem) then
    return nil
  end
  local reagents = {}
  for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
    local first = slot.reagents and slot.reagents[1]
    -- basic reagents only: optional and finishing reagents aren't needed to craft
    if first and first.itemID and slot.reagentType == Enum.CraftingReagentType.Basic then
      reagents[#reagents + 1] = { itemID = first.itemID, quantity = slot.quantityRequired or 1 }
    end
  end
  local made = ((schematic.quantityMin or 1) + (schematic.quantityMax or schematic.quantityMin or 1)) / 2
  return { name = info.name, icon = info.icon, output = schematic.outputItemID, made = made, reagents = reagents }
end

Recipes.ReadRecipe = function(recipeID, withoutItem)
  return ReadRecipe(recipeID, withoutItem)
end

local function Capture()
  if not (C and C.GetAllRecipeIDs and C.GetBaseProfessionInfo) or not IsOwnWindow() then
    return
  end
  if C.IsTradeSkillReady and not C.IsTradeSkillReady() then
    return
  end
  local profession = C.GetBaseProfessionInfo()
  local professionName = profession and profession.professionName
  local recipeIDs = C.GetAllRecipeIDs()
  if not professionName or professionName == "" or not recipeIDs or #recipeIDs == 0 then
    return
  end
  local recipes, count = {}, 0
  for _, recipeID in ipairs(recipeIDs) do
    local recipe = ReadRecipe(recipeID)
    if recipe then
      recipes[recipeID] = recipe
      count = count + 1
    end
  end
  if count == 0 then
    return -- the list isn't loaded yet; keep what was saved
  end
  local data = CharacterData(true)
  local previous = data.professions[professionName]
  local previousCount = 0
  for _ in pairs(previous and previous.recipes or {}) do
    previousCount = previousCount + 1
  end
  data.professions[professionName] = { updated = time(), recipes = recipes }
  VS.Debug("recipes: %s, %d with an item to sell", professionName, count)
  if count ~= previousCount then
    VS.Print("learned %d %s recipes for the Crafting tab.", count, professionName)
  end
  VS.Fire("RECIPES_CHANGED")
end

-- The list updates several times while the window opens, so capture once things settle.
local pending = false
local function CaptureSoon()
  if pending then
    return
  end
  pending = true
  C_Timer.After(1, function()
    pending = false
    local ok, err = pcall(Capture)
    if not ok then
      VS.Debug("recipe capture failed: %s", tostring(err))
    end
  end)
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED" }) do
  VS.SafeRegister(events, event)
end
events:SetScript("OnEvent", CaptureSoon)
