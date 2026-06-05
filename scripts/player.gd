extends CharacterBody2D

const BLOCK_SIZE := 32
const JUMP_VELOCITY := -350.0
const SHRINK_DURATION := 0.15

# Rolling
const ROLL_DURATION := 0.2
const ROLL_AXIS_TRESHOLD := 0.2
const ROLL_DURATION_EXPONENT := 0.8

# Dashing
const DASH_SPEED := 500.0
const DASH_DISTANCE := 3
const WALL_SLIDE_SPEED := 40.0

# Touch input
const _SWIPE_THRESHOLD := 60.0
const _TAP_THRESHOLD := 25.0

# Maps semantic action names to Godot input actions (any one triggers it).
# "right"/"left" include tap so ground rolling works with a tap.
# "swipe_right"/"swipe_left" are swipe-only — used for dashing and wall movement.
const INPUT_ACTIONS := {
	"right": ["ui_right", "touch_tap_right"],
	"left": ["ui_left", "touch_tap_left"],
	"up": ["ui_up"],
	"down": ["ui_down"],
	"swipe_right": ["ui_right"],
	"swipe_left": ["ui_left"],
	"shrink": ["touch_shrink"],
	"grow": ["touch_grow"],
}

# Default abilities
@export var has_jump := false
@export var has_dash := false
# Acquired abilities
@export var has_wallclimb := false
@export var has_ceiling_crawl := false
@export var has_double_jump := false
@export var has_double_dash := false
@export var has_shrink := false

var _block_size: int = BLOCK_SIZE
var _half_block: float:
	get:
		return _block_size / 2.0

var _jump_velocity: float:
	get:
		return JUMP_VELOCITY * sqrt(float(_block_size) / BLOCK_SIZE)

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
var _is_shrunk := false
var _is_shrinking := false
var _touch_starts: Dictionary[int, Vector2] = { }
var _touch_current: Dictionary[int, Vector2] = { }
var _pinch_start_dist := -1.0
var _pinch_consumed := false


func _ready() -> void:
	var all_actions: Array[String] = []
	for actions: Array in INPUT_ACTIONS.values():
		all_actions.append_array(actions)
	for action: String in all_actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)


func die() -> void:
	get_tree().reload_current_scene()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_touch_down(event.index, event.position)
		elif _touch_starts.has(event.index):
			_on_touch_up(event.index, event.position)
	elif event is InputEventScreenDrag:
		_touch_current[event.index] = event.position


func _on_touch_down(idx: int, pos: Vector2) -> void:
	_touch_starts[idx] = pos
	_touch_current[idx] = pos
	if _touch_starts.size() == 2:
		var positions := _touch_current.values()
		_pinch_start_dist = positions[0].distance_to(positions[1])
		_pinch_consumed = false


func _on_touch_up(idx: int, pos: Vector2) -> void:
	var start := _touch_starts[idx]
	_touch_current[idx] = pos
	var pts := _touch_current.values()
	_touch_starts.erase(idx)
	_touch_current.erase(idx)

	if _pinch_start_dist < 0.0:
		_process_touch_gesture(start, pos - start)
		return

	if not _pinch_consumed:
		_process_pinch_gesture(pts[0].distance_to(pts[1]))
		_pinch_consumed = true
	if _touch_starts.is_empty():
		_pinch_start_dist = -1.0


func _process_pinch_gesture(end_dist: float) -> void:
	var dist_change := end_dist - _pinch_start_dist
	if abs(dist_change) < _SWIPE_THRESHOLD:
		return
	_fire_action("touch_shrink" if dist_change < 0 else "touch_grow")


func _process_touch_gesture(start: Vector2, delta: Vector2) -> void:
	var dist := delta.length()
	if dist < _TAP_THRESHOLD:
		var half_w := get_viewport().get_visible_rect().size.x / 2.0
		_fire_action("touch_tap_left" if start.x < half_w else "touch_tap_right")
		return
	if dist < _SWIPE_THRESHOLD:
		return
	if abs(delta.x) >= abs(delta.y):
		_fire_action("ui_right" if delta.x > 0 else "ui_left")
	else:
		_fire_action("ui_down" if delta.y > 0 else "ui_up")


