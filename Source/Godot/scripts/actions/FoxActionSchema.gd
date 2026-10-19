extends RefCounted
## Requests contain data only; authorization never appears in this schema.
const TOOLS := {
	"open_application": ["app_id"],
	"open_file": ["path"],
	"open_folder": ["path"],
	"find_file": ["root_id", "query", "max_depth", "max_results", "timeout_ms"],
	"reveal_in_explorer": ["path"],
	"read_text_file": ["path", "max_bytes"],
	"close_application": ["window_id"],
	"get_system_information": ["fields"],
}
const SYSTEM_FIELDS := ["os_version", "cpu_count", "memory_total", "battery_percent", "battery_charging", "uptime_seconds"]

static func exact_keys(data: Dictionary, keys: Array) -> bool:
	if data.size() != keys.size(): return false
	for key in keys:
		if not data.has(key): return false
	return true

static func text(value: Variant, minimum: int, maximum: int) -> bool:
	if not value is String or value.length() < minimum or value.length() > maximum: return false
	for i in value.length():
		if value.unicode_at(i) < 32 or value.unicode_at(i) == 127: return false
	return true

static func identifier(value: Variant) -> bool:
	if not text(value, 1, 64): return false
	for c in value:
		if not c in "abcdefghijklmnopqrstuvwxyz0123456789_-": return false
	return true

static func bounded_integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == int(value) and value >= minimum and value <= maximum

static func validate(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not exact_keys(raw, ["tool", "arguments"]): return {"ok": false, "reason": "request_schema"}
	if not raw.tool is String or not TOOLS.has(raw.tool): return {"ok": false, "reason": "unknown_tool"}
	if not raw.arguments is Dictionary or not exact_keys(raw.arguments, TOOLS[raw.tool]): return {"ok": false, "reason": "argument_schema"}
	var a: Dictionary = raw.arguments.duplicate(true)
	if a.has("path") and not text(a.path, 4, 512): return {"ok": false, "reason": "path_type_or_length"}
	if a.has("app_id") and not identifier(a.app_id): return {"ok": false, "reason": "app_id"}
	if a.has("window_id") and not identifier(a.window_id): return {"ok": false, "reason": "window_id"}
	if raw.tool == "read_text_file":
		if not bounded_integer(a.max_bytes, 1, 65536): return {"ok": false, "reason": "read_limit"}
		a.max_bytes = int(a.max_bytes)
	if raw.tool == "find_file":
		if not identifier(a.root_id) or not text(a.query, 1, 80) or a.query.strip_edges() != a.query: return {"ok": false, "reason": "search_query"}
		for c in a.query:
			if c in "/\\:*?\"<>|;%$": return {"ok": false, "reason": "search_query"}
		if not bounded_integer(a.max_depth, 0, 4) or not bounded_integer(a.max_results, 1, 50) or not bounded_integer(a.timeout_ms, 100, 2000): return {"ok": false, "reason": "search_limits"}
		for key in ["max_depth", "max_results", "timeout_ms"]: a[key] = int(a[key])
	if raw.tool == "get_system_information":
		if not a.fields is Array or a.fields.is_empty() or a.fields.size() > SYSTEM_FIELDS.size(): return {"ok": false, "reason": "system_fields"}
		var seen: Array = []
		for field in a.fields:
			if not field is String or not field in SYSTEM_FIELDS or field in seen: return {"ok": false, "reason": "system_fields"}
			seen.append(field)
		a.fields.sort()
	return {"ok": true, "request": {"tool": raw.tool, "arguments": a}}
