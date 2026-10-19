extends "OverlayPrototype.gd"
## T08 actual actor integration. Reuses passed T02 Windows recovery behavior;
## T09 cursor classification/attention. Physical desktop drag is T10.
const Factory = preload("res://scripts/animation/FoxActorFactory.gd")
const Director = preload("res://scripts/animation/FoxAnimationDirector.gd")
const Pointer = preload("res://scripts/interaction/FoxPointerClassifier.gd")
const Coordinates = preload("res://scripts/interaction/FoxPointerCoordinates.gd")
const Attention = preload("res://scripts/interaction/FoxCursorAttention.gd")
const InputSettings = preload("res://scripts/interaction/FoxInputSettings.gd")
const GazeGeometry = preload("res://scripts/interaction/FoxGazeGeometry.gd")
const PopupStyle = preload("res://scripts/interaction/FoxPopupStyle.gd")
const HoverTurn = preload("res://scripts/interaction/FoxHoverTurn.gd")
const HoverHint = preload("res://scripts/interaction/FoxHoverHint.gd")
const DesktopDrag = preload("res://scripts/interaction/FoxDesktopDrag.gd")
const HomeStore = preload("res://scripts/interaction/FoxHomeStore.gd")
const CursorFollow = preload("res://scripts/interaction/FoxCursorFollow.gd")
const HomeBehavior = preload("res://scripts/behavior/FoxHomeBehavior.gd")
const HomeMotion = preload("res://scripts/behavior/FoxHomeMotion.gd")
const RestRoutine = preload("res://scripts/behavior/FoxRestRoutine.gd")
const LocalAudio = preload("res://scripts/audio/FoxAudioPlayer.gd")
const AudioControls = preload("res://scripts/audio/FoxAudioControls.gd")
const Preferences = preload("res://scripts/settings/FoxPreferences.gd")
const PreferencesControls = preload("res://scripts/settings/FoxPreferencesControls.gd")
const EyePalette = preload("res://scripts/settings/FoxEyePalette.gd")
const ChatView = preload("res://scripts/chat/FoxChatView.gd")
var chat_view:Node
var t15_harness:RefCounted
var compact_dismiss_press:=false
var preferences:=Preferences.new()
var preference_preview:Dictionary=Preferences.DEFAULTS.duplicate()
var preferences_controls:VBoxContainer
var eye_palette:=EyePalette.new()
const Startup=preload("res://scripts/platform/FoxStartup.gd")
const Lifecycle=preload("res://scripts/platform/FoxLifecycle.gd")
var startup:=Startup.new()
var lifecycle:=Lifecycle.new()
var instance_acquired:=false
var windows_paused:=false
var lifecycle_age:=0.0
var lifecycle_ticks_usec:=0
var local_audio: Node
## Optional orbit control is retained for later user-requested restoration.
const CURSOR_BODY_TURN_ENABLED := false
var hover_hint: Control
const OUT := "user://PublicationChecks/"
var actor: Node3D
var director: Node
var camera: Camera3D
var desktop_test := false
var envelope_age := 0.0
var pointer := Pointer.new()
var attention := Attention.new()
var hover_turn := HoverTurn.new()
var hover_review := false
var hover_review_age := 0.0
var hover_review_counts := {"armed":0,"requests":0,"accepted":0,"declined":0}
var hover_review_phase := "idle"
var hover_review_events: Array[Dictionary]=[]
var input_settings := InputSettings.new()
var sample_age := 0.0
var cursor_enabled := false
var cursor_nearby := false
var render_cadence:=preload("FoxRenderCadence.gd").new()
var render_look:Dictionary={}
var t09_test := false
var t09_harness: RefCounted
var t10_test := false
var t10_harness: RefCounted
var t11_test:=false
var t11_harness:RefCounted
var t14_harness:RefCounted
var home_behavior:=HomeBehavior.new()
var home_motion:=HomeMotion.new()
var rest_routine:=RestRoutine.new()
var observed_home_saves:=0
var fullscreen_age:=0.0
var fullscreen_policy:=preload("FoxFullscreenPolicy.gd").new()
var fullscreen_available:=true
var last_near_cursor:=Vector2.INF
var stay_toggle:CheckBox
var behavior_events:Array[Dictionary]=[]
var desktop_drag := DesktopDrag.new()
var home_store := HomeStore.new()
var drag_anchor_delta := Vector2.ZERO
var home_save_count := 0
var cursor_follow := CursorFollow.new()
var follow_window_origin := Vector2.ZERO
var follow_braking := false
var follow_velocity := Vector2.ZERO
var follow_tempo := 1.0
var rest_follow_departure:=false
var interaction_counts := {"single":0,"double":0,"right":0,"hold":0,"release":0}
var controls_tabs:TabContainer
var dialog_guard:Node
var context_popup: Window
const CONTEXT_ACTIONS := ["panel","stay","sleep","settings","model","history","hide","exit"]