func _fire_action(action: String) -> void:
	Input.action_press(action)
	call_deferred("_release_action", action)


func _release_action(action: String) -> void:
	Input.action_release(action)


func _is_just_pressed(action: String) -> bool:
	for raw: String in INPUT_ACTIONS[action]:
		if Input.is_action_just_pressed(raw):
			return true
	return false


func _physics_process(delta: float) -> void:
	if _is_dashing:
		_handle_dash()
		move_and_slide()
		return
	if not _is_rolling:
		_handle_shrink()
	if _is_shrinking:
		return
	if _is_wall_stuck or _is_ceiling_stuck:
		_handle_stick()
		move_and_slide()
		return

	_handle_gravity(delta)
	_handle_movement()
	move_and_slide()

# Shrink handling


func _handle_shrink() -> void:
	if _is_shrinking:
		return
	var want_toggle := Input.is_key_pressed(KEY_S)
	if _is_shrunk and (want_toggle or _is_just_pressed("grow")):
		_try_grow()
	elif not _is_shrunk and (want_toggle or _is_just_pressed("shrink")) and _can_shrink():
		_do_shrink()


func _can_shrink() -> bool:
	return has_shrink and (is_on_floor() or _is_wall_stuck or _is_ceiling_stuck)


func _get_shrink_offset() -> Vector2:
	var q := BLOCK_SIZE / 4.0
	if _is_wall_stuck:
		return Vector2(_wall_stick_dir * q, -_wall_stick_dir * q)
	elif _is_ceiling_stuck:
		return Vector2(-q, -q)
	else:
		return Vector2(q, q)


func _do_shrink() -> void:
	velocity = Vector2.ZERO
	_is_shrinking = true
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(0.5, 0.5), SHRINK_DURATION)
	tween.tween_property(self, "global_position", global_position + _get_shrink_offset(), SHRINK_DURATION)
	tween.set_parallel(false)
	tween.tween_callback(
		func() -> void:
			_block_size = int(float(BLOCK_SIZE) / 2)
			_is_shrunk = true
			_is_shrinking = false
			var potential_wall_stick_dir := int(test_move(global_transform, Vector2.RIGHT * _half_block)) - int(test_move(global_transform, Vector2.LEFT * _half_block))
			if potential_wall_stick_dir != 0:
				_wall_stick_dir = potential_wall_stick_dir
			_is_wall_stuck = test_move(global_transform.translated(Vector2.RIGHT * _block_size * _wall_stick_dir), Vector2.ZERO)
			_is_ceiling_stuck = test_move(global_transform.translated(Vector2.UP * _block_size), Vector2.ZERO)
	)


func _try_grow() -> void:
	velocity = Vector2.ZERO
	var grow_center := Vector2(
		snapped(global_position.x - BLOCK_SIZE / 2.0, float(BLOCK_SIZE)) + BLOCK_SIZE / 2.0,
		snapped(global_position.y - BLOCK_SIZE / 2.0, float(BLOCK_SIZE)) + BLOCK_SIZE / 2.0,
	)
	scale = Vector2(1.0, 1.0)
	if test_move(Transform2D(rotation, grow_center), Vector2.ZERO):
		scale = Vector2(0.5, 0.5)
		return
	scale = Vector2(0.5, 0.5)
	_is_shrinking = true
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), SHRINK_DURATION)
	tween.tween_property(self, "global_position", grow_center, SHRINK_DURATION)
	tween.set_parallel(false)
	tween.tween_callback(
		func() -> void:
			_block_size = BLOCK_SIZE
			_is_shrunk = false
			_is_shrinking = false
			if _is_ceiling_stuck:
				_is_wall_stuck = test_move(global_transform.translated(Vector2.RIGHT * _block_size * _wall_stick_dir), Vector2.ZERO)
				return
			if _is_wall_stuck:
				_is_ceiling_stuck = test_move(global_transform.translated(Vector2.UP * _block_size), Vector2.ZERO)
	)

