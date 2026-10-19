extends Node
## Calibrated grounded movement and masked posture/event director;
## no cursor classification, screen drag placement, autonomy or Ollama here.
const Catalog = preload("FoxAnimationCatalog.gd")
const Mixer = preload("FoxPoseMixer.gd")
const Surface = preload("FoxSkinSurface.gd")
const Contacts = preload("FoxGroundContacts.gd")
const GazeGeometry = preload("res://scripts/interaction/FoxGazeGeometry.gd")
const COMPLETE := {"sit_down":"idle_sit", "stand_up":"idle_stand", "lie_down":"idle_lie", "get_up":"idle_stand", "sleep_enter":"sleep_loop", "wake_up":"idle_lie", "double_click_jump_sit":"idle_sit", "release":"idle_stand"}
const POSTURES := {"idle_stand":"standing", "idle_sit":"sitting", "idle_lie":"lying", "sleep_loop":"sleeping"}
const GAITS := ["walk", "run", "turn_left", "turn_right"]
const PRIORITY := {"autonomy":30, "assistant":40, "user":50}
const ATTENTION_REQUEST_RADIUS := 0.55
const ATTENTION_ARENA_RADIUS := 0.65 # 10cm reserve for grounded posture recovery.
const ATTENTION_YAW := 90.0
const ATTENTION_PHASE_FRACTION := 1.0
var catalog := Catalog.new()
var mixer := Mixer.new()
var stage: Node3D
var body := "idle_stand"
var body_time := 0.0
var pending := ""
var pending_priority := 0
var drag_direction := "horizontal"
var drag_controlled := false
var drag_velocity := Vector2.ZERO
var drag_weights := Vector3.ZERO # horizontal run, upward reach, downward descent
var follow_owned := false
var follow_error_degrees := 0.0
var reversal_degrees := 177.0
var steering_degrees_s := 120.0
var follow_rest_forward := Vector3.BACK
var follow_turn_active := false
var follow_turn_scale := 1.0
var follow_yaw_velocity := 0.0
var overlays: Dictionary = {}
var hidden := false
var full_screen := false
var release_pending := false
var manual := false
var blend_age := 1.0
var blend_duration := 0.15
var blend_source: Dictionary = {}
var floor_source := 0.0
var floor_value := 0.0
var trace: Array[Dictionary] = []
var travel_anchor := Transform3D.IDENTITY
var cycles_completed := 0
var surface := Surface.new()
var previous_surface_points := PackedVector3Array()
var contact_correction_clamped := 0
var maximum_contact_correction := 0.0
var maximum_contact_yaw := 0.0
var ground_contacts := Contacts.new()
var render_delta := 0.0
var cursor_gaze := Vector2.ZERO
var cursor_right := Vector3.RIGHT
var cursor_up := Vector3.UP
var oriented_cursor := false
var cursor_eye_angles := Vector2.ZERO
var cursor_neck_angles := Vector2.ZERO
var attention_turn := ""
var attention_turn_return := "standing"
var attention_turn_playback := false
var attention_home := Vector3.ZERO
var attention_camera_active := false
var attention_decline_reason := ""
var attention_origin_offset := Vector3.ZERO
var attention_rebases := 0
var attention_needs_rebase := false

func initialize(actor: Node3D, placement: Node3D) -> bool:
	stage = placement
	if not catalog.initialize() or not mixer.initialize(actor, catalog): return false
	if not surface.initialize(actor,mixer.skeleton): return false
	# Navigation must not inherit the authored head look-ahead in turn clips.
	var reference:Vector3=mixer.cursor_frame(mixer.rest,stage).forward
	follow_rest_forward=stage.global_basis.inverse()*reference
	follow_rest_forward.y=0;follow_rest_forward=follow_rest_forward.normalized()
	travel_anchor = _planar(stage.transform)
	attention_home = travel_anchor.origin
	set_process(not manual)
	_render()
	return true

func _process(delta: float) -> void:
	step(delta)

func _record(kind: String, detail: String = "") -> void:
	trace.append({"event":kind, "detail":detail, "body":body, "time":body_time})
	if trace.size() > 128: trace.pop_front()

func posture() -> String:
	if body in GAITS: return "walking" if body == "walk" else ("running" if body == "run" else "turning")
	return POSTURES.get(body, "drag" if body.begins_with("drag_") else "transition")

