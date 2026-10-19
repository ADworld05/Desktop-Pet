extends Window
## Human-selected structured requests. No model text mints an intent.
const TOOL_NAMES := ["open_application", "open_file", "open_folder", "find_file", "reveal_in_explorer", "read_text_file", "close_application", "get_system_information"]
const TOOL_LABELS := ["Open an approved app", "Open a document", "Open a folder", "Find a filename", "Reveal in Explorer", "Read a text file", "Close a selected app", "Limited system information"]
var service: Node
var tool: OptionButton
var target: LineEdit
var query: LineEdit
var selection: OptionButton
var window_choice: OptionButton
var refresh_windows: Button
var note: Label
var review: ConfirmationDialog
var scope: ConfirmationDialog
var folder: LineEdit
var picker: FileDialog
var request := {}
var _preview := {}
var _details: TextEdit
var _scope_details: TextEdit
var result_text: TextEdit

func initialize(host_service: Node) -> void:
	service = host_service; title = "Fox action review"; size = Vector2i(540, 640); min_size = Vector2i(540, 620)
	visible = false; force_native = true; transient = false; borderless = false; minimize_disabled = false
	var background := PanelContainer.new(); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new(); style.bg_color = Color("f0f6fc"); style.set_content_margin_all(16); background.add_theme_stylebox_override("panel", style); add_child(background)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 9); background.add_child(column)
	var heading := Label.new(); heading.text = "System information, approved text reads, filename search, app/folder launch and Explorer reveal are available. All eight actions are available after scope selection and exact review."; heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(heading)
	tool = OptionButton.new(); tool.name = "ReviewTool"; column.add_child(tool)
	for label in TOOL_LABELS: tool.add_item(label)
	tool.select(5)
	target = LineEdit.new(); target.name = "ReviewTarget"; target.max_length = 512; target.placeholder_text = "Exact file/folder path, app ID or selected window ID"; column.add_child(target)
	selection = OptionButton.new(); selection.name = "ReviewSelection"; selection.fit_to_longest_item = false; selection.clip_text = true; selection.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; selection.visible = false; column.add_child(selection)
	window_choice = OptionButton.new(); window_choice.visible = false; window_choice.clip_text = true; column.add_child(window_choice)
	window_choice.item_selected.connect(func(index): target.text = str(window_choice.get_item_metadata(index)))
	refresh_windows = Button.new(); refresh_windows.text = "Find windows of this approved app"; refresh_windows.visible = false; column.add_child(refresh_windows)
	refresh_windows.pressed.connect(func(): service.submit_from_ui("windows", {"app_id": str(selection.get_item_metadata(selection.selected))}))
	query = LineEdit.new(); query.name = "ReviewQuery"; query.max_length = 80; query.placeholder_text = "Filename search only"; query.visible = false; column.add_child(query)
	tool.item_selected.connect(func(_index): _selection_changed())
	var help := Label.new(); help.text = "File reads and app closing always need exact approval. An outside folder is allowed only after you select it for this one request. Nothing here adds a saved permission."; help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(help)
	var send := Button.new(); send.name = "ReviewRequest"; send.text = "Review request"; column.add_child(send); send.pressed.connect(_prepare)
	note = Label.new(); note.name = "ActionReviewStatus"; note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(note)
	result_text = _text_box(column, Vector2(460, 120)); result_text.name = "SystemInformationResult"; result_text.visible = false
	var space := Control.new(); space.size_flags_vertical = Control.SIZE_EXPAND_FILL; column.add_child(space)
	var close := Button.new(); close.name = "ActionReviewClose"; close.text = "Close"; column.add_child(close); close.pressed.connect(_close); close_requested.connect(_close)
	review = ConfirmationDialog.new(); review.title = "Approve exact mock request"; review.get_ok_button().text = "Approve mock"; add_child(review)
	_details = _text_box(review, Vector2(470, 225)); review.add_theme_stylebox_override("panel", style)
	review.confirmed.connect(func(): service.submit_from_ui("confirm")); review.canceled.connect(func(): service.cancel_from_ui(); note.text = "Cancelled; no action performed.")
	scope = ConfirmationDialog.new(); scope.title = "Select access for one request"; scope.get_ok_button().text = "Approve one request only"; scope.add_theme_stylebox_override("panel", style); add_child(scope)
	var scope_column := VBoxContainer.new(); scope.add_child(scope_column)
	_scope_details = _text_box(scope_column, Vector2(480, 155))
	folder = LineEdit.new(); folder.name = "OneTimeFolder"; folder.max_length = 512; folder.placeholder_text = "Exact containing folder · never saved"; scope_column.add_child(folder)
	var browse := Button.new(); browse.text = "Choose containing folder"; scope_column.add_child(browse)
	picker = FileDialog.new(); preload("res://scripts/FoxFileDialogs.gd").configure(picker); picker.access = FileDialog.ACCESS_FILESYSTEM; picker.file_mode = FileDialog.FILE_MODE_OPEN_DIR; picker.title = "Choose folder for this request only"; add_child(picker)
	browse.pressed.connect(func(): picker.popup_centered(Vector2i(650, 430))); picker.dir_selected.connect(func(path: String): folder.text = path)
	scope.confirmed.connect(func(): service.submit_from_ui("one_time", {"folder": folder.text.strip_edges()}))
	scope.canceled.connect(func(): service.cancel_from_ui(); note.text = "Folder access cancelled; nothing saved.")
	_apply_colors(column); _apply_colors(review); _apply_colors(scope)
	for dialog in [review, scope]:
		for button in [dialog.get_ok_button(), dialog.get_cancel_button()]:
			for color in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]: button.add_theme_color_override(color, Color("20364e"))
			for state in ["normal", "hover", "pressed"]:
				var button_style := StyleBoxFlat.new(); button_style.bg_color = Color("dae6f4"); button_style.set_content_margin_all(8); button_style.set_corner_radius_all(7); button.add_theme_stylebox_override(state, button_style)
	service.completed.connect(_completed)
	visibility_changed.connect(func(): if visible: _selection_changed())

