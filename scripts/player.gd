extends CharacterBody2D

const BLOCK_SIZE: int = 32
const JUMP_VELOCITY: float = -450.0

# Rolling
const ROLL_DURATION: float = 0.2
const ROLL_AXIS_TRESHOLD: float = 0.2
const ROLL_SNAP_THRESHOLD: float = BLOCK_SIZE / 4.0

# Dashing
const DASH_SPEED: float = 500.0
const DASH_DISTANCE: int = 2
const MAX_DASH_COUNT: int = 1

var _is_rolling = false
var _is_dashing = false
var _dash_target_x = 0.0
var _dash_count = 0


func die() -> void:
	get_tree().reload_current_scene()


func _physics_process(delta: float) -> void:
	if _is_dashing:
		_perform_dash()
		return

	_handle_gravity(delta)
	_handle_jump()
	_handle_movement()
	move_and_slide()


func _perform_dash() -> void:
	move_and_slide()
	var past_target := (velocity.x > 0.0 and global_position.x >= _dash_target_x) \
	or (velocity.x < 0.0 and global_position.x <= _dash_target_x)
	if past_target:
		global_position.x = _dash_target_x
		velocity = Vector2.ZERO
		_is_dashing = false
	elif is_on_wall():
		velocity = Vector2.ZERO
		_is_dashing = false


func _handle_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		_dash_count = 0


func _handle_jump() -> void:
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY


func _handle_movement() -> void:
	var dir := _get_input_dir()
	if dir == 0:
		return
	if is_on_floor():
		_roll(dir)
	else:
		_start_dash(dir)


func _get_input_dir() -> int:
	return int(Input.is_action_just_pressed("ui_right")) - int(Input.is_action_just_pressed("ui_left"))


func _roll(direction: int) -> void:
	var target_x = _get_roll_target_x(direction)
	if !_can_roll(target_x):
		return

	_is_rolling = true
	var start_pivot = global_position + Vector2(direction * BLOCK_SIZE / 2.0, BLOCK_SIZE / 2.0)
	var end_pivot = Vector2(target_x - direction * BLOCK_SIZE / 2.0, global_position.y + BLOCK_SIZE / 2.0)
	var start_pos = global_position
	var start_rot = rotation
	var roll_angle = direction * PI / 2.0

	var tween = create_tween()
	tween.tween_method(
		func(t: float) -> void:
			var pivot = start_pivot.lerp(end_pivot, t)
			var angle = roll_angle * t
			global_position = pivot + (start_pos - start_pivot).rotated(angle)
			rotation = start_rot + angle,
		0.0,
		1.0,
		ROLL_DURATION,
	)
	tween.tween_callback(
		func() -> void:
			global_position.x = snapped(global_position.x - BLOCK_SIZE / 2.0, float(BLOCK_SIZE)) + BLOCK_SIZE / 2.0
			rotation = snapped(rotation, PI / 2.0)
			_is_rolling = false
	)


func _get_roll_target_x(direction: int) -> float:
	var left_edge = global_position.x - BLOCK_SIZE / 2.0
	var next_left = (floor(left_edge * direction / BLOCK_SIZE) + 1) * BLOCK_SIZE * direction
	if direction * (next_left - left_edge) < ROLL_SNAP_THRESHOLD:
		next_left += direction * BLOCK_SIZE
	return next_left + BLOCK_SIZE / 2.0


func _can_roll(target: float) -> bool:
	var delta_to_target = target - global_position.x
	if _is_rolling or not is_on_floor() or test_move(global_transform, Vector2(delta_to_target, 0.0)):
		return false

	return true


func _start_dash(direction: int) -> void:
	if !_can_dash():
		return

	_is_dashing = true
	_dash_count += 1
	_dash_target_x = _get_dash_target_x(direction)
	velocity = Vector2(direction * DASH_SPEED, 0.0)


func _can_dash() -> bool:
	if _is_dashing or _dash_count >= MAX_DASH_COUNT or is_on_floor():
		return false

	return true


func _get_dash_target_x(direction: int) -> float:
	var edge = global_position.x - direction * BLOCK_SIZE / 2.0
	var base = floor(edge * direction / BLOCK_SIZE) * BLOCK_SIZE * direction
	var offset = direction * (edge - base)
	var blocks = DASH_DISTANCE if offset < BLOCK_SIZE / 2.0 else DASH_DISTANCE + 1
	return base + direction * (blocks * BLOCK_SIZE + BLOCK_SIZE / 2.0)


func _on_hit_box_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemy") and body.has_method("on_player_contact"):
		body.on_player_contact(self)
