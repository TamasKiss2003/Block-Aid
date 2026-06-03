extends CharacterBody2D

const BLOCK_SIZE := 32
const JUMP_VELOCITY := -450.0

# Rolling
const ROLL_DURATION := 0.2
const ROLL_AXIS_TRESHOLD := 0.2
const ROLL_SNAP_THRESHOLD := BLOCK_SIZE / 8.0
const ROLL_DURATION_EXPONENT := 0.8
const ROLL_END_DELAY := 0.05

# Dashing
const DASH_SPEED := 500.0
const DASH_DISTANCE := 3
const WALL_SLIDE_SPEED := 40.0

# Default abilities
@export var has_jump := false
@export var has_dash := false
# Acquired abilities
@export var has_wallclimb := false
@export var has_ceiling_crawl := false
@export var has_double_jump := false
@export var has_double_dash := false

var _max_dash_count: int:
	get:
		return 2 if has_double_dash else 1
var _is_rolling := false
var _air_jump_used := false
var _is_dashing := false
var _dash_target_x := 0.0
var _dash_count := 0
var _is_wall_stuck := false
var _is_ceiling_stuck := false
var _wall_stick_dir := 0
var _wall_stick_aligning := false
var _wall_tween: Tween = null


func die() -> void:
	get_tree().reload_current_scene()


func _physics_process(delta: float) -> void:
	if _is_dashing:
		_handle_dash()
		return
	if _is_wall_stuck or _is_ceiling_stuck:
		_handle_stick()
		return

	_handle_gravity(delta)
	_handle_movement()
	move_and_slide()

# Dash handling


func _handle_dash() -> void:
	move_and_slide()
	var past_target := (velocity.x > 0.0 and global_position.x >= _dash_target_x) \
	or (velocity.x < 0.0 and global_position.x <= _dash_target_x)
	if past_target:
		global_position.x = _dash_target_x
		velocity = Vector2.ZERO
		_is_dashing = false
	elif is_on_wall():
		var target_x_delta := _dash_target_x - global_position.x
		var dash_dir := 0 if abs(target_x_delta) < 1 else int(sign(target_x_delta))
		var floor_near := test_move(global_transform, Vector2(0.0, BLOCK_SIZE + ROLL_SNAP_THRESHOLD))
		velocity = Vector2.ZERO
		_is_dashing = false
		if not floor_near and dash_dir != 0:
			_is_wall_stuck = true
			_wall_stick_dir = dash_dir
			_dash_count = 0
			_align_to_wall_grid()


func _align_to_wall_grid() -> void:
	var target_y: float = ceil((global_position.y - BLOCK_SIZE / 2.0) / BLOCK_SIZE) * BLOCK_SIZE + BLOCK_SIZE / 2.0
	_tween_wall_y(target_y)


func _slide_down_wall() -> void:
	_tween_wall_y(global_position.y + BLOCK_SIZE)


func _tween_wall_y(target_y: float) -> void:
	if is_equal_approx(global_position.y, target_y):
		_on_wall_tween_done()
		return
	_wall_stick_aligning = true
	_wall_tween = create_tween()
	_wall_tween.tween_property(self, "global_position:y", target_y, abs(target_y - global_position.y) / WALL_SLIDE_SPEED)
	_wall_tween.tween_callback(_on_wall_tween_done)


func _on_wall_tween_done() -> void:
	_wall_stick_aligning = false
	_wall_tween = null

	if not _is_wall_stuck:
		return
	if not test_move(global_transform, Vector2(_wall_stick_dir * 1.0, 0.0)):
		_release_stick()
		return
	if not has_wallclimb:
		_slide_down_wall()

# Wall climb handling


