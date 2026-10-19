extends RefCounted
const Atomic=preload("FoxAtomicJson.gd")
static var PATH: String:
	get: return preload("res://scripts/Paths.gd").directory("config").path_join("preferences.json")
const DEFAULTS:={"version":1,"pet_name":"Pet","user_name":"","size_percent":100.0,"eye_color":"Original","topmost":true,"taskbar":false,"taskbar_policy_version":1,"fullscreen_pause":false,"fullscreen_policy_version":2,"glass_opacity":0.72,"glass_blur":0.75,"glass_tint":0.3}
const EYE_COLORS:=["Original","Blue","Green","Amber"]
var values:Dictionary=DEFAULTS.duplicate()
var load_status:="missing"

func sanitize(candidate:Dictionary) -> Dictionary:
	var result:=DEFAULTS.duplicate()
	for key in ["pet_name","user_name"]:
		var text:Variant=candidate.get(key)
		if text is String:
			var clean:=""
			for letter in text.strip_edges().left(40):
				if letter.unicode_at(0)>=32 and letter.unicode_at(0)!=127:clean+=letter
			result[key]=clean
	if result.pet_name.is_empty():result.pet_name=DEFAULTS.pet_name
	var size:Variant=candidate.get("size_percent")
	if (size is int or size is float) and is_finite(float(size)):result.size_percent=clampf(float(size),75,150)
	if candidate.get("eye_color") in EYE_COLORS:result.eye_color=candidate.eye_color
	for key in ["topmost","taskbar","fullscreen_pause"]:
		if candidate.get(key) is bool:result[key]=candidate[key]
	for key in ["glass_opacity","glass_blur","glass_tint"]:
		var value:Variant=candidate.get(key)
		if (value is int or value is float) and is_finite(float(value)):result[key]=clampf(float(value),0.35 if key=="glass_opacity" else 0.0,0.95 if key=="glass_opacity" else 1.0)
	return result

func load_local(path:String="") -> void:
	var loaded:=Atomic.read_local(PATH if path.is_empty() else path)
	load_status=loaded.status
	var candidate:Dictionary=loaded.data.duplicate()
	# User requested one explicit default change. After migration, retain an opt-in.
	if candidate.get("fullscreen_policy_version",0)<2:candidate.fullscreen_pause=false
	# Hide legacy pet taskbar entries once; a later explicit opt-in is retained.
	if candidate.get("taskbar_policy_version",0)<1:candidate.taskbar=false
	values=sanitize(candidate)

func save_local(path:String="") -> Error:
	values=sanitize(values)
	return Atomic.write_local(PATH if path.is_empty() else path,values)
