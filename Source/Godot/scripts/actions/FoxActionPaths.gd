extends RefCounted
## Metadata-only Windows bridge. Any unavailable resolution denies the request.
const Schema = preload("res://scripts/actions/FoxActionSchema.gd")

static func lexical(raw: Variant) -> Dictionary:
	if not Schema.text(raw, 4, 512): return {"ok": false, "reason": "invalid_path"}
	var path: String = raw.replace("\\", "/")
	if path.length() < 4 or path[1] != ":" or path[2] != "/" or not path[0].to_lower() in "abcdefghijklmnopqrstuvwxyz": return {"ok": false, "reason": "absolute_local_path_required"}
	if path.substr(2).contains(":"): return {"ok": false, "reason": "alternate_stream_or_scheme"}
	for c in path:
		if c in "\"<>|*?%$": return {"ok": false, "reason": "path_metacharacter"}
	var parts := path.substr(3).split("/", true)
	# Reject dot traversal and ambiguous spellings rather than silently rewriting them.
	for part in parts:
		if part.is_empty() or part in [".", ".."] or part.ends_with(".") or part.ends_with(" "): return {"ok": false, "reason": "ambiguous_component"}
	return {"ok": true, "path": path}

static func resolve(raw: Variant) -> Dictionary:
	return _resolve(raw, "resolve_metadata")

static func resolve_application(raw: Variant) -> Dictionary:
	if not raw is String or raw.get_extension().to_lower() != "exe": return {"ok": false, "reason": "application_required"}
	return _resolve(raw, "resolve_application")

static func _resolve(raw: Variant, method: String) -> Dictionary:
	var checked := lexical(raw)
	if not checked.ok: return checked
	if OS.get_name() != "Windows" or not ClassDB.class_exists("FoxPathBoundary"): return {"ok": false, "reason": "resolution_unavailable"}
	var response: Variant = JSON.parse_string(ClassDB.class_call_static("FoxPathBoundary", method, checked.path))
	if not response is Dictionary or not response.get("ok", false): return response if response is Dictionary else {"ok": false, "reason": "resolution_unavailable"}
	if not Schema.exact_keys(response, ["ok", "path", "identity", "stamp", "size", "directory"]) or not lexical(response.path).ok or not response.identity is String or not response.stamp is String or not response.directory is bool or not Schema.bounded_integer(response.size, 0, 9007199254740991): return {"ok": false, "reason": "invalid_resolver_response"}
	response.size = int(response.size)
	return response

static func inside(target: String, root: String) -> bool:
	# Native bridge rejects case-sensitive directory trees and canonicalizes aliases.
	return target.to_lower() == root.to_lower() or target.to_lower().begins_with(root.to_lower() + "/")

static func same_object(a: Dictionary, b: Dictionary) -> bool:
	return a.get("ok", false) and b.get("ok", false) and a.path.to_lower() == b.path.to_lower() and a.identity == b.identity and a.directory == b.directory

static func fingerprint(target: Dictionary) -> String:
	return JSON.stringify([target.path.to_lower(), target.identity, target.stamp, target.size, target.directory]).sha256_text()