func _ready() -> void:
	# Claim the current-user instance before reading/migrating any stores.
	var claimed:int=FoxWindowBridge.acquire_instance("--t13-validation" in OS.get_cmdline_user_args())
	if claimed!=1:
		set_process(false);set_process_input(false)
		if claimed<0:push_error("Cannot secure the Desktop Pet instance (%s). Startup stopped safely."%claimed)
		get_tree().quit(0 if claimed==0 else 1);return
	instance_acquired=true
	# Optional T20 profile is calibrated for this host, not a universal index.
	# Reject driver fallback / a changed adapter before touching user stores.
	if "--fox-integrated-profile" in OS.get_cmdline_user_args() and (RenderingServer.get_current_rendering_method()!="mobile" or RenderingServer.get_current_rendering_driver_name()!="d3d12" or RenderingServer.get_video_adapter_name()!="AMD Radeon(TM) Graphics"):
		push_error("Integrated profile adapter changed or Direct3D12 unavailable. Use StartDesktopFox.exe (Compatibility) and remeasure the graphics profile.")
		FoxWindowBridge.release_instance();instance_acquired=false;set_process(false);get_tree().quit(1);return
	if Paths.prepare_runtime()!=OK:
		push_error("Windows user-data folder unavailable: " + Paths.RUNTIME_ROOT + "")
		FoxWindowBridge.release_instance();instance_acquired=false;set_process(false);get_tree().quit(1);return
	var first_run_script=preload("res://scripts/settings/FoxFirstRun.gd")
	if not FileAccess.file_exists(first_run_script.marker()) and not "--t13-validation" in OS.get_cmdline_user_args():
		set_process(false);set_process_input(false)
		var welcome=first_run_script.new()
		await welcome.run(self)
		set_process(true);set_process_input(true)
	preferences.load_local();preference_preview=preferences.values.duplicate()
	local_audio=LocalAudio.new();add_child(local_audio)
	if not local_audio.initialize():push_error("Local sound assets unavailable; pet remains usable.")
	desktop_test = "--t08-desktop-test" in OS.get_cmdline_user_args()
	t09_test = "--t09-test" in OS.get_cmdline_user_args() or "--t09-cycle5-test" in OS.get_cmdline_user_args()
	t10_test="--t10-follow-test" in OS.get_cmdline_user_args() or "--t10-follow-home-probe" in OS.get_cmdline_user_args()
	hover_review="--t09-cycle5-review" in OS.get_cmdline_user_args()
	for argument in OS.get_cmdline_user_args():
		if argument in ["--t09-test","--t09-cycle2-test","--t09-cycle3-test","--t09-cycle4-test","--t09-cycle5-test","--t10-test","--t10-home-probe"]:
			push_error("Historical validation retained. Use current --t10-follow-test for this runtime.")
			get_tree().quit(1)
			return
	t11_test="--t11-test" in OS.get_cmdline_user_args()
	home_behavior.load_local()
	input_settings.load_local()
	cursor_follow.load_local()
	pointer.initialize(input_settings.values)
	attention.initialize(input_settings.values)
	# T02 remains a separate unchanged test scene with its own evidence paths.
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--t02-"):
			push_error("Use OverlayPrototype.tscn for T02 tests.")
			get_tree().quit(1)
			return
	super._ready()
	lifecycle.status=FoxWindowBridge.watch_lifecycle()
	if lifecycle.status!=1:push_warning("Windows lifecycle notification coverage is incomplete: "+str(lifecycle.status))
	preview_preferences(preferences.values)
	panel.close_requested.connect(discard_preferences)
	if preferences.load_status=="missing" and preferences.save_local()!=OK:push_error("Could not save initial pet preferences in the Windows user-data folder.")
	# One-time metadata migration; approved interaction values remain unchanged.
	for store in [input_settings,cursor_follow]:
		var legacy:Variant=JSON.parse_string(FileAccess.get_file_as_string(store.PATH)) if FileAccess.file_exists(store.PATH) else {}
		var needs_migration:bool=legacy is Dictionary and (not legacy.has("version") or (store==cursor_follow and (legacy.has("run_enter_px_s") or not legacy.has("approach_px"))))
		if needs_migration and store.save_local()!=OK:push_error("Could not migrate preference metadata in the Windows user-data folder.")
	if not FileAccess.file_exists(local_audio.settings.PATH) and local_audio.settings.save_local()!=OK:push_error("Could not save initial sound preferences.")
	home_behavior.initialize(Time.get_ticks_usec(),Vector2(pet.position))
	if not t11_test and not t10_test and not t09_test and not desktop_test and home_behavior.save_local()!=OK:push_error("Could not save home activity settings in the Windows user-data folder.")
	pet.title = "Desktop Pet"
	panel.title = "Desktop Pet — controls"
	if "--t09-review" in OS.get_cmdline_user_args():
		pet.title="Desktop Pet — T09 candidate"
		panel.title="Desktop Pet — T09 controls"
	if "--t10-review" in OS.get_cmdline_user_args():
		pet.title="Desktop Pet — T10 candidate"
		panel.title="Desktop Pet — T10 controls"
	if "--t11-review" in OS.get_cmdline_user_args():
		pet.title="Desktop Pet — T11 candidate"
		panel.title="Desktop Pet — T11 controls"
	if "--t12-review" in OS.get_cmdline_user_args():
		pet.title="Desktop Pet — T12 candidate"
		panel.title="Desktop Pet — T12 controls"
		open_panel()
		_show_audio_controls.call_deferred()
	if "--t13-review" in OS.get_cmdline_user_args():
		pet.title="Desktop Pet — T13 candidate";panel.title="Desktop Pet — T13 controls"
		open_panel();show_preferences.call_deferred()
	if t11_test:
		t11_harness=load(preload("res://scripts/Paths.gd").development_root().path_join("Tests/Godot/test_home_desktop.gd")).new()
		t11_harness.run(self)
	if CURSOR_BODY_TURN_ENABLED:
		hover_hint=HoverHint.new()
		hover_hint.mouse_filter=Control.MOUSE_FILTER_IGNORE
		pet.add_child.call_deferred(hover_hint)
	if desktop_test: _desktop_acceptance()
	if t09_test:
		# Tests live outside the packaged project; fixed local test path only.
		var script_path := preload("res://scripts/Paths.gd").development_root().path_join("Tests/Godot/test_pointer_cycle5_desktop.gd")
		var harness = load(script_path)
		if harness:
			t09_harness=harness.new()
			t09_harness.run(self)
	if "--t10-follow-test" in OS.get_cmdline_user_args():
		t10_harness=load(preload("res://scripts/Paths.gd").development_root().path_join("Tests/Godot/test_follow_desktop.gd")).new()
		t10_harness.run(self)
	if "--t10-follow-home-probe" in OS.get_cmdline_user_args():
		var file=FileAccess.open(preload("res://scripts/Paths.gd").development_root().path_join("Validation/T10/iteration-3/restart_probe.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify({"position":[pet.position.x,pet.position.y],"size":[pet.size.x,pet.size.y],"record":home_store.load_local(),"native_state":FoxWindowBridge.get_window_state()},"\t"));file.close()
		_quit()
	# Fixed app-owned proof runner, available only in the debug prototype.
	# It is dormant during ordinary use and never accepts a user-supplied path.
	if OS.has_feature("debug") and "--t14-proof" in OS.get_cmdline_user_args():
		t14_harness=load(preload("res://scripts/Paths.gd").development_root().path_join("Validation/T14/iteration-1/combined_probe.gd")).new()
		t14_harness.run.call_deferred(self)
	if OS.has_feature("debug") and "--t15-menu-blur-proof" in OS.get_cmdline_user_args():
		t15_harness=load(preload("res://scripts/Paths.gd").development_root().path_join("Validation/T09/iteration-7/test_menu.gd")).new()
		t15_harness.run.call_deferred(self)
	if OS.has_feature("debug") and "--t15-controls-proof" in OS.get_cmdline_user_args():
		t15_harness=load(preload("res://scripts/Paths.gd").development_root().path_join("Validation/Controls/iteration-1/test_controls.gd")).new()
		t15_harness.run.call_deferred(self)
	if OS.has_feature("debug") and "--t15-full-glass-proof" in OS.get_cmdline_user_args():
		t15_harness=load(preload("res://scripts/Paths.gd").development_root().path_join("Validation/T15/iteration-7/test_glass.gd")).new()
		t15_harness.run.call_deferred(self)
	if OS.has_feature("debug") and "--t15-conversation-proof" in OS.get_cmdline_user_args():
		t15_harness=load(preload("res://scripts/Paths.gd").development_root().path_join("Validation/T15/iteration-6/test_conversation.gd")).new()
		t15_harness.run.call_deferred(self)
	if OS.has_feature("debug") and "--t15-windows-proof" in OS.get_cmdline_user_args():
		t15_harness=load(preload("res://scripts/Paths.gd").development_root().path_join("Validation/T15/iteration-5/test_windows.gd")).new()
		t15_harness.run.call_deferred(self)
	if "--t15-review" in OS.get_cmdline_user_args():
		pet.title="Desktop Pet — T15 candidate";chat_view.open_chat()
	if OS.has_feature("debug") and "--t15-proof" in OS.get_cmdline_user_args():
		t15_harness=load(preload("res://scripts/Paths.gd").development_root().path_join("Validation/T15/iteration-1/test_desktop.gd")).new()
		t15_harness.run.call_deferred(self)
	if OS.has_feature("debug") and "--t15-package-proof" in OS.get_cmdline_user_args():
		t15_harness=load(preload("res://scripts/Paths.gd").development_root().path_join("Validation/T15/iteration-1/test_package.gd")).new()
		t15_harness.run.call_deferred(self)
	if OS.has_feature("debug") and "--t15-compact-proof" in OS.get_cmdline_user_args():
		t15_harness=load(preload("res://scripts/Paths.gd").development_root().path_join("Validation/T15/iteration-2/test_compact.gd")).new()
		t15_harness.run.call_deferred(self)
	if OS.has_feature("debug") and "--t15-compact-package-proof" in OS.get_cmdline_user_args():
		t15_harness=load(preload("res://scripts/Paths.gd").development_root().path_join("Validation/T15/iteration-2/test_package.gd")).new()
		t15_harness.run.call_deferred(self)
	if OS.has_feature("debug") and "--t15-mini-proof" in OS.get_cmdline_user_args():
		t15_harness=load(preload("res://scripts/Paths.gd").development_root().path_join("Validation/T15/iteration-3/test_mini.gd")).new()
		t15_harness.run.call_deferred(self)
	if OS.has_feature("debug") and "--t15-mini-package-proof" in OS.get_cmdline_user_args():
		t15_harness=load(preload("res://scripts/Paths.gd").development_root().path_join("Validation/T15/iteration-3/test_package.gd")).new()
		t15_harness.run.call_deferred(self)
	if OS.has_feature("debug") and "--t15-mini-bench" in OS.get_cmdline_user_args():
		t15_harness=load(preload("res://scripts/Paths.gd").development_root().path_join("Validation/T15/iteration-3/benchmark.gd")).new()
		t15_harness.run.call_deferred(self)
	if "--t16-review" in OS.get_cmdline_user_args():
		pet.title="Desktop Pet — T16 candidate";chat_view.open_chat()
	if OS.has_feature("debug") and "--t16-package-proof" in OS.get_cmdline_user_args():
		t15_harness=load(preload("res://scripts/Paths.gd").development_root().path_join("Validation/T16/iteration-1/test_desktop.gd")).new()
		t15_harness.run.call_deferred(self)
	if "--chat-ui-review" in OS.get_cmdline_user_args():
		pet.title="Desktop Pet — chat correction";chat_view.open_chat()
	if OS.has_feature("debug") and "--chat-ui-proof" in OS.get_cmdline_user_args():
		t15_harness=load(preload("res://scripts/Paths.gd").development_root().path_join("Validation/T15/iteration-4/test_desktop.gd")).new()
		t15_harness.run.call_deferred(self)

func _place_pet(center: bool) -> void:
	var previous_origin:=Vector2(pet.position) if pet else Vector2.ZERO
	super._place_pet(center)
	var percentage:float=preference_preview.size_percent/100.0
	if not is_equal_approx(percentage,1.0):
		var usable:=DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen(pet.get_window_id()))
		pet.size=Vector2i(Vector2(pet.size)*percentage).min(usable.size).max(Vector2i.ONE)
		pet.position=Geometry.fit_position(pet.position,pet.size,usable)
		_apply_envelope()
	if center:
		var areas: Array[Rect2i]=[]
		for screen in DisplayServer.get_screen_count(): areas.append(DisplayServer.screen_get_usable_rect(screen))
		pet.position=home_store.restored(home_store.load_local(),pet.size,areas,pet.position)
	elif rest_routine.edge_location and director and camera:
		# Preserve the visible pet's edge position, not its transparent margins.
		pet.position=Vector2i(rest_routine.Plan.clamp_origin(previous_origin,rest_routine.footprint(self),rest_routine.area(self)).round())
	desktop_drag.reframe(Vector2(pet.position))
	follow_window_origin=Vector2(pet.position)

func _drag_scale() -> Vector2:
	return Vector2(pet.size)/pet.get_visible_rect().size

func _drag_anchor() -> Vector2:
	return camera.unproject_position(director.view_center())

func _arm_drag(point: Vector2, now: float) -> void:
	rest_routine.edge_location=false
	var screen_point := Coordinates.logical_to_screen(point,Vector2(pet.position),Vector2(pet.size),pet.get_visible_rect().size)
	if cursor_follow.active():_abort_follow()
	cursor_follow.press(now,screen_point)
	var area:=Rect2(DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen(pet.get_window_id())))
	rest_follow_departure=not area.encloses(Rect2(Vector2(pet.position),Vector2(pet.size)))
	follow_window_origin=Vector2(pet.position);follow_braking=false;follow_velocity=Vector2.ZERO;follow_tempo=1.0
	if not t09_test and not t10_test and not t11_test: FoxWindowBridge.set_drag_tracking(true)

