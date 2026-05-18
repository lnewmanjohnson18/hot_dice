extends Node3D

# Seat angles (radians from +Z, clockwise).
# P1, P2 share the front long side (±30° from front).
# P3 is the right short end (90°).
# P4, P5 share the back long side (150°, 210°).
# P6 is the left short end (270°).
const SEAT_ANGLES: Array[float] = [
	11.0 * PI / 6.0,   # P1 — front-left  (330°)
	PI / 6.0,          # P2 — front-right  (30°)
	PI / 2.0,          # P3 — right end    (90°)
	5.0 * PI / 6.0,    # P4 — back-right  (150°)
	7.0 * PI / 6.0,    # P5 — back-left   (210°)
	3.0 * PI / 2.0,    # P6 — left end    (270°)
]

# Base drop positions for seat 0 (front player, angle = 0).  Rotated per seat.
const _BASE_DROP: Array[Vector3] = [
	Vector3(-0.6, 3.5, 3.2), Vector3(0.0, 3.5, 3.2), Vector3(0.6, 3.5, 3.2),
	Vector3(-0.5, 3.5, 3.4), Vector3(0.0, 3.5, 3.4), Vector3(0.5, 3.5, 3.4),
]

@onready var _dice: Array = $Dice.get_children()
@onready var _camera: Camera3D           = $Camera3D
@onready var _roll_button: Button        = $UI/RollButton
@onready var _lock_in_button: Button     = $UI/LockInButton
@onready var _pass_button: Button        = $UI/PassButton
@onready var _roll_again_button: Button  = $UI/RollAgainButton
@onready var _roll_label: Label          = $UI/ScorePanel/RollScoreLabel
@onready var _turn_label: Label          = $UI/ScorePanel/TurnScoreLabel
@onready var _total_label: Label         = $UI/ScorePanel/TotalScoreLabel
@onready var _bust_popup: Panel          = $UI/BustPopup
@onready var _bust_label: Label          = $UI/BustPopup/BustLabel
@onready var _hot_dice_popup: Panel      = $UI/HotDicePopup
@onready var _unlock_popup: Panel        = $UI/UnlockPopup
@onready var _unlock_label: Label        = $UI/UnlockPopup/UnlockLabel
@onready var _scoreboard: Node3D         = $Scoreboard

var _dice_done := 0
var _rolling_count := 0
var _roll_values: Array[int] = []
var _roller_id := 0
var _player_ids: Array[int] = []
var _current_player_idx := 0
var _scores: Dictionary = {}
var _roll_finished := false
var _roll_gen := 0

var _accumulated_turn_score := 0
var _player_seat: Dictionary = {}   # player_id -> seat index (0-5)
var _local_seat_idx := 0
var _unlocked_players: Array[int] = []
var _out_of_play_slots := {}  # die -> slot index
var _next_slot := 0
var _debug_cam_active := false
var _debug_pip_active := false
var _debug_label: Label
var _debug_pip_label: Label

# ── Camera state ──────────────────────────────────────────────────────────────
# _cam_blend: 0 = Looking at Table, 1 = Standing Up
var _cam_blend := 0.0
var _cam_yaw   := 0.0   # radians, offset from center
var _cam_pitch := 0.0   # radians, offset from center
var _cam_blend_tween: Tween

const _CAM_TABLE_LOOK    := Vector3(0.0,  0.0,  0.0)
const _CAM_TABLE_YAW_LIM := 10.0   # degrees ±
const _CAM_TABLE_PIT_LIM := 10.0   # degrees ±

const _CAM_STAND_YAW_LIM := 90.0   # degrees ±
const _CAM_STAND_PIT_LIM := 45.0   # degrees ±

const _CAM_BLEND_SPEED   := 0.45   # seconds

const _DEBUG_ORBIT_SPEED := 1.5  # rad/s — W/S elevation along circular path
const _DEBUG_YAW_SPEED   := 1.5  # rad/s — A/D look direction
const _DEBUG_PAN_SPEED   := 5.0  # units/s — arrow key X/Y translate

# ── Dice rest state ───────────────────────────────────────────────────────────
var   _rest_y    := 0.22  # updated via raycast after first physics frame
const _REST_STEP := 0.40  # vertical offset per stacked die


