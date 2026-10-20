extends VBoxContainer
const Policy = preload("res://scripts/actions/FoxActionPolicy.gd")
const Store = preload("res://scripts/actions/FoxPermissionStore.gd")
const Schema = preload("res://scripts/actions/FoxActionSchema.gd")
const Service = preload("res://scripts/actions/FoxActionService.gd")
const Review = preload("res://scripts/actions/FoxActionReview.gd")
var service: Node
var action_review: Window
var audit_window: Window
var audit_text: TextEdit
var _validation_pending := {}
var _validation_input := ""
var policy: RefCounted
var store: RefCounted
var staged := {"version": 1, "roots": [], "apps": []}
var paths: ItemList
var applications: ItemList
var path_input: LineEdit
var status: Label
var confirm: ConfirmationDialog
var picker: FileDialog
var applying := false
var _pending: Dictionary = {}
var _selection_summary: TextEdit

func initialize(app_owned_config: String = "", app_owned_audit: String = "") -> void:
	if app_owned_config.is_empty(): app_owned_config=preload("res://scripts/Paths.gd").directory("machine_config").path_join("permissions.json")
	if app_owned_audit.is_empty(): app_owned_audit=preload("res://scripts/Paths.gd").directory("logs").path_join("actions.jsonl")
	name = "PermissionControls"; add_theme_constant_override("separation", 7)
	service = Service.new(); add_child(service); service.initialize(app_owned_config, app_owned_audit)
	policy = service._policy; store = service._store
	service.completed.connect(_completed)
	var header := Label.new(); header.text = "Permissions"; header.add_theme_font_size_override("font_size", 18); add_child(header)
	var help := Label.new(); help.text = "Choose folders and apps here. Empty lists allow no file/app access. System information, approved text reads, filename search and app/folder/reveal actions are available. Documents use a local desktop association; close preserves save prompts. File reads require separate confirmation."; help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(help)
	path_input = LineEdit.new(); path_input.name = "PermissionPath"; path_input.placeholder_text = "Paste an exact folder path or an .exe path"; path_input.max_length = 512; add_child(path_input)
	var add_row := HBoxContainer.new(); add_child(add_row)
	for entry in [["Add folder", "root"], ["Add app", "app"], ["Browse folder", "browse"]]:
		var button := Button.new(); button.text = entry[0]; button.name = "Permission_" + entry[1]; add_row.add_child(button)
		button.pressed.connect(_add.bind(entry[1]))
	var roots_label := Label.new(); roots_label.text = "Selected folders"; add_child(roots_label)
	paths = ItemList.new(); paths.name = "PermissionRoots"; paths.custom_minimum_size.y = 70; add_child(paths)
	var apps_label := Label.new(); apps_label.text = "Selected apps Â· fixed executable, no custom arguments"; add_child(apps_label)
	applications = ItemList.new(); applications.name = "PermissionApps"; applications.custom_minimum_size.y = 60; add_child(applications)
	var buttons := HBoxContainer.new(); add_child(buttons)
	for entry in [["Remove selected", "remove"], ["Apply permissions", "apply"], ["Revoke all", "revoke"]]:
		var button := Button.new(); button.text = entry[0]; button.name = "Permission_" + entry[1]; buttons.add_child(button); button.pressed.connect(_action.bind(entry[1]))
	var review_row := HBoxContainer.new(); add_child(review_row)
	for entry in [["Action history", "audit"], ["Review an action", "review"]]:
		var button := Button.new(); button.text = entry[0]; button.name = "Permission_" + entry[1]; review_row.add_child(button); button.pressed.connect(_action.bind(entry[1]))
	status = Label.new(); status.name = "PermissionStatus"; status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(status)
	confirm = ConfirmationDialog.new(); confirm.title = "Approve selected access"; confirm.get_ok_button().text = "Save selected access"; add_child(confirm)
	confirm.add_theme_stylebox_override("panel", _background())
	confirm.add_theme_color_override("font_color", Color("20364e"))
	_selection_summary = TextEdit.new(); _selection_summary.editable = false
	_selection_summary.custom_minimum_size = Vector2(510, 220); _selection_summary.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_selection_summary.add_theme_color_override("font_readonly_color", Color("20364e")); _selection_summary.add_theme_stylebox_override("read_only", _background()); confirm.add_child(_selection_summary)
	confirm.confirmed.connect(_save); confirm.canceled.connect(func(): _pending.clear())
	picker = FileDialog.new(); preload("res://scripts/FoxFileDialogs.gd").configure(picker); picker.access = FileDialog.ACCESS_FILESYSTEM; picker.file_mode = FileDialog.FILE_MODE_OPEN_DIR; picker.title = "Choose a permitted folder"; add_child(picker)
	picker.dir_selected.connect(func(path: String): path_input.text = path; _add("root"))
	action_review = Review.new(); add_child(action_review); action_review.initialize(service)
	_build_audit(); _refresh(); status.text = "Loading permissions on the background worker…"
	service.submit_from_ui("load")