func _follow_center() -> Vector2:
	return follow_window_origin+Vector2(pet.size)*.5

func _screen_direction_world(vector: Vector2) -> Vector3:
	var origin:=Vector3(director.stage.position.x,0,director.stage.position.z)
	var projected:=camera.unproject_position(origin)
	var a:=camera.unproject_position(origin+Vector3.RIGHT)-projected
	var b:=camera.unproject_position(origin+Vector3.BACK)-projected
	var logical:=vector/_drag_scale()
	var determinant:=a.x*b.y-a.y*b.x
	if absf(determinant)<.00001:return Vector3.ZERO
	return Vector3((logical.x*b.y-logical.y*b.x)/determinant,0,(a.x*logical.y-a.y*logical.x)/determinant).normalized()

func _step_follow(delta: float, screen_point: Vector2, now: float=-1.0) -> bool:
	if not cursor_follow.busy():return false
	if now<0:now=Time.get_ticks_msec()/1000.0
	var screen := DisplayServer.window_get_current_screen(pet.get_window_id())
	var area := DisplayServer.screen_get_usable_rect(screen)
	var half:=Vector2(pet.size)*.5
	var reachable:=Rect2(Vector2(area.position)+half,Vector2((area.size-pet.size).max(Vector2i.ZERO)))
	if rest_follow_departure:reachable=reachable.grow(-12)
	cursor_follow.sample(now,screen_point,_follow_center(),reachable)
	if not cursor_follow.active():return false
	var old:=Vector3(director.stage.position.x,0,director.stage.position.z)
	var target_vector:=cursor_follow.target-_follow_center()
	var tempo:=1.0
	if cursor_follow.arrival_pending:follow_braking=true
	if follow_braking:director.follow_stop()
	else:
		director.follow_drive(_screen_direction_world(target_vector),cursor_follow.mode,delta)
		if director.body in ["turn_left","turn_right"]:tempo=.9
		elif director.body in ["walk","run"]:
			var forward:Vector3=director.follow_forward()
			var pixels:Vector2=(camera.unproject_position(old+forward)-camera.unproject_position(old))*_drag_scale()
			var length:float=director.catalog.animations[director.body].length
			var stride:float=director.catalog.travel(director.body,length).origin.length()/length
			var requested:float=cursor_follow.pace
			if cursor_follow.stopped:requested=minf(requested,target_vector.length()/.3)
			tempo=clampf(requested/maxf(1.0,pixels.length()*stride),.10,1.8)
			if absf(director.follow_error_degrees)>150:tempo=minf(tempo,.75)
	follow_tempo=move_toward(follow_tempo,tempo,delta*3.0)
	director.step(delta*(1.0 if follow_braking else follow_tempo))
	var placed:=Vector3(director.stage.position.x,0,director.stage.position.z)
	if follow_braking:
		# Stance contact correction belongs inside the viewport. Do not turn
		# its root recovery into desktop drift after the target was reached.
		follow_velocity=follow_velocity.move_toward(Vector2.ZERO,550.0*delta)
	else:
		var measured:Vector2=(camera.unproject_position(placed)-camera.unproject_position(old))*_drag_scale()/maxf(.001,delta)
		follow_velocity=follow_velocity.lerp(measured,1.0-exp(-delta/.08))
	var movement:=follow_velocity*delta
	if follow_braking and movement.length()>target_vector.length():movement=movement.limit_length(target_vector.length())
	follow_window_origin+=movement
	follow_window_origin=_fit_follow_departure(follow_window_origin,area)
	pet.position=Vector2i(roundi(follow_window_origin.x),roundi(follow_window_origin.y))
	if follow_braking and director.body=="idle_stand" and director.blend_age>=director.blend_duration:
		cursor_follow.acknowledge_stop();follow_braking=false;follow_velocity=Vector2.ZERO;_save_home()
	return true

func _fit_follow_departure(origin:Vector2,area:Rect2i) -> Vector2:
	if rest_follow_departure:
		_follow_camera()
		origin=rest_routine.Plan.clamp_origin(origin,rest_routine.footprint(self),Rect2(area))
		if Rect2(area).encloses(Rect2(origin,Vector2(pet.size))):rest_follow_departure=false
		return origin
	return origin.clamp(Vector2(area.position),Vector2((area.end-pet.size).max(area.position)))

func _finish_drag(now: float, screen_point: Variant=null) -> void:
	FoxWindowBridge.set_drag_tracking(false)
	cursor_follow.release(now,Vector2(DisplayServer.mouse_get_position()) if screen_point==null else screen_point)

func _save_home() -> void:
	var screen := DisplayServer.window_get_current_screen(pet.get_window_id())
	var area := DisplayServer.screen_get_usable_rect(screen)
	pet.position=Geometry.fit_position(pet.position,pet.size,area)
	var error := home_store.save_local(pet.position,pet.size,area)
	if error!=OK: push_error("Could not save fox home on G:; placement remains available until Exit.")
	else: home_save_count+=1

func _abort_follow() -> void:
	var moving:=cursor_follow.cancel()
	if director:director.follow_stop()
	follow_braking=false;follow_velocity=Vector2.ZERO;follow_tempo=1.0
	if moving:_save_home()

func _create_mesh() -> void:
	mesh_root = Node3D.new()
	add_child(mesh_root)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#eef0ff")
	environment.ambient_light_energy = 0.45
	environment_node.environment = environment
	mesh_root.add_child(environment_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45,-30,0)
	light.light_energy = 0.6
	mesh_root.add_child(light)
	var stage := Node3D.new()
	mesh_root.add_child(stage)
	actor = Factory.create_actor()
	if not actor:
		push_error("Approved fox model unavailable in this application package.")
		get_tree().quit(1);return
	stage.add_child(actor)
	render_look=preload("FoxRenderLook.gd").apply(actor,RenderingServer.get_current_rendering_driver_name())
	director = Director.new()
	# This window controller owns the clock, including hidden/minimized pauses.
	director.manual = true
	add_child(director)
	# Required initialization must run in release builds, where assert is removed.
	if not director.initialize(actor,stage):
		push_error("Approved animation binding failed in this application package.")
		get_tree().quit(1);return
	if not eye_palette.initialize(actor):push_warning("Eye color customization unavailable for this model.")
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.25
	mesh_root.add_child(camera)
	camera.current = true
	_follow_camera()

