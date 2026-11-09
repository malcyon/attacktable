-- The window: one colored bar in roll order, and the same numbers as a table
-- under it. /attacktable opens it. The plan is in PLAN.md.

local _, ns = ...
local Rules, Stats, Log = ns.Rules, ns.Stats, ns.Log

-- Parts of the plan that are not built yet stay out of the window until their
-- flag is turned on.
local FEATURES = {
	ranged = true, -- the Ranged tab
	attacksOnYou = true, -- "Attacks on you", the tank view
}

local NAMES = {
	miss = "Miss", dodge = "Dodge", parry = "Parry", glancing = "Glancing",
	block = "Block", crit = "Crit", crushing = "Crushing", hit = "Hit",
}
local COLORS = {
	miss = { 0.50, 0.50, 0.50 }, dodge = { 0.90, 0.78, 0.16 },
	parry = { 0.92, 0.51, 0.12 }, glancing = { 0.47, 0.75, 0.92 },
	block = { 0.47, 0.53, 0.59 }, crit = { 0.84, 0.16, 0.16 },
	crushing = { 0.58, 0.30, 0.80 }, hit = { 0.27, 0.71, 0.27 },
}
-- Every row the window can show; each view uses some of them.
local ALL_KEYS = { "miss", "dodge", "parry", "glancing", "block", "crit", "crushing", "hit" }

local GOLD = { 1, 0.82, 0 }
local EDITED = { 0.55, 0.8, 1 }

-- What moves each result, and how sure the numbers are (docs/attack-table.md
-- for your attacks; PLAN.md "Attacks on you" for the monster's).
local NOTES = {
	yours = {
		miss = { "Changes with: your hit, weapon skill, target level, two weapons (white swings)." },
		dodge = { "Changes with: weapon skill, target level, expertise. Happens from behind too." },
		parry = { "Changes with: target level. Only from the front." },
		glancing = { "White swings only. Changes with: target level. Weapon skill above level x 5 changes the damage lost, not the chance." },
		block = { "Changes with: target level. Only from the front; never above 5%." },
		crit = { "Changes with: your crit, target level; at +3 the boss reduction." },
		hit = { "Whatever is left of the roll." },
	},
	ranged = {
		miss = { "Changes with: your hit, ranged weapon skill, target level." },
		dodge = { "Monsters do not dodge ranged attacks. Edit it if you see dodges." },
		block = { "Changes with: target level. Only from the front; never above 5%." },
		crit = { "Changes with: your ranged crit, target level; at +3 the boss reduction." },
		hit = { "Whatever is left of the roll." },
	},
	onYou = {
		miss = { "Changes with: your defense, the monster's level." },
		dodge = { "Your dodge chance from the character sheet, lowered for a higher monster." },
		parry = { "Your parry chance from the character sheet, lowered for a higher monster. Only from the front." },
		block = { "Your block chance from the character sheet (needs a shield), lowered for a higher monster. Only from the front." },
		crit = { "Changes with: your defense, the monster's level. In Forever, none while the monster's skill is under 10 above your defense." },
		crushing = { "150% damage. Only from monsters 3+ levels above you; defense cannot lower it, only push it off the end." },
		hit = { "Whatever is left of the roll." },
	},
}

local db
local frame, bar, rows = nil, {}, {}
local state = {} -- the latest estimate, values and slices

local function Pct(v)
	return string.format("%.1f%%", v)
end

local function Signed(v)
	return string.format("%+.1f%%", v)
end

local function OnYou()
	return FEATURES.attacksOnYou and db.view == "onYou"
end

-- The Ranged tab, on "Your attacks" only, and only with a ranged weapon.
local function Ranged()
	return FEATURES.ranged and not OnYou() and db.tab == "ranged" and state.hasRanged
end

-- Which table is showing: "yours", "ranged" or "onYou".
local function Mode()
	if OnYou() then return "onYou" end
	return Ranged() and "ranged" or "yours"
end

local function Edits()
	return db.edits[Mode()]
end

-- A flat button that looks selected (dark red, gold text) or not.
local function MakeButton(parent, text, onClick)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	b:SetBackdropBorderColor(0.43, 0.39, 0.31)
	b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	b.label:SetPoint("CENTER")
	b.label:SetText(text)
	b:SetSize(b.label:GetStringWidth() + 18, 22)
	b:SetScript("OnClick", onClick)
	function b:SetSelected(on)
		if on then
			self:SetBackdropColor(0.35, 0.08, 0.08, 1)
			self.label:SetTextColor(unpack(GOLD))
		else
			self:SetBackdropColor(0.12, 0.12, 0.14, 1)
			self.label:SetTextColor(0.6, 0.6, 0.6)
		end
	end
	b:SetSelected(false)
	return b
end

local function Tooltip(owner, build)
	owner:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		build(GameTooltip)
		GameTooltip:Show()
	end)
	owner:SetScript("OnLeave", GameTooltip_Hide)
end

