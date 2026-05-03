# scenes/game.tscn

Main gameplay scene. Contains:
- `DirectionalLight3D` + `Camera3D` at (0, 7, 7) on a 45° bird's-eye angle
- `Table` (StaticBody3D) — green felt cylinder (radius 4.2) with a `PhysicsMaterial` (bounce=0, friction=0.8); wall collision and wall visuals are generated at runtime by `table.gd`
- `Dice` (Node3D) — 6 instances of `die.tscn` (Die1–Die6), each parked at Y=-1 until rolled
- `UI` (CanvasLayer) — Roll Dice button (bottom center), ScorePanel VBoxContainer (top center) with RollScoreLabel and TotalScoreLabel

Script: `scripts/game.gd`.
