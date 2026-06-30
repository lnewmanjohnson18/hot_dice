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
	Vector3(-1.2, 3.5, 6.4), Vector3(0.0, 3.5, 6.4), Vector3(1.2, 3.5, 6.4),
	Vector3(-1.0, 3.5, 6.8), Vector3(0.0, 3.5, 6.8), Vector3(1.0, 3.5, 6.8),
]

# Item slot positions for seat 0, at the near table edge in front of each player.
const _BASE_ITEM_SLOTS: Array[Vector3] = [
	Vector3(-2.30, 0.0, 7.0),
	Vector3( 0.00, 0.0, 7.0),
	Vector3( 2.30, 0.0, 7.0),
]

const ItemScene: PackedScene = preload("res://scenes/item.tscn")

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
@onready var _confirm_pass_popup: Panel  = $UI/ConfirmPassPopup
@onready var _warm_dice_popup: Panel     = $UI/WarmDicePopup
@onready var _warm_dice_label: Label     = $UI/WarmDicePopup/WarmDiceLabel
@onready var _scoreboard: Node3D         = $Scoreboard
@onready var _shop_hud_panel: Panel      = $UI/ShopHudPanel
@onready var _shop_hud_label: Label      = $UI/ShopHudPanel/ShopHudLabel
@onready var _shop_confirm_popup: Panel  = $UI/ShopConfirmPopup
@onready var _shop_confirm_label: Label  = $UI/ShopConfirmPopup/ShopConfirmLabel

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
var _warm_dice_count: int = 0   # remaining dice from the previous passer (0 = no offer)
var _warm_dice_score: int = 0   # turn score the previous passer accumulated
var _warm_dice_from: int  = 0   # player_id of the passer
var _warm_dice_pending: bool = false  # true when warm dice popup should show after unlock popup
var _next_slot := 0

var _shop_phase_active: bool = false
var _shop_pick_order: Array[int] = []
var _shop_pick_idx: int = 0
var _shop_items: Array = []
var _shop_platform: Node3D = null
var _shop_had_first: bool = false
var _pending_shop_item_idx: int = -1   # item awaiting Select-confirm popup (-1 = none)

var _player_items: Dictionary = {}     # player_id -> Array of ItemNode
var _reroll_mode_active: bool = false
var _single_reroll_active: bool = false
var _reroll_hud_label: Label
var _tooltip_panel: PanelContainer
var _tooltip_name_label: Label
var _tooltip_desc_label: Label
var _tooltip_charges_label: Label
var _tooltip_hovered_item: ItemNode = null
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
var _cam_mouselook_active := false

const _CAM_TABLE_PIT_LIM     := 10.0    # degrees ±
const _CAM_STAND_PIT_LIM     := 75.0    # degrees ±
const _CAM_BLEND_SPEED        := 0.45   # seconds
const _CAM_MOUSE_SENSITIVITY  := 0.003  # radians per pixel

const _DEBUG_ORBIT_SPEED := 1.5  # rad/s — W/S elevation along circular path
const _DEBUG_YAW_SPEED   := 1.5  # rad/s — A/D look direction
const _DEBUG_PAN_SPEED   := 5.0  # units/s — arrow key X/Y translate

