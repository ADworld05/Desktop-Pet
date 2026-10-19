extends RefCounted
## Trusted UI calls and untrusted request data have separate entry points.
## Live capabilities are fixed by the host service; model data cannot mint intent or permissions.
const Schema = preload("res://scripts/actions/FoxActionSchema.gd")
const Paths = preload("res://scripts/actions/FoxActionPaths.gd")
const Audit = preload("res://scripts/actions/FoxActionAudit.gd")
const Dispatcher = preload("res://scripts/actions/FoxActionMockDispatcher.gd")
const Risk = preload("res://scripts/actions/FoxActionRisk.gd")
const Runtime = preload("res://scripts/actions/FoxActionRuntime.gd")
const SystemInformation = preload("res://scripts/actions/FoxSystemInformation.gd")
const TextReader = preload("res://scripts/actions/FoxTextReader.gd")
const ScopedActions = preload("res://scripts/actions/FoxScopedActions.gd")
const WindowActions = preload("res://scripts/actions/FoxWindowActions.gd")
var _live_window_actions := false
var _live_scoped_actions := false
var _live_text_read := false
var _live_system_information := false
const DOCUMENTS := ["txt", "md", "json", "pdf", "docx", "xlsx", "pptx", "png", "jpg", "jpeg", "webp"]
const TEXT_FILES := ["txt", "md", "json"]
const BLOCKED_APPS := ["cmd", "powershell", "pwsh", "wscript", "cscript", "mshta", "rundll32", "regsvr32", "reg", "python", "pythonw", "node", "bash", "sh", "wsl", "java", "dotnet", "msiexec", "schtasks", "wmic", "conhost", "wt", "windowsterminal", "git", "gcc"]
const INTENT_LIFETIME_MS := 120000
const APPROVAL_LIFETIME_MS := 60000
const MAX_PENDING := 32
var audit: RefCounted
var dispatcher := Dispatcher.new()
var _clock: Callable
var _roots: Dictionary = {}
var _apps: Dictionary = {}
var _windows: Dictionary = {}
var _window_source: Callable
var _runtime_safety: Callable
var _temporary: Dictionary = {}
var _epoch := 0
var _intents: Dictionary = {}
var _reviews: Dictionary = {}
var _approvals: Dictionary = {}
var _configuration := {"version": 1, "roots": [], "apps": []}

func _init(app_owned_audit_path: String = "", monotonic_clock: Callable = Callable(), verified_window_source: Callable = Callable(), runtime_safety: Callable = Callable()) -> void:
	audit = Audit.new(app_owned_audit_path)
	_clock = monotonic_clock
	_window_source = verified_window_source; _runtime_safety = runtime_safety

func _safe_runtime() -> bool:
	var result: Variant = _runtime_safety.call() if _runtime_safety.is_valid() else Runtime.safety()
	return result is Dictionary and result.get("ok") == true and result.get("elevated", false) == false

func cancel_all_from_user() -> void:
	_intents.clear(); _reviews.clear(); _approvals.clear(); _temporary.clear()

func _target_fingerprint(target: Dictionary) -> String:
	return _hash(target) if target.has("window_id") else Paths.fingerprint(target)

func _now() -> int:
	return int(_clock.call()) if _clock.is_valid() else Time.get_ticks_msec()

func _nonce() -> String:
	var bytes := Crypto.new().generate_random_bytes(32)
	return bytes.hex_encode() if bytes.size() == 32 else ""

func _hash(request: Dictionary) -> String:
	# Schema normalizes types and field ordering; JSON recursively sorts dictionary keys.
	return JSON.stringify(request, "", true).sha256_text()

func _cleanup() -> void:
	for table in [_intents, _reviews, _approvals, _temporary]:
		for token in table.keys():
			if table[token].expires <= _now(): table.erase(token)

