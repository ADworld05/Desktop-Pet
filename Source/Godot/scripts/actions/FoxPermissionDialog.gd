extends ConfirmationDialog
## Direct UI confirmation only. Display exact saved action; no model-authored instructions.
signal decision(review_id: String, approval_token: String)
var _policy: RefCounted
var _review := ""
var _description: TextEdit

func initialize(host_policy: RefCounted) -> void:
	_policy = host_policy; title = "Review fox action · Mock only"
	min_size = Vector2i(460, 260); get_ok_button().text = "Approve mock"
	for button in [get_ok_button(), get_cancel_button()]:
		for color in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]: button.add_theme_color_override(color, Color("20364e"))
	_description = TextEdit.new(); _description.editable = false
	_description.custom_minimum_size = Vector2(430, 220)
	_description.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_description.add_theme_color_override("font_readonly_color", Color("20364e"))
	_description.add_theme_font_size_override("font_size", 15)
	add_child(_description)
	var background := StyleBoxFlat.new(); background.bg_color = Color("f0f6fc"); background.set_corner_radius_all(10)
	add_theme_stylebox_override("panel", background)
	_description.add_theme_stylebox_override("read_only", background)
	confirmed.connect(_approve); canceled.connect(_cancel); close_requested.connect(_cancel)

func present(preview: Dictionary) -> void:
	if not preview.get("ok", false): return
	if not _review.is_empty(): _cancel()
	_review = preview.review_id
	var details: Dictionary = preview.request.arguments.duplicate(true); details.erase("path")
	_description.text = "Mock review: no Windows action will be performed.\n\nAction: " + preview.request.tool + " · " + preview.risk + "\nTarget: " + str(preview.target) + "\nLimits: " + JSON.stringify(details) + "\n\nApproval lasts 60 seconds, applies once to this exact request, and is cancelled if the target changes."
	popup_centered(Vector2i(480, 290))

func _approve() -> void:
	var review := _review; _review = ""
	if review.is_empty(): return
	decision.emit(review, _policy.approve_from_user(review))

func _cancel() -> void:
	var review := _review; _review = ""
	if review.is_empty(): return
	_policy.cancel_from_user(review); decision.emit(review, "")

func _exit_tree() -> void:
	if _policy and not _review.is_empty(): _policy.cancel_from_user(_review)