# ── Dice rest state ───────────────────────────────────────────────────────────
var   _rest_y    := 0.22  # updated via raycast after first physics frame
const _REST_STEP := 0.60  # vertical offset per stacked die


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

	_reroll_hud_label = Label.new()
	_reroll_hud_label.text = "Click a die to reroll it"
	_reroll_hud_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.2))
	_reroll_hud_label.add_theme_font_size_override("font_size", 20)
	_reroll_hud_label.position = Vector2(10, 38)
	_reroll_hud_label.visible = false
	$UI.add_child(_reroll_hud_label)

	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tip_style: StyleBoxFlat = StyleBoxFlat.new()
	tip_style.bg_color = Color(0.07, 0.07, 0.13, 0.93)
	tip_style.border_width_left = 1
	tip_style.border_width_right = 1
	tip_style.border_width_top = 1
	tip_style.border_width_bottom = 1
	tip_style.border_color = Color(0.45, 0.45, 0.70)
	tip_style.corner_radius_top_left = 4
	tip_style.corner_radius_top_right = 4
	tip_style.corner_radius_bottom_left = 4
	tip_style.corner_radius_bottom_right = 4
	tip_style.content_margin_left = 10.0
	tip_style.content_margin_right = 10.0
	tip_style.content_margin_top = 8.0
	tip_style.content_margin_bottom = 8.0
	_tooltip_panel.add_theme_stylebox_override("panel", tip_style)
	var tip_vbox: VBoxContainer = VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 5)
	_tooltip_panel.add_child(tip_vbox)
	_tooltip_name_label = Label.new()
	_tooltip_name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	_tooltip_name_label.add_theme_font_size_override("font_size", 15)
	tip_vbox.add_child(_tooltip_name_label)
	_tooltip_desc_label = Label.new()
	_tooltip_desc_label.add_theme_color_override("font_color", Color(0.88, 0.88, 0.95))
	_tooltip_desc_label.add_theme_font_size_override("font_size", 13)
	_tooltip_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tooltip_desc_label.custom_minimum_size = Vector2(200.0, 0.0)
	tip_vbox.add_child(_tooltip_desc_label)
	var tip_sep: HSeparator = HSeparator.new()
	tip_vbox.add_child(tip_sep)
	_tooltip_charges_label = Label.new()
	_tooltip_charges_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.88))
	_tooltip_charges_label.add_theme_font_size_override("font_size", 13)
	tip_vbox.add_child(_tooltip_charges_label)
	_tooltip_panel.visible = false
	$UI.add_child(_tooltip_panel)

	for die in _dice:
		die.roll_completed.connect(_on_die_roll_completed)
		die.selection_changed.connect(_on_die_selection_changed)
		die.debug_clicked.connect(func(): _on_die_debug_clicked(die))
		die.reroll_requested.connect(func(): _on_die_reroll_requested(die))
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
		_setup_all_items()
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
	_setup_all_items()
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
	var a: float = SEAT_ANGLES[seat_idx]
	return Vector3(sin(a) * 17.0, 6.75, cos(a) * 17.0)

func _seat_throw_dir(seat_idx: int) -> Vector3:
	var a: float = SEAT_ANGLES[seat_idx]
	return Vector3(-sin(a), 0.0, -cos(a))

func _seat_stand_look(seat_idx: int) -> Vector3:
	var pos: Vector3 = _seat_stand_pos(seat_idx)
	var a: float = SEAT_ANGLES[seat_idx]
	# fmod keeps face_a in [0, 2π) so P1 (330°→2π) and P2 (30°→0) both snap to 0,
	# giving sin/cos exactly 0/1 instead of near-zero floats.
	var face_a: float = fmod(round(a / (PI * 0.5)) * (PI * 0.5), PI * 2.0)
	var fn: Vector3 = Vector3(sin(face_a), 0.0, cos(face_a))
	var d: float = pos.x * fn.x + pos.z * fn.z
	return Vector3(pos.x - fn.x * d, 0.5, pos.z - fn.z * d)

func _seat_drop_positions(seat_idx: int) -> Array[Vector3]:
	var a: float = SEAT_ANGLES[seat_idx]
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
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		var die_idx: int = -1
		for i in _dice.size():
			var d: RigidBody3D = _dice[i] as RigidBody3D
			if d == die:
				die_idx = i
				break
		if die_idx >= 0:
			request_force_face.rpc_id(1, die_idx, next)
	else:
		die.force_face(next)


@rpc("any_peer", "reliable")
func request_force_face(die_idx: int, face_value: int) -> void:
	if not multiplayer.is_server():
		return
	if die_idx < 0 or die_idx >= _dice.size():
		return
	var die: RigidBody3D = _dice[die_idx] as RigidBody3D
	if die:
		die.force_face(face_value)


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
		if not die.is_kept() and not die.is_inherited():
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
		if _single_reroll_active:
			_single_reroll_active = false
			_roll_finished = true
			if multiplayer.has_multiplayer_peer():
				_sync_reroll_result.rpc()
			else:
				_enter_selecting()
		else:
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
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_charge_items("heatchecker", _current_player_id())
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
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_charge_player_item(_current_player_id(), "blowfly")
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
		if not die.is_kept() and not die.is_inherited():
			die.restore_collision()
			die.set_selectable(my_turn)
	if my_turn:
		_lock_in_button.visible = true
		_lock_in_button.disabled = _score_kept() == 0
		_set_items_selectable(_current_player_id(), true)
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
	_set_items_selectable(_current_player_id(), false)
	for i in kept_indices:
		if not _dice[i].is_kept():
			_dice[i].set_kept(true)

	for die in _dice:
		die.set_selectable(false)

	_move_kept_to_out_of_play()

	var inherited_count: int = 0
	for die in _dice:
		if die.is_inherited():
			inherited_count += 1
	var hot := _out_of_play_slots.size() == _dice.size() - inherited_count

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
	var banked: int = _total_turn_score()
	if not _unlocked_players.has(_current_player_id()) and banked < GameConfig.UNLOCK_THRESHOLD:
		_pass_button.visible = false
		_roll_again_button.visible = false
		_confirm_pass_popup.visible = true
		return
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0 \
			and not multiplayer.is_server():
		request_pass.rpc_id(1, banked)
	else:
		_apply_pass(_current_player_id(), banked)


