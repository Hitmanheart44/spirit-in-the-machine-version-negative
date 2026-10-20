extends Node3D
## MR4-style adventure (MR4_SYSTEMS.md), third person. Each floor is a map of big cave chambers (CaveRoom) joined
## by tunnels; you are in one room at a time and walk down a tunnel to go to the next (only that room is loaded).
## Rooms hold treasure, search spots, or the way down (a pillar of light, far from the start). Walking drains
## the team's SPIRIT and wild kami attack as you move: a shatter transition (BattleIntro), then the fight happens
## in the very room you were in. KO'd kami sit out. The last floor's way down is guarded by a boss.
## Spirit 0 / everyone KO'd / Esc ends the run (+500 fatigue); clearing it costs +150.
## Run state lives in Game.run (floor, room, position); the floor map rebuilds from its seed after each battle.

const GRID := 5           # floor map is GRID x GRID rooms
const STEP := 6.5         # spirit drain / encounter roll every STEP meters walked
const ENCOUNTER := 0.06   # chance per roll (a little under the old 0.07)
const GRACE := 8.0        # metres of calm after entering a room or a fight
const BODY := preload("res://monsters/monster_body.tscn")

var run: Dictionary
var rooms: Dictionary = {}    # Vector2i -> {"kind": "start"|"exit"|"chest"|"search"|"", "seed": int}
var room := Vector2i.ZERO
var cave: CaveRoom
var spots: Array = []         # in the current room: [{p, kind, key, node}]
var leader: MonsterBody
var followers: Array[Node3D] = []
var cam: FollowCamera
var hud: DungeonHud
var _walked := 0.0
var _last := Vector3.ZERO
var _busy := false
var _t := 0.0
var _calm := GRACE


func _ready() -> void:
	var p := Scenes.params
	if p.has("team"):  # a new run from town
		var ms: Array = []
		for i in p["team"]:
			ms.append(Game.monsters[int(i)])
		var d := Adventure.get_dungeon(str(p["dungeon"]))
		Game.run = {"dungeon": d[0], "floor": 1, "seed": randi(), "team": p["team"], "ko": [], "pos": null, "room": null,
			"visited": [], "spirit": Adventure.spirit_max(ms), "spirit_max": Adventure.spirit_max(ms), "money": 0,
			"items": {}, "opened": [], "exp": 0}
	run = Game.run
	if run.is_empty():
		Scenes.goto.call_deferred("res://world/zones/ranch_v2.tscn")
		return

	# Handle battle outcome first if returning from combat
	var res = p.get("cup_result")
	var fighter_str := str(p.get("fighter", "0"))
	var is_boss := bool(p.get("boss", false))
	if res != null:
		Scenes.params.erase("cup_result")
		if res.get("won", false):
			run["exp"] = int(run["exp"]) + (40 if is_boss else 12)
			run["money"] = int(run["money"]) + (200 if is_boss else 25) * int(run["floor"])
			if is_boss:
				_end(true, "The guardian is down. The dungeon is cleared!")
				return
		else:
			var f_idx := int(fighter_str)
			if not f_idx in (run["ko"] as Array):
				(run["ko"] as Array).append(f_idx)
			var remaining := 0
			for t_idx in (run["team"] as Array):
				if not int(t_idx) in (run["ko"] as Array):
					remaining += 1
			if remaining <= 0:
				_end(false, "The whole team was knocked out.")
				return

	if run.get("room") is Array and (run["room"] as Array).size() >= 2:
		room = Vector2i(int(run["room"][0]), int(run["room"][1]))
	elif run.get("room") is Vector2i:
		room = run["room"]

	_generate()
	_spawn_team()
	hud = DungeonHud.new()
	hud.dungeon = self
	add_child(hud)
	add_child(PostFx.new())
	_enter_room(room, -1)

	if res != null:
		if res.get("won", false):
			hud.toast("Victory!")
			_calm = GRACE
		else:
			hud.toast("%s is out for the rest of the run." % (Game.monsters[int(fighter_str)] as MonsterData).name)


func _dungeon() -> Array:
	return Adventure.get_dungeon(run["dungeon"])


# ---------------------------------------------------------------- the floor map