func paused() -> bool:
	return hidden or full_screen

func set_lifecycle(is_hidden: bool, is_full_screen: bool) -> void:
	if is_hidden or is_full_screen: cancel_attention_turn()
	hidden = is_hidden
	full_screen = is_full_screen
	if not paused() and release_pending:
		release_pending = false
		release_drag()
	_record("lifecycle", "paused" if paused() else "resumed")

func request_posture(destination: String, source: String = "user") -> bool:
	if destination not in ["standing", "sitting", "lying", "sleeping"] or not PRIORITY.has(source) or source == "assistant" or paused() or body == "pickup" or body.begins_with("drag_"): return false
	if source=="user": cancel_attention_turn()
	if PRIORITY[source] < pending_priority: return false
	pending = destination
	pending_priority = PRIORITY[source]
	_route()
	return true

func request_jump_sit() -> bool:
	if paused() or body in ["release", "double_click_jump_sit", "pickup"] or body.begins_with("drag_"): return false
	cancel_attention_turn()
	pending = "jump_sit"
	pending_priority = 50
	_route()
	return true

func begin_drag() -> bool:
	if paused() or body in ["release", "double_click_jump_sit"]: return false
	cancel_attention_turn()
	if body == "pickup" or body.begins_with("drag_"): return true
	drag_controlled=false; drag_velocity=Vector2.ZERO; drag_weights=Vector3.ZERO
	if body in GAITS or body == "walk_to_run":
		# Explicit pickup interrupts movement without resetting its placement.
		pending = ""
		pending_priority = 0
		_start("pickup")
		return true
	pending = "drag"
	pending_priority = 90
	_route()
	return true

func set_drag_direction(direction: String) -> bool:
	if paused() or direction not in ["horizontal", "up", "down"] or (body != "pickup" and not body.begins_with("drag_")): return false
	drag_direction = direction
	if body.begins_with("drag_"): _start("drag_" + direction)
	return true

func set_drag_velocity(velocity: Vector2) -> void:
	if not is_finite(velocity.x) or not is_finite(velocity.y): velocity=Vector2.ZERO
	drag_controlled=true
	drag_velocity=velocity.limit_length(1600.0)

func _drag_pose() -> Dictionary:
	var calm_time: float=catalog.animations.pickup.length-0.00001
	var pose: Dictionary=mixer.body_pose("pickup",calm_time)
	var total := 0.0
	for entry in [["drag_horizontal",drag_weights.x],["drag_up",drag_weights.y],["drag_down",drag_weights.z]]:
		var weight: float=entry[1]
		if weight<=0.00001: continue
		# Accumulate a normalized convex blend; the remainder is calm pickup.
		var prior := maxf(0.0,1.0-drag_weights.x-drag_weights.y-drag_weights.z)+total
		pose=mixer.blend_pose(pose,mixer.body_pose(entry[0],body_time),weight/maxf(0.00001,prior+weight))
		total+=weight
	return pose

func _drag_floor() -> float:
	var calm := catalog.floor_offset("pickup",catalog.animations.pickup.length-0.00001)
	return calm*(1.0-drag_weights.x-drag_weights.y-drag_weights.z)+catalog.floor_offset("drag_horizontal",body_time)*drag_weights.x+catalog.floor_offset("drag_up",body_time)*drag_weights.y+catalog.floor_offset("drag_down",body_time)*drag_weights.z

func release_drag() -> bool:
	if pending == "drag" and body != "pickup" and not body.begins_with("drag_"):
		pending = ""
		pending_priority = 0
		_record("pickup_cancelled_before_hold")
		return true
	if body != "pickup" and not body.begins_with("drag_"): return false
	if paused():
		release_pending = true
		return true
	pending = ""
	pending_priority = 0
	_start("release")
	return true