func _on_confirm_pass_no() -> void:
	_confirm_pass_popup.visible = false
	_pass_button.visible = true
	_roll_again_button.visible = true


func _on_warm_dice_yes() -> void:
	_warm_dice_popup.visible = false
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0 \
			and not multiplayer.is_server():
		request_take_warm_dice.rpc_id(1)
	else:
		_apply_warm_dice_taken()


func _on_warm_dice_no() -> void:
	_warm_dice_popup.visible = false
	_warm_dice_count = 0
	_warm_dice_score = 0
	_warm_dice_from  = 0
	_roll_button.visible = true


@rpc("any_peer", "reliable")
func request_take_warm_dice() -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != _current_player_id():
		return
	_sync_warm_dice_taken.rpc()


@rpc("authority", "call_local", "reliable")
func _sync_warm_dice_taken() -> void:
	_apply_warm_dice_taken()


func _apply_warm_dice_taken() -> void:
	_accumulated_turn_score = _warm_dice_score
	_turn_label.text = "Turn: %d" % _accumulated_turn_score
	var locked_count: int = _dice.size() - _warm_dice_count
	var base_y: float = _rest_y
	for i in locked_count:
		var slot: int = _next_slot
		_next_slot += 1
		_dice[i].set_inherited(true)
		_dice[i].slide_to(_out_of_play_position(slot, base_y), 0.5)
	_warm_dice_count = 0
	_warm_dice_score = 0
	_warm_dice_from  = 0
	if _is_my_turn():
		_roll_button.visible = true


@rpc("any_peer", "reliable")
func request_pass(banked: int) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != _current_player_id():
		return
	_apply_pass(_current_player_id(), banked)


func _apply_pass(passer_id: int, banked: int) -> void:
	var locked_count: int = _out_of_play_slots.size()
	var warm_count: int = _dice.size() - locked_count if locked_count > 0 else 0
	var newly_unlocked := false
	if _unlocked_players.has(passer_id):
		_scores[passer_id] = _scores.get(passer_id, 0) + banked
	elif banked >= GameConfig.UNLOCK_THRESHOLD:
		newly_unlocked = true
		_unlocked_players.append(passer_id)
		_scores[passer_id] = banked
	var trigger_shop: bool = newly_unlocked and not _shop_had_first \
			and _unlocked_players.size() == _player_ids.size()
	if trigger_shop:
		warm_count = 0
	_current_player_idx = (_current_player_idx + 1) % _player_ids.size()
	if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
		_sync_turn_advance.rpc(_current_player_idx, _scores.duplicate(), _unlocked_players.duplicate(), warm_count, banked, passer_id, newly_unlocked)
		if newly_unlocked:
			_announce_unlock.rpc(passer_id)
		if trigger_shop:
			_shop_had_first = true
			_sync_start_shop_phase.rpc(_compute_shop_pick_order(), _generate_shop_pool(_player_ids.size() + 2))
	else:
		_warm_dice_count = warm_count
		_warm_dice_score = banked
		_warm_dice_from  = passer_id
		if newly_unlocked:
			_show_unlock_popup(passer_id)
		_end_turn(newly_unlocked)
		if trigger_shop:
			_shop_had_first = true
			_begin_shop_phase(_compute_shop_pick_order(), _generate_shop_pool(_player_ids.size() + 2))


@rpc("authority", "call_local", "reliable")
func _sync_turn_advance(next_idx: int, scores: Dictionary, unlocked_ids: Array[int],
		warm_count: int, warm_score: int, warm_from: int, newly_unlocked: bool) -> void:
	_current_player_idx = next_idx
	_scores = scores
	_unlocked_players = unlocked_ids
	_warm_dice_count = warm_count
	_warm_dice_score = warm_score
	_warm_dice_from  = warm_from
	_end_turn(newly_unlocked)


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
		if _warm_dice_pending:
			_warm_dice_pending = false
			_warm_dice_popup.visible = true
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
	var a: float = SEAT_ANGLES[_player_seat.get(_current_player_id(), 0) as int]
	var right := Vector3(cos(a), 0.0, -sin(a))   # player's right when facing table
	var facing := Vector3(-sin(a), 0.0, -cos(a)) # player's facing toward center
	var pile := slot / 3
	var height := slot % 3
	var fwd_sign := 0.5 if pile == 0 else -0.5
	return right * 8.6 - facing * fwd_sign + Vector3(0.0, base_y + height * 0.6, 0.0)