func _generate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(run["seed"]) + int(run["floor"]) * 7919
	var want := mini(7 + int(run["floor"]) / 2, 11)
	var c := Vector2i(GRID / 2, GRID / 2)
	var order: Array[Vector2i] = [c]
	rooms[c] = {}
	var guard := 0
	while order.size() < want and guard < 400:  # random walk, branching from any room already made
		guard += 1
		var from: Vector2i = order[rng.randi() % order.size()]
		var n: Vector2i = from + [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP][rng.randi() % 4]
		if n.x < 0 or n.y < 0 or n.x >= GRID or n.y >= GRID or rooms.has(n):
			continue
		rooms[n] = {}
		order.append(n)
	# the way down is the room the most steps from the start
	var dist := {order[0]: 0}
	var q: Array[Vector2i] = [order[0]]
	while not q.is_empty():
		var cur: Vector2i = q.pop_front()
		for e in 4:
			var n: Vector2i = cur + _off(e)
			if rooms.has(n) and not dist.has(n):
				dist[n] = int(dist[cur]) + 1
				q.append(n)
	var far := order[0]
	for k in dist:
		if int(dist[k]) > int(dist[far]):
			far = k
	var i := 0
	for k in order:
		var kind := ""
		if k == order[0]:
			kind = "start"
		elif k == far:
			kind = "exit"
		else:
			kind = ["chest", "search", "", "chest", "search"][i % 5]
			i += 1
		rooms[k] = {"kind": kind, "seed": int(run["seed"]) * 31 + int(run["floor"]) * 977 + k.x * 101 + k.y * 7}
	if run["room"] == null:
		run["room"] = [order[0].x, order[0].y]
	room = Vector2i(int(run["room"][0]), int(run["room"][1]))


static func _off(e: int) -> Vector2i:
	return [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP][e]


func exits_of(c: Vector2i) -> Array:
	var out: Array = []
	for e in 4:
		if rooms.has(c + _off(e)):
			out.append(e)
	return out


## What the arena needs to rebuild this room as the fight stage.
func stage() -> Dictionary:
	return {"theme": run["dungeon"], "seed": rooms[room]["seed"], "exits": exits_of(room)}


# ---------------------------------------------------------------- rooms

## Build room c. from_exit = the side we came in through (-1 = load / restore position).
func _enter_room(c: Vector2i, from_exit: int) -> void:
	if cave != null:
		cave.queue_free()
	for s in spots:
		if s.has("node") and is_instance_valid(s["node"]):
			s["node"].queue_free()
	spots.clear()
	room = c
	run["room"] = [c.x, c.y]
	var vk := "%d:%d:%d" % [run["floor"], c.x, c.y]
	if not vk in run["visited"]:
		(run["visited"] as Array).append(vk)
	cave = CaveRoom.make(stage())
	add_child(cave)
	var info: Dictionary = rooms[c]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(info["seed"])
	var kind: String = info["kind"]
	if kind == "exit":
		spots.append({"p": Vector3.ZERO, "kind": "exit", "key": "exit"})
	elif kind == "chest" or kind == "search":
		var key := vk + ":" + kind
		if not key in run["opened"]:
			var a := rng.randf() * TAU
			spots.append({"p": Vector3(cos(a), 0, sin(a)) * rng.randf_range(4.0, 9.0), "kind": kind, "key": key})
	for s in spots:
		_spot_visual(s)
	if from_exit >= 0:  # arrive at the mouth of the tunnel we came through (the opposite side of this room)
		var d: Vector3 = CaveRoom.DIRS[(from_exit + 2) % 4]
		leader.global_position = d * (CaveRoom.R - 3.0) + Vector3(0, 0.3, 0)
		leader.velocity = Vector3.ZERO
		run["pos"] = leader.global_position
		for i in followers.size():
			followers[i].position = d * (CaveRoom.R - 1.0 + i * 1.5)
	_last = leader.global_position
	_calm = GRACE


func _go_through(e: int) -> void:
	_busy = true
	await hud.fade(1.0, 0.35)
	_enter_room(room + _off(e), e)
	await hud.fade(0.0, 0.35)
	_busy = false


