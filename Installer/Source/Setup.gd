extends Control
const Core=preload("InstallCore.gd")
var core:=Core.new()
var worker:Thread
var status:RichTextLabel
var choices:Dictionary={}
var buttons:Array[Button]=[]
var action:=""
var confirmation:ConfirmationDialog
func text(parent:Node,value:String,size:int=16)->Label:
	var label:=Label.new();label.text=value;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.add_theme_font_size_override("font_size",size);parent.add_child(label);return label
func button(parent:Node,value:String,callback:Callable)->Button:
	var b:=Button.new();b.text=value;b.custom_minimum_size.y=42;b.size_flags_horizontal=Control.SIZE_EXPAND_FILL;b.pressed.connect(callback);parent.add_child(b);buttons.append(b);return b
func _ready()->void:
	get_window().title="Desktop Pet Setup"
	get_window().min_size=Vector2i(320,300)
	get_window().keep_title_visible=true
	var work:=DisplayServer.screen_get_usable_rect()
	get_window().size=Vector2i(720,760).min(work.size-Vector2i(32,64))
	get_window().position=work.position+(work.size-get_window().size)/2
	var theme:=Theme.new();var font:=SystemFont.new();font.font_names=PackedStringArray(["Segoe UI"]);theme.default_font=font;theme.default_font_size=16
	theme.set_color("font_color","Label",Color("203b54"));theme.set_color("default_color","RichTextLabel",Color("203b54"));theme.set_color("font_color","CheckBox",Color("203b54"))
	var box:=StyleBoxFlat.new();box.bg_color=Color("f7fbff");box.border_color=Color("bdcfdf");box.set_border_width_all(1);box.set_corner_radius_all(9);box.content_margin_left=14;box.content_margin_right=14;box.content_margin_top=9;box.content_margin_bottom=9
	theme.set_stylebox("normal","Button",box);var hover:=box.duplicate();hover.bg_color=Color("dfedfa");theme.set_stylebox("hover","Button",hover);theme.set_color("font_color","Button",Color("203b54"))
	# Define every state: engine defaults use white text/dark panels, which
	# become unreadable when mixed with this light setup theme.
	for type in ["Button","CheckBox"]:
		for state in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]:
			theme.set_color(state,type,Color("203b54"))
		theme.set_color("font_disabled_color",type,Color("53677a"))
		for state in ["normal","hover","pressed","hover_pressed","disabled"]:
			var surface:=box.duplicate() as StyleBoxFlat
			surface.bg_color=Color("e1e9f1") if state=="disabled" else (Color("cedff0") if state in ["pressed","hover_pressed"] else (Color("dfedfa") if state=="hover" else Color("f7fbff")))
			theme.set_stylebox(state,type,surface)
		var focus:=StyleBoxFlat.new();focus.bg_color=Color(0,0,0,0);focus.border_color=Color("326b9e");focus.set_border_width_all(2);focus.set_corner_radius_all(9);theme.set_stylebox("focus",type,focus)
	var dialog_panel:=box.duplicate() as StyleBoxFlat;dialog_panel.bg_color=Color("edf5fc")
	theme.set_stylebox("panel","AcceptDialog",dialog_panel)
	var frame:=dialog_panel.duplicate() as StyleBoxFlat;frame.expand_margin_top=36
	theme.set_stylebox("embedded_border","Window",frame)
	theme.set_stylebox("embedded_unfocused_border","Window",frame)
	theme.set_color("title_color","Window",Color("203b54"));theme.set_color("title_outline_modulate","Window",Color(0,0,0,0))
	var cross:=Image.create(18,18,false,Image.FORMAT_RGBA8);cross.fill(Color(0,0,0,0))
	for n in range(4,14):
		for offset in [-1,0,1]:
			cross.set_pixel(n,n+offset,Color("203b54"));cross.set_pixel(n,17-n+offset,Color("203b54"))
	var close_icon:=ImageTexture.create_from_image(cross)
	theme.set_icon("close","Window",close_icon);theme.set_icon("close_pressed","Window",close_icon)
	self.theme=theme
	var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+edge,28)
	add_child(margin)
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;margin.add_child(scroll)
	var column:=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.add_theme_constant_override("separation",9);scroll.add_child(column)
	text(column,"Desktop Pet",32);text(column,"Install, update or remove your local companion",18)
	var path:=PanelContainer.new();path.add_theme_stylebox_override("panel",box);column.add_child(path)
	text(path,"Application:  "+Core.DEFAULT+"\nChats and memory: %APPDATA%/DesktopFox\nMachine settings: %LOCALAPPDATA%/DesktopFox/Config",16)
	text(column,"Optional shortcuts",17)
	var saved:Dictionary=core.installed().get("shortcuts",{})
	for row in [["Desktop","Create a desktop shortcut"],["Menu","Add a Start-menu shortcut"],["Startup","Start Desktop Pet when I sign in"]]:
		var cb:=CheckBox.new();cb.text=row[1];cb.button_pressed=bool(saved.get(row[0],false));column.add_child(cb);choices[row[0]]=cb
	text(column,"Ollama and model weights are kept where they are.\nSetup does not download models or enable online services.",14)
	var row:=HFlowContainer.new();row.add_theme_constant_override("h_separation",10);column.add_child(row)
	button(row,"Install / Update",func():begin("install"))
	button(row,"Restore previous version",func():confirm("restore"))
	button(row,"Uninstall",func():confirm("uninstall"))
	status=RichTextLabel.new();status.custom_minimum_size.y=90;status.size_flags_vertical=Control.SIZE_EXPAND_FILL;status.bbcode_enabled=false;status.selection_enabled=true;column.add_child(status)
	status.text="Ready. Nothing changes until you choose an action.\nUnsigned release candidate · no administrator access required."
	var footer:=HBoxContainer.new();column.add_child(footer)
	button(footer,"Open installed pet",launch)
	button(footer,"Close",func():get_tree().quit())
	confirmation=ConfirmationDialog.new();confirmation.title="Confirm Desktop Pet change";confirmation.dialog_autowrap=true;confirmation.min_size=Vector2i(470,170);confirmation.theme=theme;add_child(confirmation)
	confirmation.confirmed.connect(func():begin(action))
	get_tree().auto_accept_quit=false;get_window().close_requested.connect(func():
		if worker:status.text="Please wait for the file operation to finish before closing."
		else:get_tree().quit())
	if OS.has_feature("editor") and "--preview" in OS.get_cmdline_user_args():preview.call_deferred()
	if OS.has_feature("editor") and "--contrast-preview" in OS.get_cmdline_user_args():contrast_preview.call_deferred()
	if OS.get_environment("FOX_SETUP_MODE")=="uninstall":confirm.call_deferred("uninstall")
