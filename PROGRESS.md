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

# Open Issues

- Any player after the first cannot lock in dice properly. They slide to the right briefly but then go back to the main play area.
- Any player after the first does not see a roll animation after their first roll.
- If the second player passes back to the first player the first player does not see the option to start their second turn.