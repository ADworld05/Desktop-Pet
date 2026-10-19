extends Node
## One serialized worker owns policy/store. The UI receives detached snapshots only.
signal completed(kind: String, result: Dictionary)
const Policy = preload("res://scripts/actions/FoxActionPolicy.gd")
const Store = preload("res://scripts/actions/FoxPermissionStore.gd")
const Runtime = preload("res://scripts/actions/FoxActionRuntime.gd")
const Schema = preload("res://scripts/actions/FoxActionSchema.gd")
var _policy: RefCounted
var _store: RefCounted
var _thread: Thread
var _mutex := Mutex.new()
var _generation := 0
var _job_generation := 0
var _job_kind := ""
var _closing := false
var _intent := ""
var _request := {}
var _review := ""
var state := {"configuration": {"version": 1, "roots": [], "apps": []}, "status": "loading", "writable": false}

func initialize(config_path: String, audit_path: String) -> void:
	_policy = Policy.new(audit_path); _store = Store.new(_policy, config_path)
	_policy._live_system_information = true # Fixed host capability; no request/model flag.
	_policy._live_text_read = true # Still requires scope, exact per-read approval and handle checks.
	_policy._live_scoped_actions = true # Fixed finite adapters; production selections remain empty.
	_policy._live_window_actions = true
	set_process(false)

func busy() -> bool:
	return _thread != null

func offer_untrusted_candidate(raw: Variant) -> Dictionary:
	# No intent, permission, grant, thread job or execution is created here.
	var checked := Schema.validate(raw)
	return {"ok": checked.ok, "requires_direct_user_selection": true, "executed": false}

func submit_from_ui(kind: String, data: Dictionary = {}) -> bool:
	if _closing or busy() or not kind in ["load", "validate", "save", "audit", "windows", "prepare", "one_time", "confirm", "cancel"]: return false
	_thread = Thread.new(); _job_kind = kind
	_mutex.lock(); _job_generation = _generation; _mutex.unlock()
	var error := _thread.start(_work.bind(kind, data.duplicate(true), _job_generation))
	if error != OK: _thread = null; completed.emit(kind, {"ok": false, "reason": "worker_unavailable"}); return false
	set_process(true); return true

func cancel_from_ui() -> void:
	if _closing: return
	_mutex.lock(); _generation += 1; _mutex.unlock()
	if ClassDB.class_has_method("FoxPathBoundary", "cancel_search"): ClassDB.class_call_static("FoxPathBoundary", "cancel_search")
	if not busy(): submit_from_ui("cancel")

func _current(generation: int) -> bool:
	_mutex.lock(); var current := generation == _generation; _mutex.unlock(); return current

func _work(kind: String, data: Dictionary, generation: int) -> Dictionary:
	if not _current(generation): return {"ok": false, "reason": "cancelled", "executed": false}
	var result: Dictionary = {}
	match kind:
		"load":
			_store.load_local(); result = {"ok": true}
		"validate":
			result = Policy.new().configure_from_user_selection(data)
		"save":
			result = _store.save_user_selection(data)
		"audit":
			result = _policy.audit.read_recent()
		"windows":
			result = _policy.list_windows_from_user(str(data.get("app_id", "")))
		"prepare":
			_policy.cancel_all_from_user(); _review = ""; _intent = ""
			var checked := Schema.validate(data)
			if not checked.ok: result = {"ok": false, "reason": checked.reason}
			else:
				_request = checked.request; _intent = _policy.begin_user_intent(_request)
				if _request.tool == "close_application": _policy.select_verified_window_from_user(_request.arguments.window_id)
				result = _policy.prepare(_request, _intent)
				if result.get("reason") == "outside_selected_roots" or (result.get("reason") == "root_not_selected" and _request.tool == "find_file" and _request.arguments.root_id == "one_time"):
					# Prepare consumes denied intents; retain a fresh intent for an exact one-time review.
					_intent = _policy.begin_user_intent(_request)
					result.needs_one_time_selection = not _intent.is_empty()
				if result.get("ok", false): _review = result.review_id
		"one_time":
			if not Schema.exact_keys(data, ["folder"]) or not data.folder is String: result = {"ok": false, "reason": "scope_schema"}
			else:
				result = _policy.approve_one_time_area_from_user(_request, _intent, data.folder)
				if result.ok:
					result = _policy.prepare(_request, _intent)
					if result.ok: _review = result.review_id
		"confirm":
			if not _current(generation): result = {"ok": false, "reason": "cancelled", "executed": false}
			else: result = _policy.dispatch_authorized(_review, _policy.approve_from_user(_review))
			_review = ""; _intent = ""
		"cancel":
			_policy.cancel_all_from_user(); _review = ""; _intent = ""; result = {"ok": true, "status": "cancelled_no_execution", "executed": false}
	if not _current(generation):
		_policy.cancel_all_from_user(); _review = ""; _intent = ""
		var performed: bool = result.get("executed", false)
		result = {"ok": false, "reason": "cancelled_result_discarded" if performed else "cancelled", "executed": performed, "access_attempted": result.get("access_attempted", false)}
	result.state = {"configuration": _policy.configuration(), "status": _store.status, "writable": _store.writable, "safety": Runtime.safety()}
	return result

func _process(_delta: float) -> void:
	if _thread == null or _thread.is_alive(): return
	var result: Dictionary = _thread.wait_to_finish(); _thread = null; set_process(false)
	if result.has("state"): state = result.state.duplicate(true)
	completed.emit(_job_kind, result)

func _exit_tree() -> void:
	_closing = true
	_mutex.lock(); _generation += 1; _mutex.unlock()
	if ClassDB.class_has_method("FoxPathBoundary", "cancel_search"): ClassDB.class_call_static("FoxPathBoundary", "cancel_search")
	if _thread != null: _thread.wait_to_finish(); _thread = null
