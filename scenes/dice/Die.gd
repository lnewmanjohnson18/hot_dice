extends RigidBody3D

signal settled(face_value: int)

# Local-space normals for each face value (standard die: opposite faces sum to 7)
const FACE_NORMALS := {
	1: Vector3(0, 1, 0),
	2: Vector3(0, 0, -1),
	3: Vector3(1, 0, 0),
	4: Vector3(-1, 0, 0),
	5: Vector3(0, 0, 1),
	6: Vector3(0, -1, 0),
}

const SETTLE_VELOCITY_THRESHOLD := 0.05
const SETTLE_CHECK_INTERVAL := 0.2

var _settle_timer := 0.0
var _is_settled := false
var face_value := 0

func roll(impulse_range := 5.0) -> void:
	_is_settled = false
	face_value = 0
	var impulse := Vector3(
		randf_range(-impulse_range, impulse_range),
		randf_range(2.0, impulse_range),
		randf_range(-impulse_range, impulse_range)
	)
	var torque := Vector3(
		randf_range(-10.0, 10.0),
		randf_range(-10.0, 10.0),
		randf_range(-10.0, 10.0)
	)
	apply_central_impulse(impulse)
	apply_torque_impulse(torque)

func _physics_process(delta: float) -> void:
	if _is_settled:
		return
	_settle_timer += delta
	if _settle_timer >= SETTLE_CHECK_INTERVAL:
		_settle_timer = 0.0
		if linear_velocity.length() < SETTLE_VELOCITY_THRESHOLD and \
		   angular_velocity.length() < SETTLE_VELOCITY_THRESHOLD:
			_on_settled()

func _on_settled() -> void:
	_is_settled = true
	face_value = _read_face()
	emit_signal("settled", face_value)

func _read_face() -> int:
	var best_dot := -INF
	var best_face := 1
	for face in FACE_NORMALS:
		var world_normal: Vector3 = global_transform.basis * FACE_NORMALS[face]
		var d := world_normal.dot(Vector3.UP)
		if d > best_dot:
			best_dot = d
			best_face = face
	return best_face
