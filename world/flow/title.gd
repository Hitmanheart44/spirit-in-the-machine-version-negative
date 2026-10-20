extends Node3D
## Title screen (the game's main scene): the camera drifts over the cliff ranch and the shrine hill at golden hour,
## the title in brush lettering, and Continue / New Game / Quit. Continue loads the save and goes to the ranch;
## New Game (asks first if a save exists) starts fresh: intro, then the character creator.

const RANCH := "res://world/zones/ranch_v2.tscn"

var cam: Camera3D
var _t := 0.0
var _menu: VBoxContainer
var _confirm: VBoxContainer
var _delete_confirm: VBoxContainer
var _options: VBoxContainer
var _box: VBoxContainer
var _hide_for_options: Array = []   # the flourish, tagline and spacer: out of the way while Options is open


func _ready() -> void:
	var world := Overworld.new()
	world.zone = "intro"  # the ranch and the shrine hill together
	add_child(world)
	cam = Camera3D.new()
	cam.fov = 60.0
	cam.far = 1500.0
	add_child(cam)
	cam.make_current()
	_ui()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(delta: float) -> void:  # a slow drift round the ranch, looking out toward the sea and the shrine
	_t += delta
	var a := 0.35 + _t * 0.025
	cam.position = Vector3(cos(a) * 46.0, 22.0 + sin(_t * 0.1) * 2.0, sin(a) * 46.0)
	cam.look_at(Vector3(4, 2, -6))


func _ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.theme = UIStyle.theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var shade := ColorRect.new()  # darken the left side so the lettering reads
	shade.color = Color(0, 0, 0, 0.0)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := GradientTexture2D.new()
	g.gradient = Gradient.new()
	g.gradient.set_color(0, Color(0.05, 0.03, 0.02, 0.88))
	g.gradient.set_color(1, Color(0.05, 0.03, 0.02, 0.0))
	g.fill_from = Vector2(0, 0.5)
	g.fill_to = Vector2(0.75, 0.5)
	var tr := TextureRect.new()
	tr.texture = g
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(tr)
	root.add_child(_vignette())
	root.add_child(_petals())
	var box := VBoxContainer.new()
	box.position = Vector2(90, 150)
	box.add_theme_constant_override("separation", 14)
	root.add_child(box)
	box.add_child(UIStyle.label("Spirit in the Machine", 84, UIStyle.TEXT, "display"))
	var rule := TextureRect.new()   # gold flourish under the title
	rule.texture = load("res://assets/ui/divider.png")
	rule.custom_minimum_size = Vector2(620, 18)
	rule.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rule.stretch_mode = TextureRect.STRETCH_SCALE
	rule.modulate = Color(1.3, 1.1, 0.8)
	box.add_child(rule)
	var sub := UIStyle.label("Everything that serves long enough grows a soul.", 22, UIStyle.ACCENT, "display")
	box.add_child(sub)
	_box = box
	box.modulate.a = 0.0   # fade the whole block in
	box.position.x -= 40.0
	var tw := create_tween().set_parallel()
	tw.tween_property(box, "modulate:a", 1.0, 1.4).set_delay(0.3)
	tw.tween_property(box, "position:x", 90.0, 1.4).set_delay(0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 60)
	box.add_child(gap)
	_hide_for_options = [rule, sub, gap]
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 10)
	box.add_child(_menu)
	if Save.exists():
		_button(_menu, "CONTINUE", _continue).grab_focus.call_deferred()
	var ng := _button(_menu, "NEW GAME", _new_game)
	if not Save.exists():
		ng.grab_focus.call_deferred()
	if Save.exists():
		_button(_menu, "DELETE SAVE", _ask_delete)
	_button(_menu, "OPTIONS", _show_options)
	_button(_menu, "QUIT", get_tree().quit)
	_confirm = VBoxContainer.new()
	_confirm.add_theme_constant_override("separation", 10)
	_confirm.visible = false
	box.add_child(_confirm)
	_confirm.add_child(UIStyle.label("Start over? Your current ranch will be lost.", 20, UIStyle.BAD, "body"))
	_button(_confirm, "YES, START A NEW RANCH", _start_fresh)
	_button(_confirm, "BACK", func():
		_confirm.visible = false
		_menu.visible = true)
	_delete_confirm = VBoxContainer.new()
	_delete_confirm.add_theme_constant_override("separation", 10)
	_delete_confirm.visible = false
	box.add_child(_delete_confirm)
	_delete_confirm.add_child(UIStyle.label("Delete your saved ranch? This cannot be undone.", 20, UIStyle.BAD, "body"))
	_button(_delete_confirm, "YES, DELETE MY SAVE", _delete_save)
	_button(_delete_confirm, "BACK", func():
		_delete_confirm.visible = false
		_menu.visible = true)
	_options = VBoxContainer.new()
	_options.add_theme_constant_override("separation", 10)
	_options.visible = false
	box.add_child(_options)
	var ver := UIStyle.label("v2 prototype", 12, UIStyle.DIM, "mono")
	root.add_child(ver)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.position += Vector2(-130, -30)


