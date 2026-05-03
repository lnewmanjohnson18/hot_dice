extends Node3D
const DROP_POSITIONS = [
	Vector3(0.0, 1.5, -0.35),
	Vector3( 0.0, 1.5, -0.35),
	Vector3( 0.9, 1.5, -0.35),
	Vector3(-0.9, 1.5,  0.35),
	Vector3( 0.0, 1.5,  0.35),
	Vector3( 0.9, 1.5,  0.35),
]

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$Die.roll($Die.position)
	$Die2.roll($Die2.position)
	$Die3.roll($Die3.position)
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