func _blocked_root(path: String) -> bool:
	if path.length() < 5: return true
	var app_paths = preload("res://scripts/Paths.gd")
	var protected := [app_paths.RUNTIME_ROOT, app_paths.application_root()]
	# The checkout is protected only while developing. Release protects its own
	# installation wherever it is extracted, plus this host's configured store.
	if OS.has_feature("editor"): protected.append(app_paths.development_root())
	var model_store := OS.get_environment("OLLAMA_MODELS").replace("\\", "/").trim_suffix("/")
	if model_store.is_empty(): model_store=OS.get_environment("USERPROFILE").path_join(".ollama/models").replace("\\", "/")
	if model_store.is_absolute_path(): protected.append(model_store)
	var selected_store:=str(preload("res://scripts/chat/FoxOllamaDiscovery.gd").configuration().get("store",""))
	if selected_store.is_absolute_path():protected.append(selected_store)
	for variable in ["SystemRoot", "ProgramFiles", "ProgramFiles(x86)", "ProgramData", "LOCALAPPDATA", "APPDATA"]:
		var area := OS.get_environment(variable).replace("\\", "/")
		if not area.is_empty(): protected.append(area)
	for area in protected:
		if Paths.inside(path, area) or Paths.inside(area, path): return true
	return false

func _snapshot_equal(a: Dictionary, b: Dictionary) -> bool:
	return Paths.same_object(a, b) and Paths.fingerprint(a) == Paths.fingerprint(b)

func configure_from_user_selection(raw: Variant) -> Dictionary:
	# Only a deliberate app-owned settings selection calls this method. No memory import.
	if not raw is Dictionary or not Schema.exact_keys(raw, ["version", "roots", "apps"]) or raw.version != 1 or raw.version is bool or not raw.roots is Array or not raw.apps is Array or raw.roots.size() > 16 or raw.apps.size() > 16: return {"ok": false, "reason": "configuration_schema"}
	if (not raw.roots.is_empty() or not raw.apps.is_empty()) and not _safe_runtime(): return {"ok": false, "reason": "non_elevated_context_required"}
	var roots := {}; var apps := {}
	for item in raw.roots:
		if not item is Dictionary or not Schema.exact_keys(item, ["id", "path"]) or not Schema.identifier(item.id) or roots.has(item.id): return {"ok": false, "reason": "root_schema"}
		var resolved := Paths.resolve(item.path)
		if not resolved.ok or not resolved.directory: return {"ok": false, "reason": "root_unavailable"}
		if _blocked_root(resolved.path): return {"ok": false, "reason": "protected_or_broad_root"}
		for existing in roots.values():
			if Paths.inside(resolved.path, existing.path) or Paths.inside(existing.path, resolved.path): return {"ok": false, "reason": "overlapping_roots"}
		roots[item.id] = resolved
	for item in raw.apps:
		if not item is Dictionary or not Schema.exact_keys(item, ["id", "path"]) or not Schema.identifier(item.id) or apps.has(item.id): return {"ok": false, "reason": "app_schema"}
		var resolved := Paths.resolve_application(item.path)
		if not resolved.ok or resolved.directory or resolved.path.get_extension().to_lower() != "exe": return {"ok": false, "reason": "app_unavailable"}
		var base: String = resolved.path.get_file().get_basename().to_lower()
		if base in BLOCKED_APPS or base.begins_with("python") or base.begins_with("powershell"): return {"ok": false, "reason": "blocked_interpreter"}
		apps[item.id] = resolved
	_roots = roots; _apps = apps; _configuration = raw.duplicate(true)
	_epoch += 1; cancel_all_from_user(); _windows.clear()
	return {"ok": true, "mode": "mock_only", "roots": roots.size(), "apps": apps.size()}

func configuration() -> Dictionary:
	return _configuration.duplicate(true)