func _create_panel() -> void:
	super._create_panel()
	var margin := panel.get_child(1) as MarginContainer
	var column := margin.get_child(0) as VBoxContainer
	var scroll := ScrollContainer.new()
	panel.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.reparent(scroll)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var motion := GridContainer.new()
	motion.columns = 3
	column.add_child(motion)
	column.move_child(motion,2)
	for entry in [["Stand","standing"],["Sit","sitting"],["Lie","lying"],["Sleep","sleeping"]]:
		_button(motion,entry[0],func(): _user_posture(entry[1]))
	for entry in [["Walk","walk"],["Run","run"],["Turn left","turn_left"],["Turn right","turn_right"]]:
		_button(motion,entry[0],func(): director.request_grounded_gait(entry[1]))
	_button(motion,"Jump → sit",func(): director.request_jump_sit())
	_button(motion,"Pick up",func(): director.begin_drag())
	_button(motion,"Release",func(): director.release_drag())
	_button(motion,"Blink",func(): director.request_overlay("blink","user"))
	top_toggle.text = "Keep pet on top"
	taskbar_toggle.text = "Show pet in taskbar"
	pass_toggle.text = "Pass all clicks through pet"
	draft.placeholder_text = "Write a note here. Closing controls keeps your draft."
	for control in column.get_children():
		if control is Label or control is Button:
			control.text = control.text.replace("placeholder","pet").replace("prototype","Desktop Pet")
	var size_row := column.get_child(7) as HBoxContainer
	if size_row and size_row.get_child(0) is Label: size_row.get_child(0).text = "Pet size:"
	var footer := column.get_child(column.get_child_count()-1) as Label
	if footer: footer.text = "Use the tray to show your pet or restore clicks."
	(column.get_child(0) as Label).text = "Desktop Pet"
	panel.size = Vector2i(470,700)
	var sensitivity := HBoxContainer.new()
	column.add_child(sensitivity)
	var label := Label.new(); label.text="Cursor sensitivity"; sensitivity.add_child(label)
	var slider := HSlider.new()
	slider.min_value=0.5; slider.max_value=1.5; slider.step=0.1
	slider.value=float(input_settings.values.sensitivity)
	slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	sensitivity.add_child(slider)
	slider.value_changed.connect(func(value):
		input_settings.values.sensitivity=value
		var error := input_settings.save_local()
		if error!=OK: push_error("Could not save cursor sensitivity."))
	var hover_help := Label.new()
	hover_help.text="Move the cursor nearby to let your pet look around."
	hover_help.add_theme_font_size_override("font_size",13)
	column.add_child(hover_help)
	var drag_help := Label.new()
	drag_help.text="Hold 1 second, then move far enough to lead your pet."
	drag_help.add_theme_font_size_override("font_size",13)
	column.add_child(drag_help)
	var follow_title:=Label.new();follow_title.text="Follow movement";column.add_child(follow_title)
	for entry in [["Hold before ready (ms)","hold_ms"],["Start distance (screen px)","distance_px"],["Cursor delay (ms)","delay_ms"],["Walk final approach (screen px)","approach_px"],["Walk pace (px / sec)","walk_px_s"],["Run pace (px / sec)","run_px_s"],["Stop-turn reversal (degrees)","reversal_deg"],["Steering rate (degrees / sec)","steering_deg_s"],["Resting angle (degrees)","rest_angle_deg"]]:
		var row:=HBoxContainer.new();row.set_meta("settings_group","Movement" if entry[1] in ["walk_px_s","run_px_s","steering_deg_s","rest_angle_deg"] else "Thresholds");column.add_child(row)
		var text:=Label.new();text.text=entry[0];text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(text)
		var field:=SpinBox.new();var key:String=entry[1]
		field.min_value=cursor_follow.LIMITS[key].x;field.max_value=cursor_follow.LIMITS[key].y;field.step=1;field.value=cursor_follow.settings[key];row.add_child(field)
		field.value_changed.connect(_update_follow_setting.bind(key))
	var home_title:=Label.new();home_title.text="Home and quiet time";column.add_child(home_title)
	var activity:=OptionButton.new()
	for value in ["Off","Low","Normal"]:activity.add_item(value)
	activity.select(["Off","Low","Normal"].find(home_behavior.settings.activity))
	activity.item_selected.connect(func(index):
		home_motion.stop(self,"activity changed")
		rest_routine.cancel(self,"activity changed")
		home_behavior.settings.activity=["Off","Low","Normal"][index]
		home_behavior.interact();home_behavior._schedule();_save_activity())
	var activity_row:=HBoxContainer.new();column.add_child(activity_row)
	var activity_label:=Label.new();activity_label.text="Idle gestures";activity_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;activity_row.add_child(activity_label);activity_row.add_child(activity)
	stay_toggle=CheckBox.new();stay_toggle.text="Stay Here — mark current home";stay_toggle.button_pressed=bool(input_settings.values.stay_here);column.add_child(stay_toggle)
	stay_toggle.toggled.connect(func(value):
		home_motion.stop(self,"Stay Here changed")
		rest_routine.cancel(self,"Stay Here changed")
		input_settings.values.stay_here=value
		if input_settings.save_local()!=OK:push_error("Could not save Stay Here.")
		if value:_save_home();home_behavior.set_home(Vector2(pet.position));observed_home_saves=home_save_count
		home_behavior.interact())
	_button(column,"Sleep / Wake",func():_menu_action("sleep"))
	var quiet_help:=Label.new();quiet_help.text="3 minutes with the cursor away: run toward the nearest corner, then walk the last short distance and lie down.
5 further minutes lying: sleep. Cursor proximity wakes your pet and resets both timers.
Idle gestures Off and Stay Here do not disable this rest routine. No random roaming."
	quiet_help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	quiet_help.add_theme_font_size_override("font_size",13);column.add_child(quiet_help)
	draft.text_changed.connect(func():home_behavior.interact();home_motion.stop(self,"chat entry"))
	column.add_child(AudioControls.build(local_audio))
	preferences_controls=PreferencesControls.new();column.add_child(preferences_controls)
	preferences_controls.initialize(self);column.move_child(preferences_controls,2)
	chat_view=ChatView.new();add_child(chat_view);chat_view.initialize(self)
	_button(column,"Open chat",open_chat)
	for node in [motion]:node.set_meta("settings_group","Gestures")
	for node in [sensitivity,hover_help,drag_help]:node.set_meta("settings_group","Thresholds")
	for node in [home_title,activity_row,stay_toggle,quiet_help]:node.set_meta("settings_group","Movement")
	controls_tabs=preload("res://scripts/settings/FoxControlsLayout.gd").build(self,column,scroll)
	dialog_guard=preload("res://scripts/platform/FoxDialogGuard.gd").new();add_child(dialog_guard);dialog_guard.initialize(self)


func open_chat() -> void:
	if chat_view:chat_view.open_chat()

func open_panel() -> void:
	if chat_view:chat_view.hide_all()
	super.open_panel()
	if dialog_guard:dialog_guard.fit_window(panel)

func _chat_open() -> bool:
	# A minimized native Window still reports visible. It must release the pet's
	# input/render gate while its controller keeps streaming in the background.
	return chat_view!=null and ((chat_view.window.visible and chat_view.window.mode!=Window.MODE_MINIMIZED) or chat_view.compact.visible())

func _update_follow_setting(value: float, key: String) -> void:
	cursor_follow.settings[key]=value
	if cursor_follow.save_local()!=OK:push_error("Could not save follow controls on G:.")

func _show_audio_controls() -> void:
	await get_tree().process_frame
	if controls_tabs:controls_tabs.current_tab=3

func show_preferences() -> void:
	await get_tree().process_frame
	if controls_tabs:controls_tabs.current_tab=0

func preview_preferences(candidate:Dictionary) -> void:
	preference_preview=preferences.sanitize(candidate)
	pet.always_on_top=preference_preview.topmost;taskbar_visible=preference_preview.taskbar
	top_toggle.set_pressed_no_signal(preference_preview.topmost);taskbar_toggle.set_pressed_no_signal(preference_preview.taskbar)
	_place_pet(false)
	if not eye_palette.apply(preference_preview.eye_color) and preference_preview.eye_color!="Original":
		if preferences_controls:preferences_controls.status.text="Eye color preview unavailable; use Original."
	if tray_id>=0:DisplayServer.status_indicator_set_tooltip(tray_id,preference_preview.pet_name+" — Desktop Pet: right-click for controls")
	if not preference_preview.fullscreen_pause:
		fullscreen_policy.observe(0,false)
		if director.full_screen:director.set_lifecycle(director.hidden,false)
	if chat_view:chat_view.compact.apply_glass(preference_preview)

func apply_preferences(candidate:Dictionary) -> Error:
	var saved:Dictionary=preferences.values.duplicate()
	preferences.values=preferences.sanitize(candidate)
	var error:int=preferences.save_local()
	if error!=OK:preferences.values=saved;return error
	preview_preferences(preferences.values)
	_save_home()
	return OK

func discard_preferences() -> void:
	preview_preferences(preferences.values)
	if preferences_controls:preferences_controls.restore(preferences.values)

