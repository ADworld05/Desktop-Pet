extends Node
## T02 feasibility prototype. No LLM, window automation, or arbitrary launcher.
const Paths = preload("res://scripts/Paths.gd")
const Geometry = preload("res://scripts/platform/WindowGeometry.gd")
static var EVIDENCE_DIRECTORY: String:
	get: return Paths.development_root() + "/Validation/T02/iteration-5/" if OS.has_feature("editor") else Paths.directory("cache") + "/Proof/T02/"
var pet: Window
var panel: Window
var draft: TextEdit
var summary: Label
var pass_toggle: CheckButton
var top_toggle: CheckButton
var taskbar_toggle: CheckButton
var taskbar_visible := true
var last_dpi := 0
var menu: RID
var tray_id := -1
var elapsed := 0.0
var sleeping := false
var mesh_root: Node3D
var satellite: MeshInstance3D
var scale_override := 0.0
var geometry_tick := 0.0
var last_work_area := Rect2i()
var events: Array[Dictionary] = []
var preview_mode := false
var preview_step := 0
var lab_mode := false
var full_passthrough := false
var pet_hidden_by_user := false
var panel_minimized := false
var restore_pet_after_minimize := false
var motion_root: Node3D
var motion_time := 0.0
var capture_motion := false

func _ready() -> void:
	Engine.max_fps = 30
	get_tree().auto_accept_quit = false
	pet = get_window()
	_startup_trace("ready_entry")
	pet.gui_embed_subwindows = false
	pet.title = "Desktop Pet — T02 overlay"
	pet.transparent_bg = true
	pet.transparent = true
	_startup_trace("transparent")
	pet.borderless = true
	_startup_trace("borderless")
	pet.unfocusable = true
	_startup_trace("unfocusable")
	pet.always_on_top = true
	_startup_trace("topmost")
	pet.unresizable = true
	_startup_trace("unresizable")
	var command_args := OS.get_cmdline_user_args()
	preview_mode = "--t02-preview" in command_args
	lab_mode = "--t02-lab" in command_args
	if Paths.prepare_runtime() != OK:
		push_error("Windows user-data folder unavailable: " + Paths.RUNTIME_ROOT + "")
		get_tree().quit(1)
		return
	_create_mesh()
	_create_panel()
	_startup_trace("panel_created")
	_create_tray()
	_startup_trace("tray_created")
	_apply_taskbar()
	_place_pet(true)
	pet.close_requested.connect(_quit)
	pet.focus_entered.connect(func(): _event("pet_focus_entered"))
	pet.size_changed.connect(_apply_envelope)
	_event("started", {
		"engine": Engine.get_version_info()["string"],
		"transparency_available": DisplayServer.is_window_transparency_available(),
		"tray_available": tray_id >= 0,
		"native_menu": NativeMenu.has_feature(NativeMenu.FEATURE_POPUP_MENU),
	})
	if tray_id < 0:
		# An unavailable tray must not strand an unfocusable application.
		open_panel()
	if "--t02-startup-trace" in command_args:
		await get_tree().create_timer(0.5).timeout
		_startup_trace("after_first_frames")
		_quit()
	elif preview_mode:
		_capture_sequence()
	elif "--t02-native-test" in command_args:
		_native_acceptance()
	elif "--t02-panel-test" in command_args:
		_panel_acceptance()
	elif "--t02-motion-test" in command_args:
		_motion_acceptance()

func _startup_trace(stage: String) -> void:
	if "--t02-startup-trace" in OS.get_cmdline_user_args():
		print("T02_STARTUP ", JSON.stringify({"stage": stage, "state": FoxWindowBridge.get_window_state(), "unfocusable": pet.unfocusable, "borderless": pet.borderless, "transparent": pet.transparent}))

