local _, VS = ...

-- Alt+click a bag item to disenchant it.
--
-- Addon code can't cast Disenchant by itself: it needs a real click on a secure button. So while Alt is held
-- over a bag item that can be disenchanted, an invisible secure button is laid over that bag slot. Clicking
-- it casts Disenchant on the item in that slot (SecureActionButtonTemplate, type "spell" with target-bag and
-- target-slot). Secure buttons can't be moved in combat, so this is off while in combat.
--
-- Safety: if Disenchant can't start (already casting, cooldown, another spell waiting for a target), the
-- click would use the item instead - for gear that means equipping it, which binds it. PreClick turns the
-- click into a no-op in those cases.

VS.DisenchantClick = {}
local DisenchantClick = VS.DisenchantClick

local DISENCHANT = 13262 -- spell ID
local HINT_COLOR = { 0.64, 0.4, 1 }

local button = CreateFrame("Button", "VendorSniperDisenchantButton", UIParent, "SecureActionButtonTemplate")
local armed -- { bag, slot } while the button sits over a bag slot
local showingTooltip = false
local clickedAt = 0 -- GetTime() of the last click, to explain a blocked action right after it
local lastTrace -- the last "no hint" reason traced

function DisenchantClick.IsOn()
  return VS.GetSetting("altClickDisenchant") ~= false
end

local function SpellName()
  if C_Spell and C_Spell.GetSpellName then
    return C_Spell.GetSpellName(DISENCHANT)
  end
  return (GetSpellInfo(DISENCHANT))
end

local function KnowsDisenchant()
  if IsPlayerSpell and IsPlayerSpell(DISENCHANT) then
    return true
  end
  return IsSpellKnown ~= nil and IsSpellKnown(DISENCHANT)
end

-- True when Disenchant can't start right now, so a click must do nothing.
local function Busy()
  if UnitCastingInfo("player") or UnitChannelInfo("player") or SpellIsTargeting() then
    return true
  end
  local start, duration
  if C_Spell and C_Spell.GetSpellCooldown then
    local info = C_Spell.GetSpellCooldown(DISENCHANT)
    start, duration = info and info.startTime, info and info.duration
  elseif GetSpellCooldown then
    start, duration = GetSpellCooldown(DISENCHANT)
  end
  return (start or 0) > 0 and (duration or 0) > 0
end

-- The bag and slot a tooltip's owner shows, if it's a slot of the character's bags (Blizzard's bags, and
-- bag addons that use the same methods).
local function BagSlot(owner)
  if not owner or owner == button or type(owner.GetID) ~= "function" then
    return nil
  end
  local ok, bag, slot = pcall(function()
    local id = owner:GetID()
    if type(owner.GetBagID) == "function" then
      return owner:GetBagID(), id
    elseif type(owner.GetBag) == "function" then
      return owner:GetBag(), id
    end
    local parent = owner:GetParent()
    return parent and type(parent.GetID) == "function" and parent:GetID() or nil, id
  end)
  local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
  if not ok or type(bag) ~= "number" or type(slot) ~= "number" or bag < 0 or bag > lastBag or slot < 1 then
    return nil
  end
  return bag, slot
end