func _end_turn(newly_unlocked: bool = false) -> void:
	_exit_reroll_mode()
	for pid: int in _player_ids:
		_set_items_selectable(pid, false)
	var warm_count: int = _warm_dice_count
	var warm_score: int = _warm_dice_score
	var warm_from:  int = _warm_dice_from
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
	_confirm_pass_popup.visible = false
	_warm_dice_popup.visible = false
	_warm_dice_pending = false
	for die in _dice:
		die.reset_kept()
		die.set_selectable(false)
	var seat: int = _player_seat.get(_current_player_id(), 0) as int
	_reset_dice_to_rest(seat, 1.0)
	_update_turn_ui()
	_update_scoreboard()
	if _is_my_turn() and warm_count > 0:
		_roll_button.visible = false
		var from_label: String = _player_label(warm_from)
		_warm_dice_label.text = "The dice are warm! %s is passing you %d dice and %d points. Play their dice or start fresh?" \
				% [from_label, warm_count, warm_score]
		if newly_unlocked:
			_warm_dice_pending = true
		else:
			_warm_dice_popup.visible = true


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
	var a: float = SEAT_ANGLES[seat_idx]
	var c := 0.2 * sqrt(2.0)
	# Triangle of 3 stacks; tip of triangle points toward player's seat.
	var local_positions: Array[Vector3] = [
		Vector3(-c, 0.0,  0.0),
		Vector3( c, 0.0,  0.0),
		Vector3( 0.0, 0.0, -c),
	]
	# Offset the whole group 0.5 units toward the player so it sits on their side.
	var offset := Vector3(sin(a) * 1.0, 0.0, cos(a) * 1.0)
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
	var a: float = SEAT_ANGLES[_local_seat_idx]
	var face_a: float = fmod(round(a / (PI * 0.5)) * (PI * 0.5), PI * 2.0)
	var table_pos := Vector3(sin(a) * 5.5, 13.0, cos(a) * 5.5)
	# Project table_pos onto the face plane so players on the same long side
	# look in an identical direction (perpendicular to that edge).
	var fn: Vector3 = Vector3(sin(face_a), 0.0, cos(face_a))
	var d: float = table_pos.x * fn.x + table_pos.z * fn.z
	var table_look := Vector3(table_pos.x - fn.x * d, 0.0, table_pos.z - fn.z * d)
	var table_t := Transform3D(
		Basis.looking_at((table_look - table_pos).normalized(), Vector3.UP),
		table_pos)
	var stand_pos  := _seat_stand_pos(_local_seat_idx)
	var stand_look := _seat_stand_look(_local_seat_idx)
	var stand_t := Transform3D(
		Basis.looking_at((stand_look - stand_pos).normalized(), Vector3.UP),
		stand_pos)
	var base    := table_t.interpolate_with(stand_t, _cam_blend)
	var pit_lim := deg_to_rad(lerpf(_CAM_TABLE_PIT_LIM, _CAM_STAND_PIT_LIM, _cam_blend))
	_cam_pitch = clamp(_cam_pitch, -pit_lim, pit_lim)
	var yawed  := Basis(Vector3.UP, _cam_yaw) * base.basis
	var tilted := Basis(yawed.x, _cam_pitch) * yawed
	return Transform3D(tilted, base.origin)


func _set_cam_blend(target: float) -> void:
	if _cam_blend_tween:
		_cam_blend_tween.kill()
	if target == 0.0:
		_cam_mouselook_active = false
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		_cam_yaw   = 0.0
		_cam_pitch = 0.0
	else:
		_cam_mouselook_active = true
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_cam_blend_tween = create_tween()
	_cam_blend_tween.set_ease(Tween.EASE_IN_OUT)
	_cam_blend_tween.set_trans(Tween.TRANS_CUBIC)
	_cam_blend_tween.tween_property(self, "_cam_blend", target, _CAM_BLEND_SPEED)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q:
				_debug_cam_active = not _debug_cam_active
				_debug_label.visible = _debug_cam_active
				if _debug_cam_active:
					_cam_mouselook_active = false
					Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
				elif _cam_blend > 0.0:
					_cam_mouselook_active = true
					Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
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
			var clk: InputEventMouseButton = event as InputEventMouseButton
			if _shop_phase_active and clk.button_index == MOUSE_BUTTON_LEFT:
				_try_shop_pick_raycast(clk.position)
			match clk.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					_set_cam_blend(0.0)
				MOUSE_BUTTON_WHEEL_DOWN:
					_set_cam_blend(1.0)
		if event is InputEventMouseMotion and _cam_mouselook_active:
			var mm: InputEventMouseMotion = event as InputEventMouseMotion
			_cam_yaw   -= mm.relative.x * _CAM_MOUSE_SENSITIVITY
			_cam_pitch -= mm.relative.y * _CAM_MOUSE_SENSITIVITY