func _spot_visual(s: Dictionary) -> void:
	var n := Node3D.new()
	n.position = s["p"]
	add_child(n)
	s["node"] = n
	match s["kind"]:
		"exit":
			var beam := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 1.0
			cm.bottom_radius = 1.6
			cm.height = 9.0
			beam.mesh = cm
			beam.position.y = 4.5
			beam.material_override = HitFx.additive_mat(Color(0.6, 0.35, 1.0, 0.35), 3.0)
			n.add_child(beam)
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 1.7
			tm.outer_radius = 2.1
			ring.mesh = tm
			ring.material_override = HitFx.glow_mat(Color(0.7, 0.5, 1.0), 2.0)
			n.add_child(ring)
			var l := OmniLight3D.new()
			l.light_color = Color(0.6, 0.4, 1.0)
			l.light_energy = 3.0
			l.omni_range = 12.0
			l.position.y = 2.0
			n.add_child(l)
		"chest":
			if Props.model(n, "ph/treasure_chest", Vector3(0, -0.02, 0), 0.9, randf() * TAU, false) != null:
				return
			var wood := StandardMaterial3D.new()
			wood.albedo_color = Color(0.4, 0.22, 0.1)
			var box := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(1.3, 0.8, 0.85)
			box.mesh = bm
			box.position.y = 0.4
			box.material_override = wood
			n.add_child(box)
			var lid := MeshInstance3D.new()
			var lm := CylinderMesh.new()
			lm.top_radius = 0.43
			lm.bottom_radius = 0.43
			lm.height = 1.3
			lid.mesh = lm
			lid.rotation.z = PI / 2
			lid.scale = Vector3(1, 1, 1.0)
			lid.position.y = 0.8
			lid.material_override = wood
			n.add_child(lid)
			var band := MeshInstance3D.new()
			var bb := BoxMesh.new()
			bb.size = Vector3(1.34, 0.12, 0.9)
			band.mesh = bb
			band.position.y = 0.78
			band.material_override = HitFx.glow_mat(Color(1.0, 0.8, 0.3), 1.2)
			n.add_child(band)
		"search":
			if Props.model(n, "sf/crystal_2", Vector3.ZERO, 1.2, 0.0, false) != null:
				return
			var o := MeshInstance3D.new()
			o.mesh = MonsterModel._mesh("octa")
			o.scale = Vector3.ONE * 0.5
			o.position.y = 1.0
			o.material_override = HitFx.glow_mat(Color(0.4, 0.9, 1.0), 4.0)
			n.add_child(o)


# ---------------------------------------------------------------- the team

func _spawn_team() -> void:
	var team: Array = run["team"]
	var lead_i := -1
	for i in team:
		if not int(i) in (run["ko"] as Array):
			lead_i = int(i)
			break
	if lead_i < 0 and not team.is_empty():
		lead_i = int(team[0])
	leader = BODY.instantiate() as MonsterBody
	leader.data = Game.monsters[lead_i]
	var p_pos = run.get("pos")
	if p_pos is Vector3:
		leader.position = p_pos
	elif p_pos is Array and (p_pos as Array).size() >= 3:
		leader.position = Vector3(float(p_pos[0]), float(p_pos[1]), float(p_pos[2]))
	else:
		leader.position = Vector3(0, 0.3, 0)
	var pc := ExploreController.new()
	leader.add_child(pc)
	add_child(leader)
	for i in team:
		if int(i) == lead_i or int(i) in run["ko"]:
			continue
		var f := MonsterModel.create((Game.monsters[int(i)] as MonsterData).model_dict())
		f.scale = Vector3.ONE * 0.8
		f.position = leader.position + Vector3(followers.size() * 1.5 - 0.75, 0, 2)
		add_child(f)
		followers.append(f)
	cam = FollowCamera.new()
	cam.target = leader
	cam.distance = 9.5
	cam.pitch_deg = -28.0
	cam.look_height = 1.4
	cam.capture_mouse = false  # menu-style screen: right-drag to look, left click for the UI
	add_child(cam)


