extends Node

signal turn_started(player_index: int)
signal dice_rolled(values: Array)
signal dice_selected(selected_values: Array, turn_score: int)
signal turn_banked(player_index: int, banked_score: int, total_score: int)
signal bust(player_index: int)
signal hot_dice(player_index: int)
signal game_over(winner_index: int)

enum State { IDLE, ROLLING, SELECTING, GAME_OVER }

var players: Array[Dictionary] = []
var current_player := 0
var turn_score := 0
var dice_in_play := GameConfig.NUM_DICE
var state := State.IDLE

func setup(player_names: Array) -> void:
	players.clear()
	for name in player_names:
		players.append({ "name": name, "score": 0 })
	current_player = 0
	turn_score = 0
	dice_in_play = GameConfig.NUM_DICE
	state = State.IDLE

func start_game() -> void:
	state = State.ROLLING
	emit_signal("turn_started", current_player)

func on_roll_complete(values: Array) -> void:
	emit_signal("dice_rolled", values)
	if not ScoringEngine.has_any_score(values):
		_bust()

func on_dice_selected(selected_values: Array) -> void:
	var points := ScoringEngine.score(selected_values)
	turn_score += points
	dice_in_play -= selected_values.size()
	emit_signal("dice_selected", selected_values, turn_score)

	if dice_in_play == 0:
		dice_in_play = GameConfig.NUM_DICE
		emit_signal("hot_dice", current_player)

func bank() -> void:
	var p: Dictionary = players[current_player]
	p["score"] += turn_score
	emit_signal("turn_banked", current_player, turn_score, p["score"])
	if p["score"] >= GameConfig.WIN_SCORE:
		state = State.GAME_OVER
		emit_signal("game_over", current_player)
	else:
		_next_turn()

func _bust() -> void:
	turn_score = 0
	emit_signal("bust", current_player)
	_next_turn()

func _next_turn() -> void:
	current_player = (current_player + 1) % players.size()
	turn_score = 0
	dice_in_play = GameConfig.NUM_DICE
	state = State.ROLLING
	emit_signal("turn_started", current_player)