func _process(delta: float) -> void:
	if _tooltip_panel.visible:
		if _tooltip_hovered_item == null or not is_instance_valid(_tooltip_hovered_item):
			_tooltip_panel.visible = false
		else:
			_refresh_tooltip_charges()
			var mouse_pos: Vector2 = get_viewport().get_mouse_position()
			var vp_size: Vector2 = get_viewport().get_visible_rect().size
			var tip_pos: Vector2 = mouse_pos + Vector2(14.0, 14.0)
			tip_pos.x = minf(tip_pos.x, vp_size.x - _tooltip_panel.size.x - 4.0)
			tip_pos.y = minf(tip_pos.y, vp_size.y - _tooltip_panel.size.y - 4.0)
			_tooltip_panel.position = tip_pos

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

	var sorted: Array[int] = _player_ids.duplicate()
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


# ── Items ────────────────────────────────────────────────────────────────────

func _item_slot_position(seat_idx: int, slot_idx: int) -> Vector3:
	var a: float = SEAT_ANGLES[seat_idx]
	var face_a: float = fmod(round(a / (PI * 0.5)) * (PI * 0.5), TAU)
	var base: Vector3 = _BASE_ITEM_SLOTS[slot_idx]
	var center := _rot_y(Vector3(0.0, 0.0, base.z), a)
	var spread_dir := _rot_y(Vector3(1.0, 0.0, 0.0), face_a)
	var world_pos := center + spread_dir * base.x
	return Vector3(world_pos.x, _rest_y + 0.32, world_pos.z)


func _show_item_tooltip(item: ItemNode) -> void:
	_tooltip_hovered_item = item
	if item.item_type == "heatchecker":
		_tooltip_name_label.text = "Heatchecker"
		_tooltip_desc_label.text = "Gain a charge whenever another player rolls Hot Dice.\n\nActivate during your selection phase to reroll one die."
	elif item.item_type == "blowfly":
		_tooltip_name_label.text = "Blowfly"
		_tooltip_desc_label.text = "Gain a charge whenever you bust.\n\nActivate during your selection phase to reroll one die."
	else:
		_tooltip_name_label.text = item.item_type.capitalize()
		_tooltip_desc_label.text = ""
	_refresh_tooltip_charges()
	_tooltip_panel.visible = true


func _refresh_tooltip_charges() -> void:
	if _tooltip_hovered_item == null:
		return
	var pips: String = ""
	for i: int in ItemNode.MAX_CHARGES:
		pips += "● " if i < _tooltip_hovered_item.charges else "○ "
	_tooltip_charges_label.text = "Charges:  " + pips.strip_edges()


func _hide_item_tooltip() -> void:
	_tooltip_hovered_item = null
	_tooltip_panel.visible = false


func _setup_all_items() -> void:
	for pid: int in _player_ids:
		if _player_items.has(pid):
			var old_items: Array = _player_items[pid] as Array
			for old_item in old_items:
				(old_item as Node3D).queue_free()
	_player_items.clear()
	for pid: int in _player_ids:
		_give_item(pid, "heatchecker")
		_give_item(pid, "blowfly")


func _give_item(player_id: int, item_type: String) -> void:
	if not _player_items.has(player_id):
		_player_items[player_id] = []
	var items: Array = _player_items[player_id] as Array
	if items.size() >= _BASE_ITEM_SLOTS.size():
		return
	var seat: int = _player_seat.get(player_id, 0) as int
	var slot_idx: int = items.size()
	var item: ItemNode = ItemScene.instantiate() as ItemNode
	item.activated.connect(func(): _on_item_activated(item))
	item.mouse_entered.connect(func(): _show_item_tooltip(item))
	item.mouse_exited.connect(_hide_item_tooltip)
	add_child(item)
	item.setup(item_type)
	item.global_position = _item_slot_position(seat, slot_idx)
	var face_a: float = fmod(round(SEAT_ANGLES[seat] / (PI * 0.5)) * (PI * 0.5), TAU)
	item.rotation = Vector3(0.0, face_a, 0.0)
	items.append(item)


