extends CanvasLayer

@onready var player_label: Label = $PlayerLabel
@onready var scores_label: Label = $ScoresLabel
@onready var turn_score_label: Label = $TurnScoreLabel
@onready var status_label: Label = $StatusLabel
@onready var bank_button: Button = $BankButton
@onready var roll_button: Button = $RollButton

func _ready() -> void:
	GameManager.turn_started.connect(_on_turn_started)
	GameManager.dice_rolled.connect(_on_dice_rolled)
	GameManager.dice_selected.connect(_on_dice_selected)
	GameManager.turn_banked.connect(_on_turn_banked)
	GameManager.bust.connect(_on_bust)
	GameManager.hot_dice.connect(_on_hot_dice)
	GameManager.game_over.connect(_on_game_over)
	bank_button.pressed.connect(GameManager.bank)
	bank_button.disabled = true

func _on_turn_started(player_index: int) -> void:
	player_label.text = GameManager.players[player_index]["name"] + "'s Turn"
	turn_score_label.text = "Turn: 0"
	status_label.text = "Rolling..."
	bank_button.disabled = true
	roll_button.disabled = true
	_refresh_scores()

func _on_dice_rolled(_values: Array) -> void:
	status_label.text = "Select dice to score"
	bank_button.disabled = GameManager.turn_score == 0
	roll_button.disabled = false

func _on_dice_selected(_selected: Array, turn_score: int) -> void:
	turn_score_label.text = "Turn: %d" % turn_score
	bank_button.disabled = false

func _on_turn_banked(player_index: int, _banked: int, total: int) -> void:
	status_label.text = "%s banked! Total: %d" % [GameManager.players[player_index]["name"], total]
	_refresh_scores()

func _on_bust(player_index: int) -> void:
	status_label.text = "%s busted!" % GameManager.players[player_index]["name"]
	bank_button.disabled = true
	roll_button.disabled = true

func _on_hot_dice(player_index: int) -> void:
	status_label.text = "🔥 HOT DICE! All %d dice back!" % GameConfig.NUM_DICE

func _on_game_over(winner_index: int) -> void:
	status_label.text = "%s WINS!" % GameManager.players[winner_index]["name"]
	bank_button.disabled = true
	roll_button.disabled = true

func _refresh_scores() -> void:
	var lines := []
	for p in GameManager.players:
		lines.append("%s: %d" % [p["name"], p["score"]])
	scores_label.text = "\n".join(lines)
