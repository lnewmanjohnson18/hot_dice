extends Control

const PORT := 7777
const MAX_PLAYERS := 8

var _is_host := false

@onready var setup_panel: VBoxContainer = $CenterContainer/VBoxContainer/SetupPanel
@onready var lobby_panel: VBoxContainer = $CenterContainer/VBoxContainer/LobbyPanel
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel
@onready var ip_field: LineEdit = $CenterContainer/VBoxContainer/SetupPanel/IPLineEdit
@onready var player_list: VBoxContainer = $CenterContainer/VBoxContainer/LobbyPanel/PlayerList
@onready var start_button: Button = $CenterContainer/VBoxContainer/LobbyPanel/StartButton


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_host_button_pressed() -> void:
	_is_host = true
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		status_label.text = "Failed to start server."
		_is_host = false
		return
	multiplayer.multiplayer_peer = peer
	_show_lobby()
	_add_player_entry(1)  # Host is always peer ID 1
	status_label.text = "Hosting on port %d — waiting for players..." % PORT


func _on_join_button_pressed() -> void:
	var ip := ip_field.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		status_label.text = "Failed to connect."
		return
	multiplayer.multiplayer_peer = peer
	status_label.text = "Connecting to %s:%d..." % [ip, PORT]


func _on_start_button_pressed() -> void:
	start_game.rpc()


func _on_back_button_pressed() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer = null
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


# Only the host reacts to these signals — clients learn about peers via RPCs below.
func _on_peer_connected(id: int) -> void:
	if not _is_host:
		return
	var existing: Array = []
	for child in player_list.get_children():
		existing.append(int(child.name.trim_prefix("Player_")))
	_sync_player_list.rpc_id(id, existing)
	_add_player.rpc(id)
	status_label.text = "Waiting for players... (%d connected)" % player_list.get_child_count()


func _on_peer_disconnected(id: int) -> void:
	if not _is_host:
		return
	_remove_player.rpc(id)


func _on_connected_to_server() -> void:
	_show_lobby()
	status_label.text = "Connected — waiting for host to start..."


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	status_label.text = "Connection failed."


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	_show_setup()
	status_label.text = "Disconnected from host."


# Sent by host to ALL peers (including self) when someone joins.
@rpc("authority", "call_local", "reliable")
func _add_player(id: int) -> void:
	_add_player_entry(id)


# Sent by host to ALL peers (including self) when someone leaves.
@rpc("authority", "call_local", "reliable")
func _remove_player(id: int) -> void:
	_remove_player_entry(id)


# Sent by host to a single newly-connected client to backfill the existing player list.
@rpc("authority", "reliable")
func _sync_player_list(ids: Array) -> void:
	for id in ids:
		_add_player_entry(id)


@rpc("authority", "call_local", "reliable")
func start_game() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func _show_lobby() -> void:
	setup_panel.visible = false
	lobby_panel.visible = true
	start_button.visible = _is_host


func _show_setup() -> void:
	setup_panel.visible = true
	lobby_panel.visible = false
	_clear_player_list()


func _add_player_entry(id: int) -> void:
	if player_list.has_node("Player_%d" % id):
		return
	var label := Label.new()
	label.name = "Player_%d" % id
	var my_id := multiplayer.get_unique_id()
	var suffix := " (You)" if id == my_id else (" (Host)" if id == 1 else "")
	label.text = "Player %d%s" % [id, suffix]
	player_list.add_child(label)


func _remove_player_entry(id: int) -> void:
	var node := player_list.get_node_or_null("Player_%d" % id)
	if node:
		node.queue_free()


func _clear_player_list() -> void:
	for child in player_list.get_children():
		child.queue_free()