func begin_user_intent(raw: Variant) -> String:
	# Called by a direct user operation, NEVER by model/history/memory callbacks.
	_cleanup()
	var checked := Schema.validate(raw)
	if not checked.ok or _intents.size() >= MAX_PENDING or not _safe_runtime(): return ""
	var token := _nonce()
	if token.is_empty(): return ""
	_intents[token] = {"hash": _hash(checked.request), "epoch": _epoch, "expires": _now() + INTENT_LIFETIME_MS}
	return token

func approve_one_time_area_from_user(raw: Variant, intent_token: String, selected_folder: String) -> Dictionary:
	_cleanup()
	var checked := Schema.validate(raw)
	if not checked.ok or not _safe_runtime(): return {"ok": false, "reason": "request_or_runtime_denied"}
	if not _intents.has(intent_token) or _intents[intent_token].hash != _hash(checked.request): return {"ok": false, "reason": "trusted_user_intent_required"}
	if not checked.request.arguments.has("path") and not (checked.request.tool == "find_file" and checked.request.arguments.root_id == "one_time"): return {"ok": false, "reason": "one_time_folder_tools_only"}
	var root := Paths.resolve(selected_folder)
	if not root.ok or not root.directory or _blocked_root(root.get("path", "")): return {"ok": false, "reason": "selected_folder_denied"}
	if checked.request.arguments.has("path"):
		var lexical := Paths.lexical(checked.request.arguments.path)
		if not lexical.ok or not Paths.inside(lexical.path, root.path): return {"ok": false, "reason": "target_outside_one_time_folder"}
	_temporary[intent_token] = {"root": root, "hash": _hash(checked.request), "epoch": _epoch, "expires": mini(_now() + APPROVAL_LIFETIME_MS, _intents[intent_token].expires)}
	return {"ok": true, "scope": "one_request_only", "folder": root.path, "expires_in_ms": APPROVAL_LIFETIME_MS, "persistent": false}

func _verified_window(window_id: String) -> Dictionary:
	if not _window_source.is_valid() and not _live_window_actions: return {"ok": false, "reason": "verified_window_adapter_unavailable"}
	var raw: Variant = _window_source.call(window_id) if _window_source.is_valid() else WindowActions.query(window_id, _apps)
	if not raw is Dictionary or not Schema.exact_keys(raw, ["ok", "window_id", "app_id", "pid", "handle", "started", "owner", "session", "path", "visible"]) or raw.ok != true or raw.window_id != window_id or not Schema.identifier(raw.app_id) or not _apps.has(raw.app_id) or not Schema.bounded_integer(raw.pid, 1, 4294967295) or not Schema.bounded_integer(raw.handle, 1, 9007199254740991) or not Schema.text(raw.started, 1, 80) or not Schema.text(raw.owner, 1, 120) or not Schema.bounded_integer(raw.session, 0, 65535) or raw.visible != true: return {"ok": false, "reason": "window_identity_unverified"}
	var executable := Paths.resolve_application(raw.path)
	if not _snapshot_equal(executable, _apps[raw.app_id]): return {"ok": false, "reason": "window_app_mismatch"}
	var result: Dictionary = raw.duplicate(true); result.path = executable.path; result.exe_identity = executable.identity
	return result

func select_verified_window_from_user(window_id: String) -> Dictionary:
	if not Schema.identifier(window_id) or not _safe_runtime(): return {"ok": false, "reason": "window_selection_denied"}
	var checked := _verified_window(window_id)
	if not checked.ok: return checked
	_windows[window_id] = checked
	return {"ok": true, "window_id": window_id, "mode": "mock_only"}

func list_windows_from_user(app_id: String) -> Dictionary:
	if not _live_window_actions or not _apps.has(app_id) or not _safe_runtime(): return {"ok": false, "reason": "app_not_selected"}
	if not _snapshot_equal(Paths.resolve_application(_apps[app_id].path), _apps[app_id]): return {"ok": false, "reason": "app_changed"}
	return WindowActions.list_for_app(_apps[app_id])