func follow_drive(direction: Vector3, gait: String, delta: float) -> bool:
	if paused() or gait not in ["walk","run"] or direction.length()<.00001 or body in ["pickup","release","double_click_jump_sit"] or body.begins_with("drag_"):return false
	follow_owned=true;drag_controlled=false;cancel_attention_turn();attention_camera_active=false
	var forward:=follow_forward()
	forward.y=0;forward=forward.normalized();direction.y=0;direction=direction.normalized()
	var yaw:=atan2(forward.cross(direction).y,forward.dot(direction))
	follow_error_degrees=rad_to_deg(yaw)
	# A full paw-step phase is committed. A changing target is reconsidered at
	# the seam, never by restarting the look-ahead pose every rendered frame.
	if follow_turn_active:return true
	var turning:=absf(follow_error_degrees)>=reversal_degrees
	if body in ["turn_left","turn_right"]:turning=absf(follow_error_degrees)>=reversal_degrees
	if turning:
		var chosen:String="turn_left" if yaw>0 else "turn_right"
		follow_turn_scale=clampf(absf(follow_error_degrees)/90.0,.25,1.0)
		follow_turn_active=true;follow_yaw_velocity=0
		pending="";pending_priority=0
		_start(chosen,0,.25)
	elif body in ["turn_left","turn_right"]:
		pending="";pending_priority=0;_start(gait,0,.25)
	else:request_grounded_gait(gait,"user")
	if not turning and body in ["walk","run"] and blend_age>=blend_duration:
		# Small curves recruit smooth torso steering during visible strides.
		var requested:=clampf(yaw/0.35,-deg_to_rad(steering_degrees_s),deg_to_rad(steering_degrees_s))
		if absf(follow_error_degrees)<1.5:requested=0
		follow_yaw_velocity=move_toward(follow_yaw_velocity,requested,deg_to_rad(360.0)*delta)
		var angle:=follow_yaw_velocity*delta
		var pivot:=Vector3(stage.position.x,0,stage.position.z)
		var rotation:=Basis(Vector3.UP,angle)
		var adjustment:=Transform3D(rotation,pivot-rotation*pivot)
		stage.transform=adjustment*stage.transform;travel_anchor=adjustment*travel_anchor
	return true

func follow_forward() -> Vector3:
	var forward:=stage.global_basis*follow_rest_forward
	forward.y=0
	return forward.normalized()

func _body_travel(id: String, seconds: float) -> Transform3D:
	var result:Transform3D=catalog.travel(id,seconds)
	if follow_owned and id in ["turn_left","turn_right"]:
		# Scale the calibrated external arc, retaining the complete authored paw
		# cycle. A reversal takes two visible quarter turns rather than a spin.
		var yaw:=result.basis.get_euler().y*follow_turn_scale
		result.basis=Basis(Vector3.UP,yaw)
		result.origin*=follow_turn_scale
	return result

func follow_stop() -> void:
	if not follow_owned:return
	follow_owned=false;follow_turn_active=false;follow_yaw_velocity=0;pending="";pending_priority=0
	if body in GAITS or body=="walk_to_run":
		# A local grounded 250ms stance recovery, never an airborne release clip.
		_start("idle_stand",0,.25)
	elif POSTURES.has(body):request_posture("standing")

func request_overlay(id: String, source: String = "assistant") -> bool:
	if paused() or not PRIORITY.has(source) or not catalog.rows.has(id) or catalog.is_body(id): return false
	var row: Dictionary = catalog.rows[id]
	var allowed: bool = posture() in row.allowed_states or (body in GAITS and "standing" in row.allowed_states)
	if not allowed: return false
	var layer: String = row.layer
	if overlays.has(layer):
		if overlays[layer].priority > PRIORITY[source]: return false
		if catalog.rows[overlays[layer].id].action == row.action:
			overlays[layer].priority = maxi(overlays[layer].priority, PRIORITY[source])
			return true
	overlays[layer] = {"id":id, "time":0.0, "priority":PRIORITY[source]}
	_record("overlay", id)
	return true

func clear_overlay(layer: String) -> void:
	overlays.erase(layer)

func set_cursor_gaze(direction: Vector2, screen_right: Vector3, screen_up: Vector3) -> void:
	oriented_cursor=false
	if not is_finite(direction.x) or not is_finite(direction.y): direction=Vector2.ZERO
	cursor_gaze=direction.limit_length(1.0)
	cursor_right=screen_right.normalized()
	cursor_up=screen_up.normalized()

func set_oriented_gaze(eye_angles: Vector2, neck_angles: Vector2) -> void:
	oriented_cursor=true
	cursor_eye_angles=GazeGeometry.ellipse_limit(eye_angles,Vector2(6,4)) if is_finite(eye_angles.x) and is_finite(eye_angles.y) else Vector2.ZERO
	cursor_neck_angles=GazeGeometry.ellipse_limit(neck_angles,Vector2(18,8)) if is_finite(neck_angles.x) and is_finite(neck_angles.y) else Vector2.ZERO

