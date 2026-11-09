-- Reads the character's own values through the normal addon functions.
-- Forever hides these from addons in combat ("secret values"); the last
-- values read before the fight are kept and marked stale.

local _, ns = ...
local Stats = {}
ns.Stats = Stats

local build = select(4, GetBuildInfo())
Stats.isForever = build >= 16000 and build < 20000
Stats.rules = Stats.isForever and ns.Rules.FOREVER or ns.Rules.CLASSIC

local SLOT_MAIN, SLOT_OFF, SLOT_RANGED = 16, 17, 18

-- Weapon subclass to skill line, as Forever's character sheet maps them
-- (Camelot/PaperDollFrameStats.lua). Classic Era reads skill another way.
local SKILL_BY_SUBCLASS = {
	[0] = 44, [1] = 172, [2] = 45, [3] = 46, [4] = 54, [5] = 160, [6] = 229,
	[7] = 43, [8] = 55, [10] = 136, [13] = 162, [15] = 173, [16] = 176,
	[18] = 226, [19] = 228,
}
local UNARMED_SKILL, FERAL_SKILL = 162, 3014
local WEAPON_CLASS = 2
-- Bows, guns, thrown, crossbows. Wands are left out: their bolts are spells.
local RANGED_SUBCLASS = { [2] = true, [3] = true, [16] = true, [18] = true }

local function Secret(v)
	return issecretvalue ~= nil and issecretvalue(v)
end

-- Calls a game function if it exists. Returns nothing if it is missing,
-- fails, or returns a hidden value.
local sawSecret = false
local function Call(f, ...)
	if type(f) ~= "function" then return end
	local r = { pcall(f, ...) }
	if not r[1] then return end
	for i = 2, #r do
		if Secret(r[i]) then
			sawSecret = true
			return
		end
	end
	return unpack(r, 2)
end
Stats.Call = Call

local function ItemInfo(itemID)
	local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	local _, _, _, _, _, classID, subclassID = Call(f, itemID)
	return classID, subclassID
end

-- Forever: the skill line of the weapon in one slot, then rank + modifier.
local function ForeverSkill(slot)
	local skillID
	local _, class = UnitClass("player")
	if class == "DRUID" and (Call(GetShapeshiftForm) or 0) ~= 0 then
		skillID = FERAL_SKILL
	else
		local itemID = Call(GetInventoryItemID, "player", slot)
		if not itemID then
			skillID = UNARMED_SKILL
		else
			local classID, subclassID = ItemInfo(itemID)
			if classID ~= WEAPON_CLASS then return end
			skillID = SKILL_BY_SUBCLASS[subclassID]
		end
	end
	if not skillID or not C_SkillInfo then return end
	local info = Call(C_SkillInfo.GetSkillLineInfoByID, skillID)
	if not info or Secret(info.rank) or Secret(info.modifier) then return end
	return info.rank + info.modifier, info.name
end

local function WeaponSkills(level)
	local main, off
	if Stats.isForever then
		main = ForeverSkill(SLOT_MAIN)
		off = ForeverSkill(SLOT_OFF)
	else
		local mb, mm, ob, om = Call(UnitAttackBothHands, "player")
		if mb then main = mb + (mm or 0) end
		if ob and ob > 0 then off = ob + (om or 0) end
	end
	-- The game could not say: assume the usual level x 5.
	local guessed = not main
	return main or level * 5, off or main or level * 5, guessed
end

-- Crit from Agility: from the game if it can say, otherwise from Forever's table.
-- Forever's GetCritChanceFromStat gives a fraction (0.05 for 5%; Blizzard's
-- character sheet multiplies it by 100). What Classic Era's functions give is
-- not documented, so a value is read as a fraction or a percent, whichever is
-- nearer the table; the two readings differ 100 times. A 0 with Agility above
-- 0 means the game can't say.
local function AgilityCrit(class, level, agility)
	local per = ns.Rules.AgilityPerCrit(class, level)
	local expected = per and agility / per
	local function Percent(v, fraction)
		if expected and expected > 0 then
			local asFraction = math.abs(math.log(v * 100 / expected))
			local asPercent = math.abs(math.log(v / expected))
			return asFraction < asPercent and v * 100 or v
		end
		return fraction and v * 100 or v
	end
	local v = Call(GetCritChanceFromStat, 2, agility)
	if v and v > 0 then return Percent(v, true), "game" end
	v = Call(GetCritChanceFromAgility, "player")
	if v and v > 0 then return Percent(v, false), "game" end
	if expected then return expected, "table" end
	return 0, "none"
end

-- Hit from gear's hit rating, which Forever's character sheet adds to the
-- hit modifier (Camelot/PaperDollFrameStats.lua). Classic Era has no ratings.
local function RatingHit(rating)
	if not Stats.isForever or not rating then return 0 end
	return Call(GetCombatRatingBonus, rating) or 0
