class_name FollowCamera
extends Node3D
## Third-person orbit camera. Put it in the scene (NOT as a child of the target) and set `target`.
## Mouse (click to capture, Esc to release), Q/E, or the right stick orbits it. A SpringArm keeps it out of walls.
## Joins the "camera_shake" group: HitFx.shake() calls shake(amount) on it.
## Lock-on: when the target is a MonsterBody with a face_target, the camera swings behind the
## target, looking past it toward the enemy, and pulls back when they're far apart.

@export var target: Node3D
@export var distance := 7.5
@export var look_height := 1.4
@export_range(-80, 20) var pitch_deg := -22.0
@export var min_pitch_deg := -65.0
@export var max_pitch_deg := 5.0
@export var mouse_sens := 0.004
@export var stick_speed := 2.6
@export var follow := 10.0
## true (fights): a click captures the mouse for free-look, Esc frees it.
## false (menu screens): never capture; hold the RIGHT mouse button and drag to look around.
@export var capture_mouse := true
## Lock-on framing: steeper angle and an over-the-shoulder offset so the target isn't hidden.
@export var lock_pitch_deg := -26.0
@export var lock_shoulder := 1.3

var yaw := 0.0
## Sideways shift of the view in metres (a menu pane covers part of the screen and the subject should sit in the rest).
var frame_offset := 0.0
## true while a menu is open over the world: clicks and the wheel never capture the mouse or orbit the camera.
var ui_open := false
var cam: Camera3D
var _arm: SpringArm3D
var _shake := 0.0
var _shoulder := 0.0


func _ready() -> void:
	add_to_group("camera_shake")
	if not capture_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_arm = SpringArm3D.new()
	_arm.spring_length = distance
	_arm.margin = 0.3
	add_child(_arm)
	cam = Camera3D.new()
	cam.fov = 55.0
	_arm.add_child(cam)
	cam.current = true
	if target is CollisionObject3D:
		_arm.add_excluded_object((target as CollisionObject3D).get_rid())
	rotation = Vector3(deg_to_rad(pitch_deg), yaw, 0.0)
	if target != null and is_instance_valid(target):
		global_position = target.global_position + Vector3(0, look_height, 0)


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _unhandled_input(event: InputEvent) -> void:
	if ui_open:
		return
	if not capture_mouse:
		if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT):
			yaw -= event.relative.x * mouse_sens
			pitch_deg -= rad_to_deg(event.relative.y * mouse_sens)
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sens
		pitch_deg -= rad_to_deg(event.relative.y * mouse_sens)


func _process(delta: float) -> void:
	var st := Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
	yaw -= st.x * stick_speed * delta
	pitch_deg -= st.y * rad_to_deg(stick_speed) * 0.6 * delta
	pitch_deg = clampf(pitch_deg, min_pitch_deg, max_pitch_deg)
	if target != null and is_instance_valid(target):
		var goal := target.global_position + Vector3(0, look_height, 0)
		var dist := distance
		var foe := target.get("face_target") as Node3D
		var locked := foe != null and is_instance_valid(foe)
		_shoulder = lerpf(_shoulder, lock_shoulder if locked else 0.0, 1.0 - exp(-4.0 * delta))
		if locked:
			pitch_deg = lerpf(pitch_deg, lock_pitch_deg, 1.0 - exp(-3.0 * delta))
			var to := foe.global_position - target.global_position
			to.y = 0.0
			if to.length() > 0.5:
				yaw = lerp_angle(yaw, atan2(-to.x, -to.z), 1.0 - exp(-4.0 * delta))
				goal += to * 0.3
				dist += clampf(to.length() - 4.0, 0.0, 8.0) * 0.35
		_arm.spring_length = lerpf(_arm.spring_length, dist, 1.0 - exp(-4.0 * delta))
		global_position = global_position.lerp(goal, 1.0 - exp(-follow * delta))
	rotation = Vector3(deg_to_rad(pitch_deg), yaw, 0.0)
	_shake = maxf(0.0, _shake - delta * 2.0)
	cam.h_offset = _shoulder + frame_offset + randf_range(-1.0, 1.0) * _shake * 0.3
	cam.v_offset = randf_range(-1.0, 1.0) * _shake * 0.3

	var zone_node: Node = get_parent()
	while zone_node != null and not zone_node.has_method("ground"):
		zone_node = zone_node.get_parent()
	if zone_node != null and zone_node.has_method("ground"):
		var cp := cam.global_position
		var gy: float = float(zone_node.call("ground", cp.x, cp.z))
		var floor_y := gy + 0.45
		if cp.y < floor_y:
			cam.global_position.y = floor_y
