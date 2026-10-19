extends RefCounted
## Fixed read-only capability; caller must pass only policy-approved structured requests.
const Schema = preload("res://scripts/actions/FoxActionSchema.gd")
const Runtime = preload("res://scripts/actions/FoxActionRuntime.gd")
static func collect(arguments: Variant) -> Dictionary:
	var checked := Schema.validate({"tool": "get_system_information", "arguments": arguments})
	if not checked.ok: return {"ok": false, "status": "denied", "reason": checked.reason}
	if not Runtime.safety().get("ok", false): return {"ok": false, "status": "denied", "reason": "non_elevated_context_required"}
	var raw: Variant = JSON.parse_string(ClassDB.class_call_static("FoxPathBoundary", "system_information"))
	if not raw is Dictionary or not raw.get("ok", false) or not raw.get("values") is Dictionary: return {"ok": false, "status": "unavailable"}
	var values := {}; var unavailable: Array = []
	for field in checked.request.arguments.fields:
		var value: Variant = raw.values.get(field)
		var valid := value == null
		match field:
			"cpu_count": valid = valid or Schema.bounded_integer(value, 1, 4096)
			"memory_total": valid = valid or Schema.bounded_integer(value, 1, 9007199254740991)
			"uptime_seconds": valid = valid or Schema.bounded_integer(value, 0, 9007199254740991)
			"battery_percent": valid = valid or Schema.bounded_integer(value, 0, 100)
			"battery_charging": valid = valid or value is bool
			"os_version": valid = valid or Schema.text(value, 1, 80)
		if not valid: return {"ok": false, "status": "invalid_native_result"}
		if value == null: unavailable.append(field)
		else: values[field] = int(value) if value is int or value is float else value
	return {"ok": true, "status": "measured", "simulated": false, "values": values, "unavailable": unavailable}