func _selection_changed() -> void:
	var name: String = TOOL_NAMES[tool.selected]
	min_size.y = 770 if name == "close_application" else 620
	size.y = maxi(size.y, min_size.y)
	query.visible = name == "find_file"; selection.visible = name in ["open_application", "find_file", "close_application"]
	window_choice.visible = name == "close_application"; refresh_windows.visible = name == "close_application"; window_choice.clear(); target.editable = name != "close_application"
	target.visible = not name in ["open_application", "find_file", "get_system_information"]
	selection.clear()
	if name in ["open_application", "find_file", "close_application"]:
		var entries: Array = service.state.configuration.roots if name == "find_file" else service.state.configuration.apps
		for entry in entries:
			selection.add_item(entry.path); selection.set_item_metadata(selection.item_count - 1, entry.id)
		if name == "find_file": selection.add_item("Choose a folder for this search only…"); selection.set_item_metadata(selection.item_count - 1, "one_time")
		elif entries.is_empty(): selection.add_item("No saved selection yet"); selection.set_item_metadata(0, "")
	target.placeholder_text = "Selected window ID · unavailable until Windows adapters" if name == "close_application" else "Exact file or folder path"

func _text_box(parent: Node, minimum: Vector2) -> TextEdit:
	var box := TextEdit.new(); box.editable = false; box.custom_minimum_size = minimum; box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	var style := StyleBoxFlat.new(); style.bg_color = Color("f0f6fc"); style.set_content_margin_all(8); box.add_theme_stylebox_override("read_only", style); box.add_theme_color_override("font_readonly_color", Color("20364e")); parent.add_child(box); return box