func _create_mesh() -> void:
	mesh_root = Node3D.new()
	add_child(mesh_root)
	motion_root = Node3D.new()
	mesh_root.add_child(motion_root)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#cbd8f2")
	environment.ambient_light_energy = 0.8
	environment_node.environment = environment
	mesh_root.add_child(environment_node)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.8
	camera.position = Vector3(0, 0, 5)
	mesh_root.add_child(camera)
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, -35, 0)
	light.light_energy = 1.0
	mesh_root.add_child(light)
	_sphere(Vector3(0, -0.22, 0), Vector3(0.68, 0.84, 0.53), Color("#f4f5f7"))
	_sphere(Vector3(0, 0.68, 0.06), Vector3(0.42, 0.42, 0.40), Color("#c6e3f4"))
	satellite = _sphere(Vector3(0.91, -0.58, 0), Vector3(0.24, 0.24, 0.24), Color("#d7cff1"))

func _sphere(at: Vector3, extent: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	sphere.material = material
	instance.mesh = sphere
	instance.position = at
	instance.scale = extent
	motion_root.add_child(instance)
	return instance

func _create_panel() -> void:
	panel = Window.new()
	panel.title = "Desktop Pet — T02 controls"
	panel.size = Vector2i(440, 650)
	panel.unresizable = true
	panel.visible = false
	add_child(panel)
	panel.close_requested.connect(func():
		panel.hide()
		_event("panel_closed", {"draft_characters": draft.text.length()})
	)
	var background := ColorRect.new()
	background.color = Color("#172133")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var title := Label.new()
	title.text = "Desktop movement preview"
	title.add_theme_font_size_override("font_size", 22)
	column.add_child(title)
	summary = Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.custom_minimum_size.y = 72
	column.add_child(summary)
	draft = TextEdit.new()
	draft.placeholder_text = "Type here to test focus. Your draft stays when this panel closes."
	draft.custom_minimum_size.y = 100
	draft.text_changed.connect(func(): _event("typing", {"characters": draft.text.length()}))
	column.add_child(draft)
	top_toggle = CheckButton.new()
	top_toggle.text = "Keep placeholder on top"
	top_toggle.button_pressed = true
	top_toggle.toggled.connect(func(enabled: bool):
		pet.always_on_top = enabled
		_apply_taskbar()
		_event("topmost_changed", {"enabled": enabled})
	)
	column.add_child(top_toggle)
	taskbar_toggle = CheckButton.new()
	taskbar_toggle.text = "Show placeholder in taskbar"
	taskbar_toggle.button_pressed = taskbar_visible
	taskbar_toggle.toggled.connect(func(enabled: bool):
		taskbar_visible = enabled
		_apply_taskbar()
	)
	column.add_child(taskbar_toggle)
	pass_toggle = CheckButton.new()
	pass_toggle.text = "Pass all clicks through placeholder"
	pass_toggle.disabled = tray_id < 0
	pass_toggle.toggled.connect(_set_pass_through)
	column.add_child(pass_toggle)
	var scale_row := HBoxContainer.new()
	column.add_child(scale_row)
	var scale_label := Label.new()
	scale_label.text = "Size / DPI test:"
	scale_row.add_child(scale_label)
	for value in [1.0, 1.25, 1.5, 2.0]:
		var scale_button := Button.new()
		scale_button.text = str(int(value * 100)) + "%"
		scale_button.pressed.connect(func():
			scale_override = value
			_place_pet(false)
			_event("simulated_scale", {"factor": value})
		)
		scale_row.add_child(scale_button)
	_button(column, "Center in work area", func(): _place_pet(true))
	_button(column, "Hide placeholder (tray restores it)", _hide_pet)
	_button(column, "Close panel (keep draft)", func(): panel.close_requested.emit())
	_button(column, "Exit prototype", _quit)
	var limit := Label.new()
	limit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	limit.text = "Use the tray to restore the placeholder. Size buttons simulate scale; they do not change Windows DPI."
	limit.add_theme_font_size_override("font_size", 12)
	column.add_child(limit)

func _button(parent: Control, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)

func _create_tray() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_STATUS_INDICATOR):
		return
	var icon := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	icon.fill(Color.TRANSPARENT)
	for y in range(32):
		for x in range(32):
			if Vector2(x - 15.5, y - 15.5).length() < 13.0:
				icon.set_pixel(x, y, Color("#86cfff") if y < 16 else Color("#d7cff1"))
	menu = NativeMenu.create_menu()
	for item in [["Show placeholder", "show"], ["Hide placeholder", "hide"], ["Chat / controls", "panel"], ["Restore input", "input"], ["Sleep / wake", "sleep"], ["Exit", "exit"]]:
		NativeMenu.add_item(menu, item[0], _menu_action, Callable(), item[1])
	tray_id = DisplayServer.create_status_indicator(ImageTexture.create_from_image(icon), "Desktop Pet T02 — right-click for recovery", _tray_pressed)
	if tray_id >= 0:
		DisplayServer.status_indicator_set_menu(tray_id, menu)
	pass_toggle.disabled = tray_id < 0

