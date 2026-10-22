# Milestone 1 playtest QA

How it was played: the real game window, driven by `src/flow/dev/playtest_driver.gd`, which
sends genuine mouse clicks and key presses to what's on screen (menu buttons, the board,
enemy mechs, "I'll go" portraits, action bar, Enter to confirm, End Turn) and saves a
screenshot at each step. Launch it yourself with:

```
godot --path . --resolution 1920x1080 -- qa:solo qa_out:C:/some/folder
```

Modes: `qa:solo`, `qa:hotseat`, `qa:host` + `qa:join` (two windows, real online play).
QA campaigns are saved to `user://qa_saves_<mode>/`, never the player's saves. Headless
scripted-input tests (`tests/unit/test_flow_campaign.gd`) cover the same loop for solo,
hot-seat (three battlefields) and online over the in-memory transport.

Screenshots: the shared notes folder for this group of sessions,
`side-session-notes/local_013a0b22-.../qa/` (`run1/`, `run2/`, `run3/`, `online1/`-`online3/`,
`final/`), with each run's log (`*_stdout.txt`, `*_log.txt`). They aren't in the repo (each run
makes 40-60 images).

## Runs

| Run | Mode | Result |
|---|---|---|
| run1 | solo | Whole loop incl. a second mission and Save and quit → Continue. Found F1-F2, F4-F7 and B1-B5. |
| run1 | hot-seat | Soft-lock waiting for the other player's Brace answer (F3). |
| run2 | solo + hot-seat | Soft-lock: turn-order bar off screen, no way to pick (F9, B2). |
| run3 | solo + hot-seat | Both finished (14 turns each, solo through two missions and a resume). Only a momentary hint mismatch (F10). |
| online1-3 | host + friend, two windows, over the internet (PeerJS matchmaking, WebRTC) | Friend joined by room code, both played their own mechs. Found F11, F12, B8. In online3 the friend's window closed mid-battle; the host handed their mech to the AI from the menu and played on. |
| final | solo | Whole loop after all fixes: new campaign, builder, mission 1 to the debrief, level up, spend points, mission 2, Save and quit, Continue, resumed battle. 8 turns, **0 issues**. The only script errors left are B1 (42 per run). |

Loop covered: main menu → new campaign → lobby → builder → mission → battle rounds (move with
the path preview, Skirmish with the hit-chance card, Lock On, Overcharge, Brace and Overwatch
reaction prompts, End Turn, "I'll go") → debrief → level up → spend points in the builder →
next mission → in-battle menu → Save and quit → Continue → the same battle resumes.

## Fixed in this pass (my areas: net, flow, menus, campaign, content)

| # | What happened | Fix |
|---|---|---|
| F1 | Start Mission showed a grey screen: the battle screen stopped compiling after the visuals HUD replaced `RollDisplay`/`SkillCheckPopup` with `RollPopups` (no test loaded the screen). | Battle screen uses `RollPopups`; new `tests/unit/test_flow_screens.gd` fails if any menu or flow screen stops compiling. |
| F2 | The builder let a player raise their own License Level with "+". | LL is shown read-only ("goes up after every mission", Core p.18). |
| F3 | Hot-seat soft-lock: when the engine asked the *other* player at the screen whether to Brace, the screen wasn't passed to them, so the game waited forever (run1/hotseat_50_stuck.png). | The session passes the screen to whichever local player the game waits on (turn or reaction). Hot-seat test now runs three battlefields and fails without the fix. |
| F4 | "Your squad's pick" hint while the turn-order bar still said "Enemies pick next" with no "I'll go" buttons (run1/solo_29_no_ill_go.png). | The battle screen redraws the bar whenever whose pick / who acted changes. |
| F5 | The reaction prompt was a huge empty panel, cut the rule text mid-sentence, and Overwatch quoted the NPC rule ("an NPC may take the skirmish action..."), run1/solo_28 and solo_37. | Uses the player's action text (act_brace, act_overwatch) with its trigger, full sentences, panel sized to its content (run1/hotseat_31 shows the new prompt). |
| F6 | The in-battle menu said "Paused" but the AI kept playing behind it. | The AI waits while the menu is open when everyone is at this screen; online it's titled "Menu" and doesn't pause anyone. |
| F7 | No way to hand your pilot to the AI mid-battle (DESIGN: switch any time). | In-battle menu: "Let the AI fly <callsign>" / "Take back control of <callsign>". |
| F8 | After a level-up nothing in the lobby showed which pilots had points to spend. | Lobby seat rows show "N points to spend". |
| F9 | Turn-order bar slid off the left edge so "I'll go" sat under the Menu button: no way to pick (run2/solo_14_stuck.png). Cause is in the visuals bar (B2). | Workaround: the battle screen re-centers the bar a frame later. |
| F10 | "Your squad's pick" hint appeared while the board was still animating the previous turn, contradicting the bar (run3/solo_15_no_ill_go.png). | The hint waits until the animations finish. |
| F11 | A joining friend's lobby said "YOU" on the host's seat, and its hints ("Press Ready", "Chablis isn't ready") were written for the host (online1/join_02_client_lobby.png). | Rows are turned around for the friend (You / Host), and the hints are rewritten for them. |
| F12 | Online: when a friend dropped out mid-battle, the host could only wait (no time limit, as designed) with no way to go on. | Host's in-battle menu: "Let the AI fly <callsign> until <friend> is back" (and stop it again). |

