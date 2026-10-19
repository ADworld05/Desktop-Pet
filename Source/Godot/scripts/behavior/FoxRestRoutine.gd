extends RefCounted
## One movement owner after following. Reuses authored paw turns and grounded gaits.
const Plan=preload("FoxRestPlan.gd")
const Policy=preload("FoxRestPolicy.gd")
var policy:=Policy.new()
var mode:="idle"
var want_front:=false
var follow_seen:=false
var front_done:=false
var arrived:=false
var motion_failed:=false
var target:=Vector2.ZERO
var origin:=Vector2.ZERO
var velocity:=Vector2.ZERO
var tempo:=1.0
var age:=0.0
var resume_after:=0.0
var braking:=false
var gait:="walk"
var run_finished:=false
var plan:Dictionary={}
var events:Array[Dictionary]=[]
var bounds_age:=0
var local_bounds:=Rect2()
var edge_location:=false
var arrival_target:=Vector2.ZERO
func active() -> bool:return mode!="idle"
func _yield_motion(app:Node) -> void:
	var d:Node=app.director
	var pending:String=d.pending;var priority:int=d.pending_priority
	var overlays:Dictionary=d.overlays.duplicate(true)
	d.follow_stop()
	if priority>30 and not pending.is_empty() and pending not in d.GAITS:
		d.pending=pending;d.pending_priority=priority;d._route()
	for layer in overlays:
		if int(overlays[layer].priority)>30:d.overlays[layer]=overlays[layer]
func cancel(app:Node,reason:String="user/lifecycle") -> void:
	if active():_yield_motion(app)
	mode="idle";want_front=false;follow_seen=false;velocity=Vector2.ZERO;braking=false;front_done=false;arrived=false;motion_failed=false;resume_after=0;policy.reset()
	_record("cancel",{"reason":reason})
func _record(kind:String,details:Dictionary={}) -> void:
	details=details.duplicate();details.kind=kind;events.append(details)
	if events.size()>64:events.pop_front()
func area(app:Node) -> Rect2:
	return Rect2(DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen(app.pet.get_window_id())))
func desired_front(app:Node) -> Vector3:
	var center:=Vector2(app.pet.position)+Vector2(app.pet.size)*.5
	var screen:=area(app);var offset:Vector2=screen.get_center()-center
	var front:=Vector3(1.4,0,2.2).normalized()
	# Angle toward usable-area center, still front dominant at every corner.
	var angle:=deg_to_rad(float(app.cursor_follow.settings.rest_angle_deg))
	var side:float=1.0 if offset.x>=0 else -1.0
	front=Basis(Vector3.UP,angle*side)*front
	return front
func facing_error(app:Node,direction:Vector3) -> float:
	var forward:Vector3=app.director.follow_forward()
	return atan2(forward.cross(direction).y,forward.dot(direction))
func _project_bounds(app:Node,points:PackedVector3Array) -> Rect2:
	var low:=Vector2(INF,INF);var high:=Vector2(-INF,-INF)
	for point in points:
		var pixel:Vector2=app.camera.unproject_position(point)*app._drag_scale()
		low=low.min(pixel);high=high.max(pixel)
	return Rect2(low,high-low)
func footprint(app:Node) -> Rect2:
	return _project_bounds(app,app.director.surface.points())
func resting_footprint(app:Node) -> Rect2:
	var d:Node=app.director;var rotation:=Basis(Vector3.UP,facing_error(app,desired_front(app)))
	var transform:Transform3D=d.stage.transform;transform.basis=rotation*transform.basis
	var result:=Rect2();var first:=true
	for id in ["idle_lie","sleep_loop"]:
		var pose:Dictionary=d.mixer.body_pose(id,0)
		var evaluated:Dictionary=d.mixer.evaluate_pose(pose,d.stage)
		var bounds:=_project_bounds(app,d.surface.proposed_points(evaluated,transform))
		result=bounds if first else result.merge(bounds);first=false
	return result
func request_front() -> void:
	want_front=true;front_done=false
func tick(app:Node,delta:float,state:Dictionary) -> void:
	var behavior:RefCounted=app.home_behavior
	if app.cursor_follow.active():follow_seen=true
	elif follow_seen and not app.cursor_follow.busy():follow_seen=false;request_front();_record("follow_finished")
	# Explicit follow finishing is allowed with Activity Off / Stay Here.
	if state.paused or state.blocked:
		if state.paused:resume_after=behavior.clock+10
		if active():
			want_front=want_front or mode=="front"
			if mode=="edge":policy.reset()
			_yield_motion(app);mode="idle";velocity=Vector2.ZERO
		if not state.paused:policy.reset()
		return
	if want_front and mode=="idle" and app.director.body=="idle_stand" and state.stable and behavior.clock>=resume_after:
		mode="front";age=0;braking=false;want_front=false;front_done=false;_record("front_start")
	var input:=state.duplicate()
	input.off=behavior.settings.activity=="Off";input.manual_sleep=behavior.manual_sleep
	input.ready=behavior.clock>=behavior.ready_after
	input.arrived=arrived;input.front_done=front_done;input.motion_failed=motion_failed
	input.stable=state.stable and mode=="idle"
	var bounds:=footprint(app);bounds.position+=Vector2(app.pet.position)
	var command:=policy.tick(delta,input,behavior.idle_age,Plan.nearest_gap(bounds,area(app))<=Plan.REST_BAND)
	if command.is_empty():return
	app.home_motion.stop(app,"timed rest")
	_record(command,{"idle_seconds":behavior.idle_age,"rest_seconds":policy.rest_age})
	match command:
		"edge":
			var rest_bounds:=resting_footprint(app)
			plan=Plan.choose(bounds,rest_bounds,Vector2(app.pet.position),area(app))
			target=plan.target;arrival_target=target;origin=Vector2(app.pet.position);velocity=Vector2.ZERO;tempo=1;age=0;braking=false;mode="edge";arrived=false;motion_failed=false;run_finished=false
			edge_location=true
			gait="run" if origin.distance_to(target)>float(app.cursor_follow.settings.approach_px) else "walk"
			if gait=="walk":run_finished=true
			local_bounds=footprint(app).merge(rest_bounds);bounds_age=0
			_record("edge_start",{"sides":plan.sides,"target":[target.x,target.y],"gait":gait})
		"front":request_front()
		_:
			if app.director.request_posture(command,"autonomy") and command=="sleeping":behavior.set_sleep(true,true);app.sleeping=true