func _tray_pressed(button: int, _position: Vector2i) -> void:
	if button == MOUSE_BUTTON_LEFT:
		_show_pet()
		open_panel()

func _menu_action(action: Variant) -> void:
	_event("tray_action", {"action": str(action)})
	match str(action):
		"show": _show_pet()
		"hide": _hide_pet()
		"panel": open_panel()
		"input":
			_set_pass_through(false)
			pass_toggle.set_pressed_no_signal(false)
			_show_pet()
		"sleep":
			sleeping = not sleeping
			_event("sleep_changed", {"sleeping": sleeping})
		"exit": _quit()

func _place_pet(center: bool) -> void:
	var screen := DisplayServer.window_get_current_screen(pet.get_window_id())
	var usable := DisplayServer.screen_get_usable_rect(screen)
	last_dpi = FoxWindowBridge.get_window_dpi()
	var factor := scale_override if scale_override > 0.0 else clampf(last_dpi / 96.0, 1.0, 2.0)
	pet.size = Geometry.pixel_extent(factor, usable)
	pet.content_scale_size = Geometry.LOGICAL_SIZE
	pet.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	var requested := pet.position
	if center:
		requested = usable.position + (usable.size - pet.size) / 2
		if lab_mode:
			requested = Vector2i(430, 260)
	pet.position = Geometry.fit_position(requested, pet.size, usable)
	last_work_area = usable
	_apply_envelope()
	_apply_taskbar()
	_update_summary()
	_event("placed", {"position": [pet.position.x, pet.position.y], "size": [pet.size.x, pet.size.y], "reported_dpi": DisplayServer.screen_get_dpi(screen), "work_area": [usable.position.x, usable.position.y, usable.size.x, usable.size.y]})
	_event("effective_dpi", {"windows_dpi": last_dpi, "simulated_scale": scale_override})

func _apply_taskbar() -> void:
	var success := FoxWindowBridge.set_taskbar_visible(taskbar_visible) == 1
	if full_passthrough:
		success = FoxWindowBridge.set_click_through(true) == 1 and success
	if taskbar_toggle:
		taskbar_toggle.set_pressed_no_signal(taskbar_visible)
	if not success:
		push_error("Could not apply independent taskbar presence to the pet window.")
	_event("taskbar_configured", {"requested": taskbar_visible, "success": success, "native_state": FoxWindowBridge.get_window_state()})

func _apply_envelope() -> void:
	pet.mouse_passthrough_polygon = Geometry.envelope(pet.size)

func _set_pass_through(enabled: bool) -> void:
	if enabled and tray_id < 0:
		return
	# Godot's Windows flag alone does not deliver clicks to other processes.
	var success := FoxWindowBridge.set_click_through(enabled) == 1
	if not success:
		push_error("Windows click-through change failed; previous mode retained.")
		pass_toggle.set_pressed_no_signal(full_passthrough)
		return
	full_passthrough = enabled
	pass_toggle.set_pressed_no_signal(enabled)
	_apply_taskbar()
	_event("full_passthrough_changed", {"enabled": enabled, "success": success})
	_update_summary()

