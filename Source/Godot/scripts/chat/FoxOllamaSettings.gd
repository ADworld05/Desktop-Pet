extends Node
var view:Node
var window:Window
var note:Label
var slots:Dictionary={}
var limits:Dictionary={}
var profile:OptionButton
var thinking:CheckBox
var seen_catalog:=-1
var model_tag:LineEdit
var manager_note:Label
var removal:ConfirmationDialog
var pending_remove:=""
var category_name:LineEdit
var host_info:Label
var host_picker:FileDialog
var host_selection:="store"
func initialize(owner_view:Node) -> void:
	view=owner_view;window=Window.new();window.title="Desktop Pet — Local AI";window.size=Vector2i(540,720);window.visible=false;window.force_native=true;window.borderless=false;window.transient=false;window.popup_window=false;window.minimize_disabled=false;window.unresizable=false;window.min_size=Vector2i(540,620);window.theme=view.window.theme;add_child(window);window.close_requested.connect(window.hide)
	var panel:=PanelContainer.new();panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);panel.add_theme_stylebox_override("panel",view.box(Color("#f0f5fa"),16));window.add_child(panel)
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;panel.add_child(scroll)
	var column:=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.add_theme_constant_override("separation",8);scroll.add_child(column)
	var header:=HBoxContainer.new();column.add_child(header)
	var title:=Label.new();title.text="Local AI";title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title);view.drag_handle(title,window)
	var minimize:Button=view.button(header,"—",func():window.mode=Window.MODE_MINIMIZED);minimize.name="MinimizeLocalAI";minimize.tooltip_text="Minimize Local AI"
	view.button(header,"×",window.hide).tooltip_text="Close Local AI"
	note=Label.new();note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(note)
	var row:=HBoxContainer.new();column.add_child(row)
	view.button(row,"Refresh / Retry",func():view.controller.provider.refresh())
	view.button(row,"Start Ollama",func():view.controller.provider.start_ollama())
	view.button(row,"Unload",func():view.controller.stop();view.controller.provider.unload())
	host_info=Label.new();host_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(host_info)
	var host_row:=HBoxContainer.new();column.add_child(host_row)
	view.button(host_row,"Choose Ollama…",func():choose_host("executable"))
	view.button(host_row,"Choose model folder…",func():choose_host("store"))
	host_picker=FileDialog.new();preload("res://scripts/FoxFileDialogs.gd").configure(host_picker);host_picker.access=FileDialog.ACCESS_FILESYSTEM;window.add_child(host_picker)
	host_picker.file_selected.connect(apply_host);host_picker.dir_selected.connect(apply_host)
	model_tag=LineEdit.new();model_tag.placeholder_text="Ollama tag, e.g. namespace/model:tag";column.add_child(model_tag)
	var manage:=HBoxContainer.new();column.add_child(manage)
	view.button(manage,"Install model",func():start_management(false))
	view.button(manage,"Remove model…",func():
		pending_remove=model_tag.text.strip_edges()
		if not view.controller.provider.catalog.has(pending_remove):view.controller.provider.manager.status="Choose an installed model tag first";return
		removal.dialog_text="Remove local model %s? Its weights will be deleted. Chats and memory stay."%pending_remove;removal.popup_centered(Vector2i(440,180)))
	view.button(manage,"Cancel download",func():view.controller.provider.manager.cancel())
	manager_note=Label.new();manager_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(manager_note)
	var category_row:=HBoxContainer.new();column.add_child(category_row)
	category_name=LineEdit.new();category_name.placeholder_text="Category, e.g. CODING";category_name.size_flags_horizontal=Control.SIZE_EXPAND_FILL;category_row.add_child(category_name)
	view.button(category_row,"Assign tag",func():
		var provider:RefCounted=view.controller.provider
		provider.manager.status="Category saved" if provider.map_model(category_name.text.strip_edges().to_upper(),model_tag.text.strip_edges()) else "Use an installed tag and category letters/numbers/underscore")
	removal=ConfirmationDialog.new();removal.title="Confirm model removal";removal.theme=window.theme;window.add_child(removal)
	removal.confirmed.connect(func():model_tag.text=pending_remove;start_management(true))
	for slot in ["FAST","BALANCED","SLOW","ALTERNATIVE"]:
		var line:=HBoxContainer.new();column.add_child(line)
		var label:=Label.new();label.text=slot;label.custom_minimum_size.x=70;line.add_child(label)
		var choice:=OptionButton.new();choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL;line.add_child(choice);slots[slot]=choice
		choice.item_selected.connect(func(index):view.controller.stop("Mapping changed");view.controller.provider.map_model(slot,str(choice.get_item_metadata(index)));view.controller.changed.emit())
	for item in [["context","Context tokens",2048,4096,2048],["reply","Reply tokens",256,512,128],["deadline","Total deadline (s)",60,300,30],["keep_alive","Keep model loaded (s)",0,300,30]]:
		var line:=HBoxContainer.new();column.add_child(line);var label:=Label.new();label.text=item[1];label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;line.add_child(label)
		var value:=SpinBox.new();value.min_value=item[2];value.max_value=item[3];value.step=item[4];line.add_child(value);limits[item[0]]=value
	profile=OptionButton.new();profile.add_item("Automatic GPU / partial offload");profile.add_item("CPU only (slower; test before choosing)");column.add_child(profile)
	thinking=CheckBox.new();thinking.text="SMART thinking (capability gated; hidden from answers)";column.add_child(thinking)
	view.button(column,"Save limits / profile",save)
	var help:=Label.new();help.text="Fixed 127.0.0.1:11434 · one generation · no preloading\nStop cancels output; Unload releases model memory.\nModels use this machine’s Ollama storage configuration.\nChats use your Windows user-data folder; full chat → History → Storage.\nIf local-only mode cannot be verified, configure your server or quit Ollama yourself, then use Start Ollama here. No shared server is stopped automatically.\nThinking-only models may use up to 1,024 additional internal tokens (1,536 total); thinking stays hidden.";help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;help.add_theme_font_size_override("font_size",13);column.add_child(help)