func _handle_stick() -> void:
	velocity = Vector2.ZERO

	if _is_rolling:
		return

	if test_move(global_transform, Vector2.DOWN * BLOCK_SIZE / 2):
		_release_stick()
		return

	var horiz_dir := int(Input.is_action_just_pressed("ui_right")) - int(Input.is_action_just_pressed("ui_left"))
	var vert_dir := int(Input.is_action_just_pressed("ui_down")) - int(Input.is_action_just_pressed("ui_up"))

	if _is_ceiling_stuck and _is_wall_stuck:
		_handle_corner_input(horiz_dir, vert_dir)
	elif _is_wall_stuck:
		_handle_wall_input(horiz_dir, vert_dir)
	elif _is_ceiling_stuck:
		_handle_ceiling_input(horiz_dir, vert_dir)


func _handle_corner_input(horiz_dir: int, vert_dir: int) -> void:
	if horiz_dir == _wall_stick_dir:
		_release_stick()
		return

	if vert_dir != 0:
		var roll_success := _roll_wall(vert_dir, _get_vertical_roll_target(vert_dir))
		if roll_success:
			_is_ceiling_stuck = false
		return

	if horiz_dir != 0:
		var roll_success := _roll_ceiling(horiz_dir, _get_horizontal_roll_target(horiz_dir))
		if roll_success:
			_is_wall_stuck = false


func _handle_wall_input(horiz_dir: int, vert_dir: int) -> void:
	if horiz_dir == -_wall_stick_dir:
		_release_stick()
		_start_dash(horiz_dir)

	if _wall_stick_aligning:
		return

	if vert_dir != 0:
		var target := _get_vertical_roll_target(vert_dir)
		if not _roll_wall(vert_dir, target):
			target.x += _wall_stick_dir * BLOCK_SIZE
			_roll_climb(_wall_stick_dir, target)


func _handle_ceiling_input(horiz_dir: int, vert_dir: int) -> void:
	if vert_dir:
		_release_stick()

	if horiz_dir != 0:
		_roll_ceiling(horiz_dir, _get_horizontal_roll_target(horiz_dir))


func _release_stick(horizontal := true, vertical := true) -> void:
	_is_wall_stuck = !horizontal
	_is_ceiling_stuck = !vertical
	_wall_stick_aligning = false
	if _wall_tween:
		_wall_tween.kill()
		_wall_tween = null


func _get_vertical_roll_target(direction: int) -> Vector2:
	var top_edge = global_position.y - BLOCK_SIZE / 2.0
	var next_top = (floor(top_edge * direction / BLOCK_SIZE) + 1) * BLOCK_SIZE * direction
	if direction * (next_top - top_edge) < ROLL_SNAP_THRESHOLD:
		next_top += direction * BLOCK_SIZE
	return Vector2(global_position.x, next_top + BLOCK_SIZE / 2.0)


func _roll_wall(vert_dir: int, target: Vector2) -> bool:
	if not _can_wall_roll(target):
		return false

	var start_pivot = global_position + Vector2(_wall_stick_dir * BLOCK_SIZE / 2.0, vert_dir * BLOCK_SIZE / 2.0)
	var end_pivot = Vector2(target.x + _wall_stick_dir * BLOCK_SIZE / 2.0, target.y - vert_dir * BLOCK_SIZE / 2.0)
	var roll_angle := _wall_stick_dir * vert_dir * (-PI / 2.0)

	if not _is_roll_arc_clear(start_pivot, end_pivot, roll_angle):
		return false

	_is_rolling = true
	var tween := _perform_roll(start_pivot, end_pivot, roll_angle)
	tween.tween_callback(
		func() -> void:
			var is_still_stuck := test_move(global_transform, Vector2(float(_wall_stick_dir) * BLOCK_SIZE / 2, 0.0))
			if not is_still_stuck:
				_release_stick()
				return

			var has_reached_ceiling := test_move(global_transform, Vector2.UP * BLOCK_SIZE / 2)
			if has_reached_ceiling:
				_is_ceiling_stuck = true
	)
	return true


