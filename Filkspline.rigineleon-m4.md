# Leonardo Riginelli (Filkspline) - Milestone 4

Course: CGRA 359, Milestone 4
Game: The Creature's Features

For this milestone I agreed with the teacher to submit a game design reflection instead of a code one. There is no set format for that, so I have mapped it onto the milestone structure: good game design in place of good code, bad game design in place of bad code, and the code video is a video walking through the game design.

## Mark weights

| Criterion | Weight |
|---|---|
| Design video (in place of code video) | 10 |
| Good game design (in place of good code) | 25 |
| Bad game design (in place of bad code) | 25 |
| Development process | 15 |
| Reflection | 25 |
| Total | 100 |

---

# Milestone 3 summary: The Creature's Features

Course: CGRA 359, Milestone 3

## Team summary

| Name | Role | Course | Git username |
|---|---|---|---|
| Leonardo Riginelli | Experience designer, game lead, programming | CGRA 359 | Filkspline |
| Charlotte Brown | Programmer | CGRA 359 | brownchar7 |
| Braden Thomas | Programmer | GAME 390 | Braden-T-Thomas |
| Marlon Gentile | Artist | GAME 390 | Naut-0 |

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

Work was split by area: gameplay, UI and systems (Leo), upgrades, single player and NPCs (Braden), menus and online (Charlotte), art (Marlon).

### Version control, ticket tracking and branching

- 219 commits from four people over about 14 weeks (17 July to 20 October 2026). Leo 129, Braden 56, Charlotte 22, Marlon 12.
- Work was done on feature branches and merged by pull request. Leo merged most, Braden merged 12 and Charlotte 2.
- Task tracking: planning was done on a Miro board early on, then through Discord check-ins instead of a formal issue tracker or to-do list.

### Best parts as a group

- It gave the game a unique feel with a lot of personality. When you work alone you have to cut a lot of corners just to finish something. With a team you can build an overall vision together and let other people's expression come through and add to the feel of the game.
- We could build off each other's ideas, which was really fun.
- It gave us time to think about the game. If you are constantly developing it, there is little room for retrospect. When you know someone else is still making progress, and you have organised things properly, you can step back and spend time thinking about the game, which was really valuable.

---

# Individual Component

## Good game design

### 1. A negative feedback loop in a classic 2D fighter

My original idea of adding a negative feedback loop to the classic 2D fighting game formula turned out to be a good one. It led to a more fun and camaraderie based style of play. Both players get something out of every interaction no matter what happens, so there is a sense of building something together. If I beat you in a round, I get a point that brings me closer to the final victory, but you also get a new upgrade, so we are both happy with the outcome.

Because of the randomness, and because some synergies are really strong and some do not work out as well, it ends up being quite party gamey, and some of the competitiveness is lost. That is not a necessary part of the negative feedback loop in a fighting game, I just think it works best here because I wanted to focus on entry level players.

### 2. Changes that make the 2D fighter easier to understand

This is where I think a lot of the best design is. There are many small changes, but the main ones are:

- **No cross ups.** The characters look the same, so this means you are never confused about which side you are on. You are on the side of your health bar, which is the side you are sitting on. That is always the case, and it simplifies a player's understanding of positioning a lot.
- **Barrier visuals when walking backwards.** In 2D fighters, walking backwards is how you put yourself in a state where you can block, which is usually not very clear. A barrier appearing whenever you do it makes it obvious.
- **Crouching automatically blocks.** In playtesting I saw a lot of players crouch but not block, or block but not crouch. Forcing those two together simplified the defence loop and made it much more convenient.
- **Not explaining everything.** Overheads and low blocking are still not fully explained, and that is on purpose. If everything is explained to you, you lose the fun of learning how the systems work over time. It is rewarding to learn a fighting game, so leaving some things up to the player is important, especially when it is intuitive. The barrier sits about a foot above the ground, so a hit that goes below that should hit, and it does. The barriers are also angled so that standing block catches aerial attacks, but when you are crouching they look like they would be hit.

### 3. Simple gatlings that reward getting in close

The gatlings are simple and chain into each other. Because of damage scaling and knockback you cannot really combo by spamming, but you can get some quick fun hits in. This is common in fighting games, but this implementation rewards players for getting in close, which takes a lot of risk in the first place. There is also no way to deal a lot of damage at range, which forces players to engage with the defensive gameplay loop.

### 4. Card synergies

A lot of the cards have really fun synergies, and these are baked in simply because in fighting games any sort of advantage is a big advantage. Building synergies around that is really fun. In playtests, when a player got a few specific cards together and could kill the enemy in about 5 hits, they were ecstatic, because they had to pay attention to which cards they picked and what they were doing.

## Bad game design

There is a lot where the implementation is the problem, but at a core level a few things are definitely missing or wrong.

### 1. No variety in the fights aside from the cards

This could be substituted with additional characters, but building a fighting game turns out to be very front loaded on a character's kit, which makes it quite difficult to add more characters later to fill the void. This could have been avoided by researching the genre a bit more, but that is fine.