func open() -> void:
	view.controller.provider.refresh();refresh();var area:=DisplayServer.screen_get_usable_rect();window.position=view.host.Geometry.fit_position(view.window.position,window.size,area);window.mode=Window.MODE_WINDOWED;window.show();window.grab_focus()
func start_management(remove:bool)->void:
	var provider:RefCounted=view.controller.provider
	if provider.request!=0 or provider.control.running:provider.manager.status="Finish the current request or discovery first";return
	if provider.manager.begin(model_tag.text.strip_edges(),remove):manager_note.text=provider.manager.status
func choose_host(kind:String)->void:
	if view.controller.busy() or view.controller.provider.manager.transfer.running:manager_note.text="Finish the current operation first.";return
	host_selection=kind;host_picker.file_mode=FileDialog.FILE_MODE_OPEN_FILE if kind=="executable" else FileDialog.FILE_MODE_OPEN_DIR
	host_picker.filters=PackedStringArray(["ollama.exe ; Ollama executable"]) if kind=="executable" else PackedStringArray()
	host_picker.title="Choose existing Ollama executable" if kind=="executable" else "Choose the model folder used by your Ollama server"
	host_picker.popup_centered_ratio(.65)
func apply_host(path:String)->void:
	var discovery=preload("FoxOllamaDiscovery.gd")
	if not discovery.save_selection(host_selection,path):manager_note.text="Selection unavailable; choose an existing local folder or ollama.exe.";return
	var detected:=discovery.inspect();var provider:RefCounted=view.controller.provider
	provider.EXE=detected.executable;provider.STORE=detected.store.path;provider.refresh();refresh()
func refresh() -> void:
	var provider:RefCounted=view.controller.provider
	seen_catalog=provider.catalog_serial
	note.text=provider.state
	host_info.text="Runtime: "+(provider.EXE if not provider.EXE.is_empty() else "not found")+"\nModel folder: "+provider.STORE+"\nSelection is local to this PC. Files are never moved. The running service is not restarted."
	for slot in slots:
		var choice:OptionButton=slots[slot];choice.clear()
		for name in provider.catalog:
			var row:Dictionary=provider.catalog[name];choice.add_item(name+" · "+str(row.details.get("quantization_level","")));choice.set_item_metadata(choice.item_count-1,name)
			if name==provider.prefs[slot]:choice.select(choice.item_count-1)
		choice.disabled=choice.item_count==0
	for key in limits:limits[key].value=provider.prefs[key]
	profile.select(1 if provider.prefs.profile=="cpu" else 0)
	thinking.button_pressed=provider.prefs.smart_thinking
	thinking.disabled=not "thinking" in provider.catalog.get(provider.prefs.SMART,{}).get("capabilities",[])
	thinking.tooltip_text="Selected SMART model has no thinking capability" if thinking.disabled else "Thinking is never shown or saved as answer text"
func _process(_delta:float) -> void:
	if window and window.visible:
		manager_note.text=view.controller.provider.manager.status
		if seen_catalog!=view.controller.provider.catalog_serial:refresh()
		note.text=view.controller.provider.state
func save() -> void:
	view.controller.stop("Settings changed");var provider:RefCounted=view.controller.provider
	for key in limits:provider.prefs[key]=roundi(limits[key].value)
	provider.prefs.profile="cpu" if profile.selected==1 else "automatic";provider.prefs.smart_thinking=thinking.button_pressed
	note.text="Saved" if provider.save() else "Settings could not be saved"
