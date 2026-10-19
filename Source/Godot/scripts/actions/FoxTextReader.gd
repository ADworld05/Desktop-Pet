extends RefCounted
const Schema = preload("res://scripts/actions/FoxActionSchema.gd")
const Paths = preload("res://scripts/actions/FoxActionPaths.gd")
const Runtime = preload("res://scripts/actions/FoxActionRuntime.gd")
static func read_snapshot(target: Dictionary, maximum: int) -> Dictionary:
	if not Schema.exact_keys(target, ["ok", "path", "identity", "stamp", "size", "directory"]) or target.ok != true or target.directory != false or not Schema.text(target.identity, 25, 25) or not Schema.text(target.stamp, 16, 16) or not Schema.bounded_integer(target.size, 0, 65536) or not Runtime.safety().get("ok", false) or not Schema.bounded_integer(maximum, 1, 65536) or not Paths.lexical(target.path).ok: return {"ok": false, "reason": "invalid_target_or_context"}
	var packet := "\t".join([target.path, target.identity, target.stamp, str(target.size), str(maximum)])
	var result: Variant = JSON.parse_string(ClassDB.class_call_static("FoxPathBoundary", "read_text_snapshot", packet))
	if not result is Dictionary or not result.get("ok", false): return result if result is Dictionary else {"ok": false, "reason": "unavailable"}
	var bytes: PackedByteArray = String(result.hex).hex_decode()
	return {"ok": true, "text": bytes.get_string_from_utf8().trim_prefix("\ufeff"), "bytes": bytes.size(), "source": target.path, "trust": "untrusted_file_data"}
