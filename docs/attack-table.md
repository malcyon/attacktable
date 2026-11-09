# Attack table research

The research behind Attack Table's numbers: how a melee or ranged attack becomes a miss, dodge, parry, glancing blow, block, crit or hit, and how a monster's swing at you is decided. It covers WoW Classic (patch 1.12 rules, which Classic Era follows) and what WoW Forever changes. Every formula the addon uses is here, with its source.

Each claim is marked by how sure it is:

| Mark | Meaning |
|---|---|
| **Blizzard** | Stated by Blizzard: in the Classic bug-report forum, or in Forever patch notes, development notes, hotfixes or known-issues posts |
| **Measured** | Confirmed by logged player tests |
| **Estimate** | A best fit to logged data; Blizzard never gave the number |
| **Datamined** | Read from the game client's data or interface files, not tested in play |
| **Simulator** | Encoded in a simulator; the text says which |
| **Not confirmed** | A single or weak source, or general Classic knowledge without a source; the text says why |

The main Classic source is the classic-warrior wiki's [Attack table](https://github.com/magey/classic-warrior/wiki/Attack-table) page, which combines Blizzard's answers in the Classic bug-report forum with more than 150,000 logged test swings. Its formulas come from old wowwiki edits by a player called Beaza, confirmed by the wiki authors' own logs. The Forever results come from the sources in [Sources](#sources) and from the author's own combat logs, described in [Forever logs](#forever-logs).

## How one swing is decided

An automatic swing (a "white hit") is one roll from 0 to 100. The possible results are stacked in this order, and the roll lands in exactly one band:

1. Miss
2. Dodge
3. Parry
4. Glancing blow
5. Block
6. Critical hit
7. Ordinary hit (whatever is left)

The order and the one-roll design are **Not confirmed**: general Classic knowledge; the wiki page lists the chances but not the order.

Because it is one roll, the bands push each other off the table. If miss, dodge, parry, glancing and block already fill 60% of it, only 40% is left for crits and hits, so crit chance above 40% does nothing on white hits. That limit is the **crit cap**, and it is what the addon's bar shows.

**Behind the target**, monsters cannot parry or block. Dodge still happens from behind. **Not confirmed** as a stated rule, but a dual-wield test from behind logged 0 parries and 0 blocks in 48,445 swings (**Measured**, [Attack table](https://github.com/magey/classic-warrior/wiki/Attack-table)). In Forever, monsters can wrongly parry and block from behind when you stand very close (**Blizzard**, [known issues, October 1](https://us.forums.blizzard.com/en/wow/t/2352687/6)).

## Weapon skill and defense

Every result depends on the gap between your **weapon skill** and the target's **defense**:

- Your weapon skill rises as you use a weapon, up to your level × 5 (300 at level 60). Gear and racials can add more.
- A monster's defense is its level × 5, so a level 63 raid boss has 315.
- Raid bosses count as level 63, which is "+3 levels" for a level 60 player.

The formulas below use `TargetLevel*5` for the target's defense and `AttackerSkill` for your weapon skill.

## Miss

| Situation | Miss chance | Mark |
|---|---|---|
| Target 3 levels higher, one weapon | 8% | **Blizzard** |
| Gap of 10 or less | `5% + (TargetLevel*5 - AttackerSkill) * 0.1%` | **Measured** |
| Gap of 11 or more | `5% + (TargetLevel*5 - AttackerSkill) * 0.2%` | **Measured** |
| Target below level 10 | Normal chance × (target level ÷ 10) | **Measured** |
| Dual wielding, white swings | Normal chance + 19% | **Measured** |

**The 9% hit cap in Classic:** when the target's defense is more than 10 above your weapon skill, the first 1% of hit from gear or talents does nothing (**Blizzard**). Against a raid boss with 300 skill, you need 9% hit to never miss with one weapon, not 8%.

**Forever removes this.** At 1% hit against +3 targets, 300 of 4,259 attacks missed (7.04%), where Classic predicts 8% (**Measured**, summarized in [gunba CORE-001](https://github.com/gunba/wow-forever-sim/blob/forever/docs/uncertainties.md#core-001)). Forever's one-weapon boss hit cap is 8%.

**Weapon skill closes the gap.** With 305 skill the gap to 315 is 10, so the steeper formula and the 1% penalty both stop applying, and miss falls to 6% (**Blizzard** that the penalty goes away; **Measured** for the 6%).

**Dual wielding** raises the boss miss chance to 27% (8% + 19%). One test needed 28% hit to reach 0 misses: 27% hit still missed 1.01% of 48,445 swings, and 28% hit missed none of 5,398 (**Measured**). An older theory, that dual wielding gives 80% of the normal chance plus 20%, was disproved by this test.

## Dodge

| Situation | Dodge chance | Mark |
|---|---|---|
| Same-level monster | 5%, plus 0.5% per level higher | **Blizzard** |
| Boss (+3 levels) | 6.5% | **Blizzard** |
| Any monster | `5% + (TargetLevel*5 - AttackerSkill) * 0.1%` | **Measured** |
| Monster below level 10, Forever | The above × (monster level ÷ 10) | **Measured**, [Forever logs](#monsters-below-level-10) |

With 305 skill, a boss dodges 6% instead of 6.5%. In Forever, some items and a flask reduce your chance to be dodged (see [What WoW Forever changes](#what-wow-forever-changes)); the addon subtracts the game's expertise value.

## Parry

| Situation | Parry chance | Mark |
|---|---|---|
| Boss (+3 levels), from the front | 14% | **Blizzard** |
| Same-level monster, from the front | About 5% (4.97% in 7,044 swings) | **Measured** |
| Monster below level 10, Forever | About 5% × (monster level ÷ 10) | **Measured**, [Forever logs](#monsters-below-level-10) |

No source gives a formula for parry between these points. The addon uses the dodge formula there (**Not confirmed**).

## Block

| Situation | Block chance | Mark |
|---|---|---|
| Monster, from the front | `MIN(5%, 5% + (TargetLevel*5 - AttackerSkill) * 0.1%)`, never above 5% | **Measured** |
| Monster below level 10, Forever | The above × (monster level ÷ 10) | **Measured**, [Forever logs](#monsters-below-level-10) |

The wiki authors expected bosses to block 6.5% like dodge, but measured about 5%. A blocked attack still does damage, reduced by the shield's block value.

## Glancing blows

A glancing blow is a white hit that does reduced damage. Only automatic swings can glance, never abilities:

`GlancingChance = 10% + (TargetLevel*5 - MIN(AttackerLevel*5, AttackerSkill)) * 2%` (**Measured**)

| Target level | Chance to glance | Damage lost per glancing blow |
|---|---|---|
| Same level | 10% | 5% |
| +1 | 20% | 5% |
| +2 | 30% | 15% |
| +3 (boss) | 40% | 35% |

**Weapon skill doesn't change how often you glance.** It can't count above level × 5 here, so 305 skill still glances 40% of the time against a boss.

**Below your level:** no Blizzard statement or measurement. wowsims and gunba's Forever simulator use the formula as it is, so a target one level lower glances 0% ([wowsims `target.go` L327](https://github.com/wowsims/classic/blob/7779ebbf79dc7f1341e6ab939b28a3402c9a730a/sim/core/target.go#L327)); lovelaced's simulator keeps 10% for every lower level ([`model.rs` L116-122](https://github.com/lovelaced/forever-sim/blob/4e162794a91a5ad2b0c9d0bdd246ad06e16ca515/src/model.rs#L116-L122)). Both are **Simulator**. The author's Forever logs fit the formula as it is, including against monsters one level lower (see [Forever logs](#forever-logs)); the addon uses it.

**Weapon skill does change how much a glance costs.** The damage lost comes from this formula for melee classes (**Measured**):

```
Low end:  1.3 - 0.05 * (defense - skill), at most 0.91
High end: 1.2 - 0.03 * (defense - skill), at least 0.2, at most 0.99
Damage dealt = average of the two
```

| Defense minus skill | Damage lost per glance | Miss chance | Hit needed to never miss |
|---|---|---|---|
| 15 (boss, 300 skill) | 35% (measured 35.12%) | 8.0% | 9.0% |
| 13 | 27% (measured 26.74%) | 7.6% | 8.2% |
| 11 | 19% | 7.2% | 7.4% |
| 10 (boss, 305 skill) | 15% (measured 14.82%) | 6.0% | 6.0% |
| 5 | 5% (measured 4.96%) | 5.5% | 5.5% |
| 0 | 5% | 5.0% | 5.0% |

**Forever:** Blizzard lists the glancing chance as correct at all levels, but the damage lost per glance as wrong against higher-level targets (**Blizzard**, [known issues](https://us.forums.blizzard.com/en/wow/t/2352687)). One Forever test measured about 24.6% lost per glance against +3 targets instead of 35% (**Measured**, [gunba CORE-001](https://github.com/gunba/wow-forever-sim/blob/forever/docs/uncertainties.md#core-001)). No fix had been announced as of the [November 6 hotfixes](https://news.blizzard.com/en-us/article/24315281/wow-forever-hotfixes-november-6-2026). In Forever the addon shows the game's own glancing chance and damage lost (see [How the addon reads your stats](#how-the-addon-reads-your-stats)); in Classic Era it uses the formulas above.

## Critical hits

| Rule | Mark |
|---|---|
| Crit chance falls by 1% per level the target is above you, so 3% against a boss | **Blizzard** |
| Weapon skill above level × 5 does not raise crit chance against monsters | **Measured** |
| Against targets 3 or more levels above, crit from "auras" is reduced by a further flat amount | **Blizzard** that it exists |
| That amount is 1.8% | **Estimate**, from more than 60,000 hits |

**Formulas** (**Measured**):

```
BaseAttackRating = MIN(PlayerLevel*5, AttackRating)

BaseAttackRating below the monster's defense:
    CritChance = YourCrit + (BaseAttackRating - TargetDefense) * 0.2%
BaseAttackRating at or above the monster's defense:
    CritChance = YourCrit + (BaseAttackRating - TargetDefense) * 0.04%
```

### The boss reduction (the 1.8%)

**What counts as aura crit:** talents (Cruelty, Axe Specialization), gear with an `Equip:` line that gives crit, buffs (Leader of the Pack, Songflower Serenade) and consumables (Elixir of the Mongoose). Crit from Agility does not count, and neither does a class's base crit (**Measured**, magey's [Crit aura suppression](https://github.com/magey/classic-warrior/wiki/Crit-aura-suppression)). With 1% aura crit, two tests of 5,552 and 5,935 attacks found 3.7% and 4.0% total reduction: the 3% for levels plus roughly the whole 1%, which fits "1.8%, or all of your aura crit if less". One of the tests was a Hunter's Auto Shot, so the reduction applies to ranged attacks too.

**Total loss against a boss:** with at least 1.8% aura crit, a boss takes about 4.8% off the crit on your character sheet: 3% for levels and 1.8% for auras.

**Forever keeps it:** 5.19% crit observed against 5.61% expected with the reduction (**Measured**, [gunba CORE-001](https://github.com/gunba/wow-forever-sim/blob/forever/docs/uncertainties.md#core-001)). Whether Forever's Ruthless racial (+1% crit) and its crit rating on gear count as aura crit is untested.

The addon works out your aura crit by subtraction: sheet crit, minus crit from Agility, minus base crit.

**Base crit per class**, the crit a class has with zero Agility (**Simulator**, [wowsims `base_stats.go` L84-130](https://github.com/wowsims/classic/blob/7779ebbf79dc7f1341e6ab939b28a3402c9a730a/sim/core/base_stats.go#L84-L130); gunba copies it for Forever; no measured or datamined source):

| Class | Base melee crit |
|---|---|
| Warrior, Rogue, Hunter | 0% |
| Paladin | 0.7% |
| Druid | 0.9% |
| Shaman | 1.7% |
| Warlock | 2.0% |
| Priest | 3.0% |
| Mage | 3.2% |

**Agility for 1% crit in Forever**, by class and level (**Datamined**: the client's `PlayerExpectedStat` table, [wago.tools, build 1.60.1.70450](https://wago.tools/db2/PlayerExpectedStat?build=1.60.1.70450), unchanged in [build 70755](https://wago.tools/db2/PlayerExpectedStat?build=1.60.1.70755); gunba's [CORE-011](https://github.com/gunba/wow-forever-sim/blob/forever/docs/uncertainties.md#core-011) reports the same level-60 values). The addon uses it only when the game cannot report crit from Agility directly, and interpolates between the columns.

| Class | Level 10 | 20 | 30 | 40 | 50 | 60 |
|---|---|---|---|---|---|---|
| Warrior | 5.2 | 7.8 | 10.4 | 13.2 | 16.4 | 20.0 |
| Paladin | 5.8 | 8.1 | 10.7 | 13.5 | 16.5 | 19.8 |
| Hunter | 6.8 | 15.2 | 24.0 | 33.0 | 42.7 | 52.9 |
| Rogue | 3.5 | 8.1 | 13.0 | 18.0 | 23.4 | 29.0 |
| Priest | 11.0 | 12.5 | 14.0 | 15.5 | 17.5 | 20.0 |
| Shaman | 7.3 | 9.4 | 11.5 | 13.9 | 16.7 | 19.7 |
| Mage | 12.2 | 13.3 | 14.5 | 16.1 | 17.8 | 19.5 |
| Warlock | 7.7 | 9.7 | 12.0 | 14.3 | 17.0 | 20.0 |
| Druid | 6.3 | 8.8 | 11.2 | 13.9 | 16.8 | 20.0 |

The level-60 values match RankedBoost's [Agility page](https://rankedboost.com/world-of-warcraft/forever/stats/agility/): 20 Agility per 1% for most classes, 29 for Rogues and 53 for Hunters. No per-level table was found for Classic Era, where the addon relies on the game's own value.

## Special attacks ("yellow" attacks)

Abilities such as Heroic Strike, Mortal Strike, Bloodthirst, Sinister Strike and Stormstrike follow different rules (**Not confirmed**: general Classic knowledge; the wiki tested white hits only):

- They can't glance.
- The dual-wield miss penalty doesn't apply, so their miss chance is the one-weapon one.
- Miss, dodge, parry and block are rolled first. A second, separate roll then decides whether a hit crits, so abilities have no crit cap. The addon shows their crit as a share of the hits.

Some abilities break these rules: some can't be dodged, parried or blocked (Overpower in Classic); spells cast by melee classes (shocks, Flametongue, Judgement) use the spell table instead; extra automatic swings (Windfury, Sword Specialization) use the white table.

## Ranged attacks

The sources disagree on two points: whether monsters dodge ranged attacks, and whether Auto Shot's crit is part of one roll (and so can be pushed off) or a second roll.

| Source | Results | Crit | Mark |
|---|---|---|---|
| [forever-hunter wiki, Ranged Attack Table](https://github.com/classic-hunter/forever-hunter/wiki/Ranged-Attack-Table) (October 29, 2026) | Miss, block (front only), crit, hit; no dodge, parry or glancing | A second roll for all ranged attacks, so no crit cap | **Not confirmed**: "based on established Classic mechanics and Hunter testing", no logs shown |
| [wowsims `spell_outcome.go` L533-553](https://github.com/wowsims/classic/blob/7779ebbf79dc7f1341e6ab939b28a3402c9a730a/sim/core/spell_outcome.go#L533-L553), and gunba's Forever fork the same | Miss (no two-weapon penalty), block from the front | A second roll | **Simulator** |
| [lovelaced `combat.rs` L122-195](https://github.com/lovelaced/forever-sim/blob/4e162794a91a5ad2b0c9d0bdd246ad06e16ca515/src/engine/combat.rs#L122-L195) | Auto Shot: miss, dodge, block, crit, hit; no parry or glancing | Auto Shot one roll (crit cap); shots a second roll | **Simulator** |

Ranged miss uses the melee formulas with ranged weapon skill. Classic's hit suppression applies to ranged attacks; whether Forever removed it for them is **Not confirmed** ([gunba CORE-001](https://github.com/gunba/wow-forever-sim/blob/forever/docs/uncertainties.md#core-001) says the ranged scope is not established). No measured ranged results were found.

The addon follows the majority: no dodge (editable from 0%), no parry or glancing, block from the front, and crit as a second roll. Wands are not covered: their shots are spells.

## Monsters' attacks on you

A monster's white swing at you is one roll, in this order: miss, dodge, parry, block, crit, crushing blow, hit (**Simulator**: wowsims [`spell_outcome.go` L631-647](https://github.com/wowsims/classic/blob/7779ebbf79dc7f1341e6ab939b28a3402c9a730a/sim/core/spell_outcome.go#L631-L647); gunba and lovelaced the same). A **crushing blow** does 150% damage. Enough miss, dodge, parry and block pushes crushing blows and then crits off the end; tanks call that "uncrushable". Shield Block (+75% block) and Holy Shield (+30% block in Forever) exist for this.

Your **defense** is a skill, like weapon skill, that rises as monsters hit you. The gap below is the monster's weapon skill (its level × 5) minus your defense. The formulas are in Forever's character-sheet code ([`Camelot/PaperDollFrameStats.lua` L57-82](https://github.com/Gethe/wow-ui-source/blob/ca8368f2f2380cbe696854f7f2646387c278a61b/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/PaperDollFrameStats.lua#L57-L82), build 70532; **Datamined**: Blizzard's model, defined but not called by anything in that build).

| Result | Chance | Mark |
|---|---|---|
| Miss | `5% - gap * 0.04%` | **Datamined**; fits the [Forever logs](#forever-logs) |
| Dodge, parry, block | Your own chance from the character sheet, minus `0.04%` per point the monster's skill is above your level × 5 | **Simulator** for the adjustment, which is not in Blizzard's code; fits the Forever logs |
| Crit, Classic | `5% + gap * 0.04%`; enough defense makes you immune (440 at level 60 against a +3 boss) | **Datamined**, the same formula; **Not confirmed** for Classic itself: community wikis (wowwiki and vanilla-wow fandom, "Critical strike" and "Defense"), sourcing unclear. Both Forever simulators assume it (**Simulator**: [gunba `target.go`](https://github.com/gunba/wow-forever-sim/blob/forever/sim/core/target.go), [lovelaced `enemies.toml`](https://github.com/lovelaced/forever-sim/blob/main/data/base/enemies.toml)) |
| Crit, Forever | 0% while the gap is under 10; from 10 up, the Classic formula | **Measured** below 10; **Not confirmed** above. See [Monsters rarely crit](#monsters-rarely-crit) |
| Crushing blow | `gap * 2% - 15%`, only when the gap is 15 or more; defense counts only up to your level × 5 | **Datamined**. 15% from a boss at level 60, none from +2; lovelaced's simulator gives +2 monsters 5% |

**Abilities** never crush, and their crit is a second roll on the hits (**Simulator**, lovelaced). **From behind**, players are assumed to dodge but not parry or block (**Not confirmed**; lovelaced assumes it).

**Example:** a level 60 warrior with 400 defense against a level 63 boss has a gap of −85: miss 8.4%, crushing 15%, and in Classic crit 1.6%. The ordinary-hit slice is whatever is left after the warrior's own dodge, parry and block.

## Measured results

### Classic

White hits only, from the [Attack table](https://github.com/magey/classic-warrior/wiki/Attack-table) page (**Measured**). Averages are weighted by number of swings.

| Target | Swings | Hit | Crit | Miss | Parry | Dodge | Block | Glancing | Damage lost per glance |
|---|---|---|---|---|---|---|---|---|---|
| Same level | 7,044 | 61.13% | 8.21% | 5.20% | 4.97% | 5.30% | 5.11% | 10.09% | ~5.03% |
| +1 level | 2,000 | 55.20% | 2.25% | 6.00% | 5.75% | 5.95% | 4.55% | 20.30% | ~4.85% |
| +2 levels | 1,999 | 45.27% | 1.75% | 6.20% | 6.55% | 5.70% | 5.30% | 29.21% | ~14.19% |
| +3 levels | 31,779 | 22.20% | 4.42% | 7.81% | 13.97% | 6.29% | 4.94% | 40.36% | ~35.12% |
| +3, +2 skill | 1,200 | 24.75% | 3.50% | 7.83% | 12.17% | 5.17% | 3.42% | 43.17% | ~26.74% |
| +3, +5 skill | 28,063 | 21.27% | 7.80% | 5.99% | 13.49% | 6.04% | 5.13% | 40.28% | ~14.82% |
| +3, two weapons, 27% hit, behind | 48,445 | 30.60% | 21.81% | 1.01% | 0% | 6.43% | 0% | 40.15% | ~35.02% |
| +3, two weapons, 28% hit, behind | 5,398 | 31.70% | 22.05% | 0% | 0% | 6.58% | 0% | 39.68% | ~35.23% |

The wiki also lists a "+3, +9 skill" result filed as one weapon with an 18.93% miss rate. That fits a dual-wielding rogue (the 19% penalty), not one weapon, and the page doesn't explain it, so it is left out.

### Forever logs

The author's own combat logs from WoW Forever, written by the game with `/combatlog` and read with a script; no game memory or files were changed. Each line of the log gives the attacker's and target's level, so every swing at a monster of known level can be compared with the formulas above. Attack Table's stat snapshots, saved at the start of each fight, give the character's weapon skill, hit, crit and defense at that moment (**Measured** throughout this section).

| Logs | Builds | What they hold |
|---|---|---|
| November 4–6, 2026 (13 logs) | 1.60.1.70790 | Two characters with one weapon, levels 1–8: 1,366 white swings at monsters of known level. Every player in view: 27,155 white swings at monsters |
| November 6–9, 2026 (18 logs) | 1.60.1.70840 and 70862 | Five characters at levels 1–13: 2,027 white swings at monsters and 2,458 monster white swings at them. Every player in view: 18,811 landed monster swings at players |

#### Your swings

Predicted values add up the formulas swing by swing, using the character's weapon skill at that moment.

| Result | November 4–6, predicted | Logged | November 6–9, predicted | Logged |
|---|---|---|---|---|
| White swings | | 1,366 | | 2,027 |
| Miss | 34.1 | 36 | 55.4 | 58 |
| Dodge, with the below-level-10 rule | 38.9 | 34 | 63.2 | 56 |
| Parry, with the same rule | 36.8 | 41 | 49.2 | 47 |
| Block, with the same rule | 35.6 | 34 | 48.6 | 33 |
| Glancing | 190.1 | 181 | 87.7 | 90 |
| Crit | 66.3 | 69 | 149.7 | 165 |
| Crit damage | 2× | 2.00× | | |

Everything fits except blocks in the later logs, 33 against 48.6, for a reason the logs do not show; blocks also ran low in the earlier logs from other players (below). Characters' weapon skill often lagged behind the most their level allowed, which is why glancing shows up even against lower-level monsters.

#### Monsters below level 10

Below level 10, monsters dodge, parry and block less, in step with their level, just as they cause fewer misses. The Classic sources give this rule for miss only. Every player's white swings at monsters in the first 13 logs, where the log gives the monster's level (other players' hit and weapon skill are unknown, so this shows the trend, not exact chances):

| Monster level | Swings | Miss | Dodge | Parry | Block | 5% × level ÷ 10 |
|---|---|---|---|---|---|---|
| 1 | 2,090 | 0.0% | 0.3% | 0.2% | 0.7% | 0.5% |
| 2 | 1,535 | 0.7% | 0.9% | 1.4% | 1.4% | 1.0% |
| 3 | 2,234 | 1.3% | 1.4% | 1.7% | 1.2% | 1.5% |
| 4 | 1,451 | 2.3% | 2.0% | 2.8% | 2.6% | 2.0% |
| 5 | 1,036 | 0.9% | 1.6% | 2.4% | 2.1% | 2.5% |
| 6 | 1,461 | 2.9% | 2.4% | 3.1% | 2.4% | 3.0% |
| 7 | 1,267 | 4.1% | 3.0% | 3.2% | 2.8% | 3.5% |
| 8 | 599 | 3.8% | 4.2% | 4.3% | 3.8% | 4.0% |
| 9 | 160 | 4.4% | 6.2% | 1.9% | 6.9% | 4.5% |
| 10 | 208 | 8.2% | 8.2% | 6.2% | 3.4% | 5.0% |

| Totals, levels 1 to 9 (11,833 swings) | Miss | Dodge | Parry | Block |
|---|---|---|---|---|
| Logged | 206 | 205 | 243 | 226 |
| With the rule | 234 | 234 | 234 | 234 |
| A flat 5% | 592 | 592 | 592 | 592 |

The rule still held after the November 6 client update: every player's 937 white swings at monsters of logged level 1 to 9 in the first five later logs gave 22 misses, 19 dodges, 25 parries and 11 blocks, where the rule predicts 23 of each and a flat 5% 47. Blocks ran low, 11 against 23. In the later logs, one character's swings at monsters of levels 1–5 were dodged 0.5% of the time, against 4.8% without the rule and 1.4% with it. The rule stops at level 10.

**Parry by level gap** (the November 4–6 logs, raw counts). These mostly follow the monster's own level, as above, rather than the gap:

| Monster level compared with you | Shaman swings | Shaman parries | Warrior swings | Warrior parries |
|---|---|---|---|---|
| 1 lower | 130 | 1 | 244 | 4 |
| Same | 221 | 9 | 225 | 7 |
| 1 higher | 137 | 2 | 57 | 3 |
| 2 higher | 133 | 14 | 25 | 0 |

**Front or behind:** the log shows this for landed swings, from the attacker's and monster's positions and the monster's facing. It gives no positions for parries or other avoided swings, so those take theirs from the nearest landed swings. Where the swings on both sides put the attacker more than 120° off the monster's nose, 3 of 226 swings were parried, about what a monster's front gives at those levels. A looser count, using any landed swing within 2.5 seconds, finds 26 parries and 27 blocks in 2,090 swings from behind. Five logs from November 6 and 7 give a stronger hint: 5 parries where both neighbouring swings were from behind, against 51 landed swings there, when a monster's front would give about 2; the looser count finds 9 parries and 6 blocks in 459 swings. All of this fits Blizzard's bug report that monsters can parry and block from behind, but none of it pins down the moment of the parry (**Not confirmed**).

**Damage lost per glance** fits the formula once monster armor is taken out (181 glances, the November 4–6 logs; armor removed with Classic's armor formula using each monster's logged armor):

| Target defense minus weapon skill | Glances | Formula | Logged, corrected for armor |
|---|---|---|---|
| Under 5 | 59 | 5.0% | 4.6% |
| 5 to 9 | 57 | 5.8% | 2.9% |
| 10 to 14 | 53 | 20.2% | 19.3% |
| 15 or more | 12 | 50.7% | 46.3% |

#### Monsters' swings at you

Monster misses, your dodge, parry and block against them, and crushing blows all fit the formulas in [Monsters' attacks on you](#monsters-attacks-on-you). For a warrior with a shield, over 1,015 swings: miss 5.8% logged against 5.4% predicted, dodge 7.5% against 7.9%, parry 4.6% against 5.4%, block 6.8% against 6.0%. Crushing blows: 4 where 6.9 were expected, all on a character whose defense lagged.

#### Monsters rarely crit

Forever's monsters crit far less often than the 5% Classic formula, at monster levels 1 to 14:

| Swings | Landed | Crits | Rate | 95% range |
|---|---|---|---|---|
| Every player in view, any gap | 18,811 | 19 | 0.10% | 0.06% to 0.16% |
| The author's characters, gap under 10 | 2,063 | 0 | 0% | 0% to 0.18% |
| The author's characters, gap 10 or more | 57 | 3 | 5.3% | 1.1% to 14.6% |

If the rate were 5%, 0 crits in 2,063 swings would happen about once in 10⁴⁶ tries, so the Classic rate does not hold here. The crit flag is read correctly: players' own crits are 7% of their landed swings in the same logs, and monsters' crushing blows appear (24).

Crits do happen once your defense falls well behind: 3 in 57 swings, mostly on a character whose defense lagged its level, which fits Classic's 5% (3 or fewer would happen 68% of the time). The cutoff of 10 was picked after looking at the data, so the true line may be anywhere from about 5 to 15, and these swings cannot tell a defense gap from a higher-level monster.

Blizzard confirms that monsters can crit in Forever: the [Deep Dive Panel Recap](https://news.blizzard.com/en-us/article/24303313/world-of-warcraft-forever-deep-dive-panel-recap) redesigns Reckoning "to work for tanks who are immune to critical hits", and the [October 8 development notes](https://us.forums.blizzard.com/en/wow/t/2360696/5) fix Rage "from taking critical strikes or crushing blows" (**Blizzard**). No Blizzard post, simulator or fan site gives a Forever chance; a search on November 9, 2026 found none.

## What WoW Forever changes

| Topic | Forever | Mark |
|---|---|---|
| Table against +3 targets | 8% miss, 6.5% dodge, 14% parry, 40% glancing, 5% block in a 3,644-attack test: the same as Classic. Not at level 60 against a real boss | **Measured**, [gunba CORE-001](https://github.com/gunba/wow-forever-sim/blob/forever/docs/uncertainties.md#core-001) |
| Monsters below level 10 | Miss, dodge, parry and block all scale with monster level ÷ 10 | **Measured**, [Forever logs](#monsters-below-level-10) |
| Monster crits on you | Almost none at levels 1–14 while your defense keeps up | **Measured**, [Forever logs](#monsters-rarely-crit) |
| Hit suppression | Gone: every point of hit counts; the one-weapon boss hit cap is 8% | **Measured**, 4,259 attacks, same summary |
| Crit suppression against +3 | Still there | **Measured**, same summary |
| Glancing damage | Damage lost per glance against higher-level targets is a known bug; about 24.6% at +3 | **Blizzard**, [known issues](https://us.forums.blizzard.com/en/wow/t/2352687); **Measured**, same summary |
| Parry and block from behind | Monsters can parry and block from behind at very close range, a bug | **Blizzard**, [known issues, October 1](https://us.forums.blizzard.com/en/wow/t/2352687/6) |
| Racial weapon skill | Gone: Human Sword Specialization became Ruthless (+1% crit); the Orc and Dwarf weapon racials were removed | **Blizzard**, [October 15 notes](https://eu.forums.blizzard.com/en/wow/t/631316/6) and [October 26 notes](https://us.forums.blizzard.com/en/wow/t/2360696/7) |
| Items with weapon skill | Give less per item; Edgemaster's Handguards reported at +1 instead of +7 | **Blizzard**, [Deep Dive Panel Recap](https://news.blizzard.com/en-us/article/24303313/world-of-warcraft-forever-deep-dive-panel-recap); **Not confirmed** for +1 ([Warcraft Tavern](https://www.warcrafttavern.com/forever/news/weapon-skills-in-world-of-warcraft-forever/)) |
| Dodge and parry reduction | Some items reduce your chance to be dodged or parried; a flask's expertise aura removes 5% dodge | **Blizzard**, same recap; **Datamined**, [tzcnt README](https://github.com/tzcnt/WarriorSim/blob/master/data/forever/README.md) |
| Dual wield | Queued Heroic Strike no longer raises off-hand hit; Furious Precision gives off-hand hit | **Blizzard**, [October 1 notes](https://eu.forums.blizzard.com/en/wow/t/631316/4) |
| Crits in PvP | No longer have reduced efficacy; affects player targets only | **Blizzard**, [October 8 notes](https://eu.forums.blizzard.com/en/wow/t/631316/5) |
| Ruthless crit | Unknown whether it counts as aura crit | **Not confirmed**: untested |

## How the addon reads your stats

From Blizzard's interface code in [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source): the `forever` branch at 1.60.1 build 70532 (commit `ca8368f`) and the `classic_era` branch at 1.15.9 build 70576 (commit `4192ac6`) (**Datamined**).

| Need | Forever | Classic Era |
|---|---|---|
| Weapon skill | `C_SkillInfo.GetSkillLineInfoByID` (rank and modifier) | `UnitAttackBothHands`, `UnitRangedAttack` |
| Hit | `GetHitModifier`, `GetOffhandHitModifier`, `GetRangedHitModifier`, each plus hit rating from `GetCombatRatingBonus(CR_HIT_MELEE)` or `CR_HIT_RANGED`, as the character sheet adds them | `GetHitModifier` |
| Crit | `GetCritChance`, `GetRangedCritChance` | Same |
| Crit from Agility | `GetCritChanceFromStat(stat, value)`, a fraction the character sheet multiplies by 100 | Not confirmed; the Agility table is used otherwise |
| Expertise | `GetExpertisePercent` (main hand, off hand, ranged) | Exists |
| Glancing chance and damage lost | `GetGlancingBlowChance(skill, defense)` and `GetGlancingBlowPenalty(skill, defense)`, fractions; Blizzard's skills window reads them for a raid boss ([`Camelot/SkillsFrame.lua` L288-290](https://github.com/Gethe/wow-ui-source/blob/9dc84f0/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/SkillsFrame.lua#L288-L290), build 70862) | None; the formulas above |
| Defense, dodge, parry, block | `UnitDefense`, `GetDodgeChance`, `GetParryChance`, `GetBlockChance` | Same |
| Dual wielding | `IsDualWielding` | Same |

**Hidden in combat on Forever:** the hit, crit, rating, expertise, glancing and stat functions are flagged `SecretWhenUnitStatsRestricted`, so Forever hides their values in combat. The addon reads them out of combat and keeps the last values it saw; `C_Secrets.ShouldUnitStatsBeSecret()` tells it when.

**Not a Forever rule:** Forever's character-sheet code also contains fixed miss, dodge and parry tables under the comment "Hit and Expertise are being removed from items". The block is identical to the retail client's and dates from retail's removal of hit from gear.

## Still open

- Monster crits on you at level 60, from elites and bosses, and how they rise once your defense falls behind.
- Whether monsters dodge ranged attacks, and whether Auto Shot's crit can be pushed off. A logged hunter would settle both.
- The table at level 60 against a level 63 boss in Forever, and glancing damage after Blizzard's fix.
- Whether abilities still use a separate crit roll in Forever.
- Whether Ruthless and Forever's crit rating on gear count toward the 1.8%.
- Whether `GetDodgeChance` already includes defense above level × 5.
- The monster table in Classic Era: roll order, crushing chance at +2, and avoidance from behind.

**Testing it yourself:** turn on combat logging (Attack Table's checkbox, or `/combatlog`), log a few thousand swings against monsters of known level, then count the results, the way the classic-warrior wiki's authors tested Classic.

## Sources

| Source | What it gives | Mark |
|---|---|---|
| [classic-warrior wiki: Attack table](https://github.com/magey/classic-warrior/wiki/Attack-table) | Classic formulas and 150,000+ logged swings | **Blizzard** answers and **Measured** |
| [classic-warrior wiki: Crit aura suppression](https://github.com/magey/classic-warrior/wiki/Crit-aura-suppression) | What the boss crit reduction applies to | **Measured** |
| [Forever development notes](https://us.forums.blizzard.com/en/wow/t/2360696) ([EU copy](https://eu.forums.blizzard.com/en/wow/t/631316)) | Forever changes, October 1 to November 2, 2026 | **Blizzard** |
| [Forever known issues](https://us.forums.blizzard.com/en/wow/t/2352687) | Glancing damage bug; parry and block from behind | **Blizzard** |
| [Deep Dive Panel Recap](https://news.blizzard.com/en-us/article/24303313/world-of-warcraft-forever-deep-dive-panel-recap), September 13, 2026 | Weapon skill on items; tanks immune to crits | **Blizzard** |
| [Forever hotfixes](https://news.blizzard.com/en-us/article/24315281/wow-forever-hotfixes-november-6-2026) | No glancing fix as of November 6 | **Blizzard** |
| [gunba/wow-forever-sim](https://github.com/gunba/wow-forever-sim), `forever` branch: `docs/uncertainties.md` (CORE-001, CORE-011), `sim/core/target.go` | Summaries of Forever beta tests; monster crit assumption | **Measured** (summaries), **Simulator** |
| [lovelaced/forever-sim](https://github.com/lovelaced/forever-sim) | Ranged and monster tables, glancing below your level | **Simulator** |
| [wowsims/classic](https://github.com/wowsims/classic) | Roll order, ranged table, base crit | **Simulator** |
| [tzcnt/WarriorSim Forever data](https://github.com/tzcnt/WarriorSim/blob/master/data/forever/README.md) | Expertise aura | **Datamined** |
| [forever-hunter wiki: Ranged Attack Table](https://github.com/classic-hunter/forever-hunter/wiki/Ranged-Attack-Table) | Ranged results | **Not confirmed** |
| [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source) | Blizzard's interface code: character-sheet formulas and the functions the addon calls | **Datamined** |
| [wago.tools `PlayerExpectedStat`](https://wago.tools/db2/PlayerExpectedStat?build=1.60.1.70450) | Agility for 1% crit by class and level | **Datamined** |
| [RankedBoost: Agility](https://rankedboost.com/world-of-warcraft/forever/stats/agility/) | Level-60 Agility values | **Not confirmed** |
| [Warcraft Tavern: weapon skills in Forever](https://www.warcrafttavern.com/forever/news/weapon-skills-in-world-of-warcraft-forever/) | Edgemaster's Handguards at +1 | **Not confirmed** |
| The author's Forever combat logs, November 4–9, 2026 | Everything marked **Measured** with a link to [Forever logs](#forever-logs) | **Measured** |
