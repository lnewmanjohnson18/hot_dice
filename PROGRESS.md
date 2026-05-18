# Progress

- Fixed wall rim mesh (TorusMesh inner/outer radius was making it a solid disk instead of a thin rim).
- Implemented Farkle scoring: straights, three pairs, three-of-a-kind, spare 1s/5s, and FARKLE detection.
- Added click-to-keep mechanic: clicking a settled die toggles a gold highlight and freezes it out of the next roll.
- Built turn structure: Lock In moves kept dice to the side, then Pass (bank score) or Roll Again.
- Added multiplayer lobby with ENet host/join and server-authoritative roll sync.
- Fixed button visibility: Roll Dice / Lock In / Pass / Roll Again were stacking because the hide logic was incorrectly gated on a multiplayer check that always evaluated true.
- Set default IP field value to 127.0.0.1 in multiplayer lobby for easier local testing.
- Fixed turn reset: out-of-play slide tween is now owned by die.gd and killed before roll(), preventing the tween from overriding physics position after passing to the next player.
- Fixed overlapping Roll Dice / Lock In buttons on the non-server client: _set_rolling_state now hides the Roll button, mirroring what _do_roll does on the server.
- Replaced auto-tween camera with two-state mouse-look system: W / scroll-up = Looking at Table (position (0,7,6.5), ±25° yaw, ±15° pitch); S / scroll-down = Standing Up (position (0,3.5,11), ±90° yaw, ±45° pitch). States blend smoothly over 0.45 s; mouse motion always pans within the current limits. Debug camera (Q) still available.
- Added 3D scoreboard on the back wall of the play area showing players sorted by score descending, with the current player highlighted in gold.
- Fixed overlapping Lock In / Pass / Roll Again buttons for non-current players: guarded _enter_selecting, _finish_lock_in, and _trigger_hot_dice with _is_my_turn(), and added full button clear to _set_rolling_state.
- Fixed parse errors after repo rebuild: registered GameConfig, GameManager, and ScoringEngine as autoloads in project.godot.
- Wired ScoringEngine autoload into game.gd: replaced inlined _score_roll() with ScoringEngine.score() at all four call sites and deleted the duplicate method.
- Fixed scoring inconsistency: three pairs now scores 750 (GameConfig.THREE_PAIRS_SCORE) instead of the old hardcoded 1500; four/five/six-of-a-kind with 1s or 5s no longer double-count the extra dice.
- Tightened over-table camera: raised position to (0,10,2) so it looks almost straight down at the felt, and reduced yaw/pitch limits to ±10°.
- Disabled mouse-look in over-table state: mouse motion is ignored when blend=0, and yaw/pitch are reset to zero when transitioning to table so the view is always fixed overhead.
- Camera now smoothly recentres yaw and pitch to zero when transitioning to the over-table state, tweened in parallel with the position blend over 0.45 s.
- Added dice rest state: on scene load and between every turn, dice are placed in three stacks of two in a triangle at the table centre; resting dice have collision disabled so they don't deflect rolling dice, re-enabled when rolled.
- Fixed dice rest positioning: replaced global_transform setter (unreliable on frozen RigidBody3D) with global_position + quaternion; used a downward raycast after the first physics frame to find the actual table surface Y so rest positions are correct regardless of GLB model height; _end_turn refreshes the Y from a settled die each turn.
- Rotated rest-state dice 45° into diamond orientation and repositioned stacks so every adjacent pair shares an exact corner, creating a triangle of open felt in the centre.
- Fixed player 2+ dice selection: place_at() zeros collision layers but die.roll() only runs on the server, so client dice were unclickable; added restore_collision() called in _enter_selecting() so all peers have clickable dice when the selection phase begins.

- Fixed multiplayer lock-in for non-host players: dice now stay in the out-of-play zone instead of snapping back.
- Fixed turn handoff: player 1 now correctly sees the Roll button when player 2 passes back to them.
- Fixed Roll Again button staying disabled after the first use: reset disabled=false whenever the button is made visible in _finish_lock_in and _trigger_hot_dice.
- Dice now slide smoothly back to the center triangle position at the end of every turn instead of snapping.
- Added unlock rule: players must score 1000+ in a single turn before their score counts; scoreboard shows [===locked===] for locked players and a green popup announces when a player gets on the board.

- Fixed bust popup text: busting player sees "You Busted!" while other players see "Player X Busted!".
- Widened 3D scoreboard background by 10% on each side (QuadMesh x from 3.0 to 3.6).
- Added per-seat multiplayer positioning: 6 seats arranged as P1/P2 on front long side, P3 on right short end, P4/P5 on back long side, P6 on left short end. Each player's camera, dice drop zone, dice rest area, and out-of-play pile are all oriented relative to their seat. Dice slide to the incoming player's side at turn end.
- Fixed seat angles to correctly place pairs on long sides and singles on short ends (330°/30°, 90°, 150°/210°, 270°).
- Over-table camera now offsets toward the local player's side so the overhead view is centred on their half of the table.
- Players now look perpendicular to their face rather than at the table centre; look target is computed by snapping the seat angle to the nearest 90° face and projecting the seat position onto that face plane at table height.
- Added Shift+P pip debug mode: clicking any non-rolling die cycles its face value (1→2→…→6→1) by physically rotating the die; blue HUD label indicates the mode is active.
- Fixed camera mouse-look: switched from relative delta to absolute screen position mapping so a given cursor position always corresponds to the same look angle regardless of how the cursor got there.
- Fixed Hot Dice score reset: turn score is now accumulated into _accumulated_turn_score before dice are cleared, so banking after a Hot Dice correctly totals all rolls in the turn.

# Open Issues

- Any player after the first does not see a roll animation after their first roll.
