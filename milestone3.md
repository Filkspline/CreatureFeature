# Milestone 3 - The Creature's Features

Course: CGRA 359, Milestone 3

## Team summary

| Name | Role | Course | Git username |
|---|---|---|---|
| Leonardo Riginelli | Experience designer, game lead, programming | CGRA 359 | Filkspline |
| Charlotte Brown | Programmer | CGRA 359 | brownchar7 |
| Braden Thomas | Programmer | GAME 390 | Braden-T-Thomas |
| Marlon Gentile | Artist | GAME 390 | Naut-0 |

Individual contribution files: Filkspline.md, brownchar7.md, Braden-T-Thomas.md (TODO: confirm file names and whether Marlon submits one).

Other repos: none. Everything is in one repository. The project is also mirrored on the university GitLab remote.
Submodules: none. Third party addons: Tube and webrtc_native (online play).


## The game

The Creature's Features is a 2D pixel art fighting game made in Godot 4.7. Two players fight in rounds, and between rounds each player drafts upgrade cards that change their moves and stats. Modes are local versus, online versus (Tube and WebRTC), and a single player practice range with a training dummy and a tutorial. It has 11 move resources, 20 upgrade cards, controller and keyboard support, and a hit effect and shader pass for combat feedback.

## Development process

### Strengths and weaknesses of the game

Strengths:
- It is genuinely fun and has a lot of personality.
- It fixes a problem we have with a lot of fighting games, where getting beaten badly ruins the experience. In playtesting, the player who struggled the most still won a few games, and the player who lost did not seem sore about it. Both were happy to see a cool build come together, with multiple cards combining into a fun effect or strategy.
- The menus and the feel of the game work really well, even with the somewhat amateurish art.
- There is a good amount of content: a working local multiplayer mode, a work in progress online mode, and a single player tutorial and practice range.
- The core local multiplayer works well and is the most polished part.

Weaknesses:
- It is janky in places.
- Online multiplayer needs a few more rounds of iteration.
- The practice range does not clearly do everything it needs to, and looks very much like a prototype. It needs iteration.
- A few card combinations and balance points are quite broken.
- The game does not discourage certain kinds of spam well, and does not encourage a variety of play styles.
- Most of these could be improved with more playtesting and iteration.

### How we controlled the process and communication

We started mainly on the Miro board. At that stage everyone needed to be on the same page, so knowing what had to happen and when was crucial. As development moved into polish and iteration, people knew what they had to do, and it became more about telling each other what they were doing and when. From then on we mostly used Discord.

Because we had one main team lead (Leo) and a small group, it was easy to keep everything organised. Instead of handing the "what needs doing when" question to a to-do list, we communicated on Discord consistently and checked up on each other. That also led to a lot more communication and investment in the project.

Planning documents in the repo: GDD.md (scope and playtesting plan), milestone2.md, arch.md and how_it_all_talks.md (architecture and signal flow), gameplay_pass_notes.md, and HANDOFF.md (project rules, outstanding work and traps we already hit).

Work was split by area: gameplay, UI and systems (Leo), upgrades, single player and NPCs (Braden), menus and online (Charlotte), art (Marlon).

### Version control, ticket tracking and branching

- 219 commits from four people over about 14 weeks (17 July to 20 October 2026). Leo 129, Braden 56, Charlotte 22, Marlon 12.
- Work was done on feature branches and merged by pull request. Leo merged most, Braden merged 12 and Charlotte 2.
- Task tracking: planning was done on a Miro board early on, then through Discord check-ins instead of a formal issue tracker or to-do list.

### Best parts as a group

- It gave the game a unique feel with a lot of personality. When you work alone you have to cut a lot of corners just to finish something. With a team you can build an overall vision together and let other people's expression come through and add to the feel of the game.
- We could build off each other's ideas, which was really fun.
- It gave us time to think about the game. If you are constantly developing it, there is little room for retrospect. When you know someone else is still making progress, and you have organised things properly, you can step back and spend time thinking about the game, which was really valuable.