func _create_tray() -> void:
	super._create_tray()
	if menu.is_valid():NativeMenu.add_item(menu,"Settings",_menu_action,Callable(),"settings")
	if menu.is_valid():
		for index in NativeMenu.get_item_count(menu):
			NativeMenu.set_item_text(menu,index,NativeMenu.get_item_text(menu,index).replace("placeholder","pet").replace("Chat / controls","Chat"))
	if tray_id >= 0: DisplayServer.status_indicator_set_tooltip(tray_id,"Desktop Pet — right-click for controls")
	if not context_popup:
		context_popup=preload("res://scripts/interaction/FoxQuickMenu.gd").new()
		add_child(context_popup)
		context_popup.initialize(self)
		for label in ["Chat","Stay Here","Sleep / Wake","Settings","Model","History","Hide","Exit"]:context_popup.add_item(label)
		context_popup.id_pressed.connect(func(id):_menu_action(CONTEXT_ACTIONS[id]))

func recover_tray() -> void:
	if tray_id>=0:DisplayServer.delete_status_indicator(tray_id);tray_id=-1
	if menu.is_valid():NativeMenu.free_menu(menu);menu=RID()
	_create_tray()
	if tray_id>=0:DisplayServer.status_indicator_set_tooltip(tray_id,preference_preview.pet_name+" — Desktop Pet: right-click for controls")
	else:
		# A failed tray rebuild cannot strand a hidden/click-through overlay.
		_set_pass_through(false);_show_pet();open_panel()
	_event("tray_recovered",{"available":tray_id>=0})

func recover_instance() -> void:
	if chat_view:chat_view.cancel_approach("instance recovery")
	_cancel_pointer()
	# Reset transient navigation/rest/input ownership without changing settings,
	# chat draft, approved animation assets or the current home/visible position.
	if context_popup:context_popup.hide()
	_set_pass_through(false);_show_pet()
	var actual_fullscreen:int=FoxWindowBridge.get_foreground_fullscreen()
	fullscreen_policy.observe(actual_fullscreen,preference_preview.fullscreen_pause)
	director.set_lifecycle(windows_paused,fullscreen_policy.advance(0,preference_preview.fullscreen_pause))
	director.pending="";director.pending_priority=0;director.overlays.clear()
	director.follow_stop();director.cancel_attention_turn()
	if director.body=="pickup" or director.body.begins_with("drag_"):director.release_drag()
	director.request_posture("standing","user")
	home_behavior.set_sleep(false);home_behavior.interact();sleeping=false
	attention=Attention.new();attention.initialize(input_settings.values)
	hover_turn.reset();sample_age=0;cursor_nearby=false;cursor_enabled=false
	cursor_follow.stopped=false;cursor_follow.confirmation=0;cursor_follow.cursor_speed=0
	_sync_audio_lifecycle();open_panel();show_preferences.call_deferred()
	_event("instance_recovered",{"body":director.body,"pointer_pressed":pointer.pressed,"follow_busy":cursor_follow.busy()})

func _menu_action(action: Variant) -> void:
	if chat_view:chat_view.cancel_approach("menu interaction")
	home_motion.stop(self,"menu")
	rest_routine.cancel(self,"menu")
	home_behavior.interact()
	if str(action)=="sleep":sleeping=home_behavior.manual_sleep or home_behavior.auto_sleep or director.body in ["sleep_enter","sleep_loop"]
	_cancel_pointer()
	if context_popup: context_popup.hide()
	if str(action)=="panel":open_chat()
	elif str(action)=="model":open_chat();chat_view.compact.model.grab_focus()
	elif str(action)=="history":chat_view.open_full_chat();chat_view.history_row.show();chat_view.controller.history_requested.emit();chat_view.refresh()
	elif str(action)=="settings":open_panel();show_preferences.call_deferred()
	else:super._menu_action(action)
	if str(action) == "sleep":
		home_behavior.set_sleep(sleeping)
		director.request_posture("sleeping" if sleeping else "standing")
	if str(action)=="stay":
		input_settings.values.stay_here=true
		input_settings.save_local()
		if stay_toggle:stay_toggle.set_pressed_no_signal(true)
		_save_home();home_behavior.set_home(Vector2(pet.position));observed_home_saves=home_save_count
		home_behavior.set_sleep(false);sleeping=false
		director.request_posture("standing")
	_sync_audio_lifecycle()
	if str(action) in ["show","panel","settings","input","stay"]:local_audio.request("ui")

func _process(delta: float) -> void:
	if not director: return
	director.reversal_degrees=float(cursor_follow.settings.reversal_deg)
	director.steering_degrees_s=float(cursor_follow.settings.steering_deg_s)
	# Godot may smooth/cap its frame delta at low draw rates. Windows recovery
	# and foreground quiet time need the monotonic elapsed clock instead.
	var lifecycle_now:int=Time.get_ticks_usec()
	var elapsed:float=delta if lifecycle_ticks_usec==0 else maxf(0.0,float(lifecycle_now-lifecycle_ticks_usec)/1000000.0)
	lifecycle_ticks_usec=lifecycle_now
	var gap:bool=elapsed>2.0
	var lifecycle_delta:float=clampf(elapsed,0,1)
	var signals:int=FoxWindowBridge.poll_lifecycle()
	if gap:signals|=4
	lifecycle.consume(self,signals,lifecycle_delta)
	delta=clampf(delta,0,.1)
	super._process(delta)
	if not desktop_test and not t09_test and not t10_test and not t11_test:
		# Foreground policy uses elapsed time even when paused drawing runs at5Hz.
		# Keep the smaller animation step separate from the10-second quiet timer.
		fullscreen_age+=lifecycle_delta
		if fullscreen_age>=.5:
			fullscreen_age=0
			var fullscreen:int=FoxWindowBridge.get_foreground_fullscreen()
			fullscreen_available=fullscreen>=0
			fullscreen_policy.observe(fullscreen,preference_preview.fullscreen_pause)
		var should_pause:bool=fullscreen_policy.advance(lifecycle_delta,preference_preview.fullscreen_pause)
		if director.full_screen!=should_pause:director.set_lifecycle(director.hidden,should_pause)
	var native_state := FoxWindowBridge.get_window_state()
	var invisible := windows_paused or pet_hidden_by_user or panel_minimized or (native_state >= 0 and (native_state & 8) == 0)
	if director.hidden != invisible: director.set_lifecycle(invisible,director.full_screen)
	# Keep visible input/network/UI pumping at30Hz even when only drawing5Hz.
	Engine.max_fps=5 if director.paused() and not panel.visible and not _chat_open() else 30
	_sync_audio_lifecycle()
	local_audio.advance(delta)
	var enabled: bool = not invisible and not director.full_screen and not full_passthrough and not panel.visible and not _chat_open() and not context_popup.visible
	if not enabled and (cursor_enabled or pointer.pressed or cursor_follow.busy()): _cancel_pointer()
	cursor_enabled=enabled
	if not desktop_test and not t09_test and not t10_test and not t11_test:
		if pointer.pressed and FoxWindowBridge.get_drag_button_state()==0:
			var point := Coordinates.screen_to_logical(Vector2(DisplayServer.mouse_get_position()),Vector2(pet.position),Vector2(pet.size),pet.get_visible_rect().size)
			var inside := Coordinates.in_native_mask(point,Vector2(pet.size),pet.get_visible_rect().size,pet.mouse_passthrough_polygon)
			pointer.button(MOUSE_BUTTON_LEFT,false,Time.get_ticks_msec()/1000.0,point,inside)
			_dispatch_pointer()
		_sample_pointer(delta)
		_tick_home(delta)
		if chat_view:chat_view.observe_window_motion(delta)
		if not _step_follow(delta,Vector2(DisplayServer.mouse_get_position())):
			if not chat_view.step_approach(delta) and not rest_routine.step(self,delta) and not home_motion.step(self,delta,home_behavior):_step_settled_pose(delta)
	if not director.paused():_follow_camera()
	envelope_age += delta
	var envelope_interval := 1.0/30.0 if cursor_follow.active() or home_motion.active or (chat_view!=null and chat_view.approach.active()) or attention.neck_velocity.length()>0.1 or director.posture() in ["turning","transition"] else 0.1
	if not director.paused() and envelope_age >= envelope_interval:
		envelope_age = 0.0
		_apply_envelope()
	_update_summary()
	_sync_audio_lifecycle()
	_schedule_pet_render(delta)

