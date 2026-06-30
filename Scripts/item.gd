class_name ItemNode
extends StaticBody3D

signal activated(item_node: Node3D)

const MAX_CHARGES: int = 3

var item_type: String = ""
var charges: int = 0

var _selectable: bool = false
var _shop_mode: bool = false        # true while displayed as a pickable shop item
var _shop_selectable: bool = false  # true when this player may pick this shop item now

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _label: Label3D = $Label

const COLOR_HEATCHECKER := Color(0.85, 0.35, 0.05)
const COLOR_BLOWFLY     := Color(0.25, 0.65, 0.15)
const COLOR_ACTIVE      := Color(1.0, 0.88, 0.10)
const COLOR_DEPLETED    := Color(0.22, 0.22, 0.22)

var _mat: StandardMaterial3D


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mesh.set_surface_override_material(0, _mat)
	_refresh()


func setup(type: String) -> void:
	item_type = type
	_refresh()


func set_selectable(value: bool) -> void:
	_selectable = value
	_refresh()


func set_shop_mode(value: bool) -> void:
	_shop_mode = value
	_refresh()


func set_shop_selectable(value: bool) -> void:
	_shop_selectable = value
	_refresh()


func is_shop_selectable() -> bool:
	return _shop_mode and _shop_selectable


func add_charge() -> void:
	if charges < MAX_CHARGES:
		charges += 1
		_refresh()


func set_charges(n: int) -> void:
	charges = clampi(n, 0, MAX_CHARGES)
	_refresh()


func spend_charge() -> bool:
	if charges <= 0:
		return false
	charges -= 1
	_refresh()
	return true


func _refresh() -> void:
	if _mat == null:
		return
	var display_name: String = "Heatchecker" if item_type == "heatchecker" \
			else ("Blowfly" if item_type == "blowfly" else item_type)
	if _shop_mode:
		# Shop items have no charges yet; show only the name and never look depleted.
		# Keep the type color (red heatchecker / green blowfly) consistent on every
		# client; the item the local player may pick glows instead of recoloring.
		_label.text = display_name
		if item_type == "heatchecker":
			_mat.albedo_color = COLOR_HEATCHECKER
		else:
			_mat.albedo_color = COLOR_BLOWFLY
		_mat.emission_enabled = _shop_selectable
		if _shop_selectable:
			_mat.emission = COLOR_ACTIVE
			_mat.emission_energy_multiplier = 0.75
		return
	var pips: String = ""
	for i: int in MAX_CHARGES:
		pips += "●" if i < charges else "○"
	_label.text = "%s\n%s" % [display_name, pips]
	if _selectable and charges > 0:
		_mat.albedo_color = COLOR_ACTIVE
	elif charges == 0:
		_mat.albedo_color = COLOR_DEPLETED
	elif item_type == "heatchecker":
		_mat.albedo_color = COLOR_HEATCHECKER
	else:
		_mat.albedo_color = COLOR_BLOWFLY


func _input_event(_camera: Camera3D, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape: int) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _shop_mode:
				if _shop_selectable:
					activated.emit(self)
			elif _selectable and charges > 0:
				activated.emit(self)
