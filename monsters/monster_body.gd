class_name MonsterBody
extends CharacterBody3D
## A kami in the 3D world: physics body + model + movement + visual motion.
##
## No input and no AI in here. A controller child node (PlayerController, later AIController)
## steers it by setting `move_dir`, `guarding` and calling `dodge()` / Attacker.use(). That way the
## player and enemies share one body and differ only in who drives them.
## Combat parts are child nodes in monster_body.tscn: Health, Hurtbox, Attacker.
##
##   var b := preload("res://kami/monster_body.tscn").instantiate()
##   b.data = some_monster_data   # optional: left null, it summons this machine's kami
##   add_child(b)

signal dodged

## Movement feel per body class (see BESTIARY.md). speed multiplies the stat-based top speed.
const CLASS_MOVE := {
	"brute": {"speed": 0.85, "accel": 14.0, "turn": 7.0},
	"stalker": {"speed": 1.2, "accel": 32.0, "turn": 16.0},
	"duelist": {"speed": 1.05, "accel": 26.0, "turn": 14.0},
	"caster": {"speed": 0.95, "accel": 18.0, "turn": 10.0},
	"bulwark": {"speed": 0.8, "accel": 12.0, "turn": 6.0},
	"flyer": {"speed": 1.1, "accel": 16.0, "turn": 9.0, "hover": 0.5},
}
const DODGE_SPEED := 15.0
const DODGE_TIME := 0.22
const DODGE_CD := 0.8
const GRAVITY := 25.0
const GUARD_MOVE := 0.4

@export var data: MonsterData

## Set by the controller every physics frame. World space, length 0..1.
var move_dir := Vector3.ZERO
## Optional lock-on: face this node instead of the move direction.
var face_target: Node3D
## Where the kami is facing (world space, flat). Models face +Z; starts facing away from a default camera.
var face_dir := Vector3(0, 0, -1)
var top_speed := 6.0
var model: Node3D
## Held by the controller: slower movement, damage x0.4 (see Damage).
var guarding := false
## Set by Attacker while a move plays: input movement is ignored.
var move_lock := false
## Animation-only walking (0..1 of top speed) for drills shown without moving the body.
var in_place := 0.0
## Wind-up glow 0..1, set by Attacker.
var charge := 0.0
@onready var health := $Health as Health

var _move: Dictionary = CLASS_MOVE["brute"]
var _dodge_t := 0.0
var _dodge_cd := 0.0
var _dash := Vector3.ZERO
var _t := 0.0
var _visual: Node3D  # pivot that turns/leans/bobs; the model sits inside it
var _knock := Vector3.ZERO
var _knock_prev := Vector3.ZERO
var _stun := 0.0
var _flash := 0.0


var _was_busy := false
var _ko_height := 1.0


func _ready() -> void:
	if data == null:
		data = Summoner.summon_machine()
	_build()


func is_dodging() -> bool:
	return _dodge_t > 0.0


## Dodge i-frames: hits pass through while dashing.
func is_invulnerable() -> bool:
	return _dodge_t > 0.0


func is_stunned() -> bool:
	return _stun > 0.0


func knock(v: Vector3) -> void:
	_knock += Vector3(v.x, 0.0, v.z)


func stun(t: float) -> void:
	_stun = maxf(_stun, t)


func flash() -> void:
	_flash = 1.0
	MonsterModel.play_action(model, "Hit")


func dodge_cooldown_left() -> float:
	return _dodge_cd


func dodge_ready() -> bool:
	return _dodge_cd <= 0.0 and _dodge_t <= 0.0


## Dash in the move direction (or backwards if standing still). Returns false while on cooldown.
func dodge() -> bool:
	if not dodge_ready() or is_stunned() or move_lock or health.is_dead():
		return false
	var d := move_dir if move_dir.length() > 0.1 else -face_dir
	_dash = Vector3(d.x, 0.0, d.z).normalized() * DODGE_SPEED
	_dodge_t = DODGE_TIME
	_dodge_cd = DODGE_CD
	Sound.sfx("dodge", -9.0, 0.05)
	dodged.emit()
	return true


func _build() -> void:
	if _visual != null:
		_visual.queue_free()
	var def := data.main_def()
	_move = CLASS_MOVE.get(def.body_class, CLASS_MOVE["brute"])
	top_speed = (5.0 + float(data.stat("speed")) * 0.03) * float(_move["speed"])

	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	model = MonsterModel.create(data.model_dict())
	_visual.add_child(model)

	# Capsule sized from the model, so big brutes are big to hit and small stalkers are small.
	var ab := MonsterModel.bounds(model)
	var cap := CapsuleShape3D.new()
	cap.radius = clampf(minf(ab.size.x, ab.size.z) * 0.32, 0.35, 0.75)  # body, not wingspan or hair
	cap.height = maxf(cap.radius * 2.0, ab.size.y * 0.9)
	_ko_height = minf(ab.size.z, ab.size.x)
	var shape := $Shape as CollisionShape3D
	shape.shape = cap
	shape.position = Vector3(0, cap.height * 0.5, 0)
	var hurt := $Hurtbox/Shape as CollisionShape3D
	hurt.shape = cap
	hurt.position = shape.position
	collision_layer = 2
	collision_mask = 1 | 2 | 8  # world, kami, walls
	health.setup(Damage.max_hp(data))