func cursor_reference_frame() -> Dictionary:
	var pose: Dictionary=mixer.body_pose(body,body_time)
	var commands: Dictionary={}
	for layer in overlays:
		var command: Dictionary=overlays[layer]
		var row: Dictionary=catalog.rows[command.id]
		var duration: float=catalog.animations[command.id].length
		var weight := minf(1.0,command.time/0.15)
		if not row.loop and not row.get("pose_hold",false) or command.get("one_shot",false): weight=minf(weight,maxf(0.0,(duration-command.time)/0.15))
		commands[layer]={"id":command.id,"time":command.time,"weight":weight}
	return mixer.cursor_frame(mixer.compose(pose,commands),stage)

func view_center() -> Vector3:
	var skeleton: Skeleton3D=mixer.skeleton
	var pelvis := skeleton.get_bone_global_pose(skeleton.find_bone("Fox_Pelvis_01")).origin
	var chest := skeleton.get_bone_global_pose(skeleton.find_bone("Fox_Ribcage_010")).origin
	return skeleton.global_transform*((pelvis+chest)*0.5)

func request_attention_turn(yaw: float) -> bool:
	attention_decline_reason=""
	if paused() or posture() not in ["standing","sitting"] or not pending.is_empty() or not attention_turn.is_empty() or not is_finite(yaw) or absf(yaw)<24.0:
		attention_decline_reason="busy or invalid";return false
	# Choose using the approved clip's measured anatomical yaw, rather than
	# its name or the camera's left/right direction. Never spin the actor.
	var selected := ""
	for id in ["turn_left","turn_right"]:
		var curve: Transform3D=catalog.travel(id,catalog.animations[id].length)
		var degrees := rad_to_deg(curve.basis.get_euler().y)
		if signf(degrees)==signf(yaw): selected=id
	if selected.is_empty():
		attention_decline_reason="clip unavailable";return false
	# Only local stepping inside the fixed pet window. Desktop home/movement
	# is still T10; alternating arcs must never accumulate an unlimited walk.
	# Check the complete calibrated path, with recovery room outside its
	# request radius for contact-corrected standing/sitting transitions.
	for frame in 31:
		var end: Transform3D=_planar(stage.transform)*catalog.travel(selected,float(frame)/30)
		var distance := end.origin-attention_home; distance.y=0.0
		if distance.length()>ATTENTION_REQUEST_RADIUS:
			attention_decline_reason="local step boundary";return false
	attention_turn_return=posture()
	attention_turn=selected
	attention_camera_active=true
	attention_needs_rebase=true
	if not request_grounded_gait(selected,"autonomy"):
		attention_turn="";attention_needs_rebase=false;attention_decline_reason="priority refusal";return false
	return true

func _body_duration() -> float:
	# Complete the original stepping cycle and exact calibrated travel.
	# Its phase-zero exit matches stance, avoiding a mid-step recovery splice.
	return catalog.animations[body].length*(ATTENTION_PHASE_FRACTION if attention_turn_playback else 1.0)

func cancel_attention_turn() -> void:
	if attention_turn.is_empty(): return
	if pending_priority==30:
		pending="standing" if body in ["turn_left","turn_right"] else ""
		pending_priority=30 if not pending.is_empty() else 0
	attention_turn=""

func request_grounded_gait(id: String, source: String = "user") -> bool:
	if id not in GAITS or not PRIORITY.has(source) or source == "assistant" or paused(): return false
	if source=="user": cancel_attention_turn()
	if source=="user": attention_camera_active=false
	if source=="user": attention_needs_rebase=false
	if body == "pickup" or body.begins_with("drag_"): return false
	if body in ["release", "double_click_jump_sit"] and source != "user": return false
	if PRIORITY[source] < pending_priority: return false
	if id == body and pending.is_empty(): return true
	pending = id
	pending_priority = PRIORITY[source]
	_route()
	return true

