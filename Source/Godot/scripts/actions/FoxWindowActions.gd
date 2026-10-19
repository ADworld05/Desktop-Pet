extends RefCounted
const Paths = preload("res://scripts/actions/FoxActionPaths.gd")
static func list_for_app(app: Dictionary) -> Dictionary:
	var raw: Variant = JSON.parse_string(ClassDB.class_call_static("FoxPathBoundary", "list_app_windows", app.path))
	if not raw is Dictionary or not raw.get("ok", false): return {"ok": false, "reason": "window_list_unavailable"}
	return raw
static func query(window_id: String, apps: Dictionary) -> Dictionary:
	if not window_id.begins_with("window_") or not window_id.trim_prefix("window_").is_valid_int(): return {"ok": false}
	var raw: Variant = JSON.parse_string(ClassDB.class_call_static("FoxPathBoundary", "query_app_window", window_id.trim_prefix("window_")))
	if not raw is Dictionary or not raw.get("ok", false): return {"ok": false}
	for id in apps:
		if str(raw.path).to_lower() == str(apps[id].path).to_lower():
			raw.window_id = window_id; raw.app_id = id; return raw
	return {"ok": false}
static func close(target: Dictionary) -> Dictionary:
	var executable := Paths.resolve_application(target.path)
	if not executable.ok or executable.identity != target.exe_identity: return {"ok": false, "reason": "app_changed", "executed": false}
	var packet := "\t".join([executable.path, executable.identity, executable.stamp, str(executable.size), str(int(target.handle)), str(int(target.pid)), target.started, str(int(target.session))])
	var raw: Variant = JSON.parse_string(ClassDB.class_call_static("FoxPathBoundary", "close_app_window", packet))
	if not raw is Dictionary: return {"ok": false, "reason": "close_unavailable", "executed": false}
	raw.simulated = false; raw.executed = raw.get("ok", false); return raw