func _show_pet() -> void:
	pet_hidden_by_user = false
	if panel_minimized:
		panel.mode = Window.MODE_WINDOWED
		panel_minimized = false
	var success := FoxWindowBridge.set_overlay_visible(true) == 1
	_place_pet(false)
	_event("shown", {"success": success})

func _hide_pet() -> void:
	if tray_id < 0:
		open_panel()
		return
	var success := FoxWindowBridge.set_overlay_visible(false) == 1
	if success:
		pet_hidden_by_user = true
	_event("hidden", {"success": success})

func open_panel() -> void:
	var usable := DisplayServer.screen_get_usable_rect()
	panel.position = Geometry.fit_position(pet.position + Vector2i(pet.size.x + 12, 0), panel.size, usable)
	# show() alone does not restore a previously minimized native window.
	panel.mode = Window.MODE_WINDOWED
	_sync_minimize()
	panel.show()
	panel.grab_focus()
	draft.grab_focus()
	_update_summary()
	_event("panel_opened", {"draft_characters": draft.text.length()})

func _update_summary() -> void:
	if summary:
		summary.text = "A moving placeholder for desktop tests.\nClick-through: %s · Minimize hides pet too.\nUse the tray to restore input or wake movement." % ("ON" if full_passthrough else "OFF")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_event("pet_click", {"button": event.button_index})
		if event.button_index == MOUSE_BUTTON_LEFT:
			open_panel()
		elif event.button_index == MOUSE_BUTTON_RIGHT and menu.is_valid():
			NativeMenu.popup(menu, DisplayServer.mouse_get_position())

func _process(delta: float) -> void:
	elapsed += delta
	_sync_minimize()
	if motion_root and not sleeping and not panel_minimized and not capture_motion:
		motion_time += delta
		_pose_motion(motion_time)
	geometry_tick += delta
	if geometry_tick >= 1.0:
		geometry_tick = 0.0
		var area := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen(pet.get_window_id()))
		if area != last_work_area or FoxWindowBridge.get_window_dpi() != last_dpi:
			_place_pet(false)

func _sync_minimize() -> void:
	if not panel:
		return
	var minimized_now := panel.mode == Window.MODE_MINIMIZED
	if minimized_now == panel_minimized:
		return
	panel_minimized = minimized_now
	if minimized_now:
		restore_pet_after_minimize = not pet_hidden_by_user
		FoxWindowBridge.set_overlay_visible(false)
		_event("companion_minimized")
	elif restore_pet_after_minimize:
		FoxWindowBridge.set_overlay_visible(true)
		_place_pet(false)
		restore_pet_after_minimize = false
		_event("companion_restored")

func _pose_motion(seconds: float) -> void:
	# A six-second sway/hop loop of the WHOLE placeholder, inside the fixed
	# envelope. Camera/light stay still. Sleep freezes phase without a wake jump.
	var phase := seconds * TAU / 6.0
	motion_root.position = Vector3(sin(phase) * 0.28, (1.0 - cos(phase * 2.0)) * 0.11, 0)
	motion_root.rotation.z = sin(phase) * 0.10
	satellite.position.x = 0.91 + sin(phase * 2.0) * 0.08
	satellite.position.y = -0.58 + cos(phase * 2.0) * 0.10

func _event(kind: String, details: Dictionary = {}) -> void:
	details["event"] = kind
	details["elapsed_seconds"] = snappedf(elapsed, 0.01)
	details["pet_has_focus"] = pet.has_focus()
	details["native_pet_state"] = FoxWindowBridge.get_window_state()
	events.append(details)
	if events.size() > 500:
		events.pop_front()
	var file := FileAccess.open(Paths.directory("logs").path_join("t02_events.json"), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(events, "\t"))
	print("T02_EVENT ", JSON.stringify(details))