func step(app:Node,delta:float) -> bool:
	if not active():return false
	if app.director.paused():return true
	age+=delta
	if mode=="front":return _front_step(app,delta)
	return _edge_step(app,delta)
func _front_step(app:Node,delta:float) -> bool:
	var d:Node=app.director
	var yaw:=facing_error(app,desired_front(app))
	if not braking and not d.follow_turn_active:
		if absf(rad_to_deg(yaw))<=8 or age>12:
			# The turn seam is a fresh support stance. Old turn support locks must
			# not twist the standing recovery back toward the previous heading.
			d.ground_contacts.clear();d.previous_surface_points.clear()
			d.body_time=0;d._render();braking=true;d.follow_stop()
		else:
			d.follow_owned=true;d.follow_turn_scale=clampf(absf(rad_to_deg(yaw))/90,.08,1);d.follow_turn_active=true;d.follow_yaw_velocity=0
			d.pending="";d.pending_priority=0;d._start("turn_left" if yaw>0 else "turn_right",0,.25)
	if braking:d.previous_surface_points.clear()
	d.step(delta*.85 if not braking else delta)
	if braking and d.body=="idle_stand" and d.blend_age>=d.blend_duration:
		d.ground_contacts.clear();d.previous_surface_points.clear();d.blend_source.clear();d._render()
		mode="idle";front_done=absf(rad_to_deg(facing_error(app,desired_front(app))))<=10
		motion_failed=not front_done;_record("front_done",{"error_degrees":rad_to_deg(facing_error(app,desired_front(app)))})
	return true
func _edge_step(app:Node,delta:float) -> bool:
	var d:Node=app.director;var distance:=target-origin
	# Walking can project farther than the final low pose, especially at the top
	# edge. Stop at the nearest visible feasible destination instead of endlessly
	# stepping against the window boundary. Latch the endpoint while braking.
	if not braking:arrival_target=Plan.clamp_origin(target,footprint(app),area(app),2)
	var stopping_distance:=minf(distance.length(),origin.distance_to(arrival_target))
	if stopping_distance<=8 or age>=40:braking=true
	var old:=Vector3(d.stage.position.x,0,d.stage.position.z)
	var wanted:=1.0
	if braking:d.follow_stop()
	else:
		if gait=="run" and distance.length()<=float(app.cursor_follow.settings.approach_px):gait="walk";run_finished=true;_record("slow_to_walk",{"remaining_px":distance.length()})
		d.follow_drive(app._screen_direction_world(distance),gait,delta)
		if d.body in ["turn_left","turn_right"]:wanted=.85
		elif d.body in ["walk","run"]:
			var forward:Vector3=d.follow_forward()
			var pixels:Vector2=(app.camera.unproject_position(old+forward)-app.camera.unproject_position(old))*app._drag_scale()
			var length:float=d.catalog.animations[d.body].length
			var stride:float=d.catalog.travel(d.body,length).origin.length()/length
			var requested:=minf(float(app.cursor_follow.settings.run_px_s if gait=="run" else app.cursor_follow.settings.walk_px_s),sqrt(maxf(0,2*550.0*maxf(0,stopping_distance-8))))
			if gait=="walk":requested=minf(requested,stopping_distance/.3)
			wanted=clampf(requested/maxf(1,pixels.length()*stride),.1,1.7)
			if absf(d.follow_error_degrees)>150:wanted=minf(wanted,.75)
	tempo=move_toward(tempo,wanted,delta*3)
	d.step(delta if braking else delta*tempo)
	var placed:=Vector3(d.stage.position.x,0,d.stage.position.z)
	if braking:velocity=velocity.move_toward(Vector2.ZERO,500*delta)
	else:
		var measured:Vector2=(app.camera.unproject_position(placed)-app.camera.unproject_position(old))*app._drag_scale()/maxf(.001,delta)
		velocity=velocity.lerp(measured,1-exp(-delta/.08))
	var movement:=velocity*delta
	if braking:movement=movement.limit_length(distance.length())
	app._follow_camera()
	# Current visible geometry, not the transparent window rectangle, is clamped.
	local_bounds=footprint(app)
	origin=Plan.clamp_origin(origin+movement,local_bounds,area(app),2)
	app.pet.position=Vector2i(roundi(origin.x),roundi(origin.y))
	if braking and d.body=="idle_stand" and d.blend_age>=d.blend_duration:
		velocity=Vector2.ZERO;mode="idle";braking=false;arrived=age<40 and origin.distance_to(arrival_target)<=20;motion_failed=not arrived
		_record("edge_done",{"arrived":arrived,"error_px":origin.distance_to(target),"visible_endpoint_error_px":origin.distance_to(arrival_target),"seconds":age})
	return true