func _visual_hz() -> int:
	if director.paused():return 0
	var busy:bool=cursor_nearby or pointer.pressed or not pointer.pending.is_empty() or cursor_follow.busy() or home_motion.active or rest_routine.active() or (chat_view!=null and chat_view.approach.active())
	if busy or panel.visible or _chat_open() or context_popup.visible or not director.pending.is_empty() or not director.overlays.is_empty() or director.blend_age<director.blend_duration or director.attention_turn_playback or attention.neck_velocity.length()>.1:return render_cadence.ACTIVE_HZ
	if director.body=="sleep_loop":return render_cadence.SLEEP_HZ
	if director.body in director.POSTURES:return render_cadence.REST_HZ
	return render_cadence.ACTIVE_HZ

func _step_settled_pose(delta:float) -> void:
	var hz:int=_visual_hz()
	var tick:float=render_cadence.pose_tick(delta,hz)
	if tick>0:director.step(tick,hz<render_cadence.ACTIVE_HZ)

func _schedule_pet_render(delta:float) -> void:
	var draw:bool=render_cadence.draw_tick(delta,_visual_hz())
	RenderingServer.viewport_set_update_mode(pet.get_viewport_rid(),RenderingServer.VIEWPORT_UPDATE_ONCE if draw else RenderingServer.VIEWPORT_UPDATE_DISABLED)

func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not director or desktop_test: return
	if event.window_id!=pet.get_window_id(): return
	# Dismiss an open compact popup without arming drag, click, or double-click.
	if event.button_index==MOUSE_BUTTON_LEFT and compact_dismiss_press:
		if not event.pressed:compact_dismiss_press=false
		return
	if chat_view and chat_view.compact.visible() and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			compact_dismiss_press=true;_cancel_pointer();chat_view.compact.close_popup()
		return
	if full_passthrough or pet_hidden_by_user or panel_minimized or director.paused() or panel.visible or _chat_open() or context_popup.visible: return
	# Godot converts event.position into this viewport's logical units.
	var inside := Coordinates.in_native_mask(event.position,Vector2(pet.size),pet.get_visible_rect().size,pet.mouse_passthrough_polygon)
	if inside and event.pressed:
		home_motion.stop(self,"user press")
		rest_routine.cancel(self,"user press")
		home_behavior.interact()
		if home_behavior.auto_sleep:
			home_behavior.set_sleep(false);sleeping=false;director.request_posture("standing")
		if event.button_index==MOUSE_BUTTON_RIGHT and cursor_follow.active():_abort_follow()
		hover_turn.reset()
		director.cancel_attention_turn()
	if inside and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and not pointer.pressed:
		_arm_drag(event.position,Time.get_ticks_msec()/1000.0)
	pointer.button(event.button_index,event.pressed,Time.get_ticks_msec()/1000.0,event.position,inside)
	_dispatch_pointer()
	if event.button_index==MOUSE_BUTTON_LEFT and not event.pressed and not pointer.holding:
		var released_at:=Coordinates.logical_to_screen(event.position,Vector2(pet.position),Vector2(pet.size),pet.get_visible_rect().size)
		_finish_drag(Time.get_ticks_msec()/1000.0,released_at)

func _sample_pointer(delta: float) -> void:
	sample_age+=delta
	var resting: bool = not cursor_enabled or (not cursor_nearby and not pointer.pressed and pointer.pending.is_empty()) or director.posture() in ["lying","sleeping"]
	var interval := 2.0/30.0 if resting else 1.0/30.0
	if sample_age+0.000001<interval: return
	var tick := minf(sample_age,0.25); sample_age=0.0
	var now := Time.get_ticks_msec()/1000.0
	var point := Coordinates.screen_to_logical(Vector2(DisplayServer.mouse_get_position()),Vector2(pet.position),Vector2(pet.size),pet.get_visible_rect().size)
	var inside := Coordinates.in_native_mask(point,Vector2(pet.size),pet.get_visible_rect().size,pet.mouse_passthrough_polygon)
	_feed_cursor_sample(tick,now,point,inside)

func _feed_cursor_sample(tick: float, now: float, point: Vector2, inside: bool) -> void:
	# Physical cursor proximity, independent of delayed navigation/gaze target.
	var raw_head:Vector2=_cursor_anchors().head[0].center
	cursor_nearby=inside or point.distance_to(raw_head)<=float(input_settings.values.attention_radius)
	if cursor_enabled and cursor_nearby:_cursor_proximity_interact()
	if cursor_enabled:
		pointer.advance(now,point,inside)
		_dispatch_pointer()
	var following:bool=cursor_follow.active()
	if following:point=Coordinates.screen_to_logical(cursor_follow.target,Vector2(pet.position),Vector2(pet.size),pet.get_visible_rect().size)
	var anchors := _cursor_anchors()
	var center: Vector2 = anchors.head[0].center
	var zone := Attention.pick_zone(point,anchors) if inside else ""
	var allowed: bool = cursor_enabled and not panel.visible and not _chat_open() and ((not pointer.pressed and (director.posture() in ["standing","sitting"] or director.attention_turn_playback)) or following)
	var relative := _cursor_relative_angles(point)
	var body_center := camera.unproject_position(director.view_center())
	var turn_allowed: bool=CURSOR_BODY_TURN_ENABLED and allowed and not context_popup.visible and pointer.pending.is_empty() and director.posture() in ["standing","sitting"] and director.pending.is_empty()
	var request := hover_turn.sample(tick,now,point,body_center,relative.x,turn_allowed,center)
	var accepted := false
	if request!=0.0: accepted=director.request_attention_turn(request)
	if hover_hint:hover_hint.show_state(hover_turn,body_center,director.attention_turn_playback)
	if hover_review:_hover_review_state(tick,request,accepted)
	if not cursor_enabled or not pointer.pending.is_empty() or pointer.pressed or panel.visible or context_popup.visible or point.distance_to(body_center)>HoverTurn.MAX_RADIUS:
		director.cancel_attention_turn()
	var gaze_point:Vector2=center+(point-center).limit_length(float(input_settings.values.attention_radius)*.9) if following else point
	var cue := attention.sample(tick,now,gaze_point,center,zone if not following and not director.attention_turn_playback else "",allowed,relative)
	director.set_oriented_gaze(attention.eye_angles,attention.neck_angles)
	if not cue.is_empty() and director.request_overlay(cue,"user"):
		var layer: String=director.catalog.rows[cue].layer
		director.overlays[layer]["one_shot"]=true

func _hover_review_state(delta: float, request: float, accepted: bool) -> void:
	# Review only: bounded app-state counts, never mouse coordinates or paths.
	if hover_turn.phase=="armed" and hover_review_phase!="armed":hover_review_counts.armed+=1
	hover_review_phase=hover_turn.phase
	if request!=0.0:
		hover_review_counts.requests+=1
		hover_review_counts.accepted+=int(accepted);hover_review_counts.declined+=int(not accepted)
		hover_review_events.append({"direction":"positive anatomical yaw" if request>0 else "negative anatomical yaw","accepted":accepted,"body":director.body,"reason":director.attention_decline_reason})
		if hover_review_events.size()>16:hover_review_events.pop_front()
	hover_review_age+=delta
	if hover_review_age<1.0 and request==0.0:return
	hover_review_age=0.0
	var file=FileAccess.open(preload("res://scripts/Paths.gd").development_root().path_join("Validation/T09/iteration-5/review_state.json"),FileAccess.WRITE)
	if file:file.store_string(JSON.stringify({"cursor_body_turn_enabled":CURSOR_BODY_TURN_ENABLED,"phase":hover_review_phase,"counts":hover_review_counts,"recent":hover_review_events,"posture":director.posture(),"body":director.body,"attention_playing":director.attention_turn_playback,"controls_open":panel.visible,"full_clickthrough":full_passthrough,"cursor_coordinates_logged":false},"\t"))

func _cursor_relative_angles(point: Vector2) -> Vector2:
	var frame: Dictionary=director.cursor_reference_frame()
	# Virtual attention plane is in front of the head, toward the screen. Its
	# depth gives a real direction even when cursor/head project to one pixel.
	var head_depth: float=(frame.origin-camera.global_position).dot(-camera.global_basis.z)
	var target := camera.project_position(point,maxf(camera.near,head_depth-0.4))
	return GazeGeometry.relative_angles(target-frame.origin,frame.forward,frame.up)