func _capture_sequence() -> void:
	var results: Array[Dictionary] = []
	for factor in [1.0, 1.25, 1.5, 2.0]:
		scale_override = factor
		_place_pet(true)
		await get_tree().create_timer(0.2).timeout
		await RenderingServer.frame_post_draw
		var image := pet.get_texture().get_image()
		var outside_count := 0
		var opaque_count := 0
		var polygon := Geometry.envelope(image.get_size())
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				if image.get_pixel(x, y).a > 0.02:
					opaque_count += 1
					if not Geometry2D.is_point_in_polygon(Vector2(x, y), polygon):
						outside_count += 1
		var name := "overlay_" + str(int(factor * 100)) + ".png"
		image.save_png(EVIDENCE_DIRECTORY + name)
		results.append({"simulated_scale": factor, "image_size": [image.get_width(), image.get_height()], "visible_pixels": opaque_count, "visible_pixels_outside_envelope": outside_count})
	var file := FileAccess.open(EVIDENCE_DIRECTORY + "render_checks.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	file.close()
	open_panel()
	await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	panel.get_texture().get_image().save_png(EVIDENCE_DIRECTORY + "controls_preview.png")
	_quit()

func _quit(exit_code: int = 0) -> void:
	_event("exit_requested")
	if tray_id >= 0:
		DisplayServer.delete_status_indicator(tray_id)
		tray_id = -1
	if menu.is_valid():
		NativeMenu.free_menu(menu)
		menu = RID()
	get_tree().quit(exit_code)

func _native_acceptance() -> void:
	# Exercises production actions in-process; it does not inject desktop input.
	var results: Array[Dictionary] = []
	var startup := FoxWindowBridge.get_window_state()
	results.append({"case": "startup_without_activation", "native_state": startup, "passed": startup >= 0 and (startup & 4) != 0 and (startup & 32) == 0})
	await get_tree().create_timer(0.3).timeout
	for enabled in [true, false, true]:
		taskbar_visible = enabled
		_apply_taskbar()
		await get_tree().process_frame
		var state := FoxWindowBridge.get_window_state()
		results.append({"case": "taskbar_" + str(enabled), "native_state": state,
			"passed": state >= 0 and (state & 4) != 0 and (state & 32) == 0 and ((state & 1) != 0) == enabled and ((state & 2) != 0) != enabled})
	for enabled in [true, false]:
		_set_pass_through(enabled)
		var state := FoxWindowBridge.get_window_state()
		results.append({"case": "passthrough_preserves_taskbar_" + str(enabled), "native_state": state, "passed": (state & 5) == 5 and (state & 32) == 0})
		results.append({"case": "os_passthrough_styles_" + str(enabled), "native_state": state, "passed": ((state & 384) == 384) == enabled})
	_set_pass_through(true)
	pet.always_on_top = false
	_apply_taskbar()
	var refreshed := FoxWindowBridge.get_window_state()
	results.append({"case": "passthrough_survives_godot_flag_refresh", "native_state": refreshed, "passed": (refreshed & 389) == 389})
	_set_pass_through(false)
	pet.always_on_top = true
	_apply_taskbar()
	_hide_pet()
	var hidden := FoxWindowBridge.get_window_state()
	results.append({"case": "hide", "native_state": hidden, "passed": (hidden & 8) == 0})
	_show_pet()
	var shown := FoxWindowBridge.get_window_state()
	results.append({"case": "show_without_activation", "native_state": shown, "passed": (shown & 13) == 13 and (shown & 32) == 0})
	for enabled in [false, true]:
		pet.always_on_top = enabled
		_apply_taskbar()
		var state := FoxWindowBridge.get_window_state()
		results.append({"case": "topmost_" + str(enabled), "native_state": state, "passed": ((state & 16) != 0) == enabled and (state & 5) == 5})
	var dpi := FoxWindowBridge.get_window_dpi()
	results.append({"case": "effective_windows_dpi", "dpi": dpi, "passed": dpi >= 96})
	var file := FileAccess.open(EVIDENCE_DIRECTORY + "native_checks.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	file.close()
	_quit(0 if results.all(func(row: Dictionary): return row.passed) else 1)

func _panel_acceptance() -> void:
	# Synthetic state test; this does not claim physical keyboard-input acceptance.
	var results: Array[Dictionary] = []
	open_panel()
	draft.text = "T02 synthetic draft retention"
	await get_tree().create_timer(0.2).timeout
	panel.mode = Window.MODE_MINIMIZED
	await get_tree().create_timer(0.2).timeout
	var was_minimized := panel.mode == Window.MODE_MINIMIZED
	results.append({"case": "panel_minimize_hides_pet", "passed": was_minimized and (FoxWindowBridge.get_window_state() & 8) == 0})
	open_panel()
	await get_tree().create_timer(0.2).timeout
	results.append({"case": "restore_minimized_panel", "was_minimized": was_minimized, "mode_after": panel.mode, "passed": was_minimized and panel.mode == Window.MODE_WINDOWED and panel.visible})
	results.append({"case": "panel_restore_restores_pet", "passed": (FoxWindowBridge.get_window_state() & 8) != 0})
	_hide_pet()
	panel.mode = Window.MODE_MINIMIZED
	await get_tree().create_timer(0.2).timeout
	open_panel()
	await get_tree().create_timer(0.2).timeout
	results.append({"case": "user_hidden_pet_stays_hidden_after_restore", "passed": (FoxWindowBridge.get_window_state() & 8) == 0})
	_show_pet()
	panel.close_requested.emit()
	var was_hidden := not panel.visible
	open_panel()
	await get_tree().create_timer(0.2).timeout
	results.append({"case": "draft_survives_close_reopen", "was_hidden": was_hidden, "passed": was_hidden and panel.visible and draft.text == "T02 synthetic draft retention"})
	var file := FileAccess.open(EVIDENCE_DIRECTORY + "panel_checks.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(results, "\t"))
	file.close()
	await RenderingServer.frame_post_draw
	panel.get_texture().get_image().save_png(EVIDENCE_DIRECTORY + "controls_preview.png")
	_quit(0 if results.all(func(row: Dictionary): return row.passed) else 1)

func _motion_acceptance() -> void:
	capture_motion = true
	DirAccess.make_dir_recursive_absolute(EVIDENCE_DIRECTORY + "motion")
	var results: Array[Dictionary] = []
	var minimum_center := INF
	var maximum_center := -INF
	for frame in range(72):
		_pose_motion(frame / 12.0)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var picture := pet.get_texture().get_image()
		var polygon := Geometry.envelope(picture.get_size())
		var outside := 0
		var visible := 0
		var sum_x := 0.0
		for y in range(picture.get_height()):
			for x in range(picture.get_width()):
				if picture.get_pixel(x, y).a > 0.02:
					visible += 1
					sum_x += x
					if not Geometry2D.is_point_in_polygon(Vector2(x, y), polygon):
						outside += 1
		var center := sum_x / maxi(visible, 1)
		minimum_center = minf(minimum_center, center)
		maximum_center = maxf(maximum_center, center)
		picture.save_png(EVIDENCE_DIRECTORY + "motion/frame_%03d.png" % frame)
		results.append({"frame": frame, "outside_pixels": outside, "visible_pixels": visible})
	var file := FileAccess.open(EVIDENCE_DIRECTORY + "motion_checks.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"frames": results, "centroid_travel_pixels": maximum_center - minimum_center, "visible_motion_passed": maximum_center - minimum_center > 30.0}, "\t"))
	file.close()
	_quit()