func _build_audit() -> void:
	audit_window = Window.new(); audit_window.name = "ActionAuditWindow"; audit_window.title = "Fox action history"; audit_window.size = Vector2i(620, 400); audit_window.min_size = Vector2i(450, 300); audit_window.visible = false; audit_window.force_native = true; audit_window.transient = false; audit_window.borderless = false; audit_window.minimize_disabled = false; add_child(audit_window)
	audit_window.close_requested.connect(audit_window.hide)
	var panel := PanelContainer.new(); panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); var background := _background(); background.set_content_margin_all(12); panel.add_theme_stylebox_override("panel", background); audit_window.add_child(panel)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 8); panel.add_child(column)
	var title := Label.new(); title.text = "Recent action checks Â· local, redacted, last 256 entries"; title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; title.add_theme_color_override("font_color", Color("20364e")); column.add_child(title)
	audit_text = TextEdit.new(); audit_text.name = "ActionAuditText"; audit_text.editable = false; audit_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY; audit_text.size_flags_vertical = Control.SIZE_EXPAND_FILL; audit_text.add_theme_stylebox_override("read_only", _background()); audit_text.add_theme_color_override("font_readonly_color", Color("20364e")); column.add_child(audit_text)
	var close := Button.new(); close.text = "Close"; close.add_theme_color_override("font_color", Color("20364e")); column.add_child(close); close.pressed.connect(audit_window.hide)

func _completed(kind: String, result: Dictionary) -> void:
	if kind == "audit":
		if not result.get("ok", false): audit_text.text = "Action history is unavailable. Original logs are preserved."; return
		var lines := PackedStringArray()
		for row in result.rows: lines.append(row.utc + " UTC  Â·  " + row.action.replace("_", " ") + "\n" + row.target + "  Â·  " + row.approval.replace("_", " ") + "\n" + row.outcome.replace("_", " "))
		audit_text.text = "\n\n".join(lines) if not lines.is_empty() else "No action checks recorded yet."
		if result.skipped: audit_text.text += "\n\nInvalid log rows skipped: " + str(result.skipped)
		return
	if not kind in ["load", "validate", "save"]: return
	if not result.get("ok", false): status.text = "Not saved/added: " + str(result.get("reason", "unavailable")).replace("_", " ") + "."; return
	if kind == "validate":
		staged = _validation_pending.duplicate(true); _validation_pending.clear()
		if path_input.text == _validation_input: path_input.clear()
		_refresh(); status.text = "Selection staged. Apply permissions to review and save it."; return
	staged = service.state.configuration.duplicate(true); _refresh()
	status.text = "No file/app access selected. Choose later if you prefer." if service.state.status == "missing" else "Saved selections: " + str(staged.roots.size()) + " folders, " + str(staged.apps.size()) + " apps. All eight actions are available after scope selection and exact review."
	for name in ["Permission_apply", "Permission_revoke"]: find_child(name, true, false).disabled = not service.state.writable
	if not service.state.writable: status.text = "Saved permissions unavailable/invalid: access denied; original file preserved."
	if not service.state.safety.get("ok", false): status.text += " PC action checks require a verified non-administrator process."

func _background() -> StyleBoxFlat:
	var style := StyleBoxFlat.new(); style.bg_color = Color("f0f6fc"); style.set_corner_radius_all(10); return style

func _refresh() -> void:
	paths.clear(); applications.clear()
	for item in staged.roots: paths.add_item(item.path)
	for item in staged.apps: applications.add_item(item.path)

func _add(kind: String) -> void:
	if service.busy(): status.text = "A permission check is finishing. Try again shortly."; return
	if kind == "browse": picker.popup_centered(Vector2i(650, 430)); return
	var area := "roots" if kind == "root" else "apps"
	var proposal: Dictionary = staged.duplicate(true)
	proposal[area].append({"id": kind + "_" + Crypto.new().generate_random_bytes(6).hex_encode(), "path": path_input.text.strip_edges()})
	_validation_pending = proposal; _validation_input = path_input.text
	service.submit_from_ui("validate", proposal); status.text = "Validating the selected path on the background worker…"

func _action(action: String) -> void:
	if service.busy(): status.text = "A permission check is finishing. Try again shortly."; return
	if action == "review": action_review.popup_centered(); return
	if action == "audit": audit_text.text = "Loading…"; audit_window.popup_centered(); service.submit_from_ui("audit"); return
	if action == "remove":
		for pair in [[paths, "roots"], [applications, "apps"]]:
			var selected: PackedInt32Array = pair[0].get_selected_items()
			if not selected.is_empty(): staged[pair[1]].remove_at(selected[0])
		_refresh(); status.text = "Removal staged. Apply permissions to revoke the selected access."; return
	_pending = {"version": 1, "roots": [], "apps": []} if action == "revoke" else staged.duplicate(true)
	var lines := ["Only the selections below will be allowed. This does not approve reading any file contents or closing an app. All eight actions are available after scope selection and exact review."]
	for item in _pending.roots: lines.append("Folder: " + item.path)
	for item in _pending.apps: lines.append("App: " + item.path + " (no arguments)")
	if _pending.roots.is_empty() and _pending.apps.is_empty(): lines.append("No folders or apps: deny all access.")
	_selection_summary.text = "\n\n".join(lines); confirm.popup_centered(Vector2i(570, 300))

func _save() -> void:
	if _pending.is_empty(): return
	if not service.submit_from_ui("save", _pending): status.text = "A permission check is still finishing. Apply again shortly."; return
	_pending.clear(); status.text = "Saving your confirmed selections…"
