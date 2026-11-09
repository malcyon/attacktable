# Attack Table: plan

An addon that draws your character's melee or ranged attack table as one colored bar, in the order the game rolls it, so you can see when crit is pushed off the end. Version 1 is built (`Rules.lua`, `Stats.lua`, `Log.lua`, `AttackTable.lua`); this file records the decisions, the research, and what comes next. The rules behind the numbers, with their sources, are in the author's research notes (`docs/attack-table.md`, not part of this repository); the code comments cite that file too.

## Decisions

| Part | Decision |
|---|---|
| Scope | Melee and ranged attacks only. Spells are out: a spell rolls hit, resistance and crit separately, so nothing is pushed off its table |
| Opening it | `/attacktable`; a button somewhere later |
| Whose table | Toggle at the top: "Your attacks" (you attacking a monster) or "Attacks on you" (a monster attacking you, for tanks); see below |
| Tabs | Melee and Ranged on "Your attacks", shown only with a bow, gun, crossbow or thrown weapon equipped (wands are spells). On Ranged, White/Special and the hand buttons are hidden, since every ranged attack rolls crit the same way |
| Combat log | Checkbox "Turn on combat logging at login", off by default, so the player never has to remember `/combatlog`; calls the game's `LoggingCombat(true)`, the same function `/combatlog` uses in both games. The logs are for agents to read; the addon itself cannot read them. Allowed by `AGENTS.md` |
| Stat snapshots | While combat logging is on, the addon notes at the start of each fight: the time, your level, hit, crit, Agility, weapon skill, defense, dodge, parry, block, equipped weapons, and the level of the mob you are fighting. The notes go in the addon's save file (`WTF/Account/<account>/SavedVariables/AttackTable.lua`), which the game writes at logout. An agent matches them to the combat log by time. On Forever, stats are hidden in combat, so the snapshot uses the last values read before the fight. Old snapshots are pruned so the file stays small |
| Ability dropdown (later) | Replaces the white/special toggle with a list of your class's abilities, hiding the slices an ability cannot have (Overpower: no dodge, parry or block in Classic). Needs each ability checked against Forever's spell data first |
| Swing counter (Classic Era only, later) | Classic Era still gives addons combat events, so the addon could count your real results and show them beside the calculated table. Forever does not give these events |
| Melee controls | White/special toggle; main-hand/off-hand toggle when dual wielding; front/behind toggle |
| Target level | Spin box from 1 to 63 with − and + buttons. Starts at your level and shows the gap ("+3"). No boss shortcut: raid bosses count as 63 only for a level 60 character. It does not read your target |
| Crit reductions | Automatic: −1% per level the target is above you, plus the boss reduction (below) when the target is 3 or more levels above |
| Editable values | Miss, dodge, parry, glancing, block and crit start as estimates and can be edited. An edited value is marked and has a reset button. Ordinary hit is whatever is left |
| Bar | One colored slice per result, in roll order. Crit that does not fit is drawn past the end in striped red. Colors: miss grey, dodge yellow, parry orange, glancing light blue, block steel, crit red, hit green |
| Table under the bar | One column of rows, like a real table: color, result, chance, range on the 0–100 roll, and a pencil on editable values. A "Room left" row sits between block and crit, and a "Crit pushed off" row at the bottom turns red when crit does not fit. A line below shows how crit was worked out. See `mockup.png` |
| Tooltips | Each slice's chance, its range on the 0–100 roll, how it was worked out, what changes it, and how sure the number is |
| Live updates | Redraws when gear, buffs, talents, level or weapon skill change, using the game's events rather than polling |
| Games | Forever (`AttackTable.toc`, interface 16001) and Classic Era (`AttackTable_Vanilla.toc`, interface 11509), each with its own rules. Classic Era still has the 9% hit suppression against bosses; Forever does not |

### White and special attacks

| | White (automatic swing) | Special (ability) |
|---|---|---|
| Glancing blows | Yes | No |
| Two-weapon +19% miss | Yes | No |
| Crit | Part of the single roll, so it can be pushed off | A second roll after the attack lands; shown as a share of hits, never pushed off |

