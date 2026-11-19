local _, VS = ...

-- What gear disenchants into, and what that's worth at Auctionator's prices.
--
-- Forever uses the classic-era enchanting materials. The table below is the classic-era disenchant table
-- (item level range -> materials with amounts and chances), written for this addon from the game's
-- published drop data. Chances are typical values; a single disenchant varies.

VS.Disenchant = {}
local Disenchant = VS.Disenchant

local GetItemInfo = C_Item.GetItemInfo

-- Materials
local STRANGE_DUST, SOUL_DUST, VISION_DUST, DREAM_DUST, ILLUSION_DUST = 10940, 11083, 11137, 11176, 16204
local LESSER_MAGIC, GREATER_MAGIC = 10938, 10939
local LESSER_ASTRAL, GREATER_ASTRAL = 10998, 11082
local LESSER_MYSTIC, GREATER_MYSTIC = 11134, 11135
local LESSER_NETHER, GREATER_NETHER = 11174, 11175
local LESSER_ETERNAL, GREATER_ETERNAL = 16202, 16203
local SMALL_GLIMMERING, LARGE_GLIMMERING = 10978, 11084
local SMALL_GLOWING, LARGE_GLOWING = 11138, 11139
local SMALL_RADIANT, LARGE_RADIANT = 11177, 11178
local SMALL_BRILLIANT, LARGE_BRILLIANT = 14343, 14344
local NEXUS_CRYSTAL = 20725

-- Uncommon (green) gear: per item level band, the dust, essence and shard with their amounts. Armor
-- mostly gives dust, weapons mostly essence.
local UNCOMMON = {
  -- maxLevel, dust {id, min, max}, essence {id, min, max}, shard id (or nil)
  { 15, { STRANGE_DUST, 1, 2 }, { LESSER_MAGIC, 1, 2 }, nil },
  { 20, { STRANGE_DUST, 2, 3 }, { GREATER_MAGIC, 1, 2 }, SMALL_GLIMMERING },
  { 25, { STRANGE_DUST, 4, 6 }, { LESSER_ASTRAL, 1, 2 }, SMALL_GLIMMERING },
  { 30, { SOUL_DUST, 1, 2 }, { GREATER_ASTRAL, 1, 2 }, LARGE_GLIMMERING },
  { 35, { SOUL_DUST, 2, 5 }, { LESSER_MYSTIC, 1, 2 }, SMALL_GLOWING },
  { 40, { VISION_DUST, 1, 2 }, { GREATER_MYSTIC, 1, 2 }, LARGE_GLOWING },
  { 45, { VISION_DUST, 2, 5 }, { LESSER_NETHER, 1, 2 }, SMALL_RADIANT },
  { 50, { DREAM_DUST, 1, 2 }, { GREATER_NETHER, 1, 2 }, LARGE_RADIANT },
  { 55, { DREAM_DUST, 2, 5 }, { LESSER_ETERNAL, 1, 2 }, SMALL_BRILLIANT },
  { 60, { ILLUSION_DUST, 1, 2 }, { GREATER_ETERNAL, 1, 2 }, LARGE_BRILLIANT },
  { 99, { ILLUSION_DUST, 2, 5 }, { GREATER_ETERNAL, 2, 3 }, LARGE_BRILLIANT },
}
local UNCOMMON_MIN_LEVEL = 5

-- Rare (blue) gear: one shard; the top band sometimes gives a Nexus Crystal instead.
local RARE = {
  { 25, { { SMALL_GLIMMERING, 1, 1, 1 } } },
  { 30, { { LARGE_GLIMMERING, 1, 1, 1 } } },
  { 35, { { SMALL_GLOWING, 1, 1, 1 } } },
  { 40, { { LARGE_GLOWING, 1, 1, 1 } } },
  { 45, { { SMALL_RADIANT, 1, 1, 1 } } },
  { 50, { { LARGE_RADIANT, 1, 1, 1 } } },
  { 55, { { SMALL_BRILLIANT, 1, 1, 1 } } },
  { 99, { { LARGE_BRILLIANT, 1, 1, 0.995 }, { NEXUS_CRYSTAL, 1, 1, 0.005 } } },
}
local RARE_MIN_LEVEL = 11

-- Epic (purple) gear
local EPIC = {
  { 45, { { SMALL_RADIANT, 2, 4, 1 } } },
  { 50, { { LARGE_RADIANT, 2, 4, 1 } } },
  { 55, { { SMALL_BRILLIANT, 2, 4, 1 } } },
  { 60, { { NEXUS_CRYSTAL, 1, 1, 1 } } },
  { 99, { { NEXUS_CRYSTAL, 1, 2, 1 } } },
}
local EPIC_MIN_LEVEL = 40