### 2. Special moves that invite spamming

We simplified the specials so that one of your buttons only does the special move you picked. The problem is that they need to be perfectly tweaked and balanced, otherwise they encourage spamming. For example, in playtests players just kept pressing the button for the slam down move over and over, because it had good range, good damage and was an overhead, so there was almost no way to stop it. That stems from the fact that you only need to press one button, with no other steps.

Compare that to the forward punch normal. It is pretty strong, but it forces you to not be blocking, because to block you need to be holding backwards. That is one of the advantages of a poking tool, since even if you do not press it you are in a block state, while setting yourself up to use the forward punch means you cannot be blocking. This is one of the great advantages of motion inputs in fighting games. For simplicity we removed them on the specials, and that led to the spamming issues.

After some balancing and more playtesting, people realised the specials were each good in very specific situations. The uppercut is a good anti air, which makes players who constantly jump in with aerials respect your space more. The projectile and the bite are very situational, with one being a long range tool and the bite only really being useful up close. That alleviated some of the problems, but it still felt a bit spammy.

### 3. Specials feel like an item instead of part of the moveset

We then made it so you can change your special between rounds, but that is missing the feeling that it is part of the moveset rather than just an item you can spam. This is fixable, but it is also a tightrope. The harder we make it to use, the less new players will like it and be able to use it properly, so it is a balance of new players versus experienced ones.

## Personal reflection

### Scope

Looking at my own group and at other groups, one of the main things to focus on is scope. This is especially hard with new people, because you do not know how much someone else can do. It is also hard when you are trying something new, which is the best way to learn, because you do not know how long it will take in the first place.

For example, I have made quite a few 2D platformers, which are really easy to get started with. In my head a fighting game would be similar, but a fighting game's entire gameplay loop is built around a single character controller, which is a huge amount of front loaded work. A Metroidvania like Hollow Knight starts with one slash in each direction and a jump, and that is kind of it. You can build around that iteratively really easily with game design, level design and new upgrades. With a fighting game it took ages to get a good feeling character controller. A really basic one needs about 5 different moves, and then you also need jumping, blocking, aerial attacks, how it interacts with the other player and how that is sent over the network. All of it is front loaded.

### Working with a group

How that interacts with the rest of the team is really interesting, because you need to understand where you will be at a certain point in time to know whether the others can join in. If your assumptions about how much the others can do are inaccurate, you bottleneck the whole development process. This could be fixed by working with people whose pace you already know, but for a first time interaction it is really difficult to measure.

The way I set it up was to strong arm the development and be very clear about being game lead. I think that worked well, but the development was still bottlenecked through me and how much I could organise and plan.

The group was very good for letting me focus on the main character controller and the other main gameplay loops, with Braden and Marlon working on the implementation and art for the cards. Because the cards only augment the original gameplay loop, I could keep working on that loop without forcing them to stop.

### Art

There is a give and take to having beginner art in the project. I had not animated before, and I think it adds a lot of personality, but it also does not look very professional. With all the new AI technology there is also a fine line between personalisation and manufactured art.

## What I will take forward

- **Organising systems better.** I loved looking into this. Using an event bus to send all the signals and functions through a single place was amazing. Everything became slightly less dependent on every other script, because they all just look to one place. It may have bottlenecked some things, but because it is a 2D game the performance did not take a hit at all. It was a really fun solution to problems I have had in other games, so I will definitely take it forward.
- **Being more creative with the idea.** My previous games were very derivative, because I wanted to practise putting in specific concepts. After this project, I think trying something very new is a much bigger learning experience, because you have to synthesise ideas from other projects. I had to understand fighting games properly to see how I could turn one into a party game. If I recreated an Asteroids style game I would not need to think about why those design decisions were made, but doing something new forces me to really understand what I am doing.

## What I would do differently

- **Multiple characters and a simpler gameplay loop from the start.** 2D fighters are predicated on characterisation, and there is not much you can do to escape that. Even 2 or maybe 3 simplified characters would do well. They could share a lot of the moves, but having unique animations would help a lot.
- **More focus on art.** Fighting games are predicated on the artistic expression of the hits, the power and the way the characters move, which visualise what is happening on screen. It is not like a puzzle or card game where the art is a layer on top, like the cherry on top. Art and animation are integral in a fighting game, and having most of it come through me, with zero animation experience, was not a great idea. The catch is that you need animation students or people who are well trained in it, which is a coin flip in a project like this where you cannot call out for the exact people you need. That said, I think it did really well.
- **A clearer art direction from the start.** Even though the direction felt clear, there were a lot of misunderstandings about the colour palette and specific design details. A sheet with a clear palette, line thicknesses and so on would have saved a lot of discussion and iteration time.
- **Plan online from the beginning.** If I really wanted online, I should have thought about it from the start so rollback could be built in. Fighting games without rollback netcode often struggle to work, because they are based on millisecond differences.
