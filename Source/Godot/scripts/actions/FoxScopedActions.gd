extends RefCounted
const Schema = preload("res://scripts/actions/FoxActionSchema.gd")
const Paths = preload("res://scripts/actions/FoxActionPaths.gd")
const Runtime = preload("res://scripts/actions/FoxActionRuntime.gd")
const TOOLS := ["open_application", "open_file", "open_folder", "find_file", "reveal_in_explorer"]

static func execute(request: Dictionary, target: Dictionary) -> Dictionary:
	var checked := Schema.validate(request)
	if not checked.ok or not request.tool in TOOLS or not Schema.exact_keys(target, ["ok", "path", "identity", "stamp", "size", "directory"]) or target.ok != true or not target.directory is bool or not Schema.text(target.identity, 25, 25) or not Schema.text(target.stamp, 16, 16) or not Schema.bounded_integer(target.size, 0, 9223372036854775807) or not Paths.lexical(target.path).ok or not Runtime.safety().get("ok", false): return {"ok": false, "reason": "invalid_request_or_context", "executed": false}
	var fields := [target.path, target.identity, target.stamp, str(target.size)]
	var method := "launch_snapshot"
	if request.tool == "find_file":
		method = "search_snapshot"
		fields.append_array([request.arguments.query, str(request.arguments.max_depth), str(request.arguments.max_results), str(request.arguments.timeout_ms)])
	else: fields.push_front(request.tool)
	var raw: Variant = JSON.parse_string(ClassDB.class_call_static("FoxPathBoundary", method, "\t".join(fields)))
	if not raw is Dictionary: return {"ok": false, "reason": "adapter_unavailable", "executed": false, "simulated": false}
	raw.simulated = false; raw.executed = raw.get("ok", false)
	if request.tool == "find_file": raw.trust = "untrusted_filename_metadata"
	return raw