func _cursor_anchors() -> Dictionary:
	var anchors := {"head":[],"ears":[],"body":[],"tail":[]}
	for entry in [["head","Fox_Head_016",Vector2(24,22)],["ears","Fox_LEar1_018",Vector2(15,16)],["ears","Fox_REar1_020",Vector2(15,16)],["body","Fox_Spine2_09",Vector2(43,29)],["tail","Fox_Tail3_04",Vector2(19,19)],["tail","Fox_Tail5_06",Vector2(19,19)]]:
		var bone: int = director.mixer.skeleton.find_bone(entry[1])
		if bone<0: continue
		var world: Vector3=director.mixer.skeleton.global_transform*director.mixer.skeleton.get_bone_global_pose(bone).origin
		anchors[entry[0]].append({"center":camera.unproject_position(world),"radius":entry[2]})
	return anchors

func _dispatch_pointer() -> void:
	for command in pointer.drain():
		interaction_counts[command.kind]+=1
		match str(command.kind):
			"single":
				director.request_overlay("click_react","user"); open_chat()
				_sync_audio_lifecycle();local_audio.request("interaction")
			"double":
				director.request_jump_sit()
				_sync_audio_lifecycle();local_audio.request("interaction")
			"hold":
				pass # Classifier reserves the gesture; navigation uses its own 1s gate.
			"release":
				var point:=Coordinates.logical_to_screen(command.position,Vector2(pet.position),Vector2(pet.size),pet.get_visible_rect().size)
				_finish_drag(Time.get_ticks_msec()/1000.0,point)
			"right":
				var screen := DisplayServer.window_get_current_screen(pet.get_window_id())
				var extent := Vector2i(context_popup.menu_extent()).max(Vector2i.ONE)
				var point := Coordinates.logical_to_screen(command.position,Vector2(pet.position),Vector2(pet.size),pet.get_visible_rect().size)
				context_popup.open_at(Rect2i(Coordinates.clamp_popup(Vector2i(point),extent,DisplayServer.screen_get_usable_rect(screen)),extent))
				_sync_audio_lifecycle();local_audio.request("ui")
	if not pointer.pressed and cursor_follow.pressed:
		_finish_drag(Time.get_ticks_msec()/1000.0)

func _cancel_pointer() -> void:
	var finished_follow:bool=cursor_follow.active() or rest_routine.follow_seen
	home_motion.stop(self,"input/lifecycle cancelled")
	rest_routine.cancel(self,"input/lifecycle cancelled")
	hover_turn.reset()
	if director: director.cancel_attention_turn()
	pointer.cancel()
	# Discard click/menu commitments; a held pose must still be released safely.
	for command in pointer.drain():
		if command.kind=="release" and director: director.release_drag()
	FoxWindowBridge.set_drag_tracking(false)
	_abort_follow()
	if finished_follow:rest_routine.request_front()

func _quit(exit_code: int = 0) -> void:
	if not instance_acquired:get_tree().quit(exit_code);return
	if chat_view:
		chat_view.controller.stop("Application closed")
		if not chat_view.controller.flush_history():push_warning("Chat history could not flush; see History storage status")
		chat_view.hide_all()
	if local_audio:local_audio.silence()
	_cancel_pointer()
	if context_popup: context_popup.hide()
	discard_preferences()
	# Commit saved values, never the unsaved preference preview. Future versions
	# refuse overwrite in the atomic store and surface an error.
	for store in [preferences,input_settings,cursor_follow,home_behavior,local_audio.settings]:
		var error:int=store.save_local()
		if error!=OK:push_warning("A saved settings store could not flush: "+error_string(error))
	_save_home()
	FoxWindowBridge.release_instance();instance_acquired=false
	super._quit(exit_code)

func _follow_camera() -> void:
	if not camera or not director: return
	var target := Vector3(director.stage.position.x,0.32,director.stage.position.z)
	if director.attention_camera_active:
		# Hover turns follow the local stage so mixed arcs cannot walk the
		# render across the fixed desktop window. Authored paw/hip steps remain.
		target=Vector3(director.stage.position.x,0.32,director.stage.position.z)
	camera.position = target+Vector3(1.4,0.6,2.2)
	camera.look_at(target)

func _apply_envelope() -> void:
	if not director or not camera: return
	var projected := PackedVector2Array()
	var size := Vector2(pet.size)
	var ratio := size / pet.get_visible_rect().size
	for point in director.surface.points():
		var pixel := camera.unproject_position(point)*ratio
		projected.append(pixel.clamp(Vector2.ZERO,size))
	var hull := Geometry2D.convex_hull(projected)
	var expanded := Geometry2D.offset_polygon(hull,6.0)
	if not expanded.is_empty():
		var polygon: PackedVector2Array = expanded[0]
		for index in polygon.size(): polygon[index]=polygon[index].clamp(Vector2.ZERO,size)
		pet.mouse_passthrough_polygon = polygon

func _save_activity() -> void:
	if home_behavior.save_local()!=OK:push_error("Could not save home activity on G:.")

func _user_posture(destination: String) -> void:
	if chat_view:chat_view.cancel_approach("explicit posture")
	home_motion.stop(self,"user posture")
	rest_routine.cancel(self,"user posture")
	home_behavior.interact();home_behavior.set_sleep(destination=="sleeping")
	sleeping=destination=="sleeping"
	director.request_posture(destination)
	_sync_audio_lifecycle()
	if destination!="sleeping":local_audio.request("ui")

func _sync_audio_lifecycle() -> void:
	if not local_audio or not director:return
	var quiet_sleep:bool=sleeping or home_behavior.manual_sleep or home_behavior.auto_sleep or director.body in ["sleep_enter","sleep_loop"] or director.pending=="sleeping"
	local_audio.set_lifecycle(pet_hidden_by_user or panel_minimized or director.hidden,director.full_screen,quiet_sleep)

func _hide_pet() -> void:
	super._hide_pet()
	if chat_view:chat_view.hide_all()
	_sync_audio_lifecycle()

func request_result_feedback() -> bool:
	# One completed-result event for future chat/task callers, never a stream token.
	var accepted:bool=director.request_overlay("task_success","assistant")
	_sync_audio_lifecycle()
	if accepted:local_audio.request("result")
	return accepted

func _home_state() -> Dictionary:
	var navigation_pending:bool=director.follow_owned and (rest_routine.active() or home_motion.active) and director.pending in director.GAITS
	var protected:bool=director.body in ["pickup","release","double_click_jump_sit"] or director.body.begins_with("drag_") or (director.pending_priority>30 and not navigation_pending) or director.attention_turn_playback
	for overlay in director.overlays.values():
		if int(overlay.get("priority",0))>30:protected=true
	var interacting:bool=panel.visible or context_popup.visible or pointer.pressed or not pointer.pending.is_empty() or cursor_follow.busy() or (chat_view!=null and chat_view.interacting())
	return {"paused":director.paused(),"blocked":interacting or protected,"interacting":interacting,"proximity":cursor_enabled and cursor_nearby,"stay":bool(input_settings.values.stay_here),"moving":home_motion.active or rest_routine.active(),"stable":director.body in director.POSTURES and director.pending.is_empty() and director.blend_age>=director.blend_duration,"posture":director.posture(),"sleeping":director.body=="sleep_loop","rest_managed":true}

func _cursor_proximity_interact() -> void:
	home_behavior.interact()
	var wake:bool=rest_routine.policy.phase!="awake" or sleeping or home_behavior.manual_sleep or home_behavior.auto_sleep or director.body in ["idle_lie","sleep_loop","lie_down","sleep_enter"] or director.pending in ["lying","sleeping"]
	if not wake:return
	rest_routine.cancel(self,"cursor proximity");home_motion.stop(self,"cursor proximity")
	home_behavior.set_sleep(false);sleeping=false
	director.request_posture("standing","user")

func _tick_home(delta: float) -> void:
	if home_save_count!=observed_home_saves:
		observed_home_saves=home_save_count;home_behavior.set_home(Vector2(pet.position))
	var state:=_home_state()
	if state.paused or state.blocked or state.stay or home_behavior.manual_sleep or home_behavior.auto_sleep or home_behavior.settings.activity=="Off":home_motion.stop(self,"policy pause")
	if state.proximity:_cursor_proximity_interact();state=_home_state()
	var command:=home_behavior.tick(delta,state)
	rest_routine.tick(self,delta,state)
	if rest_routine.active():home_motion.stop(self,"rest motion owns movement")
	# After an explicit edge retreat, ordinary roaming cannot snap back into a
	# distant old home disc. A later user follow/Stay Here establishes the home.
	var outside_home:bool=((Vector2(pet.position)-home_behavior.home)/_drag_scale()).length()>float(home_behavior.settings.radius)+1
	if command.get("kind")=="move" and (outside_home or rest_routine.active() or rest_routine.policy.phase!="awake"):return
	if command.get("kind")=="posture" and (rest_routine.active() or rest_routine.policy.phase!="awake"):return
	if command.is_empty():return
	var accepted:=false
	if command.kind=="overlay":
		accepted=director.request_overlay(command.id,"autonomy")
		if accepted:
			var layer:String=director.catalog.rows[command.id].get("layer","")
			if director.overlays.has(layer):director.overlays[layer]["one_shot"]=true
	elif command.kind=="posture":
		accepted=director.request_posture(command.id,"autonomy")
		if accepted and command.id=="sleeping":sleeping=true
	elif command.kind=="move":
		var area:=Rect2(DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen(pet.get_window_id())))
		accepted=home_motion.start(self,home_behavior.destination(Vector2(pet.position),_drag_scale(),area,Vector2(pet.size)))
	if accepted:
		home_behavior.commit(command.id)
		behavior_events.append({"seconds":snappedf(home_behavior.clock,.1),"action":command.id})
		if behavior_events.size()>32:behavior_events.pop_front()
	else:home_behavior.next_action=home_behavior.clock+5