func _physics_process(delta: float) -> void:
	_dodge_t = maxf(0.0, _dodge_t - delta)
	_dodge_cd = maxf(0.0, _dodge_cd - delta)
	_stun = maxf(0.0, _stun - delta)
	_knock *= exp(-8.0 * delta)

	var flat := Vector3(velocity.x, 0.0, velocity.z) - _knock_prev
	if _dodge_t > 0.0:
		flat = _dash
	else:
		var input := move_dir
		if move_lock or is_stunned() or health.is_dead():
			input = Vector3.ZERO
		var spd := top_speed * (GUARD_MOVE if guarding else 1.0)
		var want := Vector3(input.x, 0.0, input.z).limit_length(1.0) * spd
		flat = flat.move_toward(want, float(_move["accel"]) * top_speed * 0.25 * delta)
	_knock_prev = _knock
	velocity.x = flat.x + _knock.x
	velocity.z = flat.z + _knock.z
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

	var want_face := face_dir
	if face_target != null and is_instance_valid(face_target):
		want_face = face_target.global_position - global_position
	elif move_dir.length() > 0.1 and not move_lock and not is_stunned():
		want_face = move_dir
	want_face.y = 0.0
	if want_face.length() > 0.01:
		face_dir = want_face.normalized()


func _process(delta: float) -> void:
	if _visual == null:
		return
	_t += delta
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var k := clampf(flat.length() / maxf(top_speed, 0.1), 0.0, 1.5)

	var yaw := atan2(face_dir.x, face_dir.z)
	_visual.rotation.y = lerp_angle(_visual.rotation.y, yaw, 1.0 - exp(-float(_move["turn"]) * delta))

	# Lean into the movement: forward/back pitch, sideways roll. Velocity in the visual's own frame.
	var local := _visual.global_transform.basis.inverse() * flat
	if in_place > 0.0:
		k = maxf(k, in_place)
		local = Vector3(0, 0, in_place * top_speed)
	var lean_f := clampf(local.z / maxf(top_speed, 0.1), -1.0, 1.0) * 0.2
	var lean_s := clampf(-local.x / maxf(top_speed, 0.1), -1.0, 1.0) * 0.12
	var sm := 1.0 - exp(-10.0 * delta)
	_visual.rotation.x = lerpf(_visual.rotation.x, lean_f, sm)
	_visual.rotation.z = lerpf(_visual.rotation.z, lean_s, sm)

	var hover := float(_move.get("hover", 0.0))
	if in_place > 0.0:
		hover = 0.0   # a kami shown drilling stands on the ground and walks, whatever its body class
	var bob := absf(sin(_t * (2.5 + 7.0 * k))) * (0.03 + 0.1 * minf(k, 1.0))
	if hover > 0.0:
		bob = hover + sin(_t * 2.0) * 0.12
	_visual.position.y = bob

	# Dodge stretches along the dash, guarding crouches, getting hit squashes.
	var s := Vector3.ONE
	if _dodge_t > 0.0:
		s = Vector3(0.85, 0.85, 1.3)
	elif is_stunned():
		s = Vector3(1.15, 0.8, 1.15)
	elif guarding:
		s = Vector3(1.05, 0.88, 1.05)
	model.scale = model.scale.lerp(s, 1.0 - exp(-20.0 * delta))
	_flash = maxf(0.0, _flash - delta * 6.0)
	MonsterModel.set_flash(model, maxf(_flash, charge * 0.25))
	if health.is_dead():  # knocked out: topples onto its back and lies still on the ground
		_visual.rotation.x = lerpf(_visual.rotation.x, -PI / 2.0, 1.0 - exp(-6.0 * delta))
		_visual.position.y = lerpf(_visual.position.y, _ko_height * 0.18, 1.0 - exp(-6.0 * delta))
		if model.has_meta("skel"):
			(model.get_meta("skel") as AnimationPlayer).pause()
		return

	MonsterModel.animate(model, _t, 1.0 + k * 1.5)
	var att := get_node_or_null("Attacker") as Attacker
	var busy := att != null and att.is_busy()
	if busy and not _was_busy:
		var move_anim := att.current.anim_name if (att.current != null and att.current.anim_name != "") else "Attack"
		MonsterModel.play_action(model, _resolve_action(model, move_anim))
	_was_busy = busy
	MonsterModel.drive(model, delta, local, k, busy)


static func _resolve_action(model: Node3D, anim: String) -> String:
	if model == null or not model.has_meta("skel"):
		return anim
	var player: AnimationPlayer = model.get_meta("skel")
	if player.has_animation(anim):
		return anim
	if player.has_animation("Attack"):
		return "Attack"
	if player.has_animation("Strike"):
		return "Strike"
	return anim