# Dash handling


func _handle_dash() -> void:
	move_and_slide()
	var past_target := (velocity.x > 0.0 and global_position.x >= _dash_target_x) \
	or (velocity.x < 0.0 and global_position.x <= _dash_target_x)
	if past_target:
		global_position.x = _dash_target_x
		velocity = Vector2.ZERO
		_is_dashing = false
		return
	if not is_on_wall():
		return
	var target_x_delta := _dash_target_x - global_position.x
	var dash_dir := 0 if abs(target_x_delta) < 1 else int(sign(target_x_delta))
	var floor_near := test_move(global_transform, Vector2(0.0, _block_size + _block_size / 8.0))
	velocity = Vector2.ZERO
	_is_dashing = false
	if not floor_near and dash_dir != 0:
		_is_wall_stuck = true
		_wall_stick_dir = dash_dir
		_dash_count = 0
		_align_to_wall_grid()


func _align_to_wall_grid() -> void:
	var target_y: float = ceil((global_position.y - _half_block) / _block_size) * _block_size + _half_block
	_tween_wall_y(target_y)


func _slide_down_wall() -> void:
	_tween_wall_y(global_position.y + _block_size)


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
	if not test_move(global_transform, Vector2(float(_wall_stick_dir), 0.0)):
		_release_stick()
		return
	if not has_wallclimb and not test_move(global_transform, Vector2.DOWN * _half_block):
		_slide_down_wall()

# Wall climb handling


func _handle_stick() -> void:
	velocity = Vector2.ZERO

	if _is_rolling:
		return

	if test_move(global_transform, Vector2.DOWN * _half_block):
		if _is_wall_stuck:
			_is_ceiling_stuck = false
		else:
			_release_stick()
			return

	var horiz_dir := int(_is_just_pressed("right")) - int(_is_just_pressed("left"))
	var wall_horiz_dir := int(_is_just_pressed("swipe_right")) - int(_is_just_pressed("swipe_left"))
	var vert_dir := int(_is_just_pressed("down")) - int(_is_just_pressed("up"))

	if _is_ceiling_stuck and _is_wall_stuck:
		_handle_corner_input(horiz_dir, vert_dir)
	elif _is_wall_stuck:
		_handle_wall_input(wall_horiz_dir, vert_dir)
	elif _is_ceiling_stuck:
		_handle_ceiling_input(horiz_dir, vert_dir)


func _handle_corner_input(horiz_dir: int, vert_dir: int) -> void:
	if (horiz_dir == _wall_stick_dir and not _is_reverse_stepup(horiz_dir)) or vert_dir == -1:
		_release_stick()
		return

	if vert_dir != 0:
		var target := _get_roll_target(vert_dir, false)
		if _is_reverse_stepup(_wall_stick_dir):
			_roll_reverse_stepup(_wall_stick_dir, Vector2(target.x + _wall_stick_dir * _block_size, target.y - _block_size))
			return
		if _roll_wall(vert_dir, target):
			_is_ceiling_stuck = false
		return

	if horiz_dir != 0:
		var roll_target := _get_roll_target(horiz_dir, true)
		var has_landing_block := test_move(global_transform.translated(Vector2(_block_size * horiz_dir, -_block_size)), Vector2.ZERO)
		if not has_landing_block and horiz_dir != _wall_stick_dir:
			_roll_reverse_stepdown(horiz_dir, roll_target + Vector2.UP * _block_size)
			return
		if _roll_ceiling(horiz_dir, roll_target):
			_is_wall_stuck = false
		elif _is_reverse_stepup(horiz_dir):
			_roll_reverse_stepup(horiz_dir, roll_target)