-- The bag slot of a tooltip showing an item that can be disenchanted by Alt+click. If not: nil, why, and
-- true when the reason points at a problem (the usual reasons aren't worth a debug line on every tooltip).
local function Target(owner, link)
  if not link then
    return nil, "no item link"
  elseif not DisenchantClick.IsOn() then
    return nil, "Alt+click is turned off (/vsnipe altde)"
  elseif not KnowsDisenchant() then
    return nil, "this character doesn't know Disenchant"
  end
  local bag, slot = BagSlot(owner)
  if not bag then
    local name = owner and owner.GetName and owner:GetName() or "unnamed"
    local hasBagID = owner and type(owner.GetBagID) == "function"
    return nil, ("the tooltip isn't from a bag slot (owner %s, GetBagID %s, id %s)"):format(tostring(name),
      tostring(hasBagID), tostring(owner and owner.GetID and owner:GetID()))
  end
  local itemID = C_Item.GetItemInfoInstant(link)
  local slotItemID = C_Container.GetContainerItemID(bag, slot)
  if not itemID or slotItemID ~= itemID then
    return nil, ("bag %d slot %d holds item %s, the tooltip shows %s"):format(bag, slot, tostring(slotItemID),
      tostring(itemID)), true
  end
  if not VS.Disenchant.GetMaterials(link) then
    return nil, "the disenchant table says it can't be disenchanted"
  end
  return bag, slot
end

local function Disarm()
  if not armed or InCombatLockdown() then
    return
  end
  armed = nil
  button:Hide()
  button:ClearAllPoints()
end

local function Arm(owner, bag, slot)
  if InCombatLockdown() then
    return
  end
  local info = C_Container.GetContainerItemInfo(bag, slot)
  if info and info.isLocked then
    return -- being moved, sold or disenchanted
  end
  armed = { bag = bag, slot = slot }
  button:SetAttribute("spell", SpellName() or DISENCHANT)
  button:SetAttribute("target-bag", bag)
  button:SetAttribute("target-slot", slot)
  button:ClearAllPoints()
  button:SetAllPoints(owner)
  button:Show()
  VS.Debug("alt+click: armed over bag %d slot %d (%s), spell %q", bag, slot, owner:GetName() or "unnamed",
    tostring(button:GetAttribute("spell")))
end

-- The button --------------------------------------------------------------------------------------

button:SetFrameStrata("TOOLTIP")
-- both, so it works whichever way the "cast on key down" option is set; a second firing finds the
-- disenchant already casting and does nothing
button:RegisterForClicks("AnyUp", "AnyDown")
button:Hide()

local highlight = button:CreateTexture(nil, "OVERLAY")
highlight:SetAllPoints()
highlight:SetColorTexture(0.64, 0.21, 0.93, 0.3)

button:SetScript("PreClick", function(self, mouseButton, down)
  if InCombatLockdown() then
    return
  end
  -- left click only, and only when Disenchant can start. "*type1" = left click with any modifier held; a
  -- plain "type1" only counts for clicks without modifiers, and Alt is always held here.
  if armed and not Busy() then
    self:SetAttribute("*type1", "spell")
  else
    self:SetAttribute("*type1", nil)
  end
  clickedAt = GetTime()
  VS.Debug("alt+click: %s %s, armed %s, casting %s, targeting %s -> %s", tostring(mouseButton),
    down and "down" or "up", tostring(armed ~= nil), tostring(UnitCastingInfo("player") ~= nil),
    tostring(SpellIsTargeting()), tostring(self:GetAttribute("*type1")))
end)

-- After the secure click: Disenchant should be casting on the item. If it's waiting for a target instead
-- (the client's secure button didn't apply target-bag/target-slot), apply it to the item here. Only while
-- the spell is waiting for an item, so this can never use or equip the item.
button:SetScript("PostClick", function(_, mouseButton, down)
  local targeting = SpellIsTargeting()
  VS.Debug("alt+click: after %s %s: casting %s, targeting %s", tostring(mouseButton), down and "down" or "up",
    tostring(UnitCastingInfo("player") ~= nil), tostring(targeting))
  if armed and targeting and not InCombatLockdown()
    and (SpellCanTargetItem == nil or SpellCanTargetItem()) then
    VS.Debug("alt+click: the spell is waiting for a target - applying it to bag %d slot %d", armed.bag, armed.slot)
    C_Container.UseContainerItem(armed.bag, armed.slot)
  end
end)

button:SetScript("OnEnter", function(self)
  if armed then
    showingTooltip = true
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetBagItem(armed.bag, armed.slot)
    GameTooltip:Show()
    showingTooltip = false
  end
end)

button:SetScript("OnLeave", function()
  GameTooltip:Hide()
  Disarm()
end)

-- Tooltip hook: arms the button while Alt is held, and adds a hint line -------------------------------

local function DisplayedLink(tooltip)
  if TooltipUtil and TooltipUtil.GetDisplayedItem then
    return select(2, TooltipUtil.GetDisplayedItem(tooltip))
  end
  return select(2, tooltip:GetItem())
end

local function OnItemTooltip(tooltip)
  if tooltip ~= GameTooltip then
    return
  end
  local owner = tooltip:GetOwner()
  if owner == button then
    if armed then
      tooltip:AddLine("Click to disenchant", unpack(HINT_COLOR))
    end
    return
  end
  local link = DisplayedLink(tooltip)
  local bag, slot, problem = Target(owner, link)
  if not bag then
    -- slot = why not; problems are traced once per item and reason (tooltips refresh several times a second)
    local trace = tostring(link) .. tostring(slot)
    if problem and trace ~= lastTrace then
      lastTrace = trace
      VS.Debug("alt+click: no hint for %s: %s", tostring(link), tostring(slot))
    end
    return
  end
  if IsAltKeyDown() and not InCombatLockdown() and not showingTooltip then
    Arm(owner, bag, slot)
  end
  tooltip:AddLine(InCombatLockdown() and "Alt+click to disenchant (not in combat)" or "Alt+click to disenchant",
    unpack(HINT_COLOR))
end

if TooltipDataProcessor and Enum.TooltipDataType then
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
    local ok, err = pcall(OnItemTooltip, tooltip)
    if not ok then
      VS.Debug("alt+click disenchant: %s", tostring(err))
    end
  end)
else
  GameTooltip:HookScript("OnTooltipSetItem", OnItemTooltip)
end

-- Events -------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("MODIFIER_STATE_CHANGED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("BAG_UPDATE_DELAYED")
VS.SafeRegister(events, "ADDON_ACTION_BLOCKED")
VS.SafeRegister(events, "ADDON_ACTION_FORBIDDEN")
events:SetScript("OnEvent", function(_, event, key, down)
  if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
    -- key = the addon, down = the function
    if key == VS.name and GetTime() - clickedAt < 2 then
      VS.Print("the game blocked %s, so this Alt+click didn't disenchant.", tostring(down))
    end
    return
  end
  if event == "MODIFIER_STATE_CHANGED" then
    if key ~= "LALT" and key ~= "RALT" then
      return
    end
    if down == 1 then
      -- Alt pressed while already pointing at an item
      if GameTooltip:IsShown() and not InCombatLockdown() then
        local owner = GameTooltip:GetOwner()
        local bag, slot = Target(owner, DisplayedLink(GameTooltip))
        if bag then
          Arm(owner, bag, slot)
        end
      end
    elseif not IsAltKeyDown() then
      Disarm()
    end
  else
    -- entering combat (the last moment the button may be hidden), or the bags changed (the slot may
    -- hold something else now)
    Disarm()
  end
end)