func _route() -> void:
	if pending.is_empty(): return
	if body=="run" and pending=="walk":
		# Arrival cannot wait an entire run cycle or it can skip walking. Match
		# stride phase, blend for250ms and retain the existing planted-paw solver.
		_start("walk",_walk_arrival_phase(),0.25)
		pending="";pending_priority=0
		return
	if body in GAITS:
		# Authored exit contracts are phase zero. Coalesce a single destination.
		if body_time > 0.000001: return
		# Completion of stand-up can route twice in the same tick. Do not take
		# a finite hover turn's phase-zero exit before its first animated step.
		if attention_turn_playback and blend_age<=0.000001: return
		if pending == body:
			pending = ""
			pending_priority = 0
		elif body == "walk" and pending == "run": _start("walk_to_run",0.0,0.0)
		else: _start("idle_stand",0.0,0.25)
		return
	if not POSTURES.has(body) or blend_age < blend_duration: return
	var current := posture()
	var target := "standing" if pending in GAITS or pending in ["drag", "jump_sit"] else pending
	if current == target:
		var action := pending
		pending = ""
		pending_priority = 0
		if action == "drag": _start("pickup")
		elif action == "jump_sit": _start("double_click_jump_sit")
		elif action in GAITS: _start(action,0.0,0.25)
		return
	if current == "sleeping": _start("wake_up")
	elif current == "sitting": _start("stand_up")
	elif current == "lying": _start("sleep_enter" if target == "sleeping" else "get_up")
	elif current == "standing": _start("sit_down" if target == "sitting" else "lie_down")

func _walk_arrival_phase() -> float:
	# Pick the incoming stride nearest the current paw positions. Supported paws
	# matter most; a proportional phase alone mismatches the two source gaits.
	var current:Dictionary=mixer.evaluate_pose(mixer.last_pose,stage)
	var placement:Transform3D=current.skeleton_to_stage
	var best:=0.0;var best_error:=INF
	for sample in 24:
		var seconds:float=float(sample)/24*catalog.animations.walk.length
		var candidate:Dictionary=mixer.evaluate_pose(mixer.body_pose("walk",seconds),stage)
		var error:=0.0
		for name in surface.feet:
			var digit:int=mixer.skeleton.find_bone(name)
			var before:Vector3=(placement*current.bones[digit]).origin
			var after:Vector3=(candidate.skeleton_to_stage*candidate.bones[digit]).origin
			var weight:=4.0 if ground_contacts.locks.has(name) else 1.0
			error+=before.distance_squared_to(after)*weight
		if error<best_error:best_error=error;best=seconds
	return best

func _planar(value: Transform3D) -> Transform3D:
	var result := value
	result.origin.y = 0.0
	result.basis = result.basis.orthonormalized()
	return result

func _start(id: String, seek_seconds: float = 0.0, seconds: float = 0.15) -> void:
	if id == body: return
	blend_source = mixer.last_pose.duplicate()
	floor_source = floor_value
	blend_age = 0.0
	blend_duration = seconds
	# Capture the old mode before selecting the new clip's hover-only curve.
	attention_turn_playback=id==attention_turn and not attention_turn.is_empty()
	travel_anchor = _planar(stage.transform) * _body_travel(id,seek_seconds).affine_inverse()
	body = id
	body_time = seek_seconds
	if attention_turn_playback:
		# Hover completes the source quarter turn with a phase-zero stance exit.
		# A sitting fox stands first, then returns to sitting.
		pending=attention_turn_return; pending_priority=30
	elif id=="idle_stand" and not attention_turn.is_empty() and pending==attention_turn_return:
		attention_turn=""
	overlays.clear()
	_record("body_started", id)

func step(delta: float, sample_once: bool = false) -> void:
	if paused() or not is_finite(delta) or delta <= 0.0: return
	# Coalesce expensive skin/contact sampling only for a settled, event-free
	# posture. Active locomotion and all transitions retain every authored tick.
	var coalesce:bool=sample_once and body in POSTURES and pending.is_empty() and overlays.is_empty() and blend_age>=blend_duration and not follow_owned and not attention_turn_playback
	var remaining := clampf(delta, 0.0, 0.25)
	var sampled_elapsed:=0.0
	while remaining > 0.000001:
		var duration: float = _body_duration()
		var speed := 0.65 if attention_turn_playback else 1.0
		var tick := minf(minf(remaining, 1.0 / 30.0),(duration - body_time)/speed)
		if tick < 0.000001:
			_complete_cycle()
			continue
		body_time += tick*speed
		if drag_controlled and (body=="pickup" or body.begins_with("drag_")):
			var strength := clampf((drag_velocity.length()-25.0)/300.0,0.0,1.0)
			var axes := drag_velocity.abs()
			var vertical := axes.y/maxf(0.00001,axes.x+axes.y)
			var target := Vector3(1.0-vertical,vertical if drag_velocity.y<0 else 0.0,vertical if drag_velocity.y>=0 else 0.0)*strength
			drag_weights=drag_weights.lerp(target,1.0-exp(-tick/0.15))
		render_delta = tick
		sampled_elapsed+=tick
		blend_age += tick
		for layer in overlays.keys():
			var command: Dictionary = overlays[layer]
			command.time += tick
			var row: Dictionary = catalog.rows[command.id]
			if (not row.loop and not row.get("pose_hold", false) or command.get("one_shot",false)) and command.time >= catalog.animations[command.id].length: overlays.erase(layer)
		if not coalesce or remaining-tick<0.000001:
			if coalesce:render_delta=sampled_elapsed
			_render()
		remaining -= tick
		if body_time >= duration - 0.000001:
			var turn_seam:bool=follow_owned and body in ["turn_left","turn_right"]
			_complete_cycle()
			if turn_seam:break # Reconsider the latest delayed target before the next paw cycle.
		_route()
	_rebase_hover_rest()