func _summary(plan: Dictionary) -> String:
	if not plan.get("root_id", "").is_empty(): return "folder:" + plan.root_id
	if plan.request.arguments.has("app_id"): return "app:" + plan.request.arguments.app_id
	if plan.request.arguments.has("window_id"): return "window:" + plan.request.arguments.window_id
	return "limited-system-fields"

func _deny(tool: String, reason: String, summary: String = "unapproved") -> Dictionary:
	audit.record(tool, summary, "none", "denied:" + reason)
	return {"ok": false, "status": "denied", "reason": reason, "executed": false}

func _resolve_plan(request: Dictionary, intent_token: String = "", lease: Dictionary = {}) -> Dictionary:
	var a: Dictionary = request.arguments
	var roots: Dictionary = _roots.duplicate(true)
	var temporary: Dictionary = lease if not lease.is_empty() else _temporary.get(intent_token, {})
	var one_time: bool = not temporary.is_empty() and temporary.epoch == _epoch and temporary.expires > _now() and temporary.hash == _hash(request)
	if one_time: roots.one_time = temporary.root
	var plan := {"ok": true, "request": request.duplicate(true), "risk": Risk.classify(request.tool, one_time), "target": {}, "root_id": "", "epoch": _epoch, "one_time": one_time}
	if a.has("path"):
		# Check a selected lexical scope BEFORE native metadata probes outside it.
		var lexical := Paths.lexical(a.path)
		if not lexical.ok: return lexical
		var matching := ""
		for id in roots:
			if Paths.inside(lexical.path, roots[id].path): matching = id; break
		if matching.is_empty(): return {"ok": false, "reason": "outside_selected_roots"}
		var root_check := Paths.resolve(roots[matching].path)
		if not Paths.same_object(root_check, roots[matching]): return {"ok": false, "reason": "root_changed"}
		var target := Paths.resolve(a.path)
		if not target.ok: return target
		if not Paths.inside(target.path, root_check.path) or _blocked_root(target.path): return {"ok": false, "reason": "resolved_scope_escape"}
		if request.tool == "open_folder" and not target.directory: return {"ok": false, "reason": "folder_required"}
		if request.tool in ["open_file", "read_text_file"]:
			if target.directory: return {"ok": false, "reason": "file_required"}
			var extension: String = target.path.get_extension().to_lower()
			if not extension in (TEXT_FILES if request.tool == "read_text_file" else DOCUMENTS): return {"ok": false, "reason": "document_format_denied"}
		if request.tool == "read_text_file":
			plan.risk = "SENSITIVE"
			if target.size > a.max_bytes: return {"ok": false, "reason": "text_size_limit"}
		if request.tool == "reveal_in_explorer" and not target.directory and not target.path.get_extension().to_lower() in DOCUMENTS: return {"ok": false, "reason": "document_format_denied"}
		plan.target = target; plan.root_id = matching
	elif request.tool == "find_file":
		if not roots.has(a.root_id): return {"ok": false, "reason": "root_not_selected"}
		var current := Paths.resolve(roots[a.root_id].path)
		if not Paths.same_object(current, roots[a.root_id]): return {"ok": false, "reason": "root_changed"}
		plan.target = current; plan.root_id = a.root_id
	elif request.tool == "open_application":
		if not _apps.has(a.app_id): return {"ok": false, "reason": "app_not_selected"}
		var current := Paths.resolve_application(_apps[a.app_id].path)
		if not _snapshot_equal(current, _apps[a.app_id]): return {"ok": false, "reason": "app_changed"}
		plan.target = current
	elif request.tool == "close_application":
		if not _windows.has(a.window_id): return {"ok": false, "reason": "verified_window_adapter_unavailable"}
		var current := _verified_window(a.window_id)
		if not current.ok: return current
		if _hash(current) != _hash(_windows[a.window_id]): return {"ok": false, "reason": "window_identity_changed"}
		plan.target = current
	return plan

