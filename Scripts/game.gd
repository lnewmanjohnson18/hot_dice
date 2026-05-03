extends Node3D

const DROP_POSITIONS = [
	Vector3(-0.6, 3.5, 3.2),
	Vector3( 0.0, 3.5, 3.2),
	Vector3( 0.6, 3.5, 3.2),
	Vector3(-0.5, 3.5, 3.4),
	Vector3( 0.0, 3.5, 3.4),
	Vector3( 0.5, 3.5, 3.4),
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
@onready var _hot_dice_popup: Panel      = $UI/HotDicePopup

var _dice_done := 0
var _rolling_count := 0
var _roll_values: Array[int] = []
var _roller_id := 0
var _player_ids: Array[int] = []
var _current_player_idx := 0
var _scores: Dictionary = {}
var _roll_finished := false
var _roll_gen := 0

var _cam_default_transform: Transform3D
var _cam_tween: Tween
var _first_roll_of_turn := true
var _out_of_play_slots := {}  # die -> slot index
var _next_slot := 0
var _debug_cam_active := false
var _game_cam_target: Transform3D
var _debug_label: Label

const _DEBUG_ORBIT_SPEED := 1.5  # rad/s — W/S elevation along circular path
const _DEBUG_YAW_SPEED   := 1.5  # rad/s — A/D look direction
const _DEBUG_PAN_SPEED   := 5.0  # units/s — arrow key X/Y translate

# Position (0,10,4) looking at (0,0,1) — 73° below horizontal.

const _CAM_ROLL_TRANSFORM := Transform3D(
		Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, 0.0562, -0.9984), Vector3(0.0, 0.9984, 0.0562)),
		Vector3(0.0, 8.5, 1.4785))


func _ready() -> void:
	_cam_default_transform = _camera.transform
	_game_cam_target = _cam_default_transform

	_debug_label = Label.new()
	_debug_label.text = "DEBUG CAMERA  [Q to exit]\nW/S orbit  A/D look  Arrows pan"
	_debug_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	_debug_label.add_theme_font_size_override("font_size", 15)
	_debug_label.position = Vector2(10, 10)
	_debug_label.visible = false
	$UI.add_child(_debug_label)

	for die in _dice:
		die.roll_completed.connect(_on_die_roll_completed)
		die.selection_changed.connect(_on_die_selection_changed)
	_lock_in_button.visible = false
	_pass_button.visible = false
	_roll_again_button.visible = false
	_hot_dice_popup.visible = false
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
		_scores[0] = 0
		_update_turn_ui()


@rpc("authority", "call_local", "reliable")
func _sync_player_ids(ids: Array[int]) -> void:
	_player_ids = ids
	for pid in _player_ids:
		_scores[pid] = 0
	_update_turn_ui()


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
	if _first_roll_of_turn:
		_first_roll_of_turn = false
		_tween_camera(_CAM_ROLL_TRANSFORM, 0.7)

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

	for i in _dice.size():
		var pos: Vector3 = DROP_POSITIONS[i]
		pos.x += randf_range(-0.08, 0.08)
		pos.z += randf_range(-0.08, 0.08)
		_dice[i].roll(pos)

	_roll_gen += 1
	var gen := _roll_gen
	get_tree().create_timer(3.0).timeout.connect(func(): _on_roll_timeout(gen))


@rpc("authority", "call_local", "reliable")
func _set_rolling_state(rolling: bool, roller_id: int) -> void:
	_roll_button.disabled = rolling
	if rolling:
		_roll_button.visible = false
		var is_me := roller_id == multiplayer.get_unique_id()
		_roll_label.text = "%s rolling..." % ("You" if is_me else "Player %d" % roller_id)
		if not multiplayer.is_server():
			_tween_camera(_CAM_ROLL_TRANSFORM, 0.7)


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
	var roll_score := _score_roll(_roll_values)
	if multiplayer.has_multiplayer_peer():
		_sync_roll_result.rpc(_roller_id, roll_score)
	else:
		_apply_roll_result(0, roll_score)


@rpc("authority", "call_local", "reliable")
func _sync_roll_result(roller_id: int, roll_score: int) -> void:
	_apply_roll_result(roller_id, roll_score)


func _apply_roll_result(roller_id: int, roll_score: int) -> void:
	if roll_score == 0:
		_show_bust_popup()
	else:
		_roll_label.text = "Roll: +%d" % roll_score if roller_id == 0 \
				else "%s: +%d" % [_roller_name(roller_id), roll_score]
		_enter_selecting()


