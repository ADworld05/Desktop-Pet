extends RefCounted
const Paths=preload("res://scripts/Paths.gd")
const Migration=preload("FoxDataMigration.gd")
signal finished
var window:Window
var status:Label
var review:Dictionary={}
var import_button:Button
var picker:FileDialog

static func marker()->String:return Paths.directory("config").path_join("first_run.json")
static func missing_assets()->Array[String]:
	var missing:Array[String]=[]
	for relative in ["Models/fox.glb.bin","Animations/animation_manifest.json","Animations/T06_core_library_M3.tres","Animations/T07_personality_library_M1.tres","Animations/T07_event_library_M1.tres","Animations/T11_rest_library_M2.tres","Animations/T11_rest_manifest_M2.json","Audio/pet_chirp.wav.bin","Audio/pet_result.wav.bin","Audio/ui_tap.wav.bin"]:
		var path:=Paths.ASSET_ROOT.path_join(relative)
		if not FileAccess.file_exists(path) and not ResourceLoader.exists(path):missing.append(relative)
	return missing

func run(host:Node)->void:
	window=Window.new();window.visible=false;window.title="Desktop Pet — First launch";window.size=Vector2i(540,520);window.min_size=Vector2i(320,300);window.force_native=true;window.transient=false;window.minimize_disabled=false;window.keep_title_visible=true
	host.add_child(window)
	var theme:=Theme.new();theme.default_font_size=16
	for type in ["Label","Button"]:theme.set_color("font_color",type,Color("24384e"))
	theme.set_color("font_disabled_color","Button",Color("63768a"))
	var button_style:=StyleBoxFlat.new();button_style.bg_color=Color("dce8f3");button_style.set_content_margin_all(10);button_style.set_corner_radius_all(7)
	for state in ["normal","hover","pressed","focus"]:theme.set_stylebox(state,"Button",button_style)
	window.theme=theme
	var panel:=PanelContainer.new();panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);var bg:=StyleBoxFlat.new();bg.bg_color=Color("f0f5fa");bg.set_content_margin_all(18);panel.add_theme_stylebox_override("panel",bg);window.add_child(panel)
	var outer:=VBoxContainer.new();outer.add_theme_constant_override("separation",12);panel.add_child(outer)
	var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;outer.add_child(scroll)
	var column:=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.add_theme_constant_override("separation",12);scroll.add_child(column)
	var title:=Label.new();title.text="Welcome to Desktop Pet";title.add_theme_font_size_override("font_size",22);column.add_child(title)
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(status)
	var discovery:=preload("res://scripts/chat/FoxOllamaDiscovery.gd").inspect()
	var assets:=missing_assets()
	status.text="Data folder is writable:\n"+Paths.RUNTIME_ROOT+"\n\nGraphics: "+RenderingServer.get_current_rendering_method()+"\nRuntime assets: "+("ready" if assets.is_empty() else "missing: "+", ".join(assets))+"\n\n"+("Ollama found. Local AI will check the service and installed models. If none are available, install just one model in Local AI." if not discovery.executable.is_empty() else "Ollama installation not found in standard locations/PATH. The fox still works without AI. Install Ollama separately from ollama.com when ready, then use Local AI → Refresh.")+"\n\nYou may copy old chats, memory and settings now. Originals stay untouched. Permissions and model preferences are not transferred."
	var choose:=Button.new();choose.text="Choose previous Runtime folder…";column.add_child(choose)
	import_button=Button.new();import_button.text="Copy reviewed files";import_button.disabled=true;column.add_child(import_button)
	var proceed:=Button.new();proceed.text="Continue to fox";proceed.disabled=not assets.is_empty();outer.add_child(proceed)
	picker=FileDialog.new();preload("res://scripts/FoxFileDialogs.gd").configure(picker);picker.access=FileDialog.ACCESS_FILESYSTEM;picker.file_mode=FileDialog.FILE_MODE_OPEN_DIR;picker.title="Select the previous Runtime data folder";window.add_child(picker)
	choose.pressed.connect(func():picker.popup_centered_ratio(.65))
	picker.dir_selected.connect(func(path:String):
		review=Migration.plan(path);import_button.disabled=not review.get("ok",false) or review.get("entries",[]).is_empty()
		status.text=("Ready to copy %d files (%.2f MB). %d invalid/existing files skipped. No overwrites, model files or permissions.\n\nClick Copy reviewed files to proceed."%[review.entries.size(),float(review.bytes)/1000000,review.skipped]) if review.get("ok",false) else str(review.get("error","Folder unavailable")))
	import_button.pressed.connect(func():
		var result:=Migration.copy_reviewed(review);status.text=("Copied %d files. Originals remain untouched. Continue to load these settings and chats."%result.copied) if result.get("ok",false) else str(result.get("error","Import failed"));import_button.disabled=true)
	proceed.pressed.connect(_finish)
	window.close_requested.connect(func():
		if assets.is_empty():_finish()
		else:host.get_tree().quit(1))
	var area:=DisplayServer.screen_get_usable_rect();window.size=window.size.min(area.size-Vector2i(32,64));window.position=area.position+(area.size-window.size)/2;window.show();window.grab_focus()
	await finished
	window.queue_free()

func _finish()->void:
	var file:=FileAccess.open(marker(),FileAccess.WRITE)
	if file!=null:file.store_string('{"version":1}\n');file.close()
	finished.emit()