func confirm(kind:String)->void:
	action=kind;confirmation.dialog_text="Remove only the installed application and its own shortcuts?\nYour chats, memory, settings and models will be kept." if kind=="uninstall" else "Restore the previous application files?\nYour chats, memory, settings and models will be kept."
	var work:=DisplayServer.screen_get_usable_rect()
	confirmation.min_size=Vector2i(300,170).min(work.size-Vector2i(32,64))
	confirmation.popup_centered(Vector2i(470,200).min(work.size-Vector2i(32,64)))
	confirmation.keep_title_visible=true
func launch()->void:
	var exe:=Core.DEFAULT+"/DesktopPet.exe"
	if not FileAccess.file_exists(exe):status.text="Install Desktop Pet first.";return
	if OS.create_process(exe,PackedStringArray(),false)<0:status.text="Could not open Desktop Pet. Check the application files."
func begin(kind:String)->void:
	if worker:return
	action=kind;var wanted:Dictionary={}
	for id in choices:wanted[id]=choices[id].button_pressed;choices[id].disabled=true
	for b in buttons:b.disabled=true
	status.text={"install":"Verifying and installing application files…","restore":"Restoring the previous application files…","uninstall":"Removing application files; keeping your data…"}.get(kind,"Working…")
	worker=Thread.new()
	var code:=worker.start(func():
		if kind=="install":
			var result:=core.install(wanted)
			if result.get("installed",false):return maintenance("Register",result)
			return result
		if kind=="restore":return core.restore()
		var result:=core.uninstall()
		if not result.ok and str(result.reason).begins_with("No recognized Desktop Pet installation") and not FileAccess.file_exists(Core.DEFAULT+"/DesktopFox.exe"):
			# Retry only maintenance cleanup after an already completed app removal.
			return maintenance("Remove",{"ok":true,"reason":"Application files are already removed. Saved data was kept."})
		return maintenance("Remove",result) if result.ok else result)
	if code!=OK:worker=null;status.text="Could not start setup operation.";unlock()
func unlock()->void:
	for b in buttons:b.disabled=false
	for cb in choices.values():cb.disabled=false
func maintenance(kind:String,result:Dictionary)->Dictionary:
	var out:Array=[]
	var helper:=OS.get_executable_path().get_base_dir()+"/DesktopFoxShortcuts.exe"
	var code:=OS.execute(helper,PackedStringArray(["Maintenance",kind]),out,true,false)
	var parsed:Variant=JSON.parse_string("\n".join(out))
	if code!=0 or not parsed is Dictionary or not parsed.get("ok",false):
		result.ok=false
		result.reason+="\nMaintenance registration/cleanup needs repair (code %s). Keep this setup file and retry. Saved data remains intact."%code
	elif parsed.get("defer_self_removal",false):
		var flag:=OS.get_environment("FOX_SETUP_CLEANUP_FLAG")
		var f:=FileAccess.open(flag,FileAccess.WRITE)
		if f:
			f.store_string("uninstall complete");f.close()
			result.reason+="\nClose setup to finish removing the maintenance launcher."
		else:
			result.ok=false;result.reason+="\nCould not schedule maintenance cleanup. Keep setup and retry."
	return result
func _process(_delta:float)->void:
	if worker and not worker.is_alive():
		var result:Dictionary=worker.wait_to_finish();worker=null;status.text=str(result.get("reason","Operation finished"))
		if result.has("rollback_ok") and not result.rollback_ok:status.text+="\nClose Desktop Pet, then choose Restore previous version."
		unlock()
func preview()->void:
	DirAccess.make_dir_recursive_absolute("user://SetupChecks")
	await get_tree().process_frame;await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://SetupChecks/setup_preview.png")
	get_tree().quit()
func contrast_preview()->void:
	DirAccess.make_dir_recursive_absolute("user://SetupChecks")
	# Visual-only state fixture. Never calls begin/core mutation methods.
	choices["Desktop"].button_pressed=true;choices["Menu"].button_pressed=true
	for state in ["selected","disabled","confirmation"]:
		if state=="disabled":
			for b in buttons:b.disabled=true
			for cb in choices.values():cb.disabled=true
			status.text="Verifying and installing application files… (visual preview only)"
		if state=="confirmation":
			unlock();confirm("uninstall")
		await get_tree().process_frame;await get_tree().process_frame;await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://SetupChecks/"+state+".png")
	get_tree().quit()