func _trigger_hot_dice() -> void:
	_hot_dice_popup.visible = true
	get_tree().create_timer(2.5).timeout.connect(func() -> void:
		_hot_dice_popup.visible = false
		_out_of_play_slots.clear()
		_next_slot = 0
		for die in _dice:
			die.reset_kept()
			die.set_selectable(false)
		_pass_button.visible = true
		_roll_again_button.visible = true
	)


func _show_bust_popup() -> void:
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
	for die in _dice:
		if not die.is_kept():
			die.set_selectable(true)
	_lock_in_button.visible = true
	_lock_in_button.disabled = _score_kept() == 0
	_turn_label.text = "Turn: %d" % _score_kept()


func _kept_values() -> Array[int]:
	var vals: Array[int] = []
	for die in _dice:
		if die.is_kept():
			vals.append(die.get_face_up())
	return vals


func _score_kept() -> int:
	return _score_roll(_kept_values())


func _find_invalid_selections() -> Array:
	var all_vals := _kept_values()
	var full_score := _score_roll(all_vals)
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
		if _score_roll(without) == full_score:
			invalid.append(die)
	return invalid


func _on_die_selection_changed() -> void:
	var score := _score_kept()
	_turn_label.text = "Turn: %d" % score
	if _lock_in_button.visible:
		_lock_in_button.disabled = score == 0


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
	else:
		_pass_button.visible = true
		_roll_again_button.visible = true


func _on_pass_pressed() -> void:
	var banked := _score_kept()
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
	_scores[passer_id] = _scores.get(passer_id, 0) + banked
	_current_player_idx = (_current_player_idx + 1) % _player_ids.size()
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		_sync_turn_advance.rpc(_current_player_idx, _scores.duplicate())
	else:
		_end_turn()


@rpc("authority", "call_local", "reliable")
func _sync_turn_advance(next_idx: int, scores: Dictionary) -> void:
	_current_player_idx = next_idx
	_scores = scores
	_end_turn()


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
	var pile := slot / 3   # 0 = first pile (slots 0-2), 1 = second pile (slots 3-5)
	var height := slot % 3 # position within the pile (0 = bottom)
	return Vector3(4.3, base_y + height * 0.4, 0.5 if pile == 0 else -0.5)


func _tween_camera(target: Transform3D, duration: float) -> void:
	_game_cam_target = target
	if _debug_cam_active:
		return
	if _cam_tween:
		_cam_tween.kill()
	_cam_tween = create_tween()
	_cam_tween.set_ease(Tween.EASE_IN_OUT)
	_cam_tween.set_trans(Tween.TRANS_CUBIC)
	_cam_tween.tween_property(_camera, "transform", target, duration)


func _end_turn() -> void:
	_first_roll_of_turn = true
	_out_of_play_slots.clear()
	_next_slot = 0
	_tween_camera(_cam_default_transform, 0.7)
	_turn_label.text = "Turn: 0"
	_roll_label.text = "Roll: -"
	_lock_in_button.visible = false
	_pass_button.visible = false
	_roll_again_button.visible = false
	for die in _dice:
		die.reset_kept()
		die.set_selectable(false)
	_update_turn_ui()


# ── Debug camera ─────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			_debug_cam_active = not _debug_cam_active
			_debug_label.visible = _debug_cam_active
			if not _debug_cam_active:
				if _cam_tween:
					_cam_tween.kill()
				_camera.transform = _game_cam_target


func _process(delta: float) -> void:
	if not _debug_cam_active:
		return

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


# ── Scoring ──────────────────────────────────────────────────────────────────

func _score_roll(values: Array[int]) -> int:
	var counts: Dictionary = {}
	for v in values:
		counts[v] = counts.get(v, 0) + 1

	# Straight 1-2-3-4-5-6
	if values.size() == 6 and counts.size() == 6:
		return 1500

	# Three pairs
	var pairs := 0
	for c in counts.values():
		if c == 2:
			pairs += 1
	if pairs == 3:
		return 1500

	var score := 0
	for face: int in counts:
		var count: int = counts[face]
		if count >= 3:
			var base := 1000 if face == 1 else face * 100
			score += base * (count - 2)
			count -= 3
		if face == 1:
			score += count * 100
		elif face == 5:
			score += count * 50

	return score