func prepare(raw: Variant, intent_token: String) -> Dictionary:
	_cleanup()
	var checked := Schema.validate(raw)
	var tool: String = raw.get("tool", "unknown") if raw is Dictionary and raw.get("tool") is String else "unknown"
	if not checked.ok: return _deny(tool, checked.reason)
	if not _safe_runtime(): return _deny(tool, "non_elevated_context_required")
	if not _intents.has(intent_token) or _intents[intent_token].epoch != _epoch or _intents[intent_token].hash != _hash(checked.request): return _deny(tool, "trusted_user_intent_required")
	var plan := _resolve_plan(checked.request, intent_token)
	if not plan.ok:
		_intents.erase(intent_token); _temporary.erase(intent_token)
		return _deny(tool, plan.reason)
	if _reviews.size() >= MAX_PENDING: return _deny(tool, "pending_limit")
	var review := _nonce()
	if review.is_empty(): return _deny(tool, "nonce_unavailable")
	plan.intent = intent_token; plan.expires = _intents[intent_token].expires
	if plan.one_time: plan.expires = mini(plan.expires, _temporary[intent_token].expires)
	plan.binding = _hash(checked.request) + ":" + str(_epoch) + ":" + (_target_fingerprint(plan.target) if not plan.target.is_empty() else "system")
	_reviews[review] = plan
	# Exact display-only preview. Dispatch reads the private saved plan, not these copies.
	var mode := "mock_only"
	if _live_system_information and checked.request.tool == "get_system_information": mode = "system_information_live"
	if _live_text_read and checked.request.tool == "read_text_file": mode = "text_read_live"
	if _live_scoped_actions and checked.request.tool in ScopedActions.TOOLS: mode = "scoped_action_live"
	if _live_window_actions and checked.request.tool == "close_application": mode = "window_close_live"
	return {"ok": true, "review_id": review, "risk": plan.risk, "confirmation_required": plan.risk == "SENSITIVE", "request": checked.request.duplicate(true), "target": plan.target.get("path", ""), "mode": mode}

func approve_from_user(review_id: String) -> String:
	_cleanup()
	if not _reviews.has(review_id) or _approvals.size() >= MAX_PENDING: return ""
	var plan: Dictionary = _reviews[review_id]
	if not _intents.has(plan.intent): return ""
	var token := _nonce()
	if token.is_empty(): return ""
	_approvals[token] = {"review": review_id, "binding": plan.binding, "expires": _now() + APPROVAL_LIFETIME_MS}
	return token

func cancel_from_user(review_id: String) -> void:
	if not _reviews.has(review_id): return
	var plan: Dictionary = _reviews[review_id]
	_reviews.erase(review_id); _intents.erase(plan.intent); _temporary.erase(plan.intent)
	for token in _approvals.keys():
		if _approvals[token].review == review_id: _approvals.erase(token)
	audit.record(plan.request.tool, _summary(plan), "cancelled", "cancelled_no_execution")

func dispatch_mock(review_id: String, approval_token: String = "") -> Dictionary:
	return _dispatch(review_id, approval_token, false)

func dispatch_authorized(review_id: String, approval_token: String = "") -> Dictionary:
	return _dispatch(review_id, approval_token, true)

