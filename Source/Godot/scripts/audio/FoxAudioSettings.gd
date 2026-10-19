extends RefCounted
const Atomic=preload("res://scripts/settings/FoxAtomicJson.gd")
## Fixed app-owned path. Tests use an isolated path without touching preferences.
static var PATH: String:
	get: return preload("res://scripts/Paths.gd").directory("config").path_join("audio.json")
const DEFAULTS := {"version":1,"pet_volume":0.35,"ui_volume":0.20,"muted":false,"frequency":"Low"}
var values: Dictionary = DEFAULTS.duplicate()

func sanitize(candidate: Dictionary) -> Dictionary:
	var result := DEFAULTS.duplicate()
	for key in ["pet_volume","ui_volume"]:
		var value: Variant = candidate.get(key)
		if (value is int or value is float) and is_finite(float(value)):
			result[key] = clampf(float(value),0.0,1.0)
	if candidate.get("muted") is bool: result.muted=candidate.muted
	if candidate.get("frequency") in ["Off","Low","Normal"]: result.frequency=candidate.frequency
	return result

func load_local(path: String="") -> void:
	var loaded:=Atomic.read_local(PATH if path.is_empty() else path)
	values=sanitize(loaded.data)

func save_local(path: String="") -> Error:
	values=sanitize(values)
	return Atomic.write_local(PATH if path.is_empty() else path,values)
