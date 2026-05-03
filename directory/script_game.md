# scripts/game.gd

Attached to the `Game` node. Owns all roll flow and Farkle scoring.

**State:** `_dice_done`, `_rolling_count` (non-kept dice in current roll), `_roll_values`, `_total_score`, `_roll_finished`, `_roll_gen` (generation counter to invalidate stale SceneTreeTimers).

**Roll flow:** `_on_roll_button_pressed` → `_do_roll` → calls `die.roll()` on each non-kept die, starts a 3 s safety timer. Each die emits `roll_completed`; when `_dice_done == _rolling_count`, `_finish_roll` scores and updates UI. Timer uses a captured generation int to avoid cutting short the next roll.

**Scoring (`_score_roll`):** straight 1–6 = 1500, three pairs = 1500, three-of-a-kind base × (count−2), spare 1s = 100 each, spare 5s = 50 each. Returns 0 for FARKLE.

**Multiplayer:** server-authoritative. Clients call `request_roll` RPC; server runs physics and broadcasts result via `_sync_roll_result`. Dice positions streamed via per-die `MultiplayerSynchronizer`.