end

-- Forever's own glancing chance and damage lost, in percent, for one weapon
-- skill against one defense; Blizzard's skills window reads the same two
-- functions (Camelot/SkillsFrame.lua). The game hides them in combat, so the
-- last values read are kept. Returns nothing when the game can't say.
local glancing = {}
function Stats.GameGlancing(skill, defense)
	if not Stats.isForever then return end
	local key = skill .. ":" .. defense
	local chance = Call(GetGlancingBlowChance, skill, defense)
	local loss = Call(GetGlancingBlowPenalty, skill, defense)
	if chance and loss then glancing[key] = { chance * 100, loss * 100 } end
	local g = glancing[key]
	if g then return g[1], g[2] end
end

local last

-- Returns the current values, or the last readable ones marked stale.
function Stats.Read()
	local s = {}
	s.level = UnitLevel("player")
	s.class = select(2, UnitClass("player"))
	s.race = select(2, UnitRace("player"))

	sawSecret = false
	local hidden = Stats.isForever and C_Secrets and Call(C_Secrets.ShouldUnitStatsBeSecret)
	s.sheetCrit = Call(GetCritChance)
	s.hit = Call(GetHitModifier)
	local meleeRating = RatingHit(CR_HIT_MELEE)
	local _, agility = Call(UnitStat, "player", 2)
	if hidden or sawSecret then
		if last then
			last.stale = true
			return last
		end
		-- Nothing read yet: show the table with empty stats rather than nothing.
		s.stale = true
	end
	s.sheetCrit, agility = s.sheetCrit or 0, agility or 0
	s.hit = (s.hit or 0) + meleeRating
	local hitOff = Call(GetOffhandHitModifier)
	s.hitOff = hitOff and (hitOff + meleeRating) or s.hit
	s.agility = agility
	s.agilityCrit, s.agilitySource = AgilityCrit(s.class, s.level, agility)
	s.baseCrit = ns.Rules.BASE_CRIT[s.class] or 0
	s.skillMain, s.skillOff, s.skillGuessed = WeaponSkills(s.level)

	local mainExp, offExp, rangedExp = Call(GetExpertisePercent)
	s.dodgeReduction = mainExp or 0
	s.dodgeReductionOff = offExp or s.dodgeReduction
	s.dodgeReductionRanged = rangedExp or 0

	-- The ranged slot: only bows, guns, crossbows and thrown weapons count.
	local rangedID = Call(GetInventoryItemID, "player", SLOT_RANGED)
	local rangedClass, rangedSub = nil, nil
	if rangedID then rangedClass, rangedSub = ItemInfo(rangedID) end
	s.hasRanged = rangedClass == WEAPON_CLASS and RANGED_SUBCLASS[rangedSub] or false
	s.rangedCrit = Call(GetRangedCritChance) or s.sheetCrit
	local hitRanged = Call(GetRangedHitModifier)
	s.hitRanged = hitRanged and (hitRanged + RatingHit(CR_HIT_RANGED)) or s.hit
	s.skillRanged, s.skillRangedGuessed = s.level * 5, true
	if s.hasRanged then
		local skill
		if Stats.isForever then
			skill = ForeverSkill(SLOT_RANGED)
		else
			local base, mod = Call(UnitRangedAttack, "player")
			if base then skill = base + (mod or 0) end
		end
		if skill then s.skillRanged, s.skillRangedGuessed = skill, false end
	end

	s.dualWield = (Call(IsDualWielding) and true) or false
	s.mainhand = Call(GetInventoryItemID, "player", SLOT_MAIN)
	s.offhand = Call(GetInventoryItemID, "player", SLOT_OFF)
	s.ranged = Call(GetInventoryItemID, "player", SLOT_RANGED)

	-- Defensive values, saved in snapshots for the tank view later.
	local defBase, defMod = Call(UnitDefenseSkill, "player")
	if not defBase then defBase, defMod = Call(UnitDefense, "player") end
	s.defense = defBase and (defBase + (defMod or 0)) or nil
	s.dodge = Call(GetDodgeChance)
	s.parry = Call(GetParryChance)
	s.block = Call(GetBlockChance)

	s.stale = s.stale or false
	if not s.stale then last = s end
	return s
end

function Stats.HandName(slot)
	local itemID = Call(GetInventoryItemID, "player", slot)
	if not itemID then return "Unarmed" end
	local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	local _, _, subType = Call(f, itemID)
	return subType or "Weapon"
end

Stats.SLOT_MAIN, Stats.SLOT_OFF, Stats.SLOT_RANGED = SLOT_MAIN, SLOT_OFF, SLOT_RANGED
