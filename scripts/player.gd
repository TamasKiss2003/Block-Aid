extends CharacterBody2D

const BLOCK_SIZE := 32
const JUMP_VELOCITY := -450.0

# Rolling
const ROLL_DURATION := 0.2
const ROLL_AXIS_TRESHOLD := 0.2
const ROLL_SNAP_THRESHOLD := BLOCK_SIZE / 4.0
const ROLL_DURATION_EXPONENT := 0.8
const ROLL_END_DELAY := 0.05

# Dashing
const DASH_SPEED := 500.0
const DASH_DISTANCE := 2
const MAX_DASH_COUNT := 1

var _is_rolling := false
var _is_dashing := false
var _dash_target_x := 0.0
var _dash_count := 0


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
	if Input.is_action_just_pressed("ui_accept") and is_on_floor() and !_is_rolling:
		velocity.y = JUMP_VELOCITY


func _handle_movement() -> void:
	if is_on_floor():
		var dir := int(Input.is_action_pressed("ui_right")) - int(Input.is_action_pressed("ui_left"))
		if dir == 0:
			return
		var target := _get_roll_target(dir)
		var roll_success := _roll_sideways(dir, target)
		if not roll_success:
			target.y -= BLOCK_SIZE
			_roll_climb(dir, target)
	else:
		var dir := int(Input.is_action_just_pressed("ui_right")) - int(Input.is_action_just_pressed("ui_left"))
		if dir == 0:
			return
		_start_dash(dir)


func _get_roll_target(direction: int) -> Vector2:
	var left_edge = global_position.x - BLOCK_SIZE / 2.0
	var next_left = (floor(left_edge * direction / BLOCK_SIZE) + 1) * BLOCK_SIZE * direction
	if direction * (next_left - left_edge) < ROLL_SNAP_THRESHOLD:
		next_left += direction * BLOCK_SIZE
	return Vector2(next_left + BLOCK_SIZE / 2.0, global_position.y)


# No exceptions or try catch in gdscript so returning a boolean show the roll worked
func _roll_sideways(direction: int, target: Vector2) -> bool:
	if !_can_roll(target):
		return false

	_is_rolling = true
	var start_pivot = global_position + Vector2(direction * BLOCK_SIZE / 2.0, BLOCK_SIZE / 2.0)
	var end_pivot = Vector2(target.x - direction * BLOCK_SIZE / 2.0, target.y + BLOCK_SIZE / 2.0)
	var roll_angle = direction * PI / 2.0

	_perform_roll(start_pivot, end_pivot, roll_angle)
	return true


func _roll_climb(direction: int, target: Vector2) -> void:
	if !_can_roll(target):
		return

	_is_rolling = true
	var start_pivot = global_position + Vector2(direction * BLOCK_SIZE / 2.0, -BLOCK_SIZE / 2.0)
	var end_pivot = Vector2(target.x - direction * BLOCK_SIZE / 2.0, target.y + BLOCK_SIZE / 2.0)
	var roll_angle = direction * PI

	_perform_roll(start_pivot, end_pivot, roll_angle)


func _can_roll(target: Vector2) -> bool:
	var delta_to_target := target - global_position
	if _is_rolling or not is_on_floor() or test_move(global_transform.translated(delta_to_target), Vector2.ZERO):
		return false

	return true


func _perform_roll(start_pivot: Vector2, end_pivot: Vector2, roll_angle: float) -> void:
	var start_pos = global_position
	var start_rot = rotation

	var tween = create_tween()
	tween.tween_method(
		func(t: float) -> void:
			var pivot = start_pivot.lerp(end_pivot, t)
			var angle = roll_angle * t
			global_position = pivot + (start_pos - start_pivot).rotated(angle)
			rotation = start_rot + angle,
		0.0,
		1.0,
		ROLL_DURATION * pow(abs(roll_angle / (PI / 2.0)), ROLL_DURATION_EXPONENT),
	)
	tween.tween_callback(
		func() -> void:
			global_position.x = snapped(global_position.x - BLOCK_SIZE / 2.0, float(BLOCK_SIZE)) + BLOCK_SIZE / 2.0
			rotation = snapped(rotation, PI / 2.0)
	)
	tween.tween_interval(ROLL_END_DELAY)
	tween.tween_callback(func() -> void: _is_rolling = false)


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
