extends Node3D

const DieScene := preload("res://scenes/dice/Die.tscn")

var _dice: Array[Node] = []
var _settled_count := 0
var _roll_values: Array[int] = []

func _ready() -> void:
	GameManager.turn_started.connect(_on_turn_started)
	GameManager.setup(["Player 1", "Player 2"])
	GameManager.start_game()

func _on_turn_started(_player_index: int) -> void:
	_spawn_dice(GameManager.dice_in_play)

func _spawn_dice(count: int) -> void:
	for die in _dice:
		die.queue_free()
	_dice.clear()
	_settled_count = 0
	_roll_values.clear()

	for i in count:
		var die: RigidBody3D = DieScene.instantiate()
		add_child(die)
		die.position = Vector3(randf_range(-2.0, 2.0), 3.0, randf_range(-2.0, 2.0))
		die.settled.connect(_on_die_settled)
		_dice.append(die)
		die.roll()

func _on_die_settled(face_value: int) -> void:
	_settled_count += 1
	_roll_values.append(face_value)
	if _settled_count == _dice.size():
		GameManager.on_roll_complete(_roll_values)