local WEAPON, ARMOR = 2, 4
local NOT_DISENCHANTABLE_SLOTS = { INVTYPE_BODY = true, INVTYPE_TABARD = true, INVTYPE_NON_EQUIP_IGNORE = true }

-- Gear the game won't let you disenchant. The client has no function that says so, so they're listed here.
local NOT_DISENCHANTABLE_ITEMS = {
  [11287] = true, -- Lesser Magic Wand    (made by enchanters)
  [11288] = true, -- Greater Magic Wand   (made by enchanters)
  [11289] = true, -- Lesser Mystic Wand   (made by enchanters)
  [11290] = true, -- Greater Mystic Wand  (made by enchanters)
}

local function Band(bands, itemLevel)
  for _, band in ipairs(bands) do
    if itemLevel <= band[1] then
      return band
    end
  end
end

-- The materials an item disenchants into: list of { itemID, min, max, chance }, or nil if it can't be
-- disenchanted (or isn't loaded yet).
function Disenchant.GetMaterials(item)
  local _, link, quality, itemLevel, _, _, _, _, equipLoc, _, _, classID = GetItemInfo(item)
  if not link or (classID ~= WEAPON and classID ~= ARMOR) or not equipLoc or equipLoc == ""
    or NOT_DISENCHANTABLE_SLOTS[equipLoc] or NOT_DISENCHANTABLE_ITEMS[C_Item.GetItemInfoInstant(link)] then
    return nil
  end
  itemLevel = (C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)) or itemLevel or 0

  if quality == Enum.ItemQuality.Uncommon and itemLevel >= UNCOMMON_MIN_LEVEL then
    local band = Band(UNCOMMON, itemLevel)
    local dust, essence, shard = band[2], band[3], band[4]
    -- armor: mostly dust; weapons: mostly essence
    local main, side = dust, essence
    if classID == WEAPON then
      main, side = essence, dust
    end
    local materials = {}
    if shard then
      materials[1] = { main[1], main[2], main[3], 0.75 }
      materials[2] = { side[1], side[2], side[3], 0.20 }
      materials[3] = { shard, 1, 1, 0.05 }
    else
      materials[1] = { main[1], main[2], main[3], 0.80 }
      materials[2] = { side[1], side[2], side[3], 0.20 }
    end
    return materials
  elseif quality == Enum.ItemQuality.Rare and itemLevel >= RARE_MIN_LEVEL then
    return Band(RARE, itemLevel)[2]
  elseif quality == Enum.ItemQuality.Epic and itemLevel >= EPIC_MIN_LEVEL then
    return Band(EPIC, itemLevel)[2]
  end
end

-- Expected auction house value of disenchanting one item: value, materials, and whether some material
-- had no price (then value counts only the priced ones). nil if it can't be disenchanted.
-- priceOf(itemID) prices the materials; by default Auctionator's last saved price.
function Disenchant.GetValue(item, priceOf)
  local materials = Disenchant.GetMaterials(item)
  if not materials then
    return nil
  end
  priceOf = priceOf or VS.Prices.Auction
  local value, unpriced = 0, false
  for _, material in ipairs(materials) do
    local price = priceOf(material[1])
    if price then
      value = value + price * material[4] * (material[2] + material[3]) / 2
    else
      unpriced = true
    end
  end
  return math.floor(value), materials, unpriced
end

local AH_CUT = 0.95 -- the materials are sold on the auction house, which keeps 5%

-- What one unit of an item is worth to the sniper: value, how it's earned ("vendor" or "disenchant"),
-- vendor sell price, max stack size. With the "Disenchant" option on, gear counts at its disenchant value
-- (after the auction house cut) when that's more than a vendor pays. nil while the item isn't loaded.
-- priceOf prices the disenchant materials (see GetValue).
function Disenchant.DealValue(item, priceOf)
  local sellPrice, maxStack = VS.ItemData.GetSellInfo(item)
  if not sellPrice then
    return nil
  end
  local value, via = sellPrice, "vendor"
  if VS.GetSetting("includeDisenchant") then
    local disenchant = Disenchant.GetValue(item, priceOf)
    disenchant = disenchant and math.floor(disenchant * AH_CUT)
    if disenchant and disenchant > value then
      value, via = disenchant, "disenchant"
    end
  end
  return value, via, sellPrice, maxStack
end
