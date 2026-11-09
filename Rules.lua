-- The attack table math. Pure functions only: no game calls, so the same code
-- runs for Forever and Classic Era with a different ruleset. Every formula and
-- its evidence is in docs/attack-table.md; the marks below match it.

local _, ns = ...
local Rules = {}
ns.Rules = Rules

-- What differs between the two games.
Rules.FOREVER = {
	name = "Forever",
	hitSuppression = false, -- gone in Forever (Measured, gunba CORE-001)
	dualWieldPenalty = 19, -- Forever's sheet code also uses 19 (Datamined)
	lowLevelAvoidance = true, -- dodge, parry and block shrink below level 10 too (Measured)
}
Rules.CLASSIC = {
	name = "Classic Era",
	hitSuppression = true, -- first 1% of hit wasted when defense is 11+ above skill (Blizzard)
	dualWieldPenalty = 19, -- Measured
	lowLevelAvoidance = false, -- the Classic sources give the level 10 rule for miss only
}

Rules.BOSS_AURA_CRIT = 1.8 -- extra crit reduction at +3 levels (Estimate; Measured in Forever)

-- Crit a class has with zero Agility (Simulator, wowsims base_stats.go).
-- It is not reduced by bosses (Measured, magey Crit aura suppression).
Rules.BASE_CRIT = {
	WARRIOR = 0, ROGUE = 0, HUNTER = 0,
	PALADIN = 0.7, DRUID = 0.9, SHAMAN = 1.7,
	WARLOCK = 2.0, PRIEST = 3.0, MAGE = 3.2,
}

-- Agility for 1% crit at levels 10, 20, ... 60, from Forever's client table
-- (Datamined, docs/stats-and-ratings.md). Used only when the game cannot say.
Rules.AGILITY_PER_CRIT = {
	WARRIOR = { 5.2, 7.8, 10.4, 13.2, 16.4, 20.0 },
	PALADIN = { 5.8, 8.1, 10.7, 13.5, 16.5, 19.8 },
	HUNTER = { 6.8, 15.2, 24.0, 33.0, 42.7, 52.9 },
	ROGUE = { 3.5, 8.1, 13.0, 18.0, 23.4, 29.0 },
	PRIEST = { 11.0, 12.5, 14.0, 15.5, 17.5, 20.0 },
	SHAMAN = { 7.3, 9.4, 11.5, 13.9, 16.7, 19.7 },
	MAGE = { 12.2, 13.3, 14.5, 16.1, 17.8, 19.5 },
	WARLOCK = { 7.7, 9.7, 12.0, 14.3, 17.0, 20.0 },
	DRUID = { 6.3, 8.8, 11.2, 13.9, 16.8, 20.0 },
}

function Rules.AgilityPerCrit(class, level)
	local t = Rules.AGILITY_PER_CRIT[class]
	if not t then return nil end
	local pos = math.min(math.max(level / 10, 1), 6)
	local lo = math.floor(pos)
	local hi = math.min(lo + 1, 6)
	return t[lo] + (t[hi] - t[lo]) * (pos - lo)
end

local function Clamp(v)
	return math.min(math.max(v, 0), 100)
end