func _can_wall_roll(target: Vector2) -> bool:
	var delta := target - global_position
	if _is_rolling or _wall_stick_aligning or !has_wallclimb or !_is_wall_stuck or \
	test_move(global_transform.translated(delta), Vector2.ZERO) or \
	(not test_move(global_transform.translated(delta), Vector2(_wall_stick_dir * 1.0, 0.0)) and delta.y < 0):
		return false

	return true


func _roll_ceiling(direction: int, target: Vector2) -> bool:
	if !_can_ceiling_roll(target):
		return false

	var start_pivot = global_position + Vector2(direction * BLOCK_SIZE / 2.0, -BLOCK_SIZE / 2.0)
	var end_pivot = Vector2(target.x - direction * BLOCK_SIZE / 2.0, target.y - BLOCK_SIZE / 2.0)
	var roll_angle = direction * -PI / 2.0

	if not _is_roll_arc_clear(start_pivot, end_pivot, roll_angle):
		return false

	_is_rolling = true
	var tween := _perform_roll(start_pivot, end_pivot, roll_angle)
	tween.tween_callback(
		func() -> void:
			var is_still_stuck := test_move(global_transform, Vector2.UP * BLOCK_SIZE / 2)
			if not is_still_stuck:
				_release_stick()
				return
			var has_reached_wall := test_move(global_transform, Vector2.RIGHT * direction * BLOCK_SIZE / 2)
			if has_reached_wall:
				_is_wall_stuck = true
	)
	return true


func _can_ceiling_roll(target: Vector2):
	var delta_to_target := target - global_position
	if _is_rolling or !has_ceiling_crawl or !_is_ceiling_stuck or \
	test_move(global_transform.translated(delta_to_target), Vector2.ZERO):
		return false

	return true


func _is_roll_arc_clear(start_pivot: Vector2, end_pivot: Vector2, roll_angle: float) -> bool:
	var start_pos := global_position
	var start_rot := rotation
	var steps := int(round(abs(roll_angle) / (PI / 2.0))) * 2
	for i in range(1, steps + 1):
		var t := float(i) / float(steps + 1)
		var pivot := start_pivot.lerp(end_pivot, t)
		var angle := roll_angle * t
		var check_pos := pivot + (start_pos - start_pivot).rotated(angle)
		if test_move(Transform2D(start_rot + angle, check_pos), Vector2.ZERO):
			return false
	return true


func _handle_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		_dash_count = 0
		_air_jump_used = false

# Basic movement handling


func _handle_movement() -> void:
	if is_on_ceiling() and _air_jump_used:
		_stick_from_jump()

	if Input.is_action_just_pressed("ui_up"):
		_jump()

	if is_on_floor():
		var dir := int(Input.is_action_pressed("ui_right")) - int(Input.is_action_pressed("ui_left"))
		if dir == 0:
			return
		var target := _get_horizontal_roll_target(dir)
		var roll_success := _roll_sideways(dir, target)
		if not roll_success:
			target.y -= BLOCK_SIZE
			_roll_climb(dir, target)
	else:
		var dir := int(Input.is_action_just_pressed("ui_right")) - int(Input.is_action_just_pressed("ui_left"))
		if dir == 0:
			return
		_start_dash(dir)

func _stick_from_jump():
	_is_ceiling_stuck = true
	_air_jump_used = false
	var potential_wall_stick_dir := int(test_move(global_transform, Vector2.RIGHT * BLOCK_SIZE / 2)) - int(test_move(global_transform, Vector2.LEFT * BLOCK_SIZE / 2))
	if(potential_wall_stick_dir != 0):
		_is_wall_stuck = true
		_wall_stick_dir = potential_wall_stick_dir

func _jump() -> void:
	if !_can_jump():
		return

	if not is_on_floor():
		_air_jump_used = true
	velocity.y = JUMP_VELOCITY


func _can_jump() -> bool:
	if _is_rolling or not has_jump:
		return false
	if is_on_floor():
		return true
	return has_double_jump and not _air_jump_used