## Soft dark corners.
func _vignette() -> Control:
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	g.gradient = Gradient.new()
	g.gradient.offsets = PackedFloat32Array([0.55, 1.0])
	g.gradient.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0.03, 0.02, 0.02, 0.55)])
	var v := TextureRect.new()
	v.texture = g
	v.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	v.stretch_mode = TextureRect.STRETCH_SCALE
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return v


## Drifting cherry petals across the whole screen (CPU particles: cheap on old machines).
func _petals() -> Control:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var d := Vector2((x - 7.5) / 7.5, (y - 7.5) / 4.5).length()
			img.set_pixel(x, y, Color(1.0, 0.82, 0.88, clampf(1.0 - d, 0.0, 1.0) * 1.6))
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := CPUParticles2D.new()
	p.texture = ImageTexture.create_from_image(img)
	p.amount = 40
	p.lifetime = 14.0
	p.preprocess = 14.0
	p.position = Vector2(1500, -30)
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(900, 10)
	p.direction = Vector2(-1, 0.55)
	p.spread = 18.0
	p.gravity = Vector2(-4, 14)
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 90.0
	p.angular_velocity_min = -90.0
	p.angular_velocity_max = 90.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.1
	p.color = Color(1, 1, 1, 0.9)
	host.add_child(p)
	return host


func _button(parent: Control, text: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(340, 50)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN  # buttons stay button-sized, not the title's width
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func(): Sound.sfx("click", -8.0))
	b.pressed.connect(fn)
	parent.add_child(b)
	return b


## Options: graphics quality, sound and display, applied straight away; BACK returns to the menu.
func _show_options() -> void:
	_menu.visible = false
	_confirm.visible = false
	_delete_confirm.visible = false
	_options.visible = true
	for c in _hide_for_options:   # make room: the whole panel must fit on screen with BACK visible
		(c as Control).visible = false
	_box.position.y = 50.0
	_refresh_options()


func _refresh_options() -> void:
	for c in _options.get_children():
		c.queue_free()
	_options.add_child(UIStyle.label("Options", 30, UIStyle.TEXT, "display"))
	var bus := AudioServer.get_bus_index("Master")
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	_button(_options, "GRAPHICS:  %s" % Quality.NAMES[Quality.level].capitalize(), func() -> void:
		Quality.cycle()
		_refresh_options())
	_button(_options, "SOUND:  %s" % ("Off" if AudioServer.is_bus_mute(bus) else "On"), func() -> void:
		AudioServer.set_bus_mute(bus, not AudioServer.is_bus_mute(bus))
		_refresh_options())
	_button(_options, "DISPLAY:  %s" % ("Fullscreen" if full else "Window"), func() -> void:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		_refresh_options())
	_options.add_child(UIStyle.label("Lower graphics help older machines. Some changes finish applying when the next scene loads.", 15, UIStyle.DIM, "body"))
	_button(_options, "BACK", func() -> void:
		_options.visible = false
		_menu.visible = true
		for c in _hide_for_options:
			(c as Control).visible = true
		_box.position.y = 150.0)


func _credits() -> void:
	var txt := "Spirit in the Machine\n\nModels from Poly Haven (polyhaven.com), CC0.\n\nModels from Sketchfab, CC BY 4.0:\n"
	if FileAccess.file_exists("res://assets/CREDITS_sketchfab.txt"):
		var seen := {}
		for l in FileAccess.get_file_as_string("res://assets/CREDITS_sketchfab.txt").split("\n"):
			if l.strip_edges() != "" and not seen.has(l):
				seen[l] = true
				txt += l.split(" https://")[0] + "\n"
	var d := AcceptDialog.new()
	d.title = "Credits"
	d.dialog_text = txt
	d.min_size = Vector2i(700, 500)
	add_child(d)
	d.popup_centered()


func _continue() -> void:
	Game.set_meta("started", true)
	if not Save.read():
		_start_fresh()
		return
	Scenes.goto(RANCH)


func _ask_delete() -> void:
	_menu.visible = false
	_delete_confirm.visible = true


func _delete_save() -> void:
	Save.delete()
	Game.new_game()
	if Game.has_meta("started"):
		Game.remove_meta("started")
	if Game.has_meta("loaded"):
		Game.remove_meta("loaded")
	get_tree().reload_current_scene()   # the title comes back without Continue and Delete Save


func _new_game() -> void:
	if Save.exists():
		_menu.visible = false
		_confirm.visible = true
	else:
		_start_fresh()


func _start_fresh() -> void:
	Save.delete()
	Game.set_meta("started", true)
	if Game.has_meta("loaded"):
		Game.remove_meta("loaded")
	Game.new_game()
	Game.ap = Care.action_points()
	Save.write()
	Scenes.goto(RANCH)  # the ranch sends a fresh game on to the intro and the character creator
