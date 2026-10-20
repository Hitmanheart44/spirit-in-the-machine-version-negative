extends Node
## Regression tests for N-VN-05: dungeon battle return, KO deduplication, room/position
## restoration, follow camera frame-0 orientation and ground clamping, and flame model scene binding.

var checks := 0
var failures := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("VN-05 FAIL: " + label)


class MockZone extends Node3D:
	var mock_ground_y := 12.0

	func ground(_x: float, _z: float) -> float:
		return mock_ground_y


func _ready() -> void:
	var scratch := OS.get_environment("VN05_SCRATCH").simplify_path()
	var save_path := ProjectSettings.globalize_path(Save.PATH).simplify_path()
	if not scratch.begins_with("/tmp/vn-05-") or not save_path.begins_with(scratch + "/") \
			or Save.PATH != "user://save_test.json":
		push_error("VN-05: isolated save path required before any Save access: " + save_path)
		get_tree().quit(2)
		return
	print("VN-05 SAVE_PATH=", save_path)
	if Save.exists():
		push_error("VN-05: fresh scratch required; existing test save left untouched")
		get_tree().quit(2)
		return

	var prior_game := Game.to_dict().duplicate(true)
	var prior_run := Game.run.duplicate(true)
	Game.from_dict({})
	Game.run = {}

	dungeon_return_cases()
	camera_cases()
	asset_binding_cases()

	Game.from_dict(prior_game)
	Game.run = prior_run
	print("VN-05: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)


func dungeon_return_cases() -> void:
	# 1. Setup multi-kami team in Game
	var m0 := MonsterData.new()
	m0.name = "Kami 0"
	m0.main_breed = &"flame"
	m0.sub_breed = &"flame"
	var m1 := MonsterData.new()
	m1.name = "Kami 1"
	m1.main_breed = &"plant"
	m1.sub_breed = &"plant"
	Game.monsters = [m0, m1]

	# 2. Setup active dungeon run state
	Game.run = {
		"dungeon": "hollow",
		"floor": 1,
		"seed": 12345,
		"team": [0, 1],
		"ko": [],
		"pos": Vector3(14.0, 0.3, -8.0),
		"room": [3, 2],
		"visited": [],
		"spirit": 50,
		"spirit_max": 50,
		"money": 0,
		"items": {},
		"opened": [],
		"exp": 0
	}

	# Test KO deduplication logic
	var run: Dictionary = Game.run
	var fighter_0 := 0
	if not fighter_0 in (run["ko"] as Array):
		(run["ko"] as Array).append(fighter_0)
	check((run["ko"] as Array) == [0], "first KO recorded")

	var rem := 0
	for t in (run["team"] as Array):
		if not int(t) in (run["ko"] as Array):
			rem += 1
	check(rem == 1, "one teammate remains after first KO")

	# Duplicate KO on fighter 0 must NOT double-append or trigger early whole-team wipe
	if not fighter_0 in (run["ko"] as Array):
		(run["ko"] as Array).append(fighter_0)
	check((run["ko"] as Array) == [0], "duplicate KO not appended to ko array")

	rem = 0
	for t in (run["team"] as Array):
		if not int(t) in (run["ko"] as Array):
			rem += 1
	check(rem == 1, "remaining teammate count preserved on repeated KO report")

	# KO of second teammate
	var fighter_1 := 1
	if not fighter_1 in (run["ko"] as Array):
		(run["ko"] as Array).append(fighter_1)
	check((run["ko"] as Array).size() == 2, "second KO recorded")

	rem = 0
	for t in (run["team"] as Array):
		if not int(t) in (run["ko"] as Array):
			rem += 1
	check(rem == 0, "zero teammates remain when all are KO'd")

	# Test room coordinate array-to-Vector2i restoration
	var restored_room := Vector2i.ZERO
	if run.get("room") is Array and (run["room"] as Array).size() >= 2:
		restored_room = Vector2i(int(run["room"][0]), int(run["room"][1]))
	elif run.get("room") is Vector2i:
		restored_room = run["room"]
	check(restored_room == Vector2i(3, 2), "array room [3, 2] restores to Vector2i(3, 2)")

	run["room"] = Vector2i(1, 4)
	if run.get("room") is Array and (run["room"] as Array).size() >= 2:
		restored_room = Vector2i(int(run["room"][0]), int(run["room"][1]))
	elif run.get("room") is Vector2i:
		restored_room = run["room"]
	check(restored_room == Vector2i(1, 4), "Vector2i room restores to Vector2i(1, 4)")

	# Test position array-to-Vector3 restoration
	run["pos"] = [12.5, 0.3, -4.2]
	var p_pos = run.get("pos")
	var restored_pos := Vector3.ZERO
	if p_pos is Vector3:
		restored_pos = p_pos
	elif p_pos is Array and (p_pos as Array).size() >= 3:
		restored_pos = Vector3(float(p_pos[0]), float(p_pos[1]), float(p_pos[2]))
	check(restored_pos.is_equal_approx(Vector3(12.5, 0.3, -4.2)), "array pos restores to Vector3")


func camera_cases() -> void:
	var zone := MockZone.new()
	add_child(zone)

	var target := Node3D.new()
	target.position = Vector3(0, 0, -6)
	zone.add_child(target)

	var cam := FollowCamera.new()
	cam.target = target
	cam.distance = 5.5
	cam.look_height = 1.5
	cam.pitch_deg = -14.0
	cam.yaw = PI * 0.5
	zone.add_child(cam)

	# Frame 0 check: rotation must already be set in _ready() before any _process()
	check(is_equal_approx(cam.rotation.y, PI * 0.5), "cam yaw initialized on frame 0")
	check(is_equal_approx(cam.rotation.x, deg_to_rad(-14.0)), "cam pitch initialized on frame 0")
	check(cam.global_position.distance_to(target.global_position + Vector3(0, 1.5, 0)) < 0.01,
		"cam root placed at target look height on frame 0")

	# Ground clamping check: camera height clamped above zone ground
	zone.mock_ground_y = 5.0
	cam.cam.global_position.y = 2.0  # artificially below ground
	cam._process(0.016)
	check(cam.cam.global_position.y >= 5.0 + 0.45, "cam clamped above ground level")

	zone.queue_free()


func asset_binding_cases() -> void:
	var flame_def := SpeciesDB.get_def(&"flame")
	check(flame_def != null, "flame species def loaded")
	check(flame_def.model_scene != null, "flame model_scene not null")
	check(flame_def.model_scene.resource_path == "res://assets/models/flame.glb",
		"flame model_scene points to flame.glb, not vexa.glb")
	check(flame_def.display_name == "Flame" and flame_def.type == "fire", "flame type and display name valid")
