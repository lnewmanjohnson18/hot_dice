extends RigidBody3D

signal roll_completed(value: int)
signal selection_changed

var _rolling := false
var _kept := false
var _selectable := false
var _slide_tween: Tween

const FACE_NORMALS = [
	Vector3(0.0, 1.0, 0.0),
	Vector3(0.0, -1.0, 0.0),
	Vector3(1.0, 0.0, 0.0),
	Vector3(-1.0, 0.0, 0.0),
	Vector3(0.0, 0.0, 1.0),
	Vector3(0.0, 0.0, -1.0),
]
const FACE_VALUES = [1, 6, 3, 4, 5, 2]

const COLOR_NORMAL := Color(0.95, 0.92, 0.82, 1)
const COLOR_KEPT   := Color(0.85, 0.72, 0.08, 1)

@onready var _mesh: MeshInstance3D = $Mesh

var _mat_kept: StandardMaterial3D
var _default_collision_layer: int
var _default_collision_mask: int


func _ready() -> void:
	sleeping_state_changed.connect(_on_sleeping_state_changed)

	_default_collision_layer = collision_layer
	_default_collision_mask  = collision_mask

	_mat_kept = StandardMaterial3D.new()
	_mat_kept.albedo_color = COLOR_KEPT

	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

	_add_face_labels()


func _add_face_labels() -> void:
	# Each entry: [face_value, position, rotation_euler]
	# Positions sit just outside the 0.2 half-extent so labels clear the mesh surface.
	# Rotations orient the label's +Z outward along the face normal.
	var half := 0.201
	var face_data: Array = [
		[1, Vector3(0, half, 0),   Vector3(-PI / 2, 0, 0)],
		[6, Vector3(0, -half, 0),  Vector3(PI / 2, 0, 0)],
		[3, Vector3(half, 0, 0),   Vector3(0, PI / 2, 0)],
		[4, Vector3(-half, 0, 0),  Vector3(0, -PI / 2, 0)],
		[5, Vector3(0, 0, half),   Vector3(0, 0, 0)],
		[2, Vector3(0, 0, -half),  Vector3(0, PI, 0)],
	]
	for fd: Array in face_data:
		var label := Label3D.new()
		label.text = str(fd[0])
		label.font_size = 64
		label.pixel_size = 0.004
		label.modulate = Color(0.1, 0.05, 0.02)
		label.outline_size = 0
		label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		label.double_sided = true
		label.position = fd[1]
		label.rotation = fd[2]
		add_child(label)


func set_selectable(value: bool) -> void:
	_selectable = value


func _input_event(_camera: Camera3D, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape: int) -> void:
	if _rolling or not _selectable:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_set_kept(not _kept)


func _set_kept(value: bool) -> void:
	_kept = value
	if _kept:
		freeze = true
	_mesh.set_surface_override_material(0, _mat_kept if _kept else null)
	selection_changed.emit()


func is_kept() -> bool:
	return _kept


func set_kept(value: bool) -> void:
	_set_kept(value)


func shake_invalid() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.12, 0.12)
	_mesh.set_surface_override_material(0, mat)

	var origin := global_position
	var tw := create_tween()
	for i in 5:
		tw.tween_property(self, "global_position", origin + Vector3(0.08, 0.0, 0.0), 0.05)
		tw.tween_property(self, "global_position", origin - Vector3(0.08, 0.0, 0.0), 0.05)
	tw.tween_property(self, "global_position", origin, 0.0)
	tw.tween_callback(func() -> void:
		_mesh.set_surface_override_material(0, _mat_kept if _kept else null)
	)


func set_out_of_play() -> void:
	collision_layer = 0
	collision_mask  = 0


func reset_kept() -> void:
	collision_layer = _default_collision_layer
	collision_mask  = _default_collision_mask
	_set_kept(false)


func slide_to(target: Vector3, duration: float) -> void:
	if _slide_tween:
		_slide_tween.kill()
	_slide_tween = create_tween()
	_slide_tween.set_ease(Tween.EASE_OUT)
	_slide_tween.set_trans(Tween.TRANS_CUBIC)
	_slide_tween.tween_property(self, "global_position", target, duration)


func roll(drop_position: Vector3) -> void:
	if _kept:
		return
	if _slide_tween:
		_slide_tween.kill()
		_slide_tween = null
	_rolling = true
	global_position = drop_position
	rotation = Vector3(0.0, randf_range(0.0, TAU), 0.0)
	freeze = false
	linear_velocity = Vector3(0.0, 0.0, randf_range(-7.5, -4.5))
	angular_velocity = Vector3(-6.0, 0.0, 0.0)


func is_rolling() -> bool:
	return _rolling


func force_stop() -> void:
	_rolling = false
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func get_face_up() -> int:
	var best_dot := -2.0
	var best_index := 0
	for i in FACE_NORMALS.size():
		var world_normal: Vector3 = global_transform.basis * FACE_NORMALS[i]
		var dot: float = world_normal.dot(Vector3.UP)
		if dot > best_dot:
			best_dot = dot
			best_index = i
	return FACE_VALUES[best_index]


func _on_sleeping_state_changed() -> void:
	if sleeping and _rolling:
		_rolling = false
		roll_completed.emit(get_face_up())
