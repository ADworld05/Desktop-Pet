extends RefCounted
## Redacted, bounded, app-owned audit. Never log request text or filenames.
const MAX_RECORDS := 256
const MAX_FILE_BYTES := 262144
var _records: Array = []
var _path := ""

func _init(app_owned_path: String = "") -> void:
	_path = app_owned_path

func record(tool: String, summary: String, approval: String, outcome: String) -> bool:
	var row := {"utc": Time.get_datetime_string_from_system(true), "action": tool if tool in preload("res://scripts/actions/FoxActionSchema.gd").TOOLS else "unknown", "target": summary, "approval": approval, "outcome": outcome}
	_records.append(row)
	while _records.size() > MAX_RECORDS: _records.pop_front()
	if _path.is_empty(): return true
	# Destination is supplied by trusted composition only, never by an action request.
	var line := JSON.stringify(row) + "\n"
	if FileAccess.file_exists(_path):
		var old := FileAccess.open(_path, FileAccess.READ)
		if not old: return false
		var size := old.get_length(); old.close()
		if size + line.to_utf8_buffer().size() > MAX_FILE_BYTES:
			if FileAccess.file_exists(_path + ".1") and DirAccess.remove_absolute(_path + ".1") != OK: return false
			if DirAccess.rename_absolute(_path, _path + ".1") != OK: return false
	var file := FileAccess.open(_path, FileAccess.READ_WRITE if FileAccess.file_exists(_path) else FileAccess.WRITE)
	if not file: return false
	file.seek_end(); file.store_string(line); file.flush()
	var ok := file.get_error() == OK; file.close()
	return ok

func entries() -> Array:
	return _records.duplicate(true)

func read_recent() -> Dictionary:
	# App-owned destinations only; strict rows, bounded bytes, no model-supplied text rendered.
	var rows: Array = []; var skipped := 0
	if _path.is_empty(): return {"ok": true, "rows": entries(), "skipped": 0}
	for path in [_path + ".1", _path]:
		if not FileAccess.file_exists(path): continue
		var file := FileAccess.open(path, FileAccess.READ)
		if not file or file.get_length() > MAX_FILE_BYTES:
			if file: file.close()
			return {"ok": false, "rows": [], "reason": "audit_unavailable"}
		while not file.eof_reached():
			var line := file.get_line()
			if line.is_empty(): continue
			if line.to_utf8_buffer().size() > 2048: skipped += 1; continue
			var parser := JSON.new()
			if parser.parse(line) != OK or not parser.data is Dictionary: skipped += 1; continue
			var row: Dictionary = parser.data
			var schema = preload("res://scripts/actions/FoxActionSchema.gd")
			if not schema.exact_keys(row, ["utc", "action", "target", "approval", "outcome"]) or not schema.text(row.utc, 19, 40) or not row.action in schema.TOOLS.keys() + ["unknown"] or not schema.text(row.target, 1, 100) or not schema.text(row.approval, 1, 40) or not schema.text(row.outcome, 1, 100): skipped += 1; continue
			# Never display arbitrary imported target/description fields.
			var safe_target: bool = row.target in ["unapproved", "limited-system-fields"]
			for prefix in ["folder:", "app:", "window:"]:
				if row.target.begins_with(prefix) and schema.identifier(row.target.substr(prefix.length())): safe_target = true
			if not safe_target or not schema.identifier(row.approval) or not schema.identifier(row.outcome.replace(":", "_")): skipped += 1; continue
			rows.append(row)
			while rows.size() > MAX_RECORDS: rows.pop_front()
		file.close()
	return {"ok": true, "rows": rows, "skipped": skipped}