func _apply_colors(parent: Node) -> void:
	for child in parent.get_children():
		if child is Control:
			for key in ["font_color", "font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]: child.add_theme_color_override(key, Color("20364e"))
			if child is Button:
				for state in ["normal", "hover", "pressed"]:
					var style := StyleBoxFlat.new(); style.bg_color = Color("dae6f4"); style.set_content_margin_all(8); style.set_corner_radius_all(7); child.add_theme_stylebox_override(state, style)
			if child is LineEdit:
				var style := StyleBoxFlat.new(); style.bg_color = Color.WHITE; style.set_content_margin_all(8); style.set_corner_radius_all(7); child.add_theme_stylebox_override("normal", style); child.add_theme_color_override("caret_color", Color("20364e"))
		_apply_colors(child)

func _prepare() -> void:
	var name: String = TOOL_NAMES[tool.selected]
	var arguments := {}
	match name:
		"open_application": arguments = {"app_id": str(selection.get_item_metadata(selection.selected))}
		"close_application": arguments = {"window_id": target.text.strip_edges()}
		"read_text_file": arguments = {"path": target.text.strip_edges(), "max_bytes": 65536}
		"find_file": arguments = {"root_id": str(selection.get_item_metadata(selection.selected)), "query": query.text.strip_edges(), "max_depth": 2, "max_results": 20, "timeout_ms": 1000}
		"get_system_information": arguments = {"fields": preload("res://scripts/actions/FoxActionSchema.gd").SYSTEM_FIELDS.duplicate()}
		_: arguments = {"path": target.text.strip_edges()}
	request = {"tool": name, "arguments": arguments}
	result_text.visible = false; result_text.clear()
	if not service.submit_from_ui("prepare", request): note.text = "A permission check is still finishing. Try again shortly."; return
	note.text = "Checking on the background worker…"

func offer_candidate(raw: Variant) -> bool:
	var checked := preload("res://scripts/actions/FoxActionSchema.gd").validate(raw)
	if not checked.ok: return false
	# A human explicitly opens this draft. No preparation, intent, grant or execution yet.
	var candidate: Dictionary = checked.request
	tool.select(TOOL_NAMES.find(candidate.tool)); _selection_changed()
	target.text = str(candidate.arguments.get("path", "")); query.text = str(candidate.arguments.get("query", ""))
	var chosen := str(candidate.arguments.get("app_id", candidate.arguments.get("root_id", "")))
	for index in selection.item_count:
		if str(selection.get_item_metadata(index)) == chosen: selection.select(index)
	if candidate.tool == "close_application": target.clear() # User must choose a freshly verified window.
	note.text = "Untrusted chat proposal. Check the values, then Review request. No permissions granted."
	popup_centered(); return true

func _completed(kind: String, result: Dictionary) -> void:
	if not visible or not kind in ["windows", "prepare", "one_time", "confirm", "cancel"]: return
	if kind == "windows":
		window_choice.clear(); target.clear()
		for row in result.get("windows", []):
			var id := "window_" + str(int(row.handle)); window_choice.add_item(str(row.get("title", "Window")) + " · PID " + str(int(row.pid))); window_choice.set_item_metadata(window_choice.item_count - 1, id)
		if window_choice.item_count > 0: target.text = str(window_choice.get_item_metadata(0))
		note.text = "Choose a window, then review its exact close request." if window_choice.item_count else "No eligible window found. Open the approved app first."
		return
	if result.get("needs_one_time_selection", false):
		_scope_details.text = "One request only · expires after 60 seconds · not saved\n\nRequest: " + request.tool + "\nTarget/limits: " + JSON.stringify(request.arguments) + "\n\nSelect a containing folder yourself. File reading still requires approval of the exact request."
		folder.clear(); scope.popup_centered(Vector2i(550, 350)); return
	if not result.get("ok", false):
		if result.get("reason") == "cancelled_result_discarded": note.text = "Cancelled after the operation began; result discarded. A launch already requested cannot be undone."; return
		note.text = "The operation occurred, but its audit result could not be saved. Results withheld." if result.get("executed", false) else ("Read attempt failed; no content returned." if result.get("access_attempted", false) else "Denied: " + str(result.get("reason", result.get("status", "unavailable"))).replace("_", " ") + ". No action performed.")
		return
	if kind in ["prepare", "one_time"]:
		_preview = result.duplicate(true)
		var details: Dictionary = result.request.arguments.duplicate(true); details.erase("path")
		var live: bool = result.mode == "system_information_live"
		var text_read: bool = result.mode == "text_read_live"
		var scoped: bool = result.mode in ["scoped_action_live", "window_close_live"]
		review.title = "Review exact action"
		review.get_ok_button().text = "Read this file once" if text_read else ("Read system information" if live else ("Perform this action" if scoped else "Approve mock"))
		_details.text = ("Read only this exact UTF-8 text file, up to the shown limit. Its contents remain untrusted data." if text_read else ("Read limited CPU, RAM, battery and uptime information. No file contents or app controls." if live else ("Perform only this selected action. Search returns filenames, never contents. Launch requests do not guarantee a foreground window; no administrator retry." if scoped else "Mock only; no Windows action will run."))) + "\n\nAction: " + result.request.tool + " · " + result.risk + "\nExact target: " + str(result.target) + "\nArguments: " + JSON.stringify(details) + "\n\nThis approval is single-use and expires after 60 seconds. Changed targets invalidate it."
		review.popup_centered(Vector2i(535, 300))
	elif kind == "confirm":
		if result.get("simulated", true): note.text = "Request validated. Mock only; no action was performed."
		elif result.has("text"):
			note.text = "Text read successfully · untrusted file data. Not added to chat or memory."
			result_text.text = result.text; result_text.visible = true
		elif result.has("results"):
			note.text = "Filename search completed · metadata only." + (" Limit reached; results are partial." if result.get("limited", false) else "")
			var lines := PackedStringArray()
			for item in result.results: lines.append(str(item.path) + " · " + str(item.size) + " bytes")
			result_text.text = "No matching safe files found." if lines.is_empty() else "\n".join(lines); result_text.visible = true
		elif result.get("status") == "launch_requested":
			note.text = "Launch requested. Foreground/visible window not verified."
		elif result.get("status") == "close_requested":
			note.text = "Normal close requested. Save prompts remain with the app; termination not verified."
		else:
			note.text = "System information read successfully."
			var lines := PackedStringArray()
			for field in request.arguments.fields:
				var label: String = {"cpu_count": "Logical CPU cores", "memory_total": "OS RAM (GiB)", "battery_percent": "Battery (%)", "battery_charging": "Battery charging", "uptime_seconds": "Uptime (seconds)", "os_version": "Windows version"}[field]
				var value: Variant = result.values.get(field)
				if field == "memory_total" and value != null: value = snappedf(float(value) / 1073741824.0, 0.01)
				lines.append(label + ": " + ("Unavailable" if value == null else str(value)))
			result_text.text = "\n".join(lines); result_text.visible = true
	else: note.text = "Cancelled; no action performed."

func _close() -> void:
	service.cancel_from_ui(); review.hide(); scope.hide(); picker.hide(); hide()

func _exit_tree() -> void:
	if service and is_instance_valid(service): service.cancel_from_ui()