func _ready() -> void:
	_debug_label = Label.new()
	_debug_label.text = "DEBUG CAMERA  [Q to exit]\nW/S orbit  A/D look  Arrows pan"
	_debug_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	_debug_label.add_theme_font_size_override("font_size", 15)
	_debug_label.position = Vector2(10, 10)
	_debug_label.visible = false
	$UI.add_child(_debug_label)

	_debug_pip_label = Label.new()
	_debug_pip_label.text = "PIP DEBUG  [Shift+P to exit]\nClick a die to increment its face"
	_debug_pip_label.add_theme_color_override("font_color", Color(0.35, 0.75, 1.0))
	_debug_pip_label.add_theme_font_size_override("font_size", 15)
	_debug_pip_label.position = Vector2(10, 10)
	_debug_pip_label.visible = false
	$UI.add_child(_debug_pip_label)

	for die in _dice:
		die.roll_completed.connect(_on_die_roll_completed)
		die.selection_changed.connect(_on_die_selection_changed)
		die.debug_clicked.connect(func(): _on_die_debug_clicked(die))
	_lock_in_button.visible = false
	_pass_button.visible = false
	_roll_again_button.visible = false
	_hot_dice_popup.visible = false
	_unlock_popup.visible = false
	await get_tree().physics_frame
	_detect_rest_y()
	_reset_dice_to_rest(0)
	_setup_multiplayer()
	_init_players()


func _init_players() -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		if multiplayer.is_server():
			var ids: Array[int] = [1]
			ids.append_array(multiplayer.get_peers())
			_sync_player_ids.rpc(ids)
		# clients receive _sync_player_ids from server
	else:
		_player_ids = [0]
		_player_seat[0] = 0
		_local_seat_idx = 0
		_scores[0] = 0
		_unlocked_players.clear()
		_update_turn_ui()
		_update_scoreboard()


@rpc("authority", "call_local", "reliable")
func _sync_player_ids(ids: Array[int]) -> void:
	_player_ids = ids
	_player_seat.clear()
	for i in _player_ids.size():
		_player_seat[_player_ids[i]] = i
		_scores[_player_ids[i]] = 0
	_local_seat_idx = _player_seat.get(multiplayer.get_unique_id(), 0) as int
	_unlocked_players.clear()
	_update_turn_ui()
	_update_scoreboard()


func _current_player_id() -> int:
	return _player_ids[_current_player_idx]


func _is_my_turn() -> bool:
	var cid := _current_player_id()
	return cid == 0 or cid == multiplayer.get_unique_id()


func _update_turn_ui() -> void:
	var my_turn := _is_my_turn()
	_roll_button.visible = my_turn
	_roll_button.disabled = false
	_total_label.text = "Total: %d" % _scores.get(_current_player_id(), 0)
	if not my_turn:
		_roll_label.text = "Player %d's turn" % _current_player_id()


func _rot_y(v: Vector3, a: float) -> Vector3:
	return Vector3(v.x * cos(a) + v.z * sin(a), v.y, -v.x * sin(a) + v.z * cos(a))

func _seat_stand_pos(seat_idx: int) -> Vector3:
	var a := SEAT_ANGLES[seat_idx]
	return Vector3(sin(a) * 11.0, 6.75, cos(a) * 11.0)

func _seat_throw_dir(seat_idx: int) -> Vector3:
	var a := SEAT_ANGLES[seat_idx]
	return Vector3(-sin(a), 0.0, -cos(a))

func _seat_stand_look(seat_idx: int) -> Vector3:
	# Players look perpendicular to their face, not at the table center.
	# Snap seat angle to nearest 90° to find the outward face normal, then
	# project the standing position onto that face plane at table height.
	var pos := _seat_stand_pos(seat_idx)
	var a := SEAT_ANGLES[seat_idx]
	var face_a := round(a / (PI * 0.5)) * (PI * 0.5)
	var fn := Vector3(sin(face_a), 0.0, cos(face_a))
	var d := pos.x * fn.x + pos.z * fn.z
	return Vector3(pos.x - fn.x * d, 0.5, pos.z - fn.z * d)

func _seat_drop_positions(seat_idx: int) -> Array[Vector3]:
	var a := SEAT_ANGLES[seat_idx]
	var result: Array[Vector3] = []
	for p: Vector3 in _BASE_DROP:
		result.append(_rot_y(p, a))
	return result


func _toggle_debug_pip() -> void:
	_debug_pip_active = not _debug_pip_active
	_debug_pip_label.visible = _debug_pip_active
	for die in _dice:
		die.set_debug_pip(_debug_pip_active)