func _handle_wall_input(horiz_dir: int, vert_dir: int) -> void:
	if horiz_dir == -_wall_stick_dir:
		_release_stick()
		if test_move(global_transform, Vector2.DOWN * _block_size):
			var target := _get_roll_target(horiz_dir, true)
			_roll_sideways(horiz_dir, target)
		else:
			_start_dash(horiz_dir)
	elif horiz_dir == _wall_stick_dir:
		_release_stick()
		return

	if _wall_stick_aligning:
		return

	if vert_dir != 0:
		var target := _get_roll_target(vert_dir, false)
		if _is_reverse_stepup(_wall_stick_dir) and vert_dir > 0:
			_roll_reverse_stepup(_wall_stick_dir, Vector2(target.x + _wall_stick_dir * _block_size, target.y - _block_size))
			return
		if _roll_wall(vert_dir, target):
			return
		target.x += _wall_stick_dir * _block_size
		_roll_climb(_wall_stick_dir, target)


func _handle_ceiling_input(horiz_dir: int, vert_dir: int) -> void:
	if vert_dir:
		_release_stick()

	if horiz_dir != 0:
		var roll_target := _get_roll_target(horiz_dir, true)
		var has_landing_block := test_move(global_transform.translated(Vector2(_block_size * horiz_dir, -_block_size)), Vector2.ZERO)
		if not has_landing_block:
			_roll_reverse_stepdown(horiz_dir, roll_target + Vector2.UP * _block_size)
			return
		_roll_ceiling(horiz_dir, roll_target)


func _release_stick(horizontal := true, vertical := true) -> void:
	_is_wall_stuck = not horizontal
	_is_ceiling_stuck = not vertical
	_wall_stick_aligning = false
	if _wall_tween:
		_wall_tween.kill()
		_wall_tween = null


func _get_roll_target(direction: int, horizontal: bool) -> Vector2:
	var pos := global_position.x if horizontal else global_position.y
	var edge := pos - _half_block
	var next: float = (floor(edge * direction / _block_size) + 1) * _block_size * direction
	if direction * (next - edge) < _block_size / 8.0:
		next += direction * _block_size
	return Vector2(next + _half_block, global_position.y) if horizontal \
	else Vector2(global_position.x, next + _half_block)


func _is_reverse_stepup(dir: int) -> bool:
	return not test_move(global_transform.translated(Vector2(_block_size * dir, _block_size)), Vector2.ZERO)


func _attempt_roll(start_pivot: Vector2, end_pivot: Vector2, roll_angle: float, on_done: Callable) -> bool:
	if not _is_roll_arc_clear(start_pivot, end_pivot, roll_angle):
		return false
	_is_rolling = true
	_perform_roll(start_pivot, end_pivot, roll_angle).tween_callback(on_done)
	return true


func _roll_wall(vert_dir: int, target: Vector2) -> bool:
	if not _can_wall_roll(target):
		return false

	var start_pivot := global_position + Vector2(_wall_stick_dir * _half_block, vert_dir * _half_block)
	var end_pivot := Vector2(target.x + _wall_stick_dir * _half_block, target.y - vert_dir * _half_block)
	return _attempt_roll(
		start_pivot,
		end_pivot,
		_wall_stick_dir * vert_dir * (-PI / 2.0),
		func() -> void:
			if not test_move(global_transform, Vector2(float(_wall_stick_dir) * _half_block, 0.0)):
				_release_stick()
				return
			if test_move(global_transform, Vector2.UP * _half_block):
				_is_ceiling_stuck = true
	)


func _can_stick_roll(target: Vector2, ability: bool, is_stuck: bool) -> bool:
	return not _is_rolling and ability and is_stuck \
	and not test_move(global_transform.translated(target - global_position), Vector2.ZERO)


func _can_wall_roll(target: Vector2) -> bool:
	if not _can_stick_roll(target, has_wallclimb, _is_wall_stuck):
		return false
	var delta := target - global_position
	return test_move(global_transform.translated(delta), Vector2(_wall_stick_dir * 1.0, 0.0)) or delta.y >= 0