func _dispatch(review_id: String, approval_token: String, allow_live: bool) -> Dictionary:
	_cleanup()
	if not _reviews.has(review_id): return _deny("unknown", "review_expired_or_consumed")
	var plan: Dictionary = _reviews[review_id]
	_reviews.erase(review_id)
	var lease: Dictionary = _temporary.get(plan.intent, {}).duplicate(true); _temporary.erase(plan.intent)
	var had_intent := _intents.has(plan.intent)
	_intents.erase(plan.intent)
	var approved := false
	if _approvals.has(approval_token):
		var approval: Dictionary = _approvals[approval_token]
		approved = approval.review == review_id and approval.binding == plan.binding
		_approvals.erase(approval_token)
	# All sibling reviews sharing this intent are unusable after the first attempt.
	if not had_intent or plan.epoch != _epoch: return _deny(plan.request.tool, "intent_expired_or_consumed", _summary(plan))
	if not _safe_runtime(): return _deny(plan.request.tool, "non_elevated_context_required", _summary(plan))
	if plan.one_time and lease.is_empty(): return _deny(plan.request.tool, "one_time_scope_consumed", _summary(plan))
	if plan.risk == "SENSITIVE" and not approved: return _deny(plan.request.tool, "exact_confirmation_required", _summary(plan))
	var fresh := _resolve_plan(plan.request, plan.intent, lease)
	if not fresh.ok: return _deny(plan.request.tool, fresh.reason, _summary(plan))
	if not plan.target.is_empty() and _target_fingerprint(fresh.target) != _target_fingerprint(plan.target): return _deny(plan.request.tool, "target_changed", _summary(plan))
	if allow_live and _live_window_actions and plan.request.tool == "close_application":
		if not audit.record(plan.request.tool, _summary(plan), "exact_user_confirmation", "close_requested"): return {"ok": false, "reason": "audit_unavailable", "executed": false}
		var closed := WindowActions.close(fresh.target)
		if not audit.record(plan.request.tool, _summary(plan), "exact_user_confirmation", "close_request_sent" if closed.ok else "close_request_denied"): return {"ok": false, "status": "audit_failed_after_action", "executed": closed.get("executed", false)}
		return closed
	if allow_live and _live_scoped_actions and plan.request.tool in ScopedActions.TOOLS:
		if not audit.record(plan.request.tool, _summary(plan), "exact_user_confirmation" if approved else "trusted_user_scope", "scoped_action_requested"): return {"ok": false, "reason": "audit_unavailable", "executed": false}
		var outcome := ScopedActions.execute(plan.request, fresh.target)
		if not audit.record(plan.request.tool, _summary(plan), "exact_user_confirmation" if approved else "trusted_user_scope", "scoped_action_completed" if outcome.ok else "scoped_action_denied"):
			return {"ok": false, "status": "audit_failed_after_action", "executed": outcome.get("executed", false), "simulated": false}
		return outcome
	if allow_live and _live_text_read and plan.request.tool == "read_text_file":
		if not audit.record(plan.request.tool, _summary(plan), "exact_user_confirmation", "text_read_requested"): return {"ok": false, "reason": "audit_unavailable", "executed": false}
		var read := TextReader.read_snapshot(fresh.target, plan.request.arguments.max_bytes)
		read.simulated = false; read.executed = read.ok; read.access_attempted = true
		if not audit.record(plan.request.tool, _summary(plan), "exact_user_confirmation", "text_read_completed" if read.ok else "text_read_denied"):
			return {"ok": false, "status": "audit_failed_after_read", "executed": read.executed, "access_attempted": true, "simulated": false}
		return read
	if allow_live and _live_system_information and plan.request.tool == "get_system_information":
		if not audit.record(plan.request.tool, _summary(plan), "exact_user_confirmation" if approved else "trusted_user_scope", "system_information_requested"): return {"ok": false, "status": "denied", "reason": "audit_unavailable", "executed": false}
		var measured := SystemInformation.collect(plan.request.arguments)
		measured.executed = measured.get("ok", false)
		var recorded: bool = audit.record(plan.request.tool, _summary(plan), "exact_user_confirmation" if approved else "trusted_user_scope", "system_information_measured" if measured.ok else "system_information_unavailable")
		if not recorded: return {"ok": false, "status": "audit_failed_after_measurement", "executed": measured.executed, "simulated": false}
		return measured
	if not audit.record(plan.request.tool, _summary(plan), "exact_user_confirmation" if approved else "trusted_user_scope", "mock_validated_no_execution"): return {"ok": false, "status": "denied", "reason": "audit_unavailable", "executed": false}
	var result := dispatcher.dispatch_validated(plan)
	# The caller cannot replace this with a model-authored success response.
	return result
