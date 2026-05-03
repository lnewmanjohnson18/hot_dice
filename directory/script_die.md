# scripts/die.gd

Attached to each `Die` RigidBody3D.

**Roll:** `roll(drop_position)` skips if kept, unfreezes, sets face-parallel starting rotation (random Y only), applies forward Z velocity (-7.5 to -4.5) and forward X angular velocity (-6.0 rad/s). Emits `roll_completed(value: int)` when the body sleeps.

**Face detection:** dot-product of each face normal against world UP; maps result through `FACE_VALUES = [1,6,3,4,5,2]`.

**Selection (kept state):** left-click via `_input_event` toggles `_kept`. When kept: body is frozen (immune to being knocked) and mesh gets a gold surface override material. Un-keeping clears the override; `roll()` unfreezes on next use.

**Public API:** `is_kept()`, `reset_kept()`, `is_rolling()`, `force_stop()`, `get_face_up()`.
