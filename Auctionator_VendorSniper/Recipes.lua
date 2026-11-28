local _, VS = ...

-- Learns the recipes of each profession when its window is opened. Forever uses the retail profession API
-- (C_TradeSkillUI), which only has recipe data while the window is open, so what was seen is saved per
-- character: VendorSniperDB.characters["Name-Realm"].professions[professionName] =
--   { updated = time(), recipes = { [recipeID] = { name, icon, output, made, reagents = { {itemID, quantity} } } } }
-- Recipes without an item to sell (most enchants) are left out.
-- Recipes not learned yet are saved apart, in .unlearned[professionName] = { updated, recipes } (enchants
-- included, with output nil), for the recipe profit in trainer and recipe item tooltips. The Crafting tab
-- and the profession window only use learned ones.

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

-- A recipe as saved (see the top of this file), read from the open profession window; nil if it makes no
-- item (unless withoutItem is true: then such recipes, like enchants, have output nil), or isn't learned
-- (unless includeUnlearned is true).
local function ReadRecipe(recipeID, withoutItem, includeUnlearned)
  local info = C.GetRecipeInfo(recipeID)
  if not info or info.isDummyRecipe or not (info.learned or includeUnlearned) then
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

-- Calls fn(recipeID, recipe, professionName, learned, characterKey) for every saved recipe of this
-- character, learned or not, until it returns true. With allCharacters, your other characters' recipes
-- follow this character's.
local function EachRecipe(fn, allCharacters)
  local me = Recipes.CharacterKey()
  local keys = { me }
  if allCharacters then
    for key in pairs(VendorSniperDB.characters or {}) do
      if key ~= me then
        keys[#keys + 1] = key
      end
    end
  end
  for _, key in ipairs(keys) do
    local data = VendorSniperDB.characters and VendorSniperDB.characters[key]
    if type(data) == "table" then
      for _, group in ipairs({ { data.professions, true }, { data.unlearned, false } }) do
        for professionName, profession in pairs(group[1] or {}) do
          for recipeID, recipe in pairs(profession.recipes or {}) do
            if fn(recipeID, recipe, professionName, group[2], key) then
              return
            end
          end
        end
      end
    end
  end
end

-- A recipe by its ID (the spell a trainer teaches): recipe, professionName, learned. Saved recipes first,
-- then the game's own data, which may answer while the profession window is closed.
function Recipes.Find(recipeID)
  local found, foundProfession, foundLearned
  EachRecipe(function(id, recipe, professionName, learned)
    if id == recipeID then
      found, foundProfession, foundLearned = recipe, professionName, learned
      return true
    end
  end)
  if found or not (C and C.GetRecipeInfo) then
    return found, foundProfession, foundLearned
  end
  local ok, recipe = pcall(ReadRecipe, recipeID, true, true)
  if ok and recipe then
    return recipe, nil, nil
  end
end

-- A saved recipe by its name, e.g. "Runecloth Bag" for "Pattern: Runecloth Bag": recipeID, recipe,
-- professionName, learned, characterKey. With allCharacters, your other characters' recipes are searched
-- after this character's (a recipe item bought on one character is often for another).
function Recipes.FindByName(name, allCharacters)
  name = name:lower()
  local result
  EachRecipe(function(recipeID, recipe, professionName, learned, key)
    if recipe.name and recipe.name:lower() == name then
      result = { recipeID, recipe, professionName, learned, key }
      return true
    end
  end, allCharacters)
  if result then
    return result[1], result[2], result[3], result[4], result[5]
  end
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
  local recipes, count, unlearned, unlearnedCount = {}, 0, {}, 0
  for _, recipeID in ipairs(recipeIDs) do
    local recipe = ReadRecipe(recipeID)
    if recipe then
      recipes[recipeID] = recipe
      count = count + 1
    else
      local info = C.GetRecipeInfo(recipeID)
      recipe = info and not info.learned and ReadRecipe(recipeID, true, true)
      if recipe then
        unlearned[recipeID] = recipe
        unlearnedCount = unlearnedCount + 1
      end
    end
  end
  if count == 0 and unlearnedCount == 0 then
    return -- the list isn't loaded yet; keep what was saved
  end
  local data = CharacterData(true)
  data.unlearned = data.unlearned or {}
  data.unlearned[professionName] = { updated = time(), recipes = unlearned }
  VS.Debug("recipes: %s, %d not learned yet", professionName, unlearnedCount)
  if count == 0 then
    return -- nothing with an item to sell is learned (Enchanting); keep the Crafting tab as it was
  end
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