func _on_die_debug_clicked(die: RigidBody3D) -> void:
	var next: int = (die.get_face_up() % 6) + 1
	die.force_face(next)


func _setup_multiplayer() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	for die in _dice:
		var config := SceneReplicationConfig.new()
		config.add_property(NodePath(".:position"))
		config.property_set_replication_mode(
				NodePath(".:position"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
		config.property_set_spawn(NodePath(".:position"), true)
		config.add_property(NodePath(".:quaternion"))
		config.property_set_replication_mode(
				NodePath(".:quaternion"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
		config.property_set_spawn(NodePath(".:quaternion"), true)
		var sync := MultiplayerSynchronizer.new()
		sync.root_path = NodePath("..")
		sync.replication_config = config
		die.add_child(sync)


# ── Roll initiation ──────────────────────────────────────────────────────────

func _on_roll_button_pressed() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_roll_button.disabled = true
		request_roll.rpc_id(1)
	else:
		_do_roll(1 if multiplayer.has_multiplayer_peer() else 0)


@rpc("any_peer", "reliable")
func request_roll() -> void:
	if not multiplayer.is_server():
		return
	_do_roll(multiplayer.get_remote_sender_id())


func _do_roll(roller_id: int) -> void:
	_rolling_count = 0
	for die in _dice:
		die.set_selectable(false)
		if not die.is_kept():
			_rolling_count += 1
	if _rolling_count == 0:
		return

	_roller_id = roller_id
	_dice_done = 0
	_roll_values.clear()
	_roll_finished = false

	_roll_button.visible = false
	_lock_in_button.visible = false
	_pass_button.visible = false
	_roll_again_button.visible = false
	_roll_label.text = "Rolling..."

	if multiplayer.has_multiplayer_peer():
		_set_rolling_state.rpc(true, roller_id)

	var seat_idx: int = _player_seat.get(_roller_id if _roller_id != 0 else _current_player_id(), 0)
	var drops: Array[Vector3] = _seat_drop_positions(seat_idx)
	var throw_dir := _seat_throw_dir(seat_idx)
	for i in _dice.size():
		var pos: Vector3 = drops[i]
		pos.x += randf_range(-0.08, 0.08)
		pos.z += randf_range(-0.08, 0.08)
		_dice[i].roll(pos, throw_dir)

	_roll_gen += 1
	var gen := _roll_gen
	get_tree().create_timer(3.0).timeout.connect(func(): _on_roll_timeout(gen))


@rpc("authority", "call_local", "reliable")
func _set_rolling_state(rolling: bool, roller_id: int) -> void:
	_roll_button.disabled = rolling
	if rolling:
		_roll_button.visible = false
		_lock_in_button.visible = false
		_pass_button.visible = false
		_roll_again_button.visible = false
		var is_me := roller_id == multiplayer.get_unique_id()
		_roll_label.text = "%s rolling..." % ("You" if is_me else "Player %d" % roller_id)


# ── Roll completion ──────────────────────────────────────────────────────────

func _on_die_roll_completed(value: int) -> void:
	if _roll_finished:
		return
	_roll_values.append(value)
	_dice_done += 1
	if _dice_done == _rolling_count:
		_finish_roll()


func _on_roll_timeout(gen: int) -> void:
	if gen != _roll_gen or _roll_finished:
		return
	for die in _dice:
		if die.is_rolling():
			die.force_stop()
			_roll_values.append(die.get_face_up())
	_finish_roll()


func _finish_roll() -> void:
	if _roll_finished:
		return
	_roll_finished = true
	var roll_score := ScoringEngine.score(_roll_values)
	if multiplayer.has_multiplayer_peer():
		_sync_roll_result.rpc(_roller_id, roll_score)
	else:
		_apply_roll_result(0, roll_score)


@rpc("authority", "call_local", "reliable")
func _sync_roll_result(roller_id: int, roll_score: int) -> void:
	_apply_roll_result(roller_id, roll_score)


func _apply_roll_result(roller_id: int, roll_score: int) -> void:
	if roll_score == 0:
		_show_bust_popup(roller_id)
	else:
		_roll_label.text = "Roll: +%d" % roll_score if roller_id == 0 \
				else "%s: +%d" % [_roller_name(roller_id), roll_score]
		_enter_selecting()


func _trigger_hot_dice() -> void:
	_accumulated_turn_score += _score_kept()
	_hot_dice_popup.visible = true
	get_tree().create_timer(2.5).timeout.connect(func() -> void:
		_hot_dice_popup.visible = false
		_out_of_play_slots.clear()
		_next_slot = 0
		for die in _dice:
			die.reset_kept()
			die.set_selectable(false)
		if _is_my_turn():
			_pass_button.visible = true
			_roll_again_button.visible = true
			_roll_again_button.disabled = false
	)


func _show_bust_popup(roller_id: int) -> void:
	var is_me := roller_id == 0 or \
			(multiplayer.has_multiplayer_peer() and roller_id == multiplayer.get_unique_id())
	_bust_label.text = "You Busted!" if is_me else "Player %d Busted!" % roller_id
	_bust_popup.visible = true
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		_bust_popup.visible = false
		_current_player_idx = (_current_player_idx + 1) % _player_ids.size()
		_end_turn()
	)


func _roller_name(roller_id: int) -> String:
	var is_me := multiplayer.has_multiplayer_peer() and roller_id == multiplayer.get_unique_id()
	return "You" if is_me else "Player %d" % roller_id


# ── Selection phase ──────────────────────────────────────────────────────────

func _enter_selecting() -> void:
	var my_turn := _is_my_turn()
	for die in _dice:
		if not die.is_kept():
			die.restore_collision()
			die.set_selectable(my_turn)
	if my_turn:
		_lock_in_button.visible = true
		_lock_in_button.disabled = _score_kept() == 0
	_turn_label.text = "Turn: %d" % _total_turn_score()


func _kept_values() -> Array[int]:
	var vals: Array[int] = []
	for die in _dice:
		if die.is_kept():
			vals.append(die.get_face_up())
	return vals


func _score_kept() -> int:
	return ScoringEngine.score(_kept_values())


func _total_turn_score() -> int:
	return _accumulated_turn_score + _score_kept()


func _find_invalid_selections() -> Array:
	var all_vals := _kept_values()
	var full_score := ScoringEngine.score(all_vals)
	var invalid: Array = []
	for die in _dice:
		if not die.is_kept() or _out_of_play_slots.has(die):
			continue
		var without: Array[int] = []
		var removed := false
		for v in all_vals:
			if not removed and v == die.get_face_up():
				removed = true
			else:
				without.append(v)
		if ScoringEngine.score(without) == full_score:
			invalid.append(die)
	return invalid


func _on_die_selection_changed() -> void:
	_turn_label.text = "Turn: %d" % _total_turn_score()
	if _lock_in_button.visible:
		_lock_in_button.disabled = _score_kept() == 0


func _on_lock_in_pressed() -> void:
	var invalid := _find_invalid_selections()
	if invalid.size() > 0:
		_lock_in_button.disabled = true
		for die in invalid:
			die.shake_invalid()
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			_lock_in_button.disabled = _score_kept() == 0
		)
		return

	var kept_indices: Array[int] = []
	for i in _dice.size():
		if _dice[i].is_kept() and not _out_of_play_slots.has(_dice[i]):
			kept_indices.append(i)

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_lock_in_button.visible = false
		request_lock_in.rpc_id(1, kept_indices)
	else:
		_execute_lock_in(kept_indices)


@rpc("any_peer", "reliable")
func request_lock_in(kept_indices: Array[int]) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != _current_player_id():
		return
	_execute_lock_in(kept_indices)


func _execute_lock_in(kept_indices: Array[int]) -> void:
	for i in kept_indices:
		if not _dice[i].is_kept():
			_dice[i].set_kept(true)

	for die in _dice:
		die.set_selectable(false)

	_move_kept_to_out_of_play()

	var hot := _out_of_play_slots.size() == _dice.size()

	if multiplayer.has_multiplayer_peer():
		var out_of_play_indices: Array[int] = []
		for die in _out_of_play_slots.keys():
			for i in _dice.size():
				if _dice[i] == die:
					out_of_play_indices.append(i)
					break
		_sync_lock_in_done.rpc(kept_indices, out_of_play_indices, hot)
	else:
		_finish_lock_in(hot)


@rpc("authority", "call_local", "reliable")
func _sync_lock_in_done(kept_indices: Array[int], out_of_play_indices: Array[int], hot: bool) -> void:
	for i in kept_indices:
		if not _dice[i].is_kept():
			_dice[i].set_kept(true)
	for i in out_of_play_indices:
		if not _out_of_play_slots.has(_dice[i]):
			_dice[i].set_out_of_play()
			_out_of_play_slots[_dice[i]] = _next_slot
			_next_slot += 1
	for die in _dice:
		die.set_selectable(false)
	_finish_lock_in(hot)


func _finish_lock_in(hot: bool) -> void:
	_lock_in_button.visible = false
	if hot:
		_trigger_hot_dice()
	elif _is_my_turn():
		_pass_button.visible = true
		_roll_again_button.visible = true
		_roll_again_button.disabled = false


func _on_pass_pressed() -> void:
	var banked := _total_turn_score()
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0 \
			and not multiplayer.is_server():
		request_pass.rpc_id(1, banked)
	else:
		_apply_pass(_current_player_id(), banked)


@rpc("any_peer", "reliable")
func request_pass(banked: int) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != _current_player_id():
		return
	_apply_pass(_current_player_id(), banked)


func _apply_pass(passer_id: int, banked: int) -> void:
	var newly_unlocked := false
	if _unlocked_players.has(passer_id):
		_scores[passer_id] = _scores.get(passer_id, 0) + banked
	elif banked >= GameConfig.UNLOCK_THRESHOLD:
		newly_unlocked = true
		_unlocked_players.append(passer_id)
		_scores[passer_id] = banked
	_current_player_idx = (_current_player_idx + 1) % _player_ids.size()
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		_sync_turn_advance.rpc(_current_player_idx, _scores.duplicate(), _unlocked_players.duplicate())
		if newly_unlocked:
			_announce_unlock.rpc(passer_id)
	else:
		if newly_unlocked:
			_show_unlock_popup(passer_id)
		_end_turn()


@rpc("authority", "call_local", "reliable")
func _sync_turn_advance(next_idx: int, scores: Dictionary, unlocked_ids: Array[int]) -> void:
	_current_player_idx = next_idx
	_scores = scores
	_unlocked_players = unlocked_ids
	_end_turn()


@rpc("authority", "call_local", "reliable")
func _announce_unlock(player_id: int) -> void:
	_show_unlock_popup(player_id)


func _show_unlock_popup(player_id: int) -> void:
	var label := _player_label(player_id)
	_unlock_label.text = "You're on the board!" if label == "You" \
			else "%s is on the board!" % label
	_unlock_popup.visible = true
	get_tree().create_timer(3.0).timeout.connect(func() -> void:
		_unlock_popup.visible = false
	)


func _on_roll_again_pressed() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_roll_again_button.disabled = true
		request_roll.rpc_id(1)
	else:
		_do_roll(_roller_id)


func _move_kept_to_out_of_play() -> void:
	# Sample the table surface Y from a die that is still resting on it.
	var base_y := 0.2
	for die in _dice:
		if die.is_kept() and not _out_of_play_slots.has(die):
			base_y = die.global_position.y
			break

	for die in _dice:
		if die.is_kept() and not _out_of_play_slots.has(die):
			die.set_out_of_play()
			var slot: int = _next_slot
			_out_of_play_slots[die] = slot
			_next_slot += 1
			die.slide_to(_out_of_play_position(slot, base_y), 0.5)


func _out_of_play_position(slot: int, base_y: float) -> Vector3:
	var a := SEAT_ANGLES[_player_seat.get(_current_player_id(), 0) as int]
	var right := Vector3(cos(a), 0.0, -sin(a))   # player's right when facing table
	var facing := Vector3(-sin(a), 0.0, -cos(a)) # player's facing toward center
	var pile := slot / 3
	var height := slot % 3
	var fwd_sign := 0.5 if pile == 0 else -0.5
	return right * 4.3 - facing * fwd_sign + Vector3(0.0, base_y + height * 0.4, 0.0)


func _end_turn() -> void:
	_accumulated_turn_score = 0
	for die in _dice:
		_rest_y = die.global_position.y
		break
	_out_of_play_slots.clear()
	_next_slot = 0
	_turn_label.text = "Turn: 0"
	_roll_label.text = "Roll: -"
	_lock_in_button.visible = false
	_pass_button.visible = false
	_roll_again_button.visible = false
	for die in _dice:
		die.reset_kept()
		die.set_selectable(false)
	var seat: int = _player_seat.get(_current_player_id(), 0) as int
	_reset_dice_to_rest(seat, 1.0)
	_update_turn_ui()
	_update_scoreboard()


# ── Dice rest state ──────────────────────────────────────────────────────────

func _detect_rest_y() -> void:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(0.0, 10.0, 0.0), Vector3(0.0, -10.0, 0.0))
	var excl: Array[RID] = []
	for die in _dice:
		excl.append(die.get_rid())
	query.exclude = excl
	var hit := space.intersect_ray(query)
	if not hit.is_empty():
		_rest_y = (hit.position.y as float) + 0.22


func _reset_dice_to_rest(seat_idx: int = 0, duration: float = 0.0) -> void:
	var a := SEAT_ANGLES[seat_idx]
	var c := 0.2 * sqrt(2.0)
	# Triangle of 3 stacks; tip of triangle points toward player's seat.
	var local_positions := [
		Vector3(-c, 0.0,  0.0),
		Vector3( c, 0.0,  0.0),
		Vector3( 0.0, 0.0, -c),
	]
	# Offset the whole group 0.5 units toward the player so it sits on their side.
	var offset := Vector3(sin(a) * 0.5, 0.0, cos(a) * 0.5)
	var bas := Basis(Vector3.UP, deg_to_rad(45.0))
	for i in _dice.size():
		var stack  := i / 2
		var height := i % 2
		var xz := _rot_y(local_positions[stack], a) + offset
		var pos := Vector3(xz.x, _rest_y + height * _REST_STEP, xz.z)
		if duration > 0.0:
			_dice[i].slide_to_rest(pos, bas, duration)
		else:
			_dice[i].place_at(pos, bas)


# ── Camera ───────────────────────────────────────────────────────────────────

func _compute_cam_transform() -> Transform3D:
	var a := SEAT_ANGLES[_local_seat_idx]
	var table_pos := Vector3(sin(a) * 2.0, 10.0, cos(a) * 2.0)
	var table_t := Transform3D(
		Basis.looking_at((_CAM_TABLE_LOOK - table_pos).normalized(), Vector3.UP),
		table_pos)
	var stand_pos  := _seat_stand_pos(_local_seat_idx)
	var stand_look := _seat_stand_look(_local_seat_idx)
	var stand_t := Transform3D(
		Basis.looking_at((stand_look - stand_pos).normalized(), Vector3.UP),
		stand_pos)
	var base    := table_t.interpolate_with(stand_t, _cam_blend)
	var yaw_lim := deg_to_rad(lerpf(_CAM_TABLE_YAW_LIM, _CAM_STAND_YAW_LIM, _cam_blend))
	var pit_lim := deg_to_rad(lerpf(_CAM_TABLE_PIT_LIM, _CAM_STAND_PIT_LIM, _cam_blend))
	_cam_yaw   = clamp(_cam_yaw,   -yaw_lim, yaw_lim)
	_cam_pitch = clamp(_cam_pitch, -pit_lim, pit_lim)
	var yawed  := Basis(Vector3.UP, _cam_yaw) * base.basis
	var tilted := Basis(yawed.x, _cam_pitch) * yawed
	return Transform3D(tilted, base.origin)


func _set_cam_blend(target: float) -> void:
	if _cam_blend_tween:
		_cam_blend_tween.kill()
	_cam_blend_tween = create_tween()
	_cam_blend_tween.set_ease(Tween.EASE_IN_OUT)
	_cam_blend_tween.set_trans(Tween.TRANS_CUBIC)
	_cam_blend_tween.set_parallel(true)
	_cam_blend_tween.tween_property(self, "_cam_blend", target, _CAM_BLEND_SPEED)
	if target == 0.0:
		_cam_blend_tween.tween_property(self, "_cam_yaw",   0.0, _CAM_BLEND_SPEED)
		_cam_blend_tween.tween_property(self, "_cam_pitch", 0.0, _CAM_BLEND_SPEED)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q:
				_debug_cam_active = not _debug_cam_active
				_debug_label.visible = _debug_cam_active
			KEY_P:
				if event.shift_pressed:
					_toggle_debug_pip()
			KEY_W:
				if not _debug_cam_active:
					_set_cam_blend(0.0)
			KEY_S:
				if not _debug_cam_active:
					_set_cam_blend(1.0)

	if not _debug_cam_active:
		if event is InputEventMouseButton and event.pressed:
			match (event as InputEventMouseButton).button_index:
				MOUSE_BUTTON_WHEEL_UP:
					_set_cam_blend(0.0)
				MOUSE_BUTTON_WHEEL_DOWN:
					_set_cam_blend(1.0)
		if event is InputEventMouseMotion and _cam_blend > 0.0:
			var mm := event as InputEventMouseMotion
			var size := get_viewport().get_visible_rect().size
			var yaw_lim := deg_to_rad(lerpf(_CAM_TABLE_YAW_LIM, _CAM_STAND_YAW_LIM, _cam_blend))
			var pit_lim := deg_to_rad(lerpf(_CAM_TABLE_PIT_LIM, _CAM_STAND_PIT_LIM, _cam_blend))
			_cam_yaw   = lerpf( yaw_lim, -yaw_lim, mm.position.x / size.x)
			_cam_pitch = lerpf( pit_lim, -pit_lim, mm.position.y / size.y)


func _process(delta: float) -> void:
	if _debug_cam_active:
		# W/S — orbit camera position along a vertical circular arc, always look at origin.
		var orbit := float(Input.is_key_pressed(KEY_W)) - float(Input.is_key_pressed(KEY_S))
		if orbit != 0.0:
			var pos := _camera.global_position
			var dist := pos.length()
			if dist > 0.01:
				var elev := asin(clamp(pos.y / dist, -1.0, 1.0))
				var azim := atan2(pos.x, pos.z)
				elev = clamp(elev + orbit * _DEBUG_ORBIT_SPEED * delta, -PI * 0.49, PI * 0.49)
				_camera.global_position = Vector3(
					dist * cos(elev) * sin(azim),
					dist * sin(elev),
					dist * cos(elev) * cos(azim)
				)
				_camera.look_at(Vector3.ZERO, Vector3.UP)
		# A/D — yaw the look direction in place, rotating around world Y.
		var yaw := float(Input.is_key_pressed(KEY_A)) - float(Input.is_key_pressed(KEY_D))
		if yaw != 0.0:
			_camera.global_transform = Transform3D(
				Basis(Vector3.UP, yaw * _DEBUG_YAW_SPEED * delta) * _camera.global_transform.basis,
				_camera.global_position
			)
		# Arrow keys — translate camera position along world X and Y axes.
		var pan_x := float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT))
		var pan_y := float(Input.is_key_pressed(KEY_UP)) - float(Input.is_key_pressed(KEY_DOWN))
		if pan_x != 0.0 or pan_y != 0.0:
			_camera.global_position += Vector3(pan_x, pan_y, 0.0) * _DEBUG_PAN_SPEED * delta
		return

	_camera.transform = _compute_cam_transform()