func _process(delta: float) -> void:
	_t += delta
	var prev: Vector3 = leader.global_position
	for f in followers:  # followers trail the leader
		var to := prev - f.position
		to.y = 0.0
		var moving := to.length() > 2.2
		if moving:
			f.position += to.normalized() * minf(to.length() - 2.2, leader.top_speed * delta * 1.1)
			f.rotation.y = lerp_angle(f.rotation.y, atan2(to.x, to.z), 1.0 - exp(-10.0 * delta))
		MonsterModel.animate(f, _t)
		MonsterModel.drive(f, delta, Vector3(0, 0, 3.0 if moving else 0.0), 0.7 if moving else 0.0)
		prev = f.position
	for s in spots:  # the way-down ring turns slowly; chests and crystals stay put
		if s["kind"] == "exit" and s.has("node") and is_instance_valid(s["node"]):
			(s["node"] as Node3D).rotation.y = _t * 0.6
	if _busy:
		leader.move_dir = Vector3.ZERO
		return
	var pos := leader.global_position
	_walked += Vector2(pos.x - _last.x, pos.z - _last.z).length()
	_last = pos
	run["pos"] = pos
	for e in exits_of(room):  # down a tunnel: the next room
		var d: Vector3 = CaveRoom.DIRS[e]
		if pos.dot(d) > CaveRoom.R + CaveRoom.TUNNEL - 6.0:
			_go_through(e)
			return
	while _walked >= STEP:
		_walked -= STEP
		run["spirit"] = int(run["spirit"]) - 1
		if int(run["spirit"]) <= 0:
			_end(false, "The team's spirit gave out.")
			return
		_calm -= STEP
		if _calm <= 0.0 and randf() < ENCOUNTER and Vector2(pos.x, pos.z).length() < CaveRoom.R - 2.0:  # not inside tunnels
			_battle(false)
			return
	for s in spots:
		if s.has("node") and is_instance_valid(s["node"]) and pos.distance_to(s["p"]) < 1.8:
			_touch(s)
			return


func _touch(s: Dictionary) -> void:
	match s["kind"]:
		"chest", "search":
			if s["kind"] == "search" and randf() < 0.45:
				hud.toast("Nothing here.")
			else:
				_loot(s["kind"] == "chest")
			(run["opened"] as Array).append(s["key"])
			s["node"].queue_free()
		"exit":
			Sound.sfx("portal", -6.0)
			_busy = true
			var last := int(run["floor"]) >= int(_dungeon()[3])
			hud.ask("THE WAY DOWN", [["deeper", "FACE THE GUARDIAN" if last else "GO DEEPER", "Floor %d." % (int(run["floor"]) + (0 if last else 1))],
				["leave", "LEAVE SAFELY", "Head home with what you found. Only a little fatigue."]], func(id: String) -> void:
				if id == "leave":
					_end(true, "You found the way out and brought everyone home safely.", true)
				elif id == "deeper":
					if last:
						_battle(true)
					else:
						run["floor"] = int(run["floor"]) + 1
						run["pos"] = null
						run["room"] = null
						await hud.fade(1.0, 0.6)
						get_tree().reload_current_scene()
				else:
					_busy = false
					leader.global_position += -leader.global_position.normalized() * 3.0)


func _loot(chest: bool) -> void:
	Sound.sfx("chest" if chest else "pickup", -6.0)
	var r := randf()
	var items: Dictionary = run["items"]
	if chest and r < 0.12:
		items["stone"] = int(items.get("stone", 0)) + 1
		hud.toast("A SUMMONING STONE!")
	elif r < 0.6:
		var all := ItemDef.all()
		var it: ItemDef = all[randi() % all.size()]
		items[str(it.id)] = int(items.get(str(it.id), 0)) + 1
		hud.toast("Found: " + it.display_name)
	else:
		var g := randi_range(20, 60) * int(run["floor"])
		run["money"] = int(run["money"]) + g
		hud.toast("Found %d G" % g)
	Sound.sfx("coin", -8.0)
	HitFx.burst(self, leader.global_position + Vector3(0, 1, 0), Color(1, 0.8, 0.3), 20, 4.0)


# ---------------------------------------------------------------- battles

func _wild(boss: bool) -> MonsterData:
	var d := _dungeon()
	var foe := Summoner.summon_text("wild %s %d %d %d" % [d[0], run["seed"], run["floor"], randi()])
	var k := float(int(d[4]) * (1.6 if boss else 1.0) * (1.0 + 0.06 * int(run["floor"]))) / float(foe.total())
	for s in MonsterData.STAT_NAMES:
		foe.stats[s] = maxi(10, int(foe.stat(s) * k))
	return foe


