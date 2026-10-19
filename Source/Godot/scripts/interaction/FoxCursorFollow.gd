extends RefCounted
const Atomic=preload("res://scripts/settings/FoxAtomicJson.gd")
## Owned click-hold navigation; short in-memory history, never persisted.
static var PATH: String:
	get: return preload("res://scripts/Paths.gd").directory("config").path_join("follow.json")
const DEFAULTS := {"hold_ms":1000.0,"distance_px":275.0,"delay_ms":50.0,"approach_px":120.0,"walk_px_s":140.0,"run_px_s":420.0,"reversal_deg":177.0,"steering_deg_s":120.0,"rest_angle_deg":18.0}
const LIMITS := {"hold_ms":Vector2(600,2000),"distance_px":Vector2(150,450),"delay_ms":Vector2(50,300),"approach_px":Vector2(40,240),"walk_px_s":Vector2(60,240),"run_px_s":Vector2(250,700),"reversal_deg":Vector2(165,179),"steering_deg_s":Vector2(60,180),"rest_angle_deg":Vector2(10,30)}
var settings: Dictionary=DEFAULTS.duplicate()
var phase := "normal"
var pressed := false
var down_time := 0.0
var last_time := 0.0
var last_motion_time := 0.0
var last_cursor := Vector2.ZERO
var history: Array[Dictionary]=[]
var target := Vector2.ZERO
var cursor_speed := 0.0
var pace := 0.0
var mode := "walk"
var confirmation := 0.0
var arrival_pending := false
var stopped := false
var starts := 0

func sanitize(candidate: Dictionary) -> Dictionary:
	var values:=DEFAULTS.duplicate()
	for key in LIMITS:
		var value:Variant=candidate.get(key,DEFAULTS[key])
		if (value is float or value is int) and is_finite(float(value)): values[key]=clampf(float(value),LIMITS[key].x,LIMITS[key].y)
	return values

func load_local() -> void:
	var loaded:=Atomic.read_local(PATH,true)
	settings=sanitize(loaded.data)

func save_local() -> Error:
	settings=sanitize(settings)
	return Atomic.write_local(PATH,settings)

func active() -> bool:return phase in ["following","finishing"]
func busy() -> bool:return pressed or active()

func press(now: float, cursor: Vector2) -> bool:
	if busy() or not is_finite(now) or not is_finite(cursor.x) or not is_finite(cursor.y):return false
	pressed=true;phase="press";down_time=now;last_time=now;last_motion_time=now
	last_cursor=cursor;target=cursor;history=[{"time":now,"point":cursor}]
	cursor_speed=0.0;pace=0.0;mode="walk";confirmation=0.0;arrival_pending=false;stopped=false
	return true

func _record(now: float, cursor: Vector2, seconds: float) -> void:
	var raw:=minf(2000.0,cursor.distance_to(last_cursor)/maxf(.001,seconds))
	cursor_speed=lerpf(cursor_speed,raw,1.0-exp(-seconds/.15))
	if cursor.distance_to(last_cursor)>.8:last_motion_time=now
	last_cursor=cursor
	history.append({"time":now,"point":cursor})
	var oldest:=now-float(settings.delay_ms)/1000.0-.25
	while history.size()>2 and (history[1].time<oldest or history.size()>128):history.pop_front()

func delayed(now: float) -> Vector2:
	if history.is_empty():return target
	var moment:=now-float(settings.delay_ms)/1000.0
	if moment<=float(history[0].time):return history[0].point
	for index in range(1,history.size()):
		if moment<=float(history[index].time):
			var before:Dictionary=history[index-1];var after:Dictionary=history[index]
			var amount:=clampf((moment-float(before.time))/maxf(.000001,float(after.time)-float(before.time)),0,1)
			return before.point.lerp(after.point,amount)
	return history.back().point

func sample(now: float, cursor: Vector2, center: Vector2, reachable: Rect2) -> void:
	if not busy() or not is_finite(now) or now<=last_time or not is_finite(cursor.x) or not is_finite(cursor.y):return
	var seconds:=minf(.1,now-last_time);last_time=now
	if pressed and phase!="latched":_record(now,cursor,seconds)
	else:cursor_speed=lerpf(cursor_speed,0.0,1.0-exp(-seconds/.15))
	if phase=="press" and now-down_time>=.30:phase="hold_detected"
	if phase in ["press","hold_detected"] and now-down_time>=float(settings.hold_ms)/1000.0:phase="follow_ready"
	if phase=="follow_ready" and cursor.distance_to(center)>=float(settings.distance_px):
		phase="following";starts+=1
	if not active():return
	target=delayed(now).clamp(reachable.position,reachable.end)
	var distance:=center.distance_to(target)
	if distance<=float(settings.approach_px):mode="walk";confirmation=0
	elif mode=="run":confirmation=0
	else:
		# One spatial threshold plus short temporal confirmation prevents chatter.
		confirmation+=seconds
		if confirmation>=.18 or pace<1:mode="run";confirmation=0
	stopped=now-last_motion_time>=.25 and now-history.back().time>=float(settings.delay_ms)/1000.0 if not pressed else now-last_motion_time>=.25
	arrival_pending=stopped and distance<=12.0
	var requested:=minf(float(settings.run_px_s if mode=="run" else settings.walk_px_s),sqrt(maxf(0,2*550.0*maxf(0,distance-8))))
	if mode=="walk":requested=minf(requested,distance/.3)
	if arrival_pending:requested=0
	pace=move_toward(pace,requested,seconds*(800.0 if requested>pace else 550.0))

func release(now: float, cursor: Vector2) -> void:
	if not pressed:return
	if phase!="latched":
		_record(now,cursor,maxf(.001,now-last_time));last_time=now
	pressed=false
	if active():phase="finishing" # Explicit user choice: finish final recorded target.
	else:phase="normal";history.clear();pace=0

func acknowledge_stop() -> void:
	phase="latched" if pressed else "normal"
	history.clear();pace=0.0;arrival_pending=false

func cancel() -> bool:
	var moving:=active()
	phase="normal";pressed=false;history.clear();pace=0;arrival_pending=false
	return moving