func _roll_ceiling(direction: int, target: Vector2) -> bool:
	if not _can_ceiling_roll(target):
		return false

	var start_pivot := global_position + Vector2(direction * _half_block, -_half_block)
	var end_pivot := Vector2(target.x - direction * _half_block, target.y - _half_block)
	return _attempt_roll(
		start_pivot,
		end_pivot,
		direction * -PI / 2.0,
		func() -> void:
			if not test_move(global_transform, Vector2.UP * _half_block):
				_release_stick()
				return
			if test_move(global_transform, Vector2.RIGHT * direction * _half_block):
				_is_wall_stuck = true
				_wall_stick_dir = direction
	)


func _roll_reverse_stepdown(direction: int, target: Vector2) -> bool:
	if not _can_ceiling_roll(target):
		return false

	var start_pivot := global_position + Vector2(direction * _half_block, -_half_block)
	var end_pivot := Vector2(target.x - direction * _half_block, target.y + _half_block)
	return _attempt_roll(
		start_pivot,
		end_pivot,
		direction * -PI,
		func() -> void:
			if not test_move(global_transform, Vector2.UP * _half_block):
				_is_ceiling_stuck = false
				if !has_wallclimb:
					_release_stick()
					return

			_is_wall_stuck = true
			_wall_stick_dir = -direction
	)


func _can_ceiling_roll(target: Vector2) -> bool:
	return _can_stick_roll(target, has_ceiling_crawl, _is_ceiling_stuck)


func _roll_reverse_stepup(direction: int, target: Vector2) -> bool:
	if not _can_reverse_stepup():
		return false

	var start_pivot := global_position + Vector2(direction * _half_block, _half_block)
	var end_pivot := Vector2(target.x - direction * _half_block, target.y + _half_block)
	return _attempt_roll(
		start_pivot,
		end_pivot,
		direction * -PI,
		func() -> void:
			if not test_move(global_transform, Vector2.RIGHT * direction * _half_block):
				_is_wall_stuck = false
			_is_ceiling_stuck = true
	)


func _can_reverse_stepup() -> bool:
	return not _is_rolling and has_ceiling_crawl and (_is_ceiling_stuck or _is_wall_stuck)


func _is_roll_arc_clear(start_pivot: Vector2, end_pivot: Vector2, roll_angle: float) -> bool:
	var start_pos := global_position
	var start_rot := rotation
	var steps := int(round(abs(roll_angle) / (PI / 2.0))) * 2
	for i in range(1, steps + 1):
		var t := float(i) / float(steps + 1)
		var pivot := start_pivot.lerp(end_pivot, t)
		var angle := roll_angle * t
		var check_pos := pivot + (start_pos - start_pivot).rotated(angle)
		if test_move(Transform2D(start_rot + angle, scale, 0.0, check_pos), Vector2.ZERO):
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
	if _is_rolling:
		return

	if is_on_ceiling() and _air_jump_used:
		_stick_from_jump()

	if _is_just_pressed("up"):
		_jump()

	if is_on_floor():
		var dir := int(_is_just_pressed("right")) - int(_is_just_pressed("left"))
		if dir == 0:
			return
		var target := _get_roll_target(dir, true)
		if _roll_sideways(dir, target):
			return
		target.y -= _block_size
		if _roll_climb(dir, target):
			return
		_try_floor_wall_stick(dir)
	else:
		var dir := int(_is_just_pressed("swipe_right")) - int(_is_just_pressed("swipe_left"))
		if dir == 0:
			return
		_start_dash(dir)


func _try_floor_wall_stick(dir: int) -> void:
	if not test_move(global_transform, Vector2(float(dir), 0.0)):
		return
	_is_wall_stuck = true
	_wall_stick_dir = dir


