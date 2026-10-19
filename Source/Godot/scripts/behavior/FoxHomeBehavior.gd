extends RefCounted
const Atomic=preload("res://scripts/settings/FoxAtomicJson.gd")
## Local weighted decisions only. No cursor history, OS access or animation writes.
static var PATH: String:
	get: return preload("res://scripts/Paths.gd").directory("config").path_join("autonomy.json")
static var TEMP: String:
	get: return PATH + ".tmp"
const DEFAULTS := {"version":1,"activity":"Low","radius":110.0}
const COOLDOWNS := {"ear_twitch":24.0,"tail_idle":30.0,"look_around":35.0,"sitting":60.0,"standing":25.0,"lying":90.0,"roam":75.0}
var settings: Dictionary=DEFAULTS.duplicate()
var rng:=RandomNumberGenerator.new()
var clock:=0.0
var idle_age:=0.0
var next_action:=0.0
var next_blink:=0.0
var ready_after:=0.0
var last_action:=""
var used:Dictionary={}
var auto_sleep:=false
var manual_sleep:=false
var home:=Vector2.ZERO # native window origin, never advanced by roaming

func sanitize(candidate: Dictionary) -> Dictionary:
	var result:=DEFAULTS.duplicate()
	if candidate.get("version")!=1:return result
	if candidate.get("activity") in ["Off","Low","Normal"]:result.activity=candidate.activity
	for key in ["radius"]:
		var value:Variant=candidate.get(key)
		if (value is int or value is float) and is_finite(float(value)):
			result[key]=clampf(float(value),80,150)
	return result

func load_local() -> void:
	var loaded:=Atomic.read_local(PATH)
	settings=sanitize(loaded.data)

func save_local() -> Error:
	settings=sanitize(settings)
	return Atomic.write_local(PATH,settings)

func initialize(seed_value: int, origin: Vector2) -> void:
	rng.seed=seed_value;home=origin;clock=0;idle_age=0;used.clear();last_action=""
	auto_sleep=false;manual_sleep=false;ready_after=10;_schedule()
	next_blink=rng.randf_range(3,7)

func _schedule() -> void:
	next_action=clock+rng.randf_range(30,70) if settings.activity=="Low" else clock+rng.randf_range(18,40)

func interact() -> void:
	idle_age=0;ready_after=clock+10;next_action=maxf(next_action,ready_after)

func set_home(origin: Vector2) -> void:
	home=origin;interact();_schedule()

func set_sleep(value: bool, automatic: bool=false) -> void:
	manual_sleep=value and not automatic;auto_sleep=value and automatic
	if not value:interact();_schedule();next_blink=clock+rng.randf_range(3,7)

func commit(id: String) -> void:
	used[id]=clock
	if id!="blink":last_action=id
	if id=="sleeping":set_sleep(true,true)
	if id!="blink":_schedule()

func tick(delta: float, state: Dictionary) -> Dictionary:
	# Hidden/full-screen time is suspended, with a fresh quiet period on return.
	if state.get("paused",false):ready_after=clock+10;return {}
	clock+=clampf(delta,0,1)
	if state.get("proximity",false) or state.get("interacting",state.get("blocked",false)):interact()
	else:idle_age+=clampf(delta,0,1)
	if state.get("blocked",false):return {}
	if settings.activity=="Off" or manual_sleep or auto_sleep or state.get("sleeping",false):return {}
	if clock<ready_after:return {}
	if clock>=next_blink:
		next_blink=clock+rng.randf_range(3,7)
		return {"kind":"overlay","id":"blink"}
	if clock<next_action or state.get("moving",false) or not state.get("stable",false):return {}
	var choices:Array[Dictionary]=[]
	# Only cosmetic overlays; deterministic rest owns all idle posture/travel.
	for row in [{"kind":"overlay","id":"ear_twitch","weight":2.0},{"kind":"overlay","id":"tail_idle","weight":2.0},{"kind":"overlay","id":"look_around","weight":1.0}]:
		var id:String=row.id
		if state.get("rest_managed",false) and (id=="lying" or (idle_age>=180 and row.kind!="overlay")):continue
		if id==last_action or clock-float(used.get(id,-10000))<float(COOLDOWNS[id]):continue
		if row.kind=="posture" and id==state.get("posture"):continue
		if row.kind=="move" and (state.get("stay",true) or state.get("posture")!="standing"):continue
		choices.append(row)
	if choices.is_empty():_schedule();return {}
	var total:=0.0
	for row in choices:total+=float(row.weight)
	var choice:=rng.randf()*total
	for row in choices:
		choice-=float(row.weight)
		if choice<=0:return {"kind":row.kind,"id":row.id}
	return {}

func bounded(origin: Vector2, scale: Vector2, usable: Rect2, extent: Vector2) -> Vector2:
	var logical:Vector2=(origin-home)/scale
	var point:=home+logical.limit_length(float(settings.radius))*scale
	return point.clamp(usable.position,(usable.end-extent).max(usable.position))

func destination(current: Vector2, scale: Vector2, usable: Rect2, extent: Vector2) -> Vector2:
	# Every third eligible trip tends home; all destinations remain inside the disc.
	if ((current-home)/scale).length()>35 and rng.randf()<.33:return bounded(home,scale,usable,extent)
	var radius:=rng.randf_range(.35,.80)*float(settings.radius)
	return bounded(home+Vector2.from_angle(rng.randf()*TAU)*radius*scale,scale,usable,extent)