func _rebase_hover_rest() -> void:
	if not attention_camera_active or not attention_needs_rebase or not attention_turn.is_empty() or not pending.is_empty() or body not in ["idle_stand","idle_sit"] or blend_age<blend_duration:return
	var shift := Vector3(stage.position.x,0.0,stage.position.z)
	attention_needs_rebase=false
	if shift.length()<0.000001:return
	stage.position-=shift;travel_anchor.origin-=shift
	attention_home-=shift;attention_origin_offset+=shift
	# The new local hover home is the rested root. This is simulation origin
	# rebasing, not a desktop saved-home change or a visible actor teleport.
	attention_home=Vector3.ZERO
	for i in previous_surface_points.size():previous_surface_points[i]-=shift
	for i in ground_contacts.previous_bones.size():ground_contacts.previous_bones[i].origin-=shift
	for foot in ground_contacts.locks:
		ground_contacts.locks[foot].ankle.origin-=shift
		ground_contacts.locks[foot].digit.origin-=shift
	attention_rebases+=1

func _complete_cycle() -> void:
	if catalog.rows[body].loop:
		travel_anchor = travel_anchor * _body_travel(body,_body_duration())
		travel_anchor.basis = travel_anchor.basis.orthonormalized()
		body_time = 0.0
		cycles_completed += 1
		if follow_owned and body in ["turn_left","turn_right"]:follow_turn_active=false
	elif body == "walk_to_run":
		_start("run",float(catalog.rows.walk_to_run.to_resume_frame)/30.0,0.0)
		if pending == "run":
			pending = ""
			pending_priority = 0
	else:
		_start("drag_" + drag_direction if body == "pickup" else COMPLETE.get(body, "idle_stand"),0.0,0.15 if body=="pickup" and drag_controlled else 0.0)
	_route()

func _render() -> void:
	var base: Dictionary = mixer.body_pose(body, body_time)
	if drag_controlled and body.begins_with("drag_"): base=_drag_pose()
	var layers: Dictionary = {}
	for layer in overlays:
		var command: Dictionary = overlays[layer]
		var row: Dictionary = catalog.rows[command.id]
		var duration: float = catalog.animations[command.id].length
		var weight := minf(1.0, command.time / 0.15)
		if not row.loop and not row.get("pose_hold", false) or command.get("one_shot",false): weight = minf(weight, maxf(0.0, (duration - command.time) / 0.15))
		layers[layer] = {"id":command.id, "time":command.time, "weight":weight}
	var pose: Dictionary = mixer.compose(base, layers)
	# Cursor attention yields to authored cues and protected body events.
	if posture() in ["standing","sitting"] or body in GAITS:
		if oriented_cursor: pose=mixer.compose_oriented_cursor(pose,cursor_eye_angles,cursor_neck_angles,stage,not layers.has("gaze"),not layers.has("head"))
		else: pose=mixer.compose_cursor(pose,cursor_gaze,stage,cursor_right,cursor_up,not layers.has("gaze"),not layers.has("head"))
	var amount := smoothstep(0.0, blend_duration, blend_age) if blend_duration > 0.0 else 1.0
	if not blend_source.is_empty() and amount < 1.0: pose = mixer.blend_pose(blend_source, pose, amount)
	var destination_floor := _drag_floor() if drag_controlled and body.begins_with("drag_") else catalog.floor_offset(body,body_time)
	floor_value = lerpf(floor_source,destination_floor,amount)
	stage.transform = travel_anchor * _body_travel(body,body_time)
	stage.position.y = floor_value
	pose = _stabilize_contacts(pose)
	mixer.write_pose(pose)