## For other areas

| # | Area | Steps | Expected | Actual | Screenshot |
|---|---|---|---|---|---|
| B1 | visuals (+ rules for the event format) | Any attack that hits. | Damage pop-up and log show the damage breakdown. | `EventPlayer._damage` (event_player.gd:457) casts `damage_dealt.roll` to a Dictionary, but the rules engine sends it as a number: SCRIPT ERROR on every hit (34 in one mission) and no breakdown. FORMATS.md says `roll` is a Dice.roll record; ARCHITECTURE.md says "roll (before reductions)". Pick one. | log: run2/*_stdout.txt |
| B2 | visuals | Play a few rounds; watch the turn-order bar after updates. | Bar stays centered. | `TurnOrderBar._rebuild()` queue_frees old portraits without removing them, then `_center_box()` (deferred, same frame) measures old + new portraits: the bar slides off the left edge and the "I'll go" buttons end up under the Menu button, so a player can't pick (soft-lock). Fix: `remove_child` before `queue_free` in `_rebuild`. I added a workaround in the battle screen (re-center one frame later); remove it once fixed. | run2/solo_14_stuck.png |
| B3 | visuals | Damage or destroy an unscanned enemy. | Its stats stay "??" (unknown) until scanned. | Shows "HP 0/0 HEAT 0/0": stats are set from filtered events whose hp/total were removed for secrecy, defaulting to 0. | run1/hotseat_31_reaction_prompt.png (Placeholder Controller 4), run2/solo_14_stuck.png |
| B4 | visuals | Look at enemy portraits in the turn-order bar. | Readable names. | Long names are clipped at the start ("eholder Assa", "aining Drone"). Clip the end or ellipsize. | run1/solo_10_move_preview.png |
| B5 | visuals | Units close together; Lock On applied. | Labels readable. | 3D name/stat labels, status words (ENGAGED BRACED LOCK) and the "+ LOCK ON" pop text overlap each other and the turn-order bar. | run1/solo_29_no_ill_go.png |
| B6 | visuals (process) | Merge a HUD class rename. | Callers keep working. | The rename broke the flow battle screen silently (F1). `test_flow_screens.gd` now catches this; please run the full tests after HUD API changes. | — |
| B8 | visuals | Online or hot-seat: it's the squad's pick and another player's mech is waiting. | Only mechs you may send ("I'll go": yours or AI squadmates) show the button. | Every squad portrait shows "I'll go"; clicking another player's mech is refused with a banner. TurnOrderBar needs a per-unit "can_pick" flag; the battle screen can pass it. | online1/host_14_stuck.png |
| B7 | visuals | Start of your turn, before moving the mouse. | No card until you hover something. | Earlier staged screenshots showed the Brace hover card open at turn start. Not reproduced in the driven runs (the driver moves the mouse first). | (staged screenshot from the flow session) |

## Design questions (for the main session / user)

- **Picking AI squadmates:** in solo, every activation of an AI squadmate needs an "I'll go"
  click (as designed: "in solo you pick"). With three AI squadmates that's many clicks per
  round. Option: a lobby/battle toggle "AI squadmates go on their own after my pilots" for
  players who don't want to sequence them.
- **Long first approach:** on 20-40 space maps the first two turns are mostly moving (weapons
  greyed out, out of range). Fine by the book; maybe shorter deployment distance or a hint
  ("Out of range: move closer or Boost").

---

# QA pass 2 (everything merged: story, world, rules, visuals)

Real window, driven by `src/flow/dev/playtest_driver.gd` (new mode `qa:story`: main menu →
new story campaign → session zero → hub (sector map, codex, a conversation, the hub menu) →
builder (look creator, paint randomize, automation list) → job board → briefing → deploy →
battle (GM environment announcement, "Call for terms", squad picks, moves, attacks, Overcharge,
reactions) → debrief → level up → downtime → Save and quit → Continue). Screenshots:
`side-session-notes/.../qa/qa2_story_f/` (final story run), `qa2_hotseat/`, earlier attempts
`qa2_story` .. `qa2_story_e` show the bugs below.

| Run | Mode | Result |
|---|---|---|
| qa2_story → _e | solo story | Found Q1-Q4 (and two driver gaps: scroll into view, click Continue on GM narration). |
| qa2_story_f | solo story | Whole loop after fixes: session zero to Continue, 6 turns, **0 issues, 0 script errors**. Continue reopened the hub in downtime at LL1. |
| qa2_hotseat | hot-seat (lobby, missions only) | 12 turns, two players at one screen, **0 issues, 0 script errors**. |
| online | loopback (in-memory transport, headless) | `test_flow_story_online` (friend joins the hub, sends a build, follows into the battle, gets the debrief) and `test_flow_campaign` online battle: pass. A two-window internet run wasn't repeated this pass (done in pass 1). |

Not exercised by the driver this pass (its turns are simple: move, attack, Lock On,
Overcharge): terrain destruction, flyers, a pilot on foot, an actual parley dialogue (the early
"Call for terms" was refused with the book's reason, as it should be), extraction/recon sitreps
in the window (covered by `test_gm_sitreps`).

## Fixed in pass 2 (my areas)

| # | What happened | Fix |
|---|---|---|
| Q1 | Pressing Esc to close the hub's Codex also opened the hub Menu; its dim layer then swallowed clicks, so the conversation underneath couldn't be answered (qa2_story_c/story_09). | The hub menu ignores Esc while the Codex is open. |
| Q2 | Space advances a conversation, but it also "pressed" the focused hub Menu button, opening the menu mid-conversation (qa2_story_d/story_09). | Menu (hub and battle) and "Call for terms" are mouse-only (no keyboard focus). |
| Q3 | In story battles every pilot sitting in their mech appeared again in the turn-order bar with its own "I'll go" (8 squad portraits for 4 mechs; qa2_story_e/story_20). | The bar lists only units on the board. |
| Q4 | Those mounted pilots also got a second nameplate ("HP 6/6 HEAT 0/0") on top of their mech's. | Pilots inside their mechs aren't drawn until they get out (or the mech is wrecked, Core p.74). |
| Q5 | The hub's room code label shared the bottom-left row with the HUD's "Map (M)" button and would overlap it when hosting. | Moved above the Menu button. |

## For other areas (pass 2)

| # | Owner | Steps | Expected | Actual | Screenshot |
|---|---|---|---|---|---|
| C1 | story / visuals | New story campaign, walk the hub; camera close to NPCs. | Readable name labels. | NPC name and title labels are huge at close range ("Antonia Wiltsey-Bauswell / Commissioner") and cover a third of the screen. | qa2_story_b/story_14_job_board.png |
| C2 | story | New story campaign with 4 pilots. | "Start the campaign" visible. | It's below the fold of the session zero page; nothing says to scroll. | qa2_story/story_09_talk_stuck.png |
| C3 | visuals | Story battle with 6+ enemies. | Readable enemy names in the turn-order bar. | Still clipped at the start ("eholder Contr"): pass-1 B4 is open. | qa2_story_f/story_27_my_turn_2.png |
| C4 | visuals | Any battle. | Bar stays centered. | Fixed by visuals (the bar centers itself); the battle-screen workaround is removed. | — |
| C5 | story | Talk to an NPC. | Clear way out. | Questions loop back to the same menu; the way out is the last option only (fine, but a "Leave" label or Esc to leave would help new players). | qa2_story_f/story_08_talk_choice.png |

Pass-1 B1 (damage roll SCRIPT ERROR on every hit) no longer happens: 0 script errors in pass 2.

## Top 10 by player impact (pass 2)

1. Q1 Esc on the Codex opened the menu and blocked the conversation (soft-lock feel). **Fixed.**
2. Q3 Mounted pilots in the turn-order bar: doubled squad, confusing "I'll go" choices. **Fixed.**
3. Q2 Space opening the menu mid-conversation. **Fixed.**
4. C1 Huge hub NPC labels covering the screen (story/visuals).
5. Q4 Duplicate pilot nameplates over mechs. **Fixed.**
6. C2 Session zero's Start button hidden below the fold with a full squad (story).
7. C3 Clipped enemy names in the turn-order bar (visuals, still open from pass 1).
8. C5 Conversations: leaving is only the last option (story).
9. C4 Turn-order bar centering still needs the battle-screen workaround (visuals).
10. Q5 Room code label overlapping the hub's Map button when hosting. **Fixed.**
