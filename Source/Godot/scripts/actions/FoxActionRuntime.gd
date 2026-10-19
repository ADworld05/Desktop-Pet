extends RefCounted
static func safety() -> Dictionary:
	if OS.get_name() != "Windows" or not ClassDB.class_exists("FoxPathBoundary"): return {"ok": false, "reason": "safety_unavailable"}
	var raw: Variant = JSON.parse_string(ClassDB.class_call_static("FoxPathBoundary", "process_safety"))
	if not raw is Dictionary or raw.get("ok") != true or raw.get("elevated") != false: return {"ok": false, "reason": "non_elevated_context_required"}
	return {"ok": true, "elevated": false}
