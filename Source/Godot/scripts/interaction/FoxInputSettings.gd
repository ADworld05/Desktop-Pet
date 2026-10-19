extends RefCounted
const Atomic=preload("res://scripts/settings/FoxAtomicJson.gd")
## Fixed local file, bounded values, no arbitrary settings paths.
static var PATH: String:
	get: return preload("res://scripts/Paths.gd").directory("config").path_join("pointer.json")
const DEFAULTS := {"sensitivity":1.0,"attention_radius":210.0,"dead_zone":8.0,"smoothing_seconds":0.18,"hold_seconds":0.30,"movement_tolerance":6.0,"double_seconds":0.32,"double_distance":10.0,"hover_dwell":0.40,"hover_cooldown":4.0,"stay_here":true}
const LIMITS := {"sensitivity":Vector2(0.5,1.5),"attention_radius":Vector2(120,360),"dead_zone":Vector2(4,16),"smoothing_seconds":Vector2(0.10,0.40),"hold_seconds":Vector2(0.25,0.50),"movement_tolerance":Vector2(4,8),"double_seconds":Vector2(0.25,0.50),"double_distance":Vector2(6,16),"hover_dwell":Vector2(0.25,0.8),"hover_cooldown":Vector2(2,8)}
var values: Dictionary = DEFAULTS.duplicate()

func sanitize(candidate: Dictionary) -> Dictionary:
	var result := DEFAULTS.duplicate()
	for key in LIMITS:
		var value: Variant = candidate.get(key,DEFAULTS[key])
		if (value is float or value is int) and is_finite(float(value)):
			result[key] = clampf(float(value),LIMITS[key].x,LIMITS[key].y)
	if candidate.get("stay_here") is bool: result.stay_here=candidate.stay_here
	return result

func load_local() -> void:
	var loaded:=Atomic.read_local(PATH,true)
	values=sanitize(loaded.data)

func save_local() -> Error:
	values.merge(sanitize(values),true)
	return Atomic.write_local(PATH,values)