-- Builds a list of {label, value} lines, skipping the ones passed as false.
local function Lines(...)
	local t = {}
	for i = 1, select("#", ...) do
		local line = select(i, ...)
		if line then t[#t + 1] = line end
	end
	return t
end

-- Damage lost per glancing blow, from the defense-skill gap (Measured, Classic).
function Rules.GlancingLoss(gap)
	local low = math.min(1.3 - 0.05 * gap, 0.91)
	local high = math.min(math.max(1.2 - 0.03 * gap, 0.2), 0.99)
	return (1 - (low + high) / 2) * 100
end

-- How much of the sheet crit a +3 boss takes away, and why.
-- s: sheetCrit, agilityCrit, baseCrit (percent). Returns the reduction and the
-- crit that counts as "aura" crit (talents, buffs, gear effects, crit rating).
function Rules.BossAuraReduction(s)
	local aura = math.max(s.sheetCrit - s.agilityCrit - s.baseCrit, 0)
	return math.min(Rules.BOSS_AURA_CRIT, aura), aura
end

-- The estimates for one table, before the player's edits.
-- c: rules, playerLevel, targetLevel, skill, hit, sheetCrit, agilityCrit,
--    baseCrit, dodgeReduction, dualWield (bool), special (bool), behind (bool),
--    ranged (bool): bows, guns, crossbows and thrown weapons
function Rules.Estimate(c)
	local defense = c.targetLevel * 5
	local gap = defense - c.skill
	local levelDiff = c.targetLevel - c.playerLevel
	local e, why = {}, {}

	-- Miss (Measured formulas; Blizzard for 8% at +3)
	local miss
	if gap > 10 then
		miss = 5 + gap * 0.2
	else
		miss = 5 + gap * 0.1
	end
	-- Below level 10 a monster's miss shrinks with its level; in Forever its
	-- dodge, parry and block do too (Measured in Forever's logs;
	-- docs/attack-table.md "Monsters below level 10").
	local missScale = c.targetLevel < 10 and c.targetLevel / 10 or 1
	miss = miss * missScale
	local lowScale = c.rules.lowLevelAvoidance and missScale or 1
	local base = miss
	local penalty = 0
	if c.dualWield and not c.special then
		penalty = c.rules.dualWieldPenalty
	end
	local hit = c.hit
	local suppressed = 0
	if c.rules.hitSuppression and gap > 10 then
		suppressed = math.min(hit, 1)
	end
	e.miss = Clamp(base + penalty - (hit - suppressed))
	why.miss = Lines(
		{ "Base miss (defense " .. defense .. " vs skill " .. c.skill .. ")", base },
		penalty > 0 and { "Two weapons, white swings", penalty } or false,
		{ "Your hit", -hit },
		suppressed > 0 and { "Hit wasted (Classic hit suppression)", suppressed } or false
	)

	-- Dodge (Measured), lowered by expertise in Forever. Against ranged attacks
	-- the sources disagree; most say monsters do not dodge them.
	local dodge = (5 + gap * 0.1) * lowScale
	if c.ranged then
		e.dodge = 0
		why.dodge = { { "No dodge against ranged attacks (most sources; one simulator disagrees)", 0 } }
	else
		e.dodge = Clamp(dodge - c.dodgeReduction)
		why.dodge = Lines(
			{ lowScale < 1 and "Base dodge (low-level monster)" or "Base dodge", dodge },
			c.dodgeReduction > 0 and { "Expertise", -c.dodgeReduction } or false
		)
	end

	-- Parry: 14% at +3 (Blizzard), about 5% at the same level (Measured).
	-- In between and below, the dodge formula is used (Not confirmed).
	if c.ranged then
		e.parry = 0
		why.parry = { { "Ranged attacks cannot be parried", 0 } }
	elseif c.behind then
		e.parry = 0
		why.parry = { { "Behind the target: no parry", 0 } }
	else
		local parry = levelDiff >= 3 and 14 or Clamp((5 + gap * 0.1) * lowScale)
		e.parry = parry
		why.parry = { { levelDiff >= 3 and "Boss-level parry"
			or (lowScale < 1 and "Base parry (low-level monster)" or "Base parry"), parry } }
	end

	-- Glancing: white swings only (Measured). Skill above level x 5 does not count.
	if c.ranged then
		e.glancing = 0
		why.glancing = { { "Ranged attacks never glance", 0 } }
	elseif c.special then
		e.glancing = 0
		why.glancing = { { "Abilities never glance", 0 } }
	else
		local capped = math.min(c.playerLevel * 5, c.skill)
		e.glancing = Clamp(10 + (defense - capped) * 2)
		why.glancing = { { "10% + 2% per point of defense above " .. capped, e.glancing } }
	end
	e.glancingLoss = Rules.GlancingLoss(gap)

	-- Block: never above 5% (Measured)
	if c.behind then
		e.block = 0
		why.block = { { "Behind the target: no block", 0 } }
	else
		e.block = Clamp(math.min(5, 5 + gap * 0.1) * lowScale)
		why.block = { { lowScale < 1 and "Base block (low-level monster)" or "Base block", e.block } }
	end

	-- Crit: -0.2% per point of defense above your capped skill, +0.04% per point below (Measured);
	-- plus the boss reduction of "aura" crit at +3 and above.
	local capped = math.min(c.playerLevel * 5, c.skill)
	local levelCrit
	if capped < defense then
		levelCrit = (capped - defense) * 0.2
	else
		levelCrit = (capped - defense) * 0.04
	end
	local bossCut, aura = 0, nil
	if levelDiff >= 3 then
		bossCut, aura = Rules.BossAuraReduction(c)
	end
	e.crit = Clamp(c.sheetCrit + levelCrit - bossCut)
	why.crit = Lines(
		{ "Sheet crit", c.sheetCrit },
		{ "Target level", levelCrit },
		levelDiff >= 3 and { string.format("Boss reduction (%.1f%% of your crit counts)", aura), -bossCut } or false
	)
	e.aura = aura

	return e, why
end

-- A monster's swing at you (the tank view). Formulas from Forever's character
-- sheet code, Camelot/PaperDollFrameStats.lua (Datamined: Blizzard's model,
-- not yet shown in game); the dodge, parry and block adjustment and the roll
-- order are the simulators' (Simulator). No measured test exists.
-- c: playerLevel, targetLevel, defense, dodge, parry, block (sheet values),
--    shieldBlock (bool), special (bool), behind (bool)
Rules.SHIELD_BLOCK = 75

function Rules.EstimateDefense(c)
	local skill = c.targetLevel * 5
	local gap = skill - c.defense
	local levelGap = skill - c.playerLevel * 5
	local e, why = {}, {}

	e.miss = Clamp(5 - gap * 0.04)
	why.miss = Lines({ "Base miss", 5 }, { "Your defense " .. c.defense .. " vs its skill " .. skill, -gap * 0.04 })

	-- Your sheet chances assume an attacker of your own level; a higher
	-- monster takes 0.04% per point of its skill above your level x 5.
	local adjust = levelGap * 0.04
	local function Avoid(key, sheet, label)
		if sheet <= 0 then
			e[key] = 0
			why[key] = { { "You cannot " .. label .. " (0% on your sheet)", 0 } }
			return
		end
		e[key] = Clamp(sheet - adjust)
		why[key] = Lines({ "Your " .. label .. " chance", sheet },
			adjust ~= 0 and { "Monster level", -adjust } or false)
	end
	Avoid("dodge", c.dodge, "dodge")
	if c.behind then
		e.parry, e.block = 0, 0
		why.parry = { { "Attacked from behind: no parry (Not confirmed)", 0 } }
		why.block = { { "Attacked from behind: no block (Not confirmed)", 0 } }
	else
		Avoid("parry", c.parry, "parry")
		local block = c.block
		if c.shieldBlock and block > 0 then block = block + Rules.SHIELD_BLOCK end
		Avoid("block", block, "block")
		if c.shieldBlock and c.block > 0 then
			table.insert(why.block, 2, { "Shield Block", Rules.SHIELD_BLOCK })
			why.block[1][2] = c.block
		end
	end

	e.crit = Clamp(5 + gap * 0.04)
	why.crit = Lines({ "Base crit", 5 }, { "Your defense " .. c.defense .. " vs its skill " .. skill, gap * 0.04 })

	-- Crushing blows: white swings only; defense above your level x 5 does
	-- not count; none unless its skill is 15 or more above your defense.
	if c.special then
		e.crushing = 0
		why.crushing = { { "Monster abilities never crush (Simulator)", 0 } }
	else
		local cg = skill - math.min(c.defense, c.playerLevel * 5)
		e.crushing = cg >= 15 and Clamp(cg * 2 - 15) or 0
		why.crushing = { { cg >= 15 and ("2% per point of its skill above your defense, minus 15% (gap " .. cg .. ")")
			or ("Needs a gap of 15; here " .. cg), e.crushing } }
	end
	return e, why
end

-- The results in roll order for each table; "hit" is always what is left.
Rules.ORDER_YOURS = { "miss", "dodge", "parry", "glancing", "block", "crit" }
Rules.ORDER_ON_YOU = { "miss", "dodge", "parry", "block", "crit", "crushing" }
Rules.ORDER_RANGED = { "miss", "dodge", "block", "crit" }
-- Results that come after "Room left"; the ones that can be pushed off.
Rules.LATE = { crit = true, crushing = true }

-- Lays the chances out on the 0-100 roll.
-- White swings: one roll, so each result takes what is left and anything that
-- does not fit is pushed off. Abilities: crit is a second roll on the attacks
-- that land, so it is a share of the rest and never pushed off (Not from the
-- source). Returns slices {key, value, from, to}, the room left before the
-- late results, and how much of each was pushed off.
function Rules.Build(v, order, special)
	local slices, used, room, pushed = {}, 0, nil, {}
	local function Add(key, value)
		slices[#slices + 1] = { key = key, value = value, from = used, to = used + value }
		used = used + value
	end
	for _, key in ipairs(order) do
		if Rules.LATE[key] and not room then room = 100 - used end
		if special and key == "crit" then
			Add(key, (100 - used) * v.crit / 100)
			pushed.crit = 0
		else
			local fit = math.min(v[key], 100 - used)
			pushed[key] = v[key] - fit
			Add(key, fit)
		end
	end
	Add("hit", 100 - used)
	local total = 0
	for _, p in pairs(pushed) do total = total + p end
	return slices, room or 0, pushed, total
end