func _get_horizontal_roll_target(direction: int) -> Vector2:
	var left_edge = global_position.x - BLOCK_SIZE / 2.0
	var next_left = (floor(left_edge * direction / BLOCK_SIZE) + 1) * BLOCK_SIZE * direction
	if direction * (next_left - left_edge) < ROLL_SNAP_THRESHOLD:
		next_left += direction * BLOCK_SIZE
	return Vector2(next_left + BLOCK_SIZE / 2.0, global_position.y)


# No exceptions or try catch in gdscript so returning a boolean show the roll worked
func _roll_sideways(direction: int, target: Vector2) -> bool:
	if !_can_roll_sideways(target):
		return false

	var start_pivot = global_position + Vector2(direction * BLOCK_SIZE / 2.0, BLOCK_SIZE / 2.0)
	var end_pivot = Vector2(target.x - direction * BLOCK_SIZE / 2.0, target.y + BLOCK_SIZE / 2.0)
	var roll_angle = direction * PI / 2.0

	if not _is_roll_arc_clear(start_pivot, end_pivot, roll_angle):
		return false

	_is_rolling = true
	_perform_roll(start_pivot, end_pivot, roll_angle)
	return true


func _can_roll_sideways(target: Vector2) -> bool:
	var delta_to_target := target - global_position
	if _is_rolling or not is_on_floor() or test_move(global_transform.translated(delta_to_target), Vector2.ZERO):
		return false

	return true


func _roll_climb(direction: int, target: Vector2) -> bool:
	if !_can_roll_climb(target, direction):
		return false

	var start_pivot = global_position + Vector2(direction * BLOCK_SIZE / 2.0, -BLOCK_SIZE / 2.0)
	var end_pivot = Vector2(target.x - direction * BLOCK_SIZE / 2.0, target.y + BLOCK_SIZE / 2.0)
	var roll_angle = direction * PI

	if not _is_roll_arc_clear(start_pivot, end_pivot, roll_angle):
		return false

	_is_rolling = true
	_perform_roll(start_pivot, end_pivot, roll_angle)
	return true


func _can_roll_climb(target: Vector2, direction: int) -> bool:
	var delta_to_target := target - global_position
	if _is_rolling or \
	test_move(global_transform.translated(delta_to_target), Vector2.ZERO) or \
	!test_move(global_transform.translated(direction * Vector2.RIGHT * BLOCK_SIZE), Vector2.ZERO):
		return false

	return true


func _perform_roll(start_pivot: Vector2, end_pivot: Vector2, roll_angle: float) -> Tween:
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
			global_position.y = snapped(global_position.y - BLOCK_SIZE / 2.0, float(BLOCK_SIZE)) + BLOCK_SIZE / 2.0
			rotation = snapped(rotation, PI / 2.0)
	)
	tween.tween_interval(ROLL_END_DELAY)
	tween.tween_callback(func() -> void: _is_rolling = false)

	return tween

# Dash target setting


func _start_dash(direction: int) -> void:
	if !_can_dash():
		return

	_is_dashing = true
	_dash_count += 1
	_dash_target_x = _get_dash_target_x(direction)
	velocity = Vector2(direction * DASH_SPEED, 0.0)


func _can_dash() -> bool:
	if _is_dashing or _dash_count >= _max_dash_count or is_on_floor() or not has_dash:
		return false

	return true


func _get_dash_target_x(direction: int) -> float:
	var edge = global_position.x - direction * BLOCK_SIZE / 2.0
	var base = floor(edge * direction / BLOCK_SIZE) * BLOCK_SIZE * direction
	var offset = direction * (edge - base)
	var blocks = DASH_DISTANCE if offset < BLOCK_SIZE / 2.0 else DASH_DISTANCE + 1
	return base + direction * (blocks * BLOCK_SIZE + BLOCK_SIZE / 2.0)

# Event handlers


func _on_hit_box_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemy") and body.has_method("on_player_contact"):
		body.on_player_contact(self)
