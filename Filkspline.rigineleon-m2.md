# Filkspline (Leonardo Riginelli) - Milestone 2

## Role

Experience designer and game lead. I own the main gameplay loop, the core player script, and most of the systems underneath it: the event bus, the game manager (hitstop, round and match progression), the hit effect manager, and the upgrade pool manager. I also wrote the GDD and the outdated architecture md, but the how it talks md is correct.

## What I contributed to the MVP

- The main player script and the core fighting mechanics: hit detection, blocking, hitstun and blockstun, the state machine for grounded/airborne and crouch, and attack chains with gatling cancel windows
- The attack moves themselves (N2, N4, N8, NA, S5, S6, SA, N52), and most recently S8, the overhead move. Attacks are direction dependent.
- The event bus that other systems (UI, hit effects, upgrades) all hook into
- The game manager, handling hitstop, round wins, and the transition into the upgrade draft
- The hit effect manager and the upgrade pool manager
- Fight UI (health bars, round pips, timer, floating damage/block numbers) and the upgrade draft UI (card hand layout, selection, tweens)
- The parallax background art and the shader/visual effects in the fight loop (fog shader, impact tear shader)
- I did not do the art for the health bars or the cards, that's Marlon's work

## What I intend to have built by Milestone 3

- All player animations
- The upgrade system fully set up, with unique cards and effects. 
- Smoother player character with well implemented input buffering.
- Core gameplay loop fully playable end to end with a clear winner
- Cutscenes and Scene transitions set up.
- NPCS in background implemented.
- Special Move Upgrade Property cards and system.
- After the playtest, iterating on the upgrade cards for balance and fun, and looking at other ways of using them.
