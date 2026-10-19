extends Control
const Paths = preload("res://scripts/Paths.gd")
@onready var status_label: Label = $Margin/Content/Status

func _ready() -> void:
	Engine.max_fps = 30
	var result := Paths.prepare_runtime()
	if result == OK:
		result = Paths.write_startup_record()
	if result == OK:
		status_label.text = "Bootstrap ready\nRuntime data: " + Paths.RUNTIME_ROOT
		print("BOOTSTRAP_READY runtime_root=" + Paths.RUNTIME_ROOT)
	else:
		status_label.text = "Windows user-data folder is unavailable or unwritable.\nCheck access and restart.\nError: " + error_string(result)
		push_error("BOOTSTRAP_STORAGE_ERROR: " + error_string(result))
	$Margin/Content/Quit.pressed.connect(get_tree().quit)
	var args := OS.get_cmdline_user_args()
	if "--bootstrap-preview" in args:
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var preview_result := image.save_png(Paths.directory("cache").path_join("bootstrap_preview.png"))
		print("BOOTSTRAP_PREVIEW result=" + error_string(preview_result))
	if "--bootstrap-test" in args:
		get_tree().quit(0 if result == OK else 1)