local function PushedLines(tip)
	for _, key in ipairs({ "crushing", "crit" }) do
		local p = state.pushed[key]
		if p and p > 0 then
			tip:AddLine(string.format("%s of %s does not fit and is pushed off the end.", Pct(p), NAMES[key]:lower()), 0.84, 0.16, 0.16, true)
		end
	end
end

-- The tooltip for one result, shared by its bar slice and its table row.
local function ResultTooltip(tip, key)
	local slice = state.slices and state.slices[key]
	if not slice then return end
	local c = COLORS[key]
	tip:AddLine(NAMES[key], c[1], c[2], c[3])
	tip:AddDoubleLine("Chance", Pct(slice.value), 1, 1, 1, 1, 1, 1)
	if slice.value > 0 then
		tip:AddDoubleLine("Roll", string.format("%.1f - %.1f", slice.from, slice.to), 1, 1, 1, 1, 1, 1)
	end
	local why = state.why[key]
	if why then
		tip:AddLine(" ")
		for _, line in ipairs(why) do
			tip:AddDoubleLine(line[1], (line == why[1]) and Pct(line[2]) or Signed(line[2]), 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
		end
	end
	if key == "glancing" and not db.special then
		tip:AddLine(string.format("Each glancing blow loses about %.0f%% of its damage.", state.estimate.glancingLoss), 0.8, 0.8, 0.8, true)
	end
	if state.pushed[key] and state.pushed[key] > 0 then
		tip:AddLine(string.format("%s does not fit and is pushed off the end.", Pct(state.pushed[key])), 0.84, 0.16, 0.16, true)
	end
	if key == "crit" then
		if Ranged() then
			tip:AddLine("Shots roll crit a second time on the shots that land, so crit is never pushed off.", 0.8, 0.8, 0.8, true)
		elseif db.special then
			tip:AddLine("Abilities roll crit a second time on the attacks that land, so crit is never pushed off.", 0.8, 0.8, 0.8, true)
		end
		if not OnYou() and state.stats.agilitySource == "table" then
			tip:AddLine("Crit from Agility worked out from Forever's Agility table; the game did not give it.", 0.6, 0.6, 0.6, true)
		end
	end
	if Edits()[key] then
		tip:AddLine(string.format("Edited by you; the estimate is %s.", Pct(state.estimate[key])), EDITED[1], EDITED[2], EDITED[3], true)
	end
	local note = NOTES[Mode()][key]
	tip:AddLine(" ")
	tip:AddLine(note[1], 1, 1, 1, true)
end

local function TargetLevel(s)
	return math.min(math.max(s.level + db.levelOffset, 1), 63)
end

-- Works out the table from the current stats, settings and edits.
local function Compute()
	local s = Stats.Read()
	state.hasRanged = s.hasRanged
	local estimate, why, order
	local special = db.special
	if OnYou() then
		order = Rules.ORDER_ON_YOU
		estimate, why = Rules.EstimateDefense({
			rules = Stats.rules,
			playerLevel = s.level,
			targetLevel = TargetLevel(s),
			defense = s.defense or s.level * 5,
			dodge = s.dodge or 0,
			parry = s.parry or 0,
			block = s.block or 0,
			shieldBlock = db.shieldBlock and s.class == "WARRIOR",
			special = db.special,
			behind = db.behind,
		})
	elseif Ranged() then
		order = Rules.ORDER_RANGED
		special = true -- crit is a second roll on every ranged attack
		estimate, why = Rules.Estimate({
			rules = Stats.rules,
			playerLevel = s.level,
			targetLevel = TargetLevel(s),
			skill = s.skillRanged,
			hit = s.hitRanged,
			sheetCrit = s.rangedCrit,
			agilityCrit = s.agilityCrit,
			baseCrit = s.baseCrit,
			dodgeReduction = s.dodgeReductionRanged,
			dualWield = false,
			special = true,
			behind = db.behind,
			ranged = true,
		})
	else
		order = Rules.ORDER_YOURS
		local off = s.dualWield and db.hand == "off"
		estimate, why = Rules.Estimate({
			rules = Stats.rules,
			playerLevel = s.level,
			targetLevel = TargetLevel(s),
			skill = off and s.skillOff or s.skillMain,
			hit = off and s.hitOff or s.hit,
			sheetCrit = s.sheetCrit,
			agilityCrit = s.agilityCrit,
			baseCrit = s.baseCrit,
			dodgeReduction = off and s.dodgeReductionOff or s.dodgeReduction,
			dualWield = s.dualWield,
			special = db.special,
			behind = db.behind,
		})
	end
	local edits, values = Edits(), {}
	for _, key in ipairs(order) do
		values[key] = edits[key] or estimate[key]
	end
	local list, room, pushed, pushedTotal = Rules.Build(values, order, special)
	local slices = {}
	for _, sl in ipairs(list) do slices[sl.key] = sl end
	state.stats, state.estimate, state.why, state.order = s, estimate, why, order
	state.list, state.slices, state.room = list, slices, room
	state.pushed, state.pushedTotal = pushed, pushedTotal
end

local BAR_WIDTH, BAR_HEIGHT = 440, 30

local function DrawBar()
	-- The bar is 0-100; whatever is pushed off is drawn past the end, so the
	-- scale shrinks to fit it.
	local scale = BAR_WIDTH / (100 + state.pushedTotal)
	for _, key in ipairs(ALL_KEYS) do
		local seg, sl = bar.segments[key], state.slices[key]
		local w = sl and sl.value * scale or 0
		if w >= 0.5 then
			seg:SetPoint("LEFT", bar, "LEFT", sl.from * scale, 0)
			seg:SetWidth(w)
			seg:Show()
		else
			seg:Hide()
		end
	end
	bar.edge:SetWidth(100 * scale)
	bar.end100:SetPoint("TOP", bar, "BOTTOMLEFT", 100 * scale, -2)
	local pw = state.pushedTotal * scale
	if pw >= 0.5 then
		bar.pushed:SetPoint("LEFT", bar, "LEFT", 100 * scale + 1, 0)
		bar.pushed:SetWidth(pw)
		for i, stripe in ipairs(bar.stripes) do
			stripe:SetShown((i - 1) * 6 < pw - 3)
		end
		bar.pushed:Show()
	else
		bar.pushed:Hide()
	end
end

local ROW_HEIGHT = 24

-- Places the rows for the current view: its results in roll order, "Room
-- left" before the late results, then what was pushed off, the note and the
-- logging checkbox.
local function Layout()
	local y = frame.tableTop
	local roomPlaced = false
	local shown = {}
	for _, key in ipairs(state.order) do shown[key] = true end
	shown.hit = true
	for _, key in ipairs(ALL_KEYS) do
		local row = rows[key]
		if shown[key] then
			if Rules.LATE[key] and not roomPlaced then
				frame.lines[2]:SetPoint("TOPLEFT", 14, y)
				frame.lines[2]:SetPoint("TOPRIGHT", -14, y)
				frame.roomLabel:SetPoint("TOPLEFT", 34, y - 6)
				frame.room:SetPoint("TOPLEFT", 150, y - 6)
				y = y - 30
				roomPlaced = true
			end
			row:SetPoint("TOPLEFT", 14, y)
			row:Show()
			y = y - ROW_HEIGHT
		else
			row:Hide()
		end
	end
	frame.lines[3]:SetPoint("TOPLEFT", 14, y)
	frame.lines[3]:SetPoint("TOPRIGHT", -14, y)
	frame.pushedLabel:SetPoint("TOPLEFT", 34, y - 8)
	frame.pushedValue:SetPoint("TOPLEFT", 150, y - 8)
	y = y - 38
	frame.footnote:SetPoint("TOPLEFT", 14, y)
	y = y - 26
	frame.logging:SetPoint("TOPLEFT", 10, y)
	frame:SetHeight(-y + 40)
end

local function DrawRows()
	local edits = Edits()
	for _, key in ipairs(ALL_KEYS) do
		local row, sl = rows[key], state.slices[key]
		if sl then
			local edited = edits[key] ~= nil
			if not row.box:HasFocus() then
				row.box:SetText(Pct(sl.value))
			end
			local c = edited and EDITED or ((sl.value > 0) and { 1, 1, 1 } or { 0.5, 0.5, 0.5 })
			row.box:SetTextColor(c[1], c[2], c[3])
			row.range:SetText(sl.value > 0 and string.format("%.1f - %.1f", sl.from, sl.to) or "-")
			local g = sl.value > 0 and 1 or 0.5
			row.range:SetTextColor(g, g, g)
			if row.reset then row.reset:SetShown(edited) end
			if row.edit then row.edit:SetShown(not edited) end
		end
	end
	frame.room:SetText(Pct(state.room))

	local red = state.pushedTotal > 0
	if OnYou() then
		frame.pushedLabel:SetText("Pushed off")
		local parts = {}
		for _, key in ipairs({ "crushing", "crit" }) do
			if (state.pushed[key] or 0) > 0 then
				parts[#parts + 1] = NAMES[key] .. " " .. Pct(state.pushed[key])
			end
		end
		frame.pushedValue:SetText(#parts > 0 and table.concat(parts, ", ") or Pct(0))
	else
		frame.pushedLabel:SetText("Crit pushed off")
		frame.pushedValue:SetText(Pct(state.pushed.crit or 0))
	end
	local r, g = red and 0.84 or 0.5, red and 0.16 or 0.5
	frame.pushedLabel:SetTextColor(r, g, g)
	frame.pushedValue:SetTextColor(r, g, g)
end

local function YourFootnote()
	local s, e = state.stats, state.estimate
	if Edits().crit then
		return "Crit edited by you."
	elseif Ranged() then
		local parts = { "Ranged crit " .. Pct(s.rangedCrit) }
		for i = 2, #state.why.crit do
			local line = state.why.crit[i]
			if line[2] ~= 0 then parts[#parts + 1] = string.format("%s %s", Signed(line[2]), i == 2 and "(level)" or "(boss)") end
		end
		return table.concat(parts, " ") .. " = " .. Pct(e.crit) .. " of the shots that land; never pushed off."
	elseif (state.pushed.crit or 0) > 0 then
		return string.format("Crit wants %s; only %s fits, %s is pushed off.", Pct(e.crit), Pct(state.slices.crit.value), Pct(state.pushed.crit))
	end
	local parts = { "Crit " .. Pct(s.sheetCrit) }
	for i = 2, #state.why.crit do
		local line = state.why.crit[i]
		if line[2] ~= 0 then parts[#parts + 1] = string.format("%s %s", Signed(line[2]), i == 2 and "(level)" or "(boss)") end
	end
	return table.concat(parts, " ") .. " = " .. Pct(e.crit)
end

local function OnYouFootnote()
	local crushing = state.estimate.crushing
	if db.special then
		return "Monster abilities never crush, and their crit is a second roll."
	elseif crushing <= 0 and not Edits().crushing then
		return "No crushing blows: the monster is less than 3 levels above you."
	elseif state.slices.crushing.value <= 0 then
		return "Uncrushable: crushing blows are pushed off the end."
	end
	return string.format("Crushing blows land %s of the time; %s more miss, dodge, parry or block pushes them off.",
		Pct(state.slices.crushing.value), Pct(state.slices.crushing.value))
end

local function DrawHeader()
	local s = state.stats
	local text
	if OnYou() then
		text = string.format("Defense %d%s, dodge %s, parry %s, block %s", s.defense or s.level * 5,
			s.defense and "" or "?", Pct(s.dodge or 0), Pct(s.parry or 0), Pct(s.block or 0))
	elseif Ranged() then
		text = string.format("%s %d%s, %s hit, %s ranged crit", Stats.HandName(Stats.SLOT_RANGED), s.skillRanged,
			s.skillRangedGuessed and "?" or "", Pct(s.hitRanged), Pct(s.rangedCrit))
	else
		local off = s.dualWield and db.hand == "off"
		local slot = off and Stats.SLOT_OFF or Stats.SLOT_MAIN
		text = string.format("%s %d%s, %s hit, %s sheet crit", Stats.HandName(slot), off and s.skillOff or s.skillMain,
			s.skillGuessed and "?" or "", Pct(off and s.hitOff or s.hit), Pct(s.sheetCrit))
	end
	if s.stale then text = text .. "  |cffff8800(values from before combat)|r" end
	frame.subtitle:SetText(text)

	local level = TargetLevel(s)
	frame.level:SetText(level)
	frame.levelGap:SetText(string.format("(%+d)", level - s.level))

	if frame.yours then
		frame.yours:SetSelected(not OnYou())
		frame.onYou:SetSelected(OnYou())
	end
	-- Melee/Ranged tabs only on "Your attacks" with a ranged weapon; White and
	-- Special move left when the tabs are hidden, and hide on Ranged, where
	-- every attack rolls crit the same way.
	local tabs = FEATURES.ranged and not OnYou() and s.hasRanged
	frame.melee:SetShown(tabs)
	frame.ranged:SetShown(tabs)
	frame.melee:SetSelected(not Ranged())
	frame.ranged:SetSelected(Ranged())
	frame.white:ClearAllPoints()
	if tabs then
		frame.white:SetPoint("LEFT", frame.ranged, "RIGHT", 20, 0)
	else
		frame.white:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, frame.tabRowY)
	end
	frame.white:SetShown(not Ranged())
	frame.special:SetShown(not Ranged())
	frame.white:SetSelected(not db.special)
	frame.special:SetSelected(db.special)
	frame.front:SetSelected(not db.behind)
	frame.behind:SetSelected(db.behind)
	local hands = s.dualWield and not OnYou() and not Ranged()
	frame.main:SetSelected(db.hand ~= "off")
	frame.off:SetSelected(db.hand == "off")
	frame.main:SetShown(hands)
	frame.off:SetShown(hands)
	local shieldBlock = OnYou() and s.class == "WARRIOR"
	frame.shieldBlock:SetShown(shieldBlock)
	frame.shieldBlockLabel:SetShown(shieldBlock)
	frame.shieldBlock:SetChecked(db.shieldBlock)

	frame.footnote:SetText(OnYou() and OnYouFootnote() or YourFootnote())
	frame.logging:SetChecked(db.logAtLogin)
end

local pending = false
local function Refresh()
	if not frame or not frame:IsShown() then return end
	Compute()
	Layout()
	DrawHeader()
	DrawBar()
	DrawRows()
end

-- Many events fire together (gear swap, buffs); redraw once.
local function QueueRefresh()
	if pending then return end
	pending = true
	C_Timer.After(0.1, function()
		pending = false
		Refresh()
	end)
end
ns.QueueRefresh = QueueRefresh

local function SetEdit(key, text)
	local v = tonumber((text or ""):match("[%d%.]+"))
	if v then
		Edits()[key] = math.min(math.max(v, 0), 100)
	end
	Refresh()
end

local function Build()
	frame = CreateFrame("Frame", "AttackTableFrame", UIParent, "BackdropTemplate")
	frame:Hide() -- new frames start shown; Toggle() shows it
	frame:SetSize(480, 600)
	frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
	frame:SetBackdropColor(0.07, 0.07, 0.09, 0.95)
	frame:SetBackdropBorderColor(0.43, 0.39, 0.31)
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, _, x, y = self:GetPoint()
		db.position = { point, x, y }
	end)
	if db.position then
		frame:SetPoint(db.position[1], UIParent, db.position[1], db.position[2], db.position[3])
	else
		frame:SetPoint("CENTER")
	end
	frame:SetScript("OnShow", Refresh)
	table.insert(UISpecialFrames, "AttackTableFrame") -- Escape closes it

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetText("Attack Table")
	frame.subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.subtitle:SetPoint("TOPLEFT", 14, -36)

	-- Whose table, and which tab. Each choice appears only once its feature is
	-- built; with a single choice there is nothing to pick, so no buttons.
	local y = -58
	if FEATURES.attacksOnYou then
		frame.yours = MakeButton(frame, "Your attacks", function() db.view = "yours"; Refresh() end)
		frame.yours:SetPoint("TOPLEFT", 14, y)
		Tooltip(frame.yours, function(tip) tip:AddLine("You attacking a monster.", 1, 1, 1) end)
		frame.onYou = MakeButton(frame, "Attacks on you", function() db.view = "onYou"; Refresh() end)
		frame.onYou:SetPoint("LEFT", frame.yours, "RIGHT", 6, 0)
		Tooltip(frame.onYou, function(tip)
			tip:AddLine("A monster attacking you: the tank's view.", 1, 1, 1)
			tip:AddLine("Enough miss, dodge, parry and block pushes crushing blows, then crits, off the end.", 0.8, 0.8, 0.8, true)
		end)
		y = y - 30
	end
	-- Melee/Ranged; DrawHeader shows them only when there is a choice.
	frame.tabRowY = y
	frame.melee = MakeButton(frame, "Melee", function() db.tab = "melee"; Refresh() end)
	frame.melee:SetPoint("TOPLEFT", 14, y)
	frame.ranged = MakeButton(frame, "Ranged", function() db.tab = "ranged"; Refresh() end)
	frame.ranged:SetPoint("LEFT", frame.melee, "RIGHT", 6, 0)
	Tooltip(frame.ranged, function(tip)
		tip:AddLine("Ranged: your bow, gun, crossbow or thrown weapon", 1, 1, 1)
		tip:AddLine("No dodge, parry or glancing; block only from the front; crit is a second roll, so it is never pushed off.", 0.8, 0.8, 0.8, true)
	end)

	frame.white = MakeButton(frame, "White", function() db.special = false; Refresh() end)
	Tooltip(frame.white, function(tip)
		if OnYou() then
			tip:AddLine("White: the monster's automatic swings", 1, 1, 1)
			tip:AddLine("One roll: they can crush, and crushing blows and crits can be pushed off the end.", 0.8, 0.8, 0.8, true)
		else
			tip:AddLine("White: your automatic swings", 1, 1, 1)
			tip:AddLine("One roll: they can glance, two weapons add 19% miss, and crit can be pushed off the end.", 0.8, 0.8, 0.8, true)
		end
	end)
	frame.special = MakeButton(frame, "Special", function() db.special = true; Refresh() end)
	frame.special:SetPoint("LEFT", frame.white, "RIGHT", 6, 0)
	Tooltip(frame.special, function(tip)
		if OnYou() then
			tip:AddLine("Special: the monster's abilities", 1, 1, 1)
			tip:AddLine("They never crush, and crit is a second roll on the hits.", 0.8, 0.8, 0.8, true)
			return
		end
		tip:AddLine("Special: a typical weapon ability", 1, 1, 1)
		tip:AddLine("Mortal Strike, Bloodthirst, Heroic Strike, Sinister Strike, Stormstrike. No glancing, no two-weapon penalty; crit is a second roll on the hits.", 0.8, 0.8, 0.8, true)
		tip:AddLine(" ")
		tip:AddLine("Exceptions:", 1, 0.82, 0)
		tip:AddLine("Some abilities cannot be dodged, parried or blocked (Overpower in Classic).", 0.8, 0.8, 0.8, true)
		tip:AddLine("Shocks, Flametongue and Judgement are spells: not shown here.", 0.8, 0.8, 0.8, true)
		tip:AddLine("Windfury and Sword Specialization swings are white swings.", 0.8, 0.8, 0.8, true)
		tip:AddLine("Shots belong on the Ranged tab.", 0.8, 0.8, 0.8, true)
	end)

	y = y - 30
	local levelLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	levelLabel:SetPoint("TOPLEFT", 14, y - 5)
	levelLabel:SetText("Target level")
	local minus = MakeButton(frame, "-", function()
		db.levelOffset = math.max(db.levelOffset - (IsShiftKeyDown() and 5 or 1), 1 - UnitLevel("player"))
		Refresh()
	end)
	minus:SetPoint("TOPLEFT", 110, y)
	minus:SetWidth(24)
	frame.level = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.level:SetPoint("LEFT", minus, "RIGHT", 6, 0)
	frame.level:SetWidth(24)
	local plus = MakeButton(frame, "+", function()
		db.levelOffset = math.min(db.levelOffset + (IsShiftKeyDown() and 5 or 1), 63 - UnitLevel("player"))
		Refresh()
	end)
	plus:SetPoint("LEFT", frame.level, "RIGHT", 6, 0)
	plus:SetWidth(24)
	frame.levelGap = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.levelGap:SetPoint("LEFT", plus, "RIGHT", 8, 0)
	for _, b in ipairs({ minus, plus }) do
		Tooltip(b, function(tip) tip:AddLine("Shift-click to move 5 levels.", 1, 1, 1) end)
	end

	y = y - 30
	local posLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	posLabel:SetPoint("TOPLEFT", 14, y - 5)
	posLabel:SetText("Position")
	frame.front = MakeButton(frame, "Front", function() db.behind = false; Refresh() end)
	frame.front:SetPoint("TOPLEFT", 110, y)
	frame.behind = MakeButton(frame, "Behind", function() db.behind = true; Refresh() end)
	frame.behind:SetPoint("LEFT", frame.front, "RIGHT", 6, 0)
	Tooltip(frame.behind, function(tip)
		if OnYou() then
			tip:AddLine("The monster attacks your back: you can still dodge, but not parry or block.", 1, 1, 1, true)
		else
			tip:AddLine("Monsters cannot parry or block from behind; they still dodge.", 1, 1, 1, true)
			tip:AddLine("Forever beta bug: very close, they sometimes still parry and block.", 0.6, 0.6, 0.6, true)
		end
	end)
	frame.main = MakeButton(frame, "Main hand", function() db.hand = "main"; Refresh() end)
	frame.main:SetPoint("LEFT", frame.behind, "RIGHT", 20, 0)
	frame.off = MakeButton(frame, "Off hand", function() db.hand = "off"; Refresh() end)
	frame.off:SetPoint("LEFT", frame.main, "RIGHT", 6, 0)
	frame.shieldBlock = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	frame.shieldBlock:SetPoint("LEFT", frame.behind, "RIGHT", 16, 0)
	frame.shieldBlock:SetSize(24, 24)
	frame.shieldBlockLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.shieldBlockLabel:SetPoint("LEFT", frame.shieldBlock, "RIGHT", 2, 0)
	frame.shieldBlockLabel:SetText("Shield Block")
	frame.shieldBlock:SetScript("OnClick", function(self)
		db.shieldBlock = self:GetChecked() and true or false
		Refresh()
	end)
	Tooltip(frame.shieldBlock, function(tip)
		tip:AddLine("Shield Block active", 1, 1, 1)
		tip:AddLine("Adds 75% block, to show what Shield Block does to the table. In Classic Era the game also shows it live while the buff is up; Forever hides your stats in combat.", 0.8, 0.8, 0.8, true)
	end)

	-- The bar.
	y = y - 44
	bar = CreateFrame("Frame", nil, frame)
	bar:SetPoint("TOPLEFT", 14, y)
	bar:SetSize(BAR_WIDTH, BAR_HEIGHT)
	bar.segments = {}
	for _, key in ipairs(ALL_KEYS) do
		local seg = CreateFrame("Frame", nil, bar)
		seg:SetHeight(BAR_HEIGHT)
		local tex = seg:CreateTexture(nil, "ARTWORK")
		tex:SetAllPoints()
		tex:SetColorTexture(unpack(COLORS[key]))
		Tooltip(seg, function(tip) ResultTooltip(tip, key) end)
		bar.segments[key] = seg
	end
	-- White outline of the 0-100 table.
	bar.edge = CreateFrame("Frame", nil, bar, "BackdropTemplate")
	bar.edge:SetPoint("TOPLEFT")
	bar.edge:SetHeight(BAR_HEIGHT)
	bar.edge:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	bar.edge:SetBackdropBorderColor(0.9, 0.9, 0.9)
	bar.edge:SetFrameLevel(bar:GetFrameLevel() + 5)
	bar.edge:EnableMouse(false)
	-- Pushed off: red stripes past the end.
	bar.pushed = CreateFrame("Frame", nil, bar)
	bar.pushed:SetHeight(BAR_HEIGHT)
	local dark = bar.pushed:CreateTexture(nil, "BACKGROUND")
	dark:SetAllPoints()
	dark:SetColorTexture(0.24, 0.06, 0.06)
	bar.stripes = {}
	for i = 1, 80 do
		local stripe = bar.pushed:CreateTexture(nil, "ARTWORK")
		stripe:SetColorTexture(unpack(COLORS.crit))
		stripe:SetSize(3, BAR_HEIGHT)
		stripe:SetPoint("LEFT", (i - 1) * 6, 0)
		bar.stripes[i] = stripe
	end
	bar.pushed:SetClipsChildren(true)
	Tooltip(bar.pushed, function(tip)
		tip:AddLine("Pushed off the end", 0.84, 0.16, 0.16)
		PushedLines(tip)
	end)
	local zero = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	zero:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -2)
	zero:SetText("0")
	bar.end100 = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	bar.end100:SetText("100")

	-- The table. Rows are created once; Layout() places the ones a view uses.
	y = y - BAR_HEIGHT - 28
	local COLS = { 34, 150, 240, 400 }
	for i, h in ipairs({ "Result", "Chance", "Roll range" }) do
		local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		fs:SetPoint("TOPLEFT", COLS[i], y)
		fs:SetText(h)
	end
	frame.lines = {}
	for i = 1, 3 do
		local t = frame:CreateTexture(nil, "ARTWORK")
		t:SetColorTexture(0.43, 0.39, 0.31)
		t:SetHeight(1)
		frame.lines[i] = t
	end
	y = y - 22
	frame.lines[1]:SetPoint("TOPLEFT", 14, y)
	frame.lines[1]:SetPoint("TOPRIGHT", -14, y)
	frame.tableTop = y - 6
	for _, key in ipairs(ALL_KEYS) do
		local row = CreateFrame("Frame", nil, frame)
		row:SetSize(452, 22)
		Tooltip(row, function(tip) ResultTooltip(tip, key) end)
		local swatch = row:CreateTexture(nil, "ARTWORK")
		swatch:SetColorTexture(unpack(COLORS[key]))
		swatch:SetSize(12, 12)
		swatch:SetPoint("LEFT", 0, 0)
		local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		name:SetPoint("LEFT", COLS[1] - 14, 0)
		name:SetText(NAMES[key])

		local box = CreateFrame("EditBox", nil, row)
		box:SetFontObject("GameFontHighlight")
		box:SetSize(70, 20)
		box:SetPoint("LEFT", COLS[2] - 14, 0)
		box:SetAutoFocus(false)
		row.box = box
		if key == "hit" then
			box:EnableMouse(false)
		else
			box:SetScript("OnEnterPressed", function(self)
				SetEdit(key, self:GetText())
				self:ClearFocus()
			end)
			box:SetScript("OnEscapePressed", function(self)
				self:ClearFocus()
				Refresh()
			end)
			box:SetScript("OnEditFocusLost", function() Refresh() end)
			Tooltip(box, function(tip)
				ResultTooltip(tip, key)
				tip:AddLine(" ")
				tip:AddLine("Click to type your own value; Enter to keep it.", 1, 0.82, 0, true)
			end)
			row.edit = MakeButton(row, "edit", function() box:SetFocus(); box:HighlightText() end)
			row.edit:SetPoint("LEFT", COLS[4] - 14, 0)
			row.edit:SetHeight(18)
			row.reset = MakeButton(row, "reset", function() Edits()[key] = nil; Refresh() end)
			row.reset:SetPoint("LEFT", COLS[4] - 14, 0)
			row.reset:SetHeight(18)
			Tooltip(row.reset, function(tip) tip:AddLine("Go back to the estimate.", 1, 1, 1) end)
		end
		row.range = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		row.range:SetPoint("LEFT", COLS[3] - 14, 0)
		rows[key] = row
	end
	frame.roomLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.roomLabel:SetText("Room left")
	frame.room = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.pushedLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	frame.pushedValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")

	frame.footnote = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	frame.footnote:SetWidth(452)
	frame.footnote:SetJustifyH("LEFT")

	frame.logging = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	frame.logging:SetSize(24, 24)
	local logLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	logLabel:SetPoint("LEFT", frame.logging, "RIGHT", 4, 0)
	logLabel:SetText("Turn on combat logging at login")
	frame.logging:SetScript("OnClick", function(self)
		db.logAtLogin = self:GetChecked() and true or false
		Log.Set(db.logAtLogin)
	end)
	Tooltip(frame.logging, function(tip)
		tip:AddLine("Combat logging", 1, 1, 1)
		tip:AddLine("Saves every swing to Logs/ (the same as /combatlog), and notes your stats at the start of each fight, so the numbers can be checked later.", 0.8, 0.8, 0.8, true)
	end)
end

local function Toggle()
	if not frame then Build() end
	frame:SetShown(not frame:IsShown())
end

-- The same sword as the addon list icon (## IconTexture in the .toc).
local ICON = "Interface\\Icons\\INV_Sword_04"

-- A button on the edge of the minimap, drawn and positioned the way LibDBIcon
-- draws other addons' buttons (Questie's copy, minor 56, read as reference),
-- without bundling that library. Drag it around the edge; the angle is saved.
local minimapButton

local function PlaceMinimapButton()
	local angle = math.rad(db.minimap.angle)
	local x, y = math.cos(angle), math.sin(angle)
	local w = Minimap:GetWidth() / 2 + 5
	local h = Minimap:GetHeight() / 2 + 5
	local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
	if shape == "ROUND" then
		x, y = x * w, y * h
	else -- square and other shapes: slide along the edge
		x = math.max(-w, math.min(x * (math.sqrt(2 * w * w) - 10), w))
		y = math.max(-h, math.min(y * (math.sqrt(2 * h * h) - 10), h))
	end
	minimapButton:ClearAllPoints()
	minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function DragMinimapButton()
	local mx, my = Minimap:GetCenter()
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	db.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
	PlaceMinimapButton()
end

local function AddMinimapButton()
	if minimapButton or not Minimap then return end
	local b = CreateFrame("Button", "AttackTableMinimapButton", Minimap)
	minimapButton = b
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetSize(20, 20)
	bg:SetPoint("TOPLEFT", 7, -5)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICON)
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)
	icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	b.icon = icon
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")
	b:SetScript("OnMouseDown", function() icon:SetTexCoord(0.1, 0.9, 0.1, 0.9) end)
	b:SetScript("OnMouseUp", function() icon:SetTexCoord(0.05, 0.95, 0.05, 0.95) end)
	b:SetScript("OnClick", Toggle)
	b:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:SetScript("OnUpdate", DragMinimapButton)
	end)
	b:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Attack Table", 1, 1, 1)
		GameTooltip:AddLine("Click: open or close the window.", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("Drag: move this button around the minimap.", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("/attacktable minimap: hide or show this button.", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	PlaceMinimapButton()
	b:SetShown(not db.minimap.hide)
end

-- Forever's addon compartment (the minimap's addon list) calls this, named by
-- ## AddonCompartmentFunc in AttackTable.toc.
function AttackTable_OnAddonCompartmentClick()
	Toggle()
end

SLASH_ATTACKTABLE1 = "/attacktable"
SlashCmdList.ATTACKTABLE = function(msg)
	if strtrim(msg or ""):lower() == "minimap" then
		db.minimap.hide = not db.minimap.hide
		if minimapButton then minimapButton:SetShown(not db.minimap.hide) end
		print("Attack Table: minimap button " .. (db.minimap.hide and "hidden; /attacktable minimap shows it again." or "shown."))
		return
	end
	Toggle()
end

local events = CreateFrame("Frame")
-- Events that change the numbers. Some do not exist in both games; registering
-- an unknown event is an error, so each is tried on its own.
local REDRAW = {
	"PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED", "UNIT_AURA", "UNIT_STATS",
	"UNIT_ATTACK", "UNIT_DEFENSE", "UNIT_RANGED_ATTACK_POWER", "UNIT_RANGEDDAMAGE", "COMBAT_RATING_UPDATE", "SKILL_LINES_CHANGED", "PLAYER_LEVEL_UP",
	"CHARACTER_POINTS_CHANGED", "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE",
	"UPDATE_SHAPESHIFT_FORM", "PLAYER_REGEN_ENABLED",
}
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_TARGET_CHANGED" }) do
	events:RegisterEvent(e)
end
for _, e in ipairs(REDRAW) do
	pcall(events.RegisterEvent, events, e)
end

local UNIT_EVENTS = { UNIT_AURA = true, UNIT_STATS = true, UNIT_INVENTORY_CHANGED = true, UNIT_ATTACK = true, UNIT_DEFENSE = true,
	UNIT_RANGED_ATTACK_POWER = true, UNIT_RANGEDDAMAGE = true }

events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= "AttackTable" then return end
		AttackTableDB = AttackTableDB or {}
		db = AttackTableDB
		db.levelOffset = db.levelOffset or 0
		-- Edits are kept per view; version 1 kept one flat list.
		if type(db.edits) ~= "table" or not db.edits.yours then
			db.edits = { yours = {}, onYou = {} }
		end
		db.edits.ranged = db.edits.ranged or {}
		db.view = db.view or "yours"
		db.tab = db.tab or "melee"
		db.hand = db.hand or "main"
		db.special = db.special or false
		db.behind = db.behind or false
		db.shieldBlock = db.shieldBlock or false
		db.logAtLogin = db.logAtLogin or false
		db.minimap = db.minimap or { angle = 200, hide = false }
	elseif event == "PLAYER_LOGIN" then
		Log.OnLogin(db)
		Stats.Read() -- keep a readable copy before the first fight
		AddMinimapButton()
	elseif event == "PLAYER_TARGET_CHANGED" then
		Log.OnTargetChanged()
	elseif event == "PLAYER_REGEN_DISABLED" then
		Log.Snapshot(db)
		QueueRefresh()
	else
		if UNIT_EVENTS[event] and arg1 ~= "player" then return end
		QueueRefresh()
	end
end)
