# Milestone 2 - The Creature's Features

## Team

| Name | Course | Role |
|---|---|---|
| Leonardo Riginelli | CGRA 359 | Experience designer, game lead |
| Charlotte Brown | CGRA 359 | Programmer |
| Marlon Gentile | GAME 390 | Artist |
| Braden Thomas | GAME 390 | Programmer |

**Repositories**

- Everything (code, scenes, assets, design docs) lives in this one repository.

**Engine**

Godot 4.7 

## The game

**The Creature's Features** is a 2D local-multiplayer fighting game. Two players fight in short matches. Whoever loses a round doesn't just get sent back to square one, they get stronger, picking upgrades before the next round. This keeps matches competitive round to round instead of one player always winning due to being more skilled.

**Core loop**

Fight a round, lose or win, on a loss pick upgrades, fight the next round stronger, repeat until someone wins the match. This is what the MVP demonstrates.

**In scope**
- Core fighting mechanics: movement, attacks and specials, hit and hurtboxes
- Round and match structure with win/loss tracking
- Upgrade draft system, applied and kept between rounds
- Local two-player input, keyboard and controller
- Fight UI, hit effects, camera shake, background visuals
- Menu shell (main menu, settings, remapping, player select)
- Possibly a simple delay-based multiplayer mode. This is a stretch goal, not a commitment. One team member seems interested in building it.

**Out of scope**
- A second fully-animated player character. Right now there is one character, mirrored onto both sides. A second fully realised character with its own animations and upgrade interactions is out of scope, it turned out to need a lot more animation work than expected.
- Any additional characters beyond the one
- AI opponent or any single player mode
- Online/networked multiplayer beyond the delay-based stretch goal above

**Relationship to Milestone 1**

The GDD is Leonardo's own. No other team member's Milestone 1 design or technology was brought in.

## The plan

**Internal milestones**

- By the Week 7 playtest: upgrade system set up and functional, main menu set up, core gameplay loop fully working and playable
- Through to the playtest: general animation and code pass-throughs happening alongside the above
- A few weeks after the playtest: finish the main animation sets
- After the playtest: iterate on the upgrade cards to make them fun, look at different ways of using them (for example picking a card at the start instead of it just being tied to round losses)
- See the [Miro task board](https://miro.com/app/board/uXjVH87XTnA=/?moveToWidget=3458764678047571264&cot=14) for the full task-level breakdown, owners, and dates.

**Ownership**

- Leonardo Riginelli: core gameplay programming, move data system, game manager, round/upgrade flow, most in engine visual effects
- Charlotte Brown: camera, controller input, parallax background, menu system
- Braden Thomas: upgrade card UI and the upgrade card effect framework/upgrade system
- Marlon Gentile: character design and art, card frame design, transition art

*[How we catch a stuck owner: TBD, let me know your actual process and I'll fill this in]*

**Version control, branching and ticket tracking**

- Single GitHub repository, owned by Leonardo Riginelli
- Task tracking is done on a Miro board (table view), not GitHub Issues, with status, assignee, dates, and priority per task
- *[Branching model: not written up yet]*

**Definition of done**

Art exists for all the basic cards and move unlocks we want, the end and start menu is functional, and two people can sit down and play a full match against each other.

**Risks**

1. **Scope versus what's actually achievable with University** There's a risk of a gap between the scope we've planned and what the team can realistically finish, As the plan is based on current availability which may be considerably reduced during the more intensive second half of the trimester.
2. **Upgrade balance.** The way the upgrade cards and player setup work could mean a lot of the upgrades end up unbalanced or not fun, which would mean reworking and spending significant time rebalancing and re-animating.
3. **Delay-based multiplayer eating time from elsewhere.** If we go ahead with it, proper netcode integration could take time away from other parts of the game that need it more.

**Negotiated variations**

None at this time.

## The MVP

The build demonstrates the core loop end to end: the main scene (`test_level.tscn`) instances both players, the fight UI, camera, and hit-effect systems, and on round end the `GameManager` autoload transitions to the upgrade card selection scene, applying upgrades that carry into the next round.

**What's real**
- Movement, attack and special execution, hit and hurtbox timing driven by animation tracks and move resources
- Round-end detection and win tracking
- The upgrade draft flow (card UI, pool manager, scene transition) is wired and reachable from a real round loss
- Hit effects, camera shake, and background visuals

**What's faked**
- A developer shortcut (keys 1 and 2) can force-end a round for testing
- Some art assets in the test level are placeholder/mockup images, currently hidden
- Damage values and move balance are not finalised