# ── Scoreboard ───────────────────────────────────────────────────────────────

func _player_label(pid: int) -> String:
	if pid == 0 or (multiplayer.has_multiplayer_peer() and pid == multiplayer.get_unique_id()):
		return "You"
	return "Player %d" % pid


func _update_scoreboard() -> void:
	for child in _scoreboard.get_children():
		if child.name != "Background":
			child.free()

	if _player_ids.is_empty():
		return

	var sorted := _player_ids.duplicate()
	sorted.sort_custom(func(a: int, b: int) -> bool:
		return _scores.get(a, 0) > _scores.get(b, 0)
	)

	var title := Label3D.new()
	title.name = "SBTitle"
	title.text = "SCORES"
	title.font_size = 52
	title.pixel_size = 0.004
	title.outline_size = 0
	title.modulate = Color(1.0, 0.85, 0.2)
	title.position = Vector3(0.0, 0.8, 0.02)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scoreboard.add_child(title)

	for i in sorted.size():
		var pid: int = sorted[i]
		var is_current := pid == _current_player_id()
		var row := Label3D.new()
		row.font_size = 44
		row.pixel_size = 0.004
		row.outline_size = 0
		var locked := not _unlocked_players.has(pid)
		row.modulate = Color(1.0, 0.75, 0.08) if is_current else \
				(Color(0.55, 0.55, 0.55) if locked else Color(0.9, 0.87, 0.78))
		row.position = Vector3(0.0, 0.44 - i * 0.32, 0.02)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.text = "%d.  %s  —  [===locked===]" % [i + 1, _player_label(pid)] if locked \
				else "%d.  %s  —  %d" % [i + 1, _player_label(pid), _scores.get(pid, 0)]
		_scoreboard.add_child(row)