func _update_summary() -> void:
	if summary and director:
		summary.text = "%s · %s · Click-through %s\nUse the tray to show, hide or wake your pet." % [preference_preview.pet_name,director.posture().capitalize(),"ON" if full_passthrough else "OFF"]

func _event(kind: String, details: Dictionary = {}) -> void:
	details["event"] = kind
	details["elapsed_seconds"] = snappedf(elapsed,0.01)
	details["native_pet_state"] = FoxWindowBridge.get_window_state()
	events.append(details)
	if events.size()>500: events.pop_front()
	var file := FileAccess.open(Paths.directory("logs").path_join("desktop_events.json"),FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(events,"\t"))

func _test_tick(seconds: float) -> void:
	for frame in roundi(seconds*30): director.step(1.0/30.0)
	_follow_camera()
	_apply_envelope()

func _desktop_acceptance() -> void:
	var checks: Array[Dictionary] = []
	await get_tree().create_timer(0.2).timeout
	var startup := FoxWindowBridge.get_window_state()
	checks.append({"case":"actual_fox_startup_no_focus","passed":director.catalog.rows.size()==39 and director.mixer.skeleton.get_bone_count()==40 and (startup&4)!=0 and (startup&32)==0,"native_state":startup})
	for enabled in [false,true]:
		taskbar_visible=enabled; _apply_taskbar()
		var state := FoxWindowBridge.get_window_state()
		checks.append({"case":"taskbar_"+str(enabled),"passed":((state&1)!=0)==enabled and ((state&2)!=0)!=enabled and (state&4)!=0})
	for enabled in [false,true]:
		pet.always_on_top=enabled; _apply_taskbar()
		checks.append({"case":"topmost_"+str(enabled),"passed":((FoxWindowBridge.get_window_state()&16)!=0)==enabled and (FoxWindowBridge.get_window_state()&1)!=0})
	for enabled in [true,false]:
		_set_pass_through(enabled)
		checks.append({"case":"passthrough_"+str(enabled),"passed":((FoxWindowBridge.get_window_state()&384)==384)==enabled})
	director.request_grounded_gait("walk");_test_tick(0.5)
	_hide_pet(); await get_tree().process_frame; await get_tree().process_frame
	var phase:float=director.body_time; var placement:Transform3D=director.stage.transform
	_test_tick(0.5)
	checks.append({"case":"hide_pauses_actual_actor","passed":director.paused() and director.body_time==phase and director.stage.transform==placement and (FoxWindowBridge.get_window_state()&8)==0})
	_show_pet(); await get_tree().process_frame; await get_tree().process_frame
	_test_tick(0.2)
	checks.append({"case":"show_resumes_actual_actor","passed":not director.paused() and director.body_time!=phase and (FoxWindowBridge.get_window_state()&32)==0})
	director.set_lifecycle(false,true);_hide_pet()
	await get_tree().process_frame;await get_tree().process_frame
	_show_pet();await get_tree().process_frame;await get_tree().process_frame
	checks.append({"case":"fullscreen_policy_survives_visibility_recovery","passed":director.full_screen and director.paused()})
	director.set_lifecycle(false,false)
	open_panel();draft.text="T08 retained test draft"
	panel.mode=Window.MODE_MINIMIZED
	await get_tree().create_timer(0.15).timeout
	checks.append({"case":"minimize_hides_and_pauses_actor","passed":director.paused() and (FoxWindowBridge.get_window_state()&8)==0})
	open_panel();await get_tree().create_timer(0.15).timeout
	checks.append({"case":"restore_recovers_actor_and_draft","passed":not director.paused() and draft.text=="T08 retained test draft" and (FoxWindowBridge.get_window_state()&8)!=0})
	panel.hide()
	_menu_action("sleep");_test_tick(5.0)
	checks.append({"case":"tray_sleep_drives_actual_animation","passed":director.body=="sleep_loop"})
	_menu_action("sleep");_test_tick(5.0)
	checks.append({"case":"tray_wake_drives_actual_animation","passed":director.body=="idle_stand"})
	director.begin_drag();_test_tick(0.5);_hide_pet()
	await get_tree().process_frame;await get_tree().process_frame
	director.release_drag();_show_pet()
	await get_tree().process_frame;await get_tree().process_frame
	_test_tick(0.8)
	checks.append({"case":"hidden_release_is_recovered_on_show","passed":director.body=="idle_stand" and director.pending.is_empty() and not director.release_pending})
	var visible_checks: Array[Dictionary] = []
	for factor in [1.0,1.25,1.5,2.0]:
		scale_override=factor;_place_pet(true);_apply_envelope()
		await get_tree().process_frame;await RenderingServer.frame_post_draw
		var picture := pet.get_texture().get_image()
		var outside := 0;var visible := 0;var bounds:=Rect2i()
		for y in picture.get_height():
			for x in picture.get_width():
				if picture.get_pixel(x,y).a > 0.02:
					visible+=1
					var pixel := Vector2(x,y)*Vector2(pet.size)/Vector2(picture.get_size())
					if not Geometry2D.is_point_in_polygon(pixel,pet.mouse_passthrough_polygon): outside+=1
		picture.save_png(OUT+"desktop_%d.png"%int(factor*100))
		visible_checks.append({"simulated_scale":factor,"image_size":[picture.get_width(),picture.get_height()],"visible_pixels":visible,"visible_pixels_outside_envelope":outside,"passed":visible>1000 and outside==0})
	checks.append({"case":"transparent_actor_inside_input_envelope_at_simulated_sizes","passed":visible_checks.all(func(row):return row.passed),"renders":visible_checks})
	scale_override=1.0;_place_pet(true)
	var framing: Array[Dictionary] = []
	for id in director.catalog.rows:
		if not director.catalog.is_body(id): continue
		var duration:float=director.catalog.animations[id].length
		for fraction in [0.0,0.33,0.66,0.99]:
			director._start(id,0.0,0.0)
			director.ground_contacts.clear();director.previous_surface_points.clear()
			director.body_time=duration*fraction;director.blend_age=1.0;director._render()
			_follow_camera();_apply_envelope()
			var margin := INF
			var size := pet.get_visible_rect().size
			for point in director.surface.points():
				var pixel:=camera.unproject_position(point)
				margin=minf(margin,minf(minf(pixel.x,pixel.y),minf(size.x-pixel.x,size.y-pixel.y)))
			framing.append({"id":id,"phase_fraction":fraction,"nearest_edge_logical_pixels":margin,"passed":margin>=3.0})
	checks.append({"case":"all_enabled_body_clips_fit_transparent_window","passed":framing.all(func(row):return row.passed),"poses":framing})
	director._start("idle_stand",0.0,0.0);director.body_time=0.0;director._render();_follow_camera();_apply_envelope()
	open_panel();await get_tree().process_frame;await RenderingServer.frame_post_draw
	panel.get_texture().get_image().save_png(OUT+"desktop_controls.png")
	var passed:=checks.all(func(row):return row.passed)
	var file=FileAccess.open(OUT+"desktop_checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"checks":checks,"tray_created":tray_id>=0,"limits":["In-process Windows actions; no physical mouse/taskbar/tray gestures or actual Windows DPI changes","T09 pointer classifier and T10 screen drag placement are not implemented","Camera follows world movement inside a fixed window; autonomous desktop movement is T11","No hardware FPS or iGPU benchmark"]},"\t"));file.close()
	print("T08_DESKTOP_CHECKS ",checks.size()," PASS ",passed)
	_quit(0 if passed else 1)

func _configure_context_glass()->void:
	if context_popup and context_popup.visible:FoxGlassBridge.configure((context_popup.get_window_id()<<8)|roundi(preference_preview.get("glass_blur",.75)*100))
