extends RefCounted
## Revocation must not resurrect via a permissive backup. Corruption => empty deny-all.
const Policy = preload("res://scripts/actions/FoxActionPolicy.gd")
const Atomic = preload("res://scripts/chat/FoxHistoryAtomic.gd")
const MAX_BYTES := 32768
var policy: RefCounted
var path := ""
var status := "missing"
var writable := true

func _init(host_policy: RefCounted, app_owned_path: String) -> void:
	policy = host_policy; path = app_owned_path

func load_local() -> void:
	policy.configure_from_user_selection({"version": 1, "roots": [], "apps": []})
	status = "missing"; writable = true
	if not FileAccess.file_exists(path): return
	var file := FileAccess.open(path, FileAccess.READ)
	if not file: status = "unreadable"; writable = false; return
	if file.get_length() > MAX_BYTES: file.close(); status = "oversize"; writable = false; return
	var bytes := file.get_buffer(file.get_length()); file.close()
	if bytes.has(0) or bytes.get_string_from_utf8().to_utf8_buffer() != bytes: status = "invalid_utf8"; writable = false; return
	var parser := JSON.new()
	if parser.parse(bytes.get_string_from_utf8()) != OK: status = "invalid_json"; writable = false; return
	var raw: Variant = parser.data
	var result: Dictionary = policy.configure_from_user_selection(raw)
	if not result.ok: status = "invalid_or_unavailable"; writable = false; return
	status = "ok"

func save_user_selection(raw: Dictionary) -> Dictionary:
	if not writable: return {"ok": false, "reason": "preserved_unavailable_configuration"}
	var probe := Policy.new()
	var checked := probe.configure_from_user_selection(raw)
	if not checked.ok: return checked
	var text := JSON.stringify(raw) + "\n"
	if text.to_utf8_buffer().size() > MAX_BYTES: return {"ok": false, "reason": "configuration_oversize"}
	var error := Atomic.replace(path, text)
	if error != OK: return {"ok": false, "reason": "configuration_write_failed"}
	var activated: Dictionary = policy.configure_from_user_selection(raw)
	if not activated.ok:
		policy.configure_from_user_selection({"version": 1, "roots": [], "apps": []})
		status = "changed_during_save"; writable = false; return activated
	status = "ok"
	return activated