"Special" shows a typical weapon ability (Mortal Strike, Bloodthirst, Heroic Strike, Sinister Strike, Stormstrike). Its tooltip lists the exceptions: abilities that cannot be dodged, parried or blocked (such as Overpower in Classic); spells cast by melee classes (shocks, Flametongue, Judgement), which use the spell table and are out of scope; extra automatic swings (Windfury, Sword Specialization procs), which use the white table; and ranged abilities, which belong on the Ranged tab. The special-attack rules in `docs/attack-table.md` are marked "Not from the source"; combat logs can confirm them.

### Attacks on you

A monster's white swing at you is one roll, in this order: miss, dodge, parry, block, crit, crushing blow, hit (**Simulator**: wowsims [`spell_outcome.go` L631-647](https://github.com/wowsims/classic/blob/7779ebbf79dc7f1341e6ab939b28a3402c9a730a/sim/core/spell_outcome.go#L631-L647), gunba and lovelaced the same; no measured test found). A **crushing blow** does 150% damage. Enough miss, dodge, parry and block pushes crushing blows and then crits off the end; tanks call that "uncrushable". Shield Block (+75% block) and Holy Shield (+30% block in Forever) exist for this.

The gap below is the monster's weapon skill (its level × 5) minus your defense. Formulas from Forever's character-sheet code ([`Camelot/PaperDollFrameStats.lua` L57-82](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/PaperDollFrameStats.lua#L57-L82), build 70532; **Datamined**: Blizzard's model, defined but not yet called by anything, and not in the retail client's copy):

| Result | Chance | Notes |
|---|---|---|
| Miss | 5% − gap × 0.04% | Full defense counts |
| Dodge, parry, block | Your own chance (`GetDodgeChance`, `GetParryChance`, `GetBlockChance`) − gap × 0.04% | The adjustment is the simulators' (**Simulator**); not in Blizzard's code |
| Crit | 5% + gap × 0.04% | 5.6% from a level 63 boss at 300 defense |
| Crushing blow | gap × 2% − 15%, only when the gap is 15 or more; defense counts only up to your level × 5 | 15% from a boss at level 60, none from +2. Defense cannot lower it; only pushing it off the table can. lovelaced gives +2 monsters 5%; Blizzard's code (newer) gives 0 |

**Controls:** the same target-level spin box, white/special toggle (special attacks never crush and roll crit separately, **Simulator**, lovelaced), and front/behind toggle. Whether players can parry or block attacks from behind is **Not confirmed** (lovelaced assumes dodge only). A "Shield Block active" checkbox adds 75% block to show the effect.

**Example tank view:** a level 60 warrior with 400 defense against a level 63 boss has a gap of −85: miss 8.4%, crit 1.6%, crushing 15%. The ordinary-hit slice is whatever is left after the warrior's own dodge, parry and block.

### Boss crit reduction (the 1.8%)

Against a target 3 or more levels above you, crit from talents, buffs and gear effects loses a further 1.8%, or all of it if you have less. Crit from Agility is not reduced.

The addon works out how much of your crit counts by subtraction, keeping each part separate so a rule can change in one place:

| Part | Source | Counts toward the 1.8%? |
|---|---|---|
| Crit from Agility | The game's function if it has one; otherwise Agility ÷ the class-and-level value from `docs/stats-and-ratings.md` | No |
| Base crit | Per-class table (see findings) | No (measured in Classic) |
| Crit rating from gear (Forever) | The game reports rating crit separately | Assumed yes; untested |
| Ruthless racial (Forever, +1% since October 26; Savage was removed) | Fixed amount | Assumed yes; untested |
| Everything left (talents, buffs, "Equip:" effects) | Sheet crit minus the parts above | Yes |

The result only matters below about 3% of counted crit; above that the reduction is the full 1.8%. In that low range the tooltip says the reduction is uncertain and why.

## Versions

| Version | Contents | State |
|---|---|---|
| 1 | "Your attacks", melee: the bar, the table, tooltips, white/special, front/behind, main/off hand, target level, edits, combat logging, stat snapshots | Built 2026-10-29; window tested in Classic Era the same day |
| 2 | "Attacks on you" (the tank view) with the Shield Block checkbox (warriors only) | Built 2026-10-29; window tested in Classic Era the same day |
| 2 | The Ranged tab, following the majority of sources (no dodge, editable; crit a second roll) | Built 2026-10-29; not yet tested in game |

Unbuilt parts sit behind a flag in `FEATURES` at the top of `AttackTable.lua`; while a flag is off, its buttons are left out of the window entirely. Both `attacksOnYou` and `ranged` are on.
| Later | Ability dropdown, Classic Era swing counter, a button to open the window, a script under `tools/` that reads the combat logs and snapshots | Planned; the log script is `tools/combatlog/analyze.py` |

## Testing

Forever launched on November 4, 2026. Combat logging and stat snapshots have since worked there; the results are in `docs/attack-table.md`. The Ranged tab is still untested in Forever. Classic characters, including the Hardcore shaman, test the window, the Classic rules and the live updates. Classic Era still gives the combat log, so logged swings (`/combatlog`) can check the numbers. Shamans cannot dual wield or use ranged weapons in Classic, so those need another class. The most useful crit test is a character with little crit from talents or buffs, against a mob exactly 3 levels higher; on Hardcore that risks the character.

## Research findings (October 29, 2026)

Evidence marks are those of `docs/attack-table.md`.

### Ranged attack table

The sources disagree on two points: whether monsters dodge ranged attacks, and whether Auto Shot's crit is part of one roll (and so can be pushed off) or a second roll.

| Source | Results | Crit | Mark |
|---|---|---|---|
| [forever-hunter wiki, Ranged Attack Table](https://github.com/classic-hunter/forever-hunter/wiki/Ranged-Attack-Table) (newest, October 29) | Miss, block (front only), crit, hit; no dodge, parry or glancing | Second roll for all ranged attacks, so no crit cap | **Not confirmed**: "based on established Classic mechanics and Hunter testing", no logs shown |
| [wowsims/classic `spell_outcome.go` L533-553](https://github.com/wowsims/classic/blob/7779ebbf79dc7f1341e6ab939b28a3402c9a730a/sim/core/spell_outcome.go#L533-L553), and gunba's Forever fork the same | Miss (no two-weapon penalty), block from the front | Second roll | **Simulator** |
| [lovelaced `combat.rs` L122-195](https://github.com/lovelaced/forever-sim/blob/4e162794a91a5ad2b0c9d0bdd246ad06e16ca515/src/engine/combat.rs#L122-L195) | Auto Shot: miss, dodge, block, crit, hit; no parry or glancing | Auto Shot one roll (crit cap); shots a second roll | **Simulator** |

Ranged miss uses the melee formulas with ranged weapon skill. Classic's hit suppression applies to ranged; whether Forever removed it for ranged is **Not confirmed** (gunba [CORE-001](https://github.com/gunba/wow-forever-sim/blob/forever/docs/uncertainties.md#core-001) says the ranged scope is not established). No measured ranged results were found.

**Effect on the plan:** the Ranged tab follows the majority (no dodge, crit as a second roll) and says the sources disagree. Dodge is editable from 0%. A Classic hunter with `/combatlog` can settle it.

### Glancing below your level

No Blizzard statement or measurement. wowsims and gunba use the formula as it is, so a target one level lower glances 0% and lower targets never glance ([wowsims `target.go` L327](https://github.com/wowsims/classic/blob/7779ebbf79dc7f1341e6ab939b28a3402c9a730a/sim/core/target.go#L327)); lovelaced keeps 10% for every lower level ([`model.rs` L116-122](https://github.com/lovelaced/forever-sim/blob/4e162794a91a5ad2b0c9d0bdd246ad06e16ca515/src/model.rs#L116-L122)). Both are **Simulator**, neither cites a source. Neither simulator has glancing against players.

**Effect on the plan:** use the formula as it is (0% at one level below), mark it **Not confirmed**, and leave glancing editable.

### Base crit and the boss reduction

- **Base crit does not count toward the 1.8%** (**Measured**, magey's [Crit aura suppression](https://github.com/magey/classic-warrior/wiki/Crit-aura-suppression)). With 1% aura crit, two tests (5,552 and 5,935 attacks) found 3.7% and 4.0% total reduction: the 3% for levels plus roughly the whole 1%. That fits "1.8%, or all of your aura crit if less". The Hunter row is Auto Shot, so the reduction applies to ranged too.
- **Base crit per class** (**Simulator**, [wowsims `base_stats.go` L84-130](https://github.com/wowsims/classic/blob/7779ebbf79dc7f1341e6ab939b28a3402c9a730a/sim/core/base_stats.go#L84-L130); gunba copies it for Forever; no measured or datamined source):

  | Class | Base melee crit |
  |---|---|
  | Warrior, Rogue, Hunter | 0% |
  | Paladin | 0.7% |
  | Druid | 0.9% |
  | Shaman | 1.7% |

- **Agility to crit in Classic:** only level-60 values are known (20 Agility per 1%, 29 Rogue, 53 Hunter). No per-level Classic table was found; Forever's per-level table is in `docs/stats-and-ratings.md`.
- **Racials changed on October 26** (**Blizzard**, [development notes](https://us.forums.blizzard.com/en/wow/t/2360696/7)): Ruthless is now +1% crit, Savage and Earth Fury are removed, and Dwarves gain Artisan's Precision (+1% hit). Whether Ruthless counts toward the 1.8% is still untested. Gear crit rating likewise: nothing found.

### Addon functions

From Blizzard's interface code in Gethe/wow-ui-source: `forever` branch at 1.60.1 build 70532 (commit `ca8368f`), `classic_era` branch at 1.15.9 build 70576 (commit `4192ac6`).

| Need | Forever | Classic Era |
|---|---|---|
| Weapon skill | `C_SkillInfo.GetSkillLineInfoByID` (rank and modifier) | `UnitAttackBothHands`, `UnitRangedAttack` |
| Hit | `GetHitModifier`, `GetOffhandHitModifier`, `GetRangedHitModifier`, `HasDualWieldPenalty` | `GetHitModifier` |
| Crit | `GetCritChance`, `GetRangedCritChance` | Same |
| Crit from Agility | `GetCritChanceFromStat(stat, value)` | `GetCritChanceFromAgility` not confirmed; one `/run` in game will tell |
| Crit rating | `GetCombatRatingBonus(CR_CRIT_MELEE)` and the ranged constant | Exists but returns 0 |
| Expertise | `GetExpertise` (main hand, off hand, ranged) | Exists |
| Agility, level | `UnitStat`, `UnitLevel` | Same |
| Dual wielding | `IsDualWielding`, `C_PaperDollInfo.OffhandHasWeapon` | Same |
| Talents | `C_ClassTalents` and `C_Traits` | `C_SpecializationInfo.GetTalentInfo` |

All the redraw events in the plan exist in both games.

**Secret values on Forever:** every hit, crit, rating, expertise and stat function above is flagged `SecretWhenUnitStatsRestricted`. ForeverStats' author reports they are hidden in combat. The addon reads them out of combat, keeps the last values, and says "values from before combat" while they are hidden. `C_Secrets.ShouldUnitStatsBeSecret()` and the `ADDON_RESTRICTION_STATE_CHANGED` event tell it when.

**Not evidence:** Forever's character-sheet code contains fixed miss, dodge and parry tables under the comment "Hit and Expertise are being removed from items". The block is identical to the retail client's and dates from retail's removal of hit from gear, so it is not a Forever rule.

## Still open

- Whether monsters dodge ranged attacks, and whether Auto Shot can have crit pushed off.
- Base crit and Agility-to-crit by level in Classic.
- Whether Ruthless and Forever's gear crit rating count toward the 1.8%.
- Whether `GetCritChanceFromAgility` exists on Classic Era.
- The monster table has no measured test in Classic or Forever: roll order, crushing chance at +2, crit from defense above level × 5, and avoidance from behind.
- Whether `GetDodgeChance` already includes defense above level × 5.