func _set_items_selectable(player_id: int, selectable: bool) -> void:
	if not _player_items.has(player_id):
		return
	var items: Array = _player_items[player_id] as Array
	for item in items:
		(item as ItemNode).set_selectable(selectable)


func _charge_player_item(player_id: int, item_type: String) -> void:
	if not _player_items.has(player_id):
		return
	var items: Array = _player_items[player_id] as Array
	for i in items.size():
		var item: ItemNode = items[i] as ItemNode
		if item.item_type == item_type:
			item.add_charge()
			if multiplayer.has_multiplayer_peer():
				_sync_item_charge.rpc(player_id, i, item.charges)


func _charge_items(item_type: String, except_player_id: int = -1) -> void:
	for pid: int in _player_ids:
		if pid == except_player_id:
			continue
		if not _player_items.has(pid):
			continue
		var items: Array = _player_items[pid] as Array
		for i in items.size():
			var item: ItemNode = items[i] as ItemNode
			if item.item_type == item_type:
				item.add_charge()
				if multiplayer.has_multiplayer_peer():
					_sync_item_charge.rpc(pid, i, item.charges)


func _on_item_activated(item_node: Node3D) -> void:
	var item_idx: int = _find_item_idx(item_node)
	if item_idx < 0:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		request_item_activate.rpc_id(1, item_idx)
	else:
		_execute_item_activate(item_idx)


func _find_item_idx(item_node: Node3D) -> int:
	var pid: int = _current_player_id()
	if not _player_items.has(pid):
		return -1
	var items: Array = _player_items[pid] as Array
	for i in items.size():
		if items[i] == item_node:
			return i
	return -1


func _find_die_idx(die: Node3D) -> int:
	for i in _dice.size():
		if _dice[i] == die:
			return i
	return -1


func _execute_item_activate(item_idx: int) -> void:
	var pid: int = _current_player_id()
	if not _player_items.has(pid):
		return
	var items: Array = _player_items[pid] as Array
	if item_idx >= items.size():
		return
	var item: ItemNode = items[item_idx] as ItemNode
	if not item.spend_charge():
		return
	if multiplayer.has_multiplayer_peer():
		_sync_item_activated.rpc(pid, item_idx, item.charges)
	else:
		if _is_my_turn():
			_enter_reroll_mode()


@rpc("any_peer", "reliable")
func request_item_activate(item_idx: int) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != _current_player_id():
		return
	_execute_item_activate(item_idx)


@rpc("authority", "call_local", "reliable")
func _sync_item_activated(player_id: int, item_idx: int, new_charges: int) -> void:
	if not _player_items.has(player_id):
		return
	var items: Array = _player_items[player_id] as Array
	if item_idx >= items.size():
		return
	var item: ItemNode = items[item_idx] as ItemNode
	item.set_charges(new_charges)
	if _is_my_turn():
		_enter_reroll_mode()


@rpc("authority", "call_local", "reliable")
func _sync_item_charge(player_id: int, item_idx: int, new_charges: int) -> void:
	if not _player_items.has(player_id):
		return
	var items: Array = _player_items[player_id] as Array
	if item_idx >= items.size():
		return
	var item: ItemNode = items[item_idx] as ItemNode
	item.set_charges(new_charges)


func _enter_reroll_mode() -> void:
	_reroll_mode_active = true
	_reroll_hud_label.visible = true
	_lock_in_button.visible = false
	_pass_button.visible = false
	_roll_again_button.visible = false
	for die in _dice:
		die.set_selectable(false)
		if not die.is_kept() and not die.is_inherited():
			die.set_reroll_mode(true)


func _exit_reroll_mode() -> void:
	if not _reroll_mode_active:
		return
	_reroll_mode_active = false
	_reroll_hud_label.visible = false
	for die in _dice:
		die.set_reroll_mode(false)


func _on_die_reroll_requested(die: RigidBody3D) -> void:
	if not _reroll_mode_active:
		return
	var die_idx: int = _find_die_idx(die)
	if die_idx < 0:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		request_reroll_die.rpc_id(1, die_idx)
	else:
		_execute_reroll_die(die)


