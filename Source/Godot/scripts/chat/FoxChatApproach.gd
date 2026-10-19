extends RefCounted
## Explicit window relocation only. Compose the accepted grounded arrival driver.
const Motion=preload("res://scripts/behavior/FoxRestRoutine.gd")
const SETTLE_SECONDS:=.65
const GAP:=24.0
var motion:=Motion.new()
var observed:=Rect2()
var initialized:=false
var pending:=false
var quiet:=0.0
var outcome:="idle"
var side:=""
var waiting_stand:=false
var moves:=0
var arrived:=false
var last_target:=Vector2.ZERO
var events:Array[Dictionary]=[]
func active() -> bool:return motion.active()
func record(kind:String) -> void:
	events.append({"kind":kind,"outcome":outcome,"quiet":quiet})
	if events.size()>32:events.pop_front()
func cancel(app:Node,reason:String) -> void:
	if active():motion.cancel(app,reason)
	pending=false;quiet=0;waiting_stand=false;outcome=reason;arrived=false
func opened(app:Node,rect:Rect2) -> void:
	cancel(app,"opened");observed=rect;initialized=true
static func destination(origin:Vector2,bounds:Rect2,chat:Rect2,area:Rect2) -> Dictionary:
	var center:=chat.get_center()-bounds.size*.5-bounds.position
	var candidates:=[{"side":"left","target":Vector2(chat.position.x-GAP-bounds.end.x,center.y)},
		{"side":"right","target":Vector2(chat.end.x+GAP-bounds.position.x,center.y)},
		{"side":"above","target":Vector2(center.x,chat.position.y-GAP-bounds.end.y)},
		{"side":"below","target":Vector2(center.x,chat.end.y+GAP-bounds.position.y)}]
	var valid:Array[Dictionary]=[]
	for row in candidates:
		row.target=Motion.Plan.clamp_origin(row.target,bounds,area,8)
		var placed:=Rect2(row.target+bounds.position,bounds.size)
		if area.encloses(placed) and not placed.intersects(chat.grow(10)):
			row.distance=origin.distance_to(row.target);valid.append(row)
	# Prefer beside; if both sides lack room, use the nearest free top/bottom.
	valid.sort_custom(func(a,b):
		var a_side:bool=a.side in ["left","right"];var b_side:bool=b.side in ["left","right"]
		return a_side if a_side!=b_side else a.distance<b.distance)
	return valid[0] if not valid.is_empty() else {}
func observe(app:Node,window:Window,delta:float,held:bool) -> void:
	if not window.visible or window.mode!=Window.MODE_WINDOWED or app.director.paused() or app.pet_hidden_by_user or app.panel_minimized:
		if active() or pending:cancel(app,"window/lifecycle paused")
		return
	var rect:=Rect2(Vector2(window.get_position_with_decorations()),Vector2(window.get_size_with_decorations()))
	if not initialized:opened(app,rect);return
	if rect.position.distance_to(observed.position)>2 or rect.size.distance_to(observed.size)>2:
		if active():motion.cancel(app,"window moving")
		observed=rect;pending=true;quiet=0;waiting_stand=false;arrived=false;outcome="waiting for window release";record("changed");return
	if not pending:return
	if held:quiet=0;return
	quiet+=delta
	if quiet<SETTLE_SECONDS:return
	if app.pointer.pressed or app.cursor_follow.busy() or app.panel.visible:return
	if app.director.body in ["pickup","release","double_click_jump_sit"] or app.director.body.begins_with("drag_"):return
	if app.director.body!="idle_stand" or not app.director.pending.is_empty():
		if not waiting_stand:
			app.rest_routine.cancel(app,"chat relocated");app.home_motion.stop(app,"chat relocated");app.home_behavior.set_sleep(false);app.sleeping=false
			waiting_stand=app.director.request_posture("standing","user")
		return
	app._follow_camera()
	# Reserve silhouette room for the change in heading and the final standing blend.
	var bounds:Rect2=motion.footprint(app).grow(24)
	var choice:=destination(Vector2(app.pet.position),bounds,rect,motion.area(app))
	pending=false
	if choice.is_empty():outcome="no free adjacent area";record("no space");return
	side=choice.side;last_target=choice.target
	if Vector2(app.pet.position).distance_to(last_target)<=20:arrived=true;outcome="already nearby";return
	app.rest_routine.cancel(app,"chat relocated");app.home_motion.stop(app,"chat relocated");app.home_behavior.interact()
	motion.mode="edge";motion.target=last_target;motion.arrival_target=last_target;motion.origin=Vector2(app.pet.position);motion.velocity=Vector2.ZERO;motion.tempo=1;motion.age=0;motion.braking=false;motion.arrived=false;motion.motion_failed=false;motion.run_finished=false
	motion.gait="run" if motion.origin.distance_to(last_target)>float(app.cursor_follow.settings.approach_px) else "walk"
	moves+=1;outcome="approaching";record("start")
func step(app:Node,delta:float) -> bool:
	if not active():return false
	if app.pointer.pressed or app.cursor_follow.busy():cancel(app,"explicit pointer interaction");return false
	var stepped:bool=motion.step(app,delta)
	if not active():
		arrived=motion.arrived;outcome="standing nearby" if arrived else "bounded arrival failed";record("finish")
	return stepped
