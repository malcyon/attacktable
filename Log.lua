-- Combat logging and stat snapshots. The game writes the combat log to Logs/;
-- this addon only turns logging on. At the start of each fight it notes the
-- character's stats and the target in AttackTableDB, which the game saves to
-- WTF/ at logout, so an agent can match them to the log by time and GUID.

local _, ns = ...
local Log = {}
ns.Log = Log

local MAX_SNAPSHOTS = 2000

local function Print(text)
	print("|cffffd100Attack Table:|r " .. text)
end

function Log.IsOn()
	local Call = ns.Stats.Call
	local on = Call(IsLoggingCombat)
	if on == nil then on = Call(LoggingCombat) end
	return on and true or false
end

-- Returns true if the game accepted the change.
function Log.Set(on)
	local ok = pcall(LoggingCombat, on)
	if not ok then
		Print("the game did not let the addon change combat logging; type /combatlog instead.")
		return false
	end
	Print(on and "combat logging is on (Logs/WoWCombatLog*.txt)." or "combat logging is off.")
	return true
end

function Log.OnLogin(db)
	if db.logAtLogin and not Log.IsOn() then
		Log.Set(true)
	end
end

-- The target as last seen readable; in combat Forever may hide it.
local target = {}

local function ReadTarget()
	local Call = ns.Stats.Call
	if not UnitExists("target") then return nil end
	local t = {
		guid = Call(UnitGUID, "target"),
		name = Call(UnitName, "target"),
		level = Call(UnitLevel, "target"),
		classification = Call(UnitClassification, "target"),
	}
	if not t.guid then return nil end
	return t
end

function Log.OnTargetChanged()
	target = ReadTarget() or {}
end

function Log.Snapshot(db)
	if not Log.IsOn() then return end
	local s = ns.Stats.Read()
	local t = ReadTarget() or target
	local snap = {
		time = time(),
		when = date("%m/%d %H:%M:%S"), -- the combat log's own time format
		character = UnitName("player") .. "-" .. GetRealmName(),
		game = ns.Stats.rules.name,
		build = select(2, GetBuildInfo()),
		statsFromBeforeCombat = s.stale,
		level = s.level, class = s.class, race = s.race,
		hit = s.hit, hitOff = s.hitOff,
		sheetCrit = s.sheetCrit, agility = s.agility,
		agilityCrit = s.agilityCrit, agilityCritSource = s.agilitySource,
		skillMain = s.skillMain, skillOff = s.skillOff, skillGuessed = s.skillGuessed,
		expertiseDodge = s.dodgeReduction, expertiseDodgeOff = s.dodgeReductionOff,
		dualWield = s.dualWield,
		mainhand = s.mainhand, offhand = s.offhand, ranged = s.ranged,
		defense = s.defense, dodge = s.dodge, parry = s.parry, block = s.block,
		target = {
			guid = t.guid, name = t.name, level = t.level,
			classification = t.classification,
		},
	}
	db.snapshots = db.snapshots or {}
	local list = db.snapshots
	list[#list + 1] = snap
	while #list > MAX_SNAPSHOTS do
		table.remove(list, 1)
	end
end
