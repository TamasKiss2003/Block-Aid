extends Camera2D

@export var target: NodePath
var _target_node: Node


func _ready() -> void:
	_target_node = get_node(target)


func _process(_delta: float) -> void:
	if _target_node:
		global_position = _target_node.global_position