func _stabilize_contacts(pose: Dictionary) -> Dictionary:
	if body == "pickup" or body.begins_with("drag_"):
		previous_surface_points.clear()
		ground_contacts.clear()
		return pose
	var evaluated: Dictionary = mixer.evaluate_pose(pose,stage)
	var points := surface.proposed_points(evaluated,stage.transform)
	var minimum := INF
	for point in points: minimum = minf(minimum,point.y)
	# Never flatten a jump: only raise geometry when it would cross the plane.
	var guard := maxf(0.0,0.0005-minimum)
	stage.position.y += guard
	floor_value = stage.position.y
	if guard > 0.0:
		for vertex in points.size(): points[vertex].y += guard
	var stabilize: bool = blend_age < blend_duration or (body not in GAITS and body != "walk_to_run")
	if stabilize and not follow_owned and not previous_surface_points.is_empty():
		var pairs: Array = []
		var current_center := Vector3.ZERO
		var previous_center := Vector3.ZERO
		for foot in surface.feet:
			var shared: Array[int] = []
			for vertex in surface.feet[foot]:
				if points[vertex].y <= 0.002 and previous_surface_points[vertex].y <= 0.002:
					shared.append(vertex)
			if not shared.is_empty():
				pairs.append(shared)
				for vertex in shared:
					current_center += points[vertex]/float(shared.size())
					previous_center += previous_surface_points[vertex]/float(shared.size())
		if not pairs.is_empty():
			current_center /= float(pairs.size())
			previous_center /= float(pairs.size())
			var dot_sum := 0.0
			var cross_sum := 0.0
			for shared in pairs:
				for vertex in shared:
					var a: Vector3 = points[vertex]-current_center
					var b: Vector3 = previous_surface_points[vertex]-previous_center
					dot_sum += (a.x*b.x+a.z*b.z)/float(shared.size())
					cross_sum += (a.z*b.x-a.x*b.z)/float(shared.size())
			# Rigid plane fit: one vote per paw, no scaling or bone changes.
			var yaw := clampf(atan2(cross_sum,dot_sum),-deg_to_rad(2.0),deg_to_rad(2.0))
			maximum_contact_yaw = maxf(maximum_contact_yaw,absf(yaw))
			var rotation := Basis(Vector3.UP,yaw)
			# Bound displacement at the contact centroid, independent of distance
			# from the world origin. Rotation is around that centroid.
			var correction := previous_center-current_center
			correction.y = 0.0
			if correction.length() > 0.04:
				contact_correction_clamped += 1
				correction = correction.limit_length(0.04)
			maximum_contact_correction = maxf(maximum_contact_correction,correction.length())
			var adjustment := Transform3D(rotation,current_center+correction-rotation*current_center)
			stage.transform = adjustment*stage.transform
			travel_anchor = adjustment*travel_anchor
			for vertex in points.size(): points[vertex] = adjustment*points[vertex]
	pose = ground_contacts.solve(pose,mixer,surface,stage,points,stabilize or follow_owned,render_delta)
	evaluated = mixer.evaluate_pose(pose,stage)
	points = surface.proposed_points(evaluated,stage.transform)
	minimum = INF
	for point in points: minimum = minf(minimum,point.y)
	guard = maxf(0.0,0.0005-minimum)
	stage.position.y += guard
	floor_value = stage.position.y
	for vertex in points.size(): points[vertex].y += guard
	previous_surface_points = points
	ground_contacts.remember(evaluated,stage.transform,surface,points)
	return pose

func snapshot() -> Dictionary:
	return {"body":body, "body_time":body_time, "posture":posture(), "pending":pending, "paused":paused(), "overlay_count":overlays.size(), "overlays":overlays.duplicate(true), "trace_count":trace.size(), "world_travel":Vector2(stage.position.x, stage.position.z).length(), "cycles_completed":cycles_completed, "placement":stage.transform, "contact_correction_clamped":contact_correction_clamped, "maximum_contact_correction":maximum_contact_correction, "maximum_contact_yaw_radians":maximum_contact_yaw}