func _battle(boss: bool) -> void:
	_busy = true
	var opts: Array = []
	for i in (run["team"] as Array):
		if not int(i) in run["ko"]:
			var m: MonsterData = Game.monsters[int(i)]
			opts.append([str(i), m.breed_label().to_upper(), "rank %s  //  %s" % [m.rank, Care.fatigue_word(m.fatigue)]])
	if not boss:
		opts.append(["run", "RUN AWAY", "Costs 15 spirit."])
	var foe := _wild(boss)
	hud.ask("THE GUARDIAN BARS THE WAY! WHO FIGHTS?" if boss else "A WILD KAMI APPEARS! WHO FIGHTS?", opts, func(id: String) -> void:
		if id == "run" or id == "":
			run["spirit"] = int(run["spirit"]) - 15
			_busy = false
			if int(run["spirit"]) <= 0:
				_end(false, "The team's spirit gave out.")
			return
		var d := _dungeon()
		var params := {"player": Game.monsters[int(id)], "foes": [foe] as Array[MonsterData], "skill": 0.4 + 0.05 * int(run["floor"]),
			"title": "%s  ·  %dF%s" % [d[1], run["floor"], "  ·  BOSS" if boss else ""], "stage": stage(),
			"return_to": "res://explore/dungeon.tscn", "fighter": id, "boss": boss}
		BattleIntro.play(self, "GUARDIAN" if boss else "ENCOUNTER", foe.breed_label().to_upper(), func():
			Scenes.goto("res://combat/arena.tscn", params)))


func _after_battle(res: Dictionary, fighter: String, boss: bool) -> void:
	if res.get("won", false):
		run["exp"] = int(run["exp"]) + (40 if boss else 12)
		run["money"] = int(run["money"]) + (200 if boss else 25) * int(run["floor"])
		if boss:
			_end(true, "The guardian is down. The dungeon is cleared!")
			return
		if hud != null:
			hud.toast("Victory!")
		_calm = GRACE
	else:
		var f_idx := int(fighter)
		if not f_idx in (run["ko"] as Array):
			(run["ko"] as Array).append(f_idx)
		var remaining := 0
		for t_idx in (run["team"] as Array):
			if not int(t_idx) in (run["ko"] as Array):
				remaining += 1
		if remaining <= 0:
			_end(false, "The whole team was knocked out.")
			return
		if hud != null:
			hud.toast("%s is out for the rest of the run." % (Game.monsters[f_idx] as MonsterData).name)


func _end(cleared: bool, why: String, safe := false) -> void:
	_busy = true
	var lines: Array = [why]
	for i in (run["team"] as Array):
		var m: MonsterData = Game.monsters[int(i)]
		if safe:
			m.fatigue = mini(999, m.fatigue + 40)
		else:
			Care.adventure_cost(m, cleared)
		m.adv_exp += int(run["exp"])
		while m.adv_exp >= 100 * m.adv_level:
			m.adv_exp -= 100 * m.adv_level
			m.adv_level += 1
			lines.append("%s reached adventure level %d." % [m.name, m.adv_level])
	Game.add_money(int(run["money"]))
	lines.append("+%d G" % int(run["money"]))
	for id in (run["items"] as Dictionary):
		Game.add_item(id, int(run["items"][id]))
		lines.append("+%d %s" % [int(run["items"][id]), "Summoning Stone" if id == "stone" else str(id).capitalize()])
	lines.append("Fatigue +%d for the team." % (40 if safe else (150 if cleared else 500)))
	Game.run = {}
	Scenes.goto("res://world/zones/ranch_v2.tscn", {"adventure_result": {"lines": lines, "defeat": not cleared and why.find("knocked out") >= 0}})


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE and not _busy:
		_busy = true
		hud.ask("LEAVE THE DUNGEON?", [["quit", "LEAVE NOW", "Costs the team +500 fatigue."]], func(id: String) -> void:
			if id == "quit":
				_end(false, "You left the dungeon early.")
			else:
				_busy = false)