func _stick_from_jump() -> void:
	if !has_ceiling_crawl:
		return
	_is_ceiling_stuck = true
	_air_jump_used = false
	var potential_wall_stick_dir := int(test_move(global_transform, Vector2.RIGHT * _half_block)) - int(test_move(global_transform, Vector2.LEFT * _half_block))
	if potential_wall_stick_dir != 0:
		_is_wall_stuck = true
		_wall_stick_dir = potential_wall_stick_dir


func _jump() -> void:
	if not _can_jump():
		return

	if not is_on_floor():
		_air_jump_used = true
	velocity.y = _jump_velocity


func _can_jump() -> bool:
	if _is_rolling or not has_jump:
		return false
	if is_on_floor():
		return true
	return has_double_jump and not _air_jump_used


# No exceptions or try catch in gdscript so returning a boolean shows the roll worked
func _roll_sideways(direction: int, target: Vector2) -> bool:
	if not _can_roll_sideways(target):
		return false

	var start_pivot := global_position + Vector2(direction * _half_block, _half_block)
	var end_pivot := Vector2(target.x - direction * _half_block, target.y + _half_block)
	return _attempt_roll(start_pivot, end_pivot, direction * PI / 2.0, func() -> void: pass)


func _can_roll_sideways(target: Vector2) -> bool:
	return not _is_rolling and is_on_floor() \
	and not test_move(global_transform.translated(target - global_position), Vector2.ZERO)


func _roll_climb(direction: int, target: Vector2) -> bool:
	if not _can_roll_climb(target, direction):
		return false

	var start_pivot := global_position + Vector2(direction * _half_block, -_half_block)
	var end_pivot := Vector2(target.x - direction * _half_block, target.y + _half_block)
	return _attempt_roll(start_pivot, end_pivot, direction * PI, func() -> void: _is_wall_stuck = false)


func _can_roll_climb(target: Vector2, direction: int) -> bool:
	return not _is_rolling \
	and not test_move(global_transform.translated(target - global_position), Vector2.ZERO) \
	and test_move(global_transform.translated(direction * Vector2.RIGHT * _block_size), Vector2.ZERO)


func _perform_roll(start_pivot: Vector2, end_pivot: Vector2, roll_angle: float) -> Tween:
	var start_pos := global_position
	var start_rot := rotation

	var tween := create_tween()
	tween.tween_method(
		func(t: float) -> void:
			var pivot := start_pivot.lerp(end_pivot, t)
			var angle := roll_angle * t
			global_position = pivot + (start_pos - start_pivot).rotated(angle)
			rotation = start_rot + angle,
		0.0,
		1.0,
		ROLL_DURATION * pow(abs(roll_angle / (PI / 2.0)), ROLL_DURATION_EXPONENT),
	)
	tween.tween_callback(
		func() -> void:
			global_position.x = snapped(global_position.x - _half_block, float(_block_size)) + _half_block
			global_position.y = snapped(global_position.y - _half_block, float(_block_size)) + _half_block
			rotation = snapped(rotation, PI / 2.0)
	)
	# tween.tween_interval(ROLL_END_DELAY)
	tween.tween_callback(func() -> void: _is_rolling = false)

	return tween

# Dash target setting


func _start_dash(direction: int) -> void:
	if not _can_dash():
		return

	_is_dashing = true
	_dash_count += 1
	_dash_target_x = _get_dash_target_x(direction)
	velocity = Vector2(direction * DASH_SPEED, 0.0)


func _can_dash() -> bool:
	return not _is_dashing and _dash_count < _max_dash_count and not is_on_floor() and has_dash


func _get_dash_target_x(direction: int) -> float:
	var edge := global_position.x - direction * _half_block
	var base: float = floor(edge * direction / _block_size) * _block_size * direction
	var offset: float = direction * (edge - base)
	var blocks := DASH_DISTANCE if offset < _half_block else DASH_DISTANCE + 1
	return base + direction * (blocks * _block_size + _half_block)

# Event handlers


func _on_hit_box_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemy") and body.has_method("on_player_contact"):
		body.on_player_contact(self)
