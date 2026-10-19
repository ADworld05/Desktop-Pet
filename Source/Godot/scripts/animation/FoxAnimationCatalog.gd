extends RefCounted
## Fixed, app-owned approved assets; no model/network/action launch surface.
const Paths = preload("../Paths.gd")
const ROOT = Paths.ASSET_ROOT
var rows: Dictionary = {}
var animations: Dictionary = {}
var manifest: Dictionary

func initialize() -> bool:
	manifest = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "/Animations/animation_manifest.json"))
	if manifest.is_empty(): return false
	var core := load(ROOT + "/Animations/T06_core_library_M3.tres") as AnimationLibrary
	var personality := load(ROOT + "/Animations/T07_personality_library_M1.tres") as AnimationLibrary
	var events := load(ROOT + "/Animations/T07_event_library_M1.tres") as AnimationLibrary
	if not core or not personality or not events: return false
	for row in manifest.clips + manifest.personality_clips:
		if not row.get("enabled", true): continue
		var id: String = row.id
		var library: AnimationLibrary = core if row in manifest.clips else (events if row.layer == "body" else personality)
		if not library.has_animation(id): return false
		rows[id] = row
		animations[id] = library.get_animation(id)
	# T11 reference-based rest revision supplements the approved core library.
	# Original model, gaits and six earlier low-state clips remain recoverable.
	var rest_library:=load(ROOT+"/Animations/T11_rest_library_M2.tres") as AnimationLibrary
	var rest_manifest:Variant=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"/Animations/T11_rest_manifest_M2.json"))
	if not rest_library or not rest_manifest is Dictionary:return false
	for override in rest_manifest.clips:
		var id:String=override.id
		if id not in ["lie_down","idle_lie","get_up","sleep_enter","sleep_loop","wake_up"] or not rows.has(id) or not rest_library.has_animation(id):return false
		var revised:Dictionary=rows[id].duplicate(true)
		revised.merge(override,true)
		rows[id]=revised;animations[id]=rest_library.get_animation(id)
	return rows.size() == 39

func is_body(id: String) -> bool:
	return rows.has(id) and rows[id].get("layer", "body") == "body"

func travel(id: String, seconds: float) -> Transform3D:
	# Only the stage consumes calibrated travel, never the bone sampler.
	var trajectory: Variant = rows[id].get("trajectory")
	if trajectory == null: return Transform3D.IDENTITY
	var samples: Array = trajectory.samples
	var frame := clampf(seconds * 30.0, 0.0, float(samples.size() - 1))
	var low := int(frame)
	var high := mini(low + 1, samples.size() - 1)
	var left: Dictionary = samples[low]
	var right: Dictionary = samples[high]
	var amount := frame - low
	var a: Array = left.rotation_godot_xyzw
	var b: Array = right.rotation_godot_xyzw
	var rotation := Quaternion(a[0],a[1],a[2],a[3]).normalized().slerp(Quaternion(b[0],b[1],b[2],b[3]).normalized(),amount)
	var p: Array = trajectory.pivot_godot
	var pivot := Vector3(p[0],p[1],p[2])
	var x: Array = left.translation_godot
	var y: Array = right.translation_godot
	var shift := Vector3(x[0],x[1],x[2]).lerp(Vector3(y[0],y[1],y[2]),amount)
	var basis := Basis(rotation)
	return Transform3D(basis,shift + pivot - basis * pivot)

func sample_time(id: String, seconds: float) -> float:
	var duration: float = animations[id].length
	return fposmod(seconds, duration) if rows[id].loop else clampf(seconds, 0.0, duration)

func floor_offset(id: String, seconds: float) -> float:
	var row: Dictionary = rows[id]
	var values: Array = row.get("floor_offsets_metres", [])
	if values.is_empty(): return 0.0
	var frame: float = sample_time(id, seconds) * 30.0
	var low := mini(int(frame), values.size() - 1)
	var high := mini(low + 1, values.size() - 1)
	var amount: float = frame - low
	var lift: Array = row.get("interpolation_floor_lifts_metres", [])
	# Per-frame offsets are already baked into FoxTransform's exported keys.
	# Only the unbaked between-key guard belongs to the stage.
	return float(lift[low]) * 4.0 * amount * (1.0 - amount) if low < lift.size() else 0.0