@rpc("any_peer", "reliable")
func request_reroll_die(die_idx: int) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_remote_sender_id() != _current_player_id():
		return
	if die_idx < 0 or die_idx >= _dice.size():
		return
	var die: RigidBody3D = _dice[die_idx] as RigidBody3D
	if die and not die.is_kept() and not die.is_inherited():
		_execute_reroll_die(die)


func _execute_reroll_die(die: RigidBody3D) -> void:
	_exit_reroll_mode()
	_roll_finished = false
	_rolling_count = 1
	_dice_done = 0
	_roll_values.clear()
	_single_reroll_active = true
	var seat: int = _player_seat.get(_current_player_id(), 0) as int
	var drops: Array[Vector3] = _seat_drop_positions(seat)
	var throw_dir := _seat_throw_dir(seat)
	die.set_selectable(false)
	die.roll(drops[0], throw_dir)


@rpc("authority", "call_local", "reliable")
func _sync_reroll_result() -> void:
	_enter_selecting()


# ── Shop Phase ───────────────────────────────────────────────────────────────

func _compute_shop_pick_order() -> Array[int]:
	var order: Array[int] = _player_ids.duplicate()
	order.sort_custom(func(a: int, b: int) -> bool:
		return (_scores.get(a, 0) as int) < (_scores.get(b, 0) as int)
	)
	return order


func _generate_shop_pool(count: int) -> Array[String]:
	var types: Array[String] = [
		"heatchecker", "blowfly", "heatchecker", "blowfly",
		"heatchecker", "blowfly", "heatchecker", "blowfly",
	]
	var result: Array[String] = []
	for i in mini(count, types.size()):
		result.append(types[i])
	return result


func _begin_shop_phase(pick_order: Array[int], item_types: Array[String]) -> void:
	_shop_phase_active = true
	_shop_pick_order = pick_order
	_shop_pick_idx = 0
	_roll_button.visible = false
	# Drop to the overhead table view so the cursor is free to click shop items
	# (standing view captures the mouse, which makes the platform unclickable).
	if not _debug_cam_active:
		_set_cam_blend(0.0)
	_shop_hud_panel.visible = true
	_update_shop_hud()
	_create_shop_display(item_types)
	# Wait for any unlock popup to finish (3s) plus a short buffer before descending.
	get_tree().create_timer(3.5).timeout.connect(func() -> void:
		if not _shop_phase_active:
			return
		var tween := create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(_shop_platform, "global_position", Vector3(0.0, 3.5, 0.0), 1.2)
		tween.tween_callback(func() -> void: _activate_shop_picker())
	)


func _create_shop_display(item_types: Array[String]) -> void:
	if is_instance_valid(_shop_platform):
		_shop_platform.queue_free()
	_shop_items.clear()

	_shop_platform = Node3D.new()

	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(5.0, 0.08, 1.6)
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.07, 0.20)
	mesh_inst.set_surface_override_material(0, mat)
	_shop_platform.add_child(mesh_inst)

	var count := item_types.size()
	var spacing := 0.58
	for i in count:
		var item: ItemNode = ItemScene.instantiate() as ItemNode
		var x_pos: float = (i - (count - 1) * 0.5) * spacing
		item.position = Vector3(x_pos, 0.4, 0.0)
		item.set_shop_mode(true)
		item.activated.connect(func(): _on_shop_item_selected(item))
		item.mouse_entered.connect(func(): _show_item_tooltip(item))
		item.mouse_exited.connect(_hide_item_tooltip)
		_shop_platform.add_child(item)
		_shop_items.append(item)

	add_child(_shop_platform)
	_shop_platform.global_position = Vector3(0.0, 15.0, 0.0)

	for i in _shop_items.size():
		var item: ItemNode = _shop_items[i] as ItemNode
		item.setup(item_types[i])


func _activate_shop_picker() -> void:
	if not _shop_phase_active:
		return
	var picker: int = _shop_pick_order[_shop_pick_idx]
	var is_my_pick: bool = picker == 0 or \
			(multiplayer.has_multiplayer_peer() and picker == multiplayer.get_unique_id())
	for shop_item in _shop_items:
		var item_node: ItemNode = shop_item as ItemNode
		if is_instance_valid(item_node):
			item_node.set_shop_selectable(is_my_pick)
	_update_shop_hud()


func _update_shop_hud() -> void:
	if not _shop_phase_active or _shop_pick_idx >= _shop_pick_order.size():
		return
	var picker: int = _shop_pick_order[_shop_pick_idx]
	_shop_hud_label.text = "%s Be Shopping" % _player_label(picker)


