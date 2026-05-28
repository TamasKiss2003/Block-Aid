extends CharacterBody2D

const BLOCK_SIZE: int = 32
const JUMP_VELOCITY: float = -400.0
# Rolling
const ROLL_DURATION: float = 0.2
const ROLL_AXIS_TRESHOLD: float = 0.2
# Dashing
const DASH_SPEED: float = 500.0
const DASH_DISTANCE: int = 2
const MAX_DASH_COUNT: int = 1

var is_rolling = false
var is_dashing = false

var _dash_target_x = 0
var _dash_count = 0
var _pivot = Vector2.ZERO
var _start_pos = Vector2.ZERO
var _start_rot = 0.0
var _roll_angle = 0.0


func _can_roll(direction: int) -> bool:
	if is_rolling or not is_on_floor() or test_move(global_transform, Vector2(direction * BLOCK_SIZE, 0.0)):
		return false

	return true


func _can_dash() -> bool:
	if is_dashing or _dash_count >= MAX_DASH_COUNT or is_on_floor():
		return false

	return true


func _physics_process(delta: float) -> void:
	if is_dashing:
		move_and_slide()
		var past_target := (velocity.x > 0.0 and global_position.x >= _dash_target_x) \
		or (velocity.x < 0.0 and global_position.x <= _dash_target_x)
		if past_target:
			global_position.x = _dash_target_x
			velocity = Vector2.ZERO
			is_dashing = false
		elif is_on_wall():
			velocity = Vector2.ZERO
			is_dashing = false
		return

	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var dir = int(Input.is_action_just_pressed("ui_right")) - int(Input.is_action_just_pressed("ui_left"))
	if dir != 0:
		if is_on_floor():
			roll(dir)
		else:
			dash(dir)

	if is_on_floor():
		_dash_count = 0

	move_and_slide()


func _update_roll(t: float) -> void:
	var angle = _roll_angle * t
	global_position = _pivot + (_start_pos - _pivot).rotated(angle)
	rotation = _start_rot + angle


func roll(direction: int) -> void:
	if !_can_roll(direction):
		return

	is_rolling = true
	velocity = Vector2.ZERO
	_pivot = global_position + Vector2(direction * BLOCK_SIZE / 2.0, BLOCK_SIZE / 2.0)
	_start_pos = global_position
	_start_rot = rotation
	_roll_angle = direction * PI / 2.0

	var tween = create_tween()
	tween.tween_method(_update_roll, 0.0, 1.0, ROLL_DURATION)
	tween.tween_callback(func() -> void: is_rolling = false)


func dash(direction: int) -> void:
	if !_can_dash():
		return

	is_dashing = true
	_dash_count += 1
	_dash_target_x = global_position.x + direction * BLOCK_SIZE * DASH_DISTANCE
	velocity = Vector2(direction * DASH_SPEED, 0.0)