func _find_shop_item_idx(item_node: Node3D) -> int:
	for i in _shop_items.size():
		var item: ItemNode = _shop_items[i] as ItemNode
		if item == item_node:
			return i
	return -1


func _try_shop_pick_raycast(screen_pos: Vector2) -> void:
	# Fallback picking for the floating shop platform: raycast from the camera and
	# pick the item directly, independent of per-body _input_event hit testing.
	if not _shop_phase_active or _shop_confirm_popup.visible:
		return
	var space := get_world_3d().direct_space_state
	var from: Vector3 = _camera.project_ray_origin(screen_pos)
	var to: Vector3 = from + _camera.project_ray_normal(screen_pos) * 1000.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return
	var node: Node = hit.get("collider") as Node
	while node != null and not (node is ItemNode):
		node = node.get_parent()
	if node == null:
		return
	var item: ItemNode = node as ItemNode
	if _shop_items.has(item) and item.is_shop_selectable():
		_on_shop_item_selected(item)


func _on_shop_item_selected(item_node: Node3D) -> void:
	if not _shop_phase_active:
		return
	var item_idx: int = _find_shop_item_idx(item_node)
	if item_idx < 0:
		return
	var item: ItemNode = _shop_items[item_idx] as ItemNode
	if not is_instance_valid(item):
		return
	_pending_shop_item_idx = item_idx
	_shop_confirm_label.text = "Select %s?" % _item_display_name(item.item_type)
	_shop_confirm_popup.visible = true


func _item_display_name(item_type: String) -> String:
	if item_type == "heatchecker":
		return "Heatchecker"
	elif item_type == "blowfly":
		return "Blowfly"
	return item_type


func _on_shop_confirm_yes() -> void:
	_shop_confirm_popup.visible = false
	var item_idx: int = _pending_shop_item_idx
	_pending_shop_item_idx = -1
	if item_idx < 0:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		request_shop_pick.rpc_id(1, item_idx)
	else:
		_execute_shop_pick(item_idx)


func _on_shop_confirm_no() -> void:
	_shop_confirm_popup.visible = false
	_pending_shop_item_idx = -1


func _execute_shop_pick(item_idx: int) -> void:
	if item_idx < 0 or item_idx >= _shop_items.size():
		return
	var item: ItemNode = _shop_items[item_idx] as ItemNode
	if not is_instance_valid(item):
		return
	var item_type: String = item.item_type
	var picker: int = _shop_pick_order[_shop_pick_idx]
	if multiplayer.has_multiplayer_peer():
		_sync_shop_pick.rpc(picker, item_idx, item_type)
	else:
		_apply_shop_pick_result(picker, item_idx, item_type)


@rpc("any_peer", "reliable")
func request_shop_pick(item_idx: int) -> void:
	if not multiplayer.is_server():
		return
	if _shop_pick_idx >= _shop_pick_order.size():
		return
	if multiplayer.get_remote_sender_id() != _shop_pick_order[_shop_pick_idx]:
		return
	_execute_shop_pick(item_idx)


@rpc("authority", "call_local", "reliable")
func _sync_shop_pick(picker_id: int, item_idx: int, item_type: String) -> void:
	_apply_shop_pick_result(picker_id, item_idx, item_type)


func _apply_shop_pick_result(picker_id: int, item_idx: int, item_type: String) -> void:
	if item_idx < _shop_items.size():
		var item: ItemNode = _shop_items[item_idx] as ItemNode
		if is_instance_valid(item):
			item.queue_free()
		_shop_items[item_idx] = null
	_give_item(picker_id, item_type)
	_shop_pick_idx += 1
	if _shop_pick_idx >= _shop_pick_order.size():
		_end_shop_phase()
	else:
		_activate_shop_picker()


func _end_shop_phase() -> void:
	_shop_phase_active = false
	_shop_hud_panel.visible = false
	_shop_confirm_popup.visible = false
	_pending_shop_item_idx = -1
	_shop_items.clear()
	if is_instance_valid(_shop_platform):
		var tween := create_tween()
		tween.set_ease(Tween.EASE_IN)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(_shop_platform, "global_position", Vector3(0.0, 15.0, 0.0), 1.0)
		tween.tween_callback(func() -> void:
			if is_instance_valid(_shop_platform):
				_shop_platform.queue_free()
				_shop_platform = null
		)
	_update_turn_ui()
	_update_scoreboard()


@rpc("authority", "call_local", "reliable")
func _sync_start_shop_phase(pick_order: Array[int], item_types: Array[String]) -> void:
	_begin_shop_phase(pick_order, item_types)
