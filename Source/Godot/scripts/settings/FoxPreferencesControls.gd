extends VBoxContainer
var app:Node
var fields:Dictionary={}
var loading:=false
var status:Label
var startup_toggle:CheckBox
var startup_status:Label

func initialize(host:Node) -> void:
	app=host;name="PreferencesControls"
	add_theme_constant_override("separation",8)
	var title:=Label.new();title.text="Pet & window preferences";title.add_theme_font_size_override("font_size",18);add_child(title)
	for entry in [["Pet name","pet_name"],["Your name (optional)","user_name"]]:
		var field:=LineEdit.new();field.max_length=40;field.name=entry[1];fields[entry[1]]=field
		row(entry[0],field);field.text_changed.connect(func(_value):changed())
	var size:=SpinBox.new();size.name="size_percent";size.min_value=75;size.max_value=150;size.step=5;size.suffix="%";fields.size_percent=size;row("Pet size",size);size.value_changed.connect(func(_value):changed())
	var eye:=OptionButton.new();eye.name="eye_color"
	for color in app.preferences.EYE_COLORS:eye.add_item(color)
	fields.eye_color=eye;row("Eye color",eye);eye.item_selected.connect(func(_value):changed())
	app.top_toggle.reparent(self);app.taskbar_toggle.reparent(self)
	fields.topmost=app.top_toggle;fields.taskbar=app.taskbar_toggle
	app.top_toggle.toggled.connect(func(_value):changed());app.taskbar_toggle.toggled.connect(func(_value):changed())
	var pause:=CheckBox.new();pause.name="fullscreen_pause";pause.text="Pause during another app's full-screen mode";pause.tooltip_text="Off by default: the fox stays active. On: pause during full-screen, then wait 10 quiet seconds before resuming.";add_child(pause);fields.fullscreen_pause=pause;pause.toggled.connect(func(_value):changed())
	for entry in [["Glass opacity","glass_opacity"],["Background blur","glass_blur"],["Glass tint","glass_tint"]]:
		var glass:=SpinBox.new();glass.min_value=35 if entry[1]=="glass_opacity" else 0;glass.max_value=95 if entry[1]=="glass_opacity" else 100;glass.step=5;glass.suffix="%";fields[entry[1]]=glass;row(entry[0],glass);glass.value_changed.connect(func(_value):changed())
		if entry[1]=="glass_blur":glass.tooltip_text="Windows controls the Acrylic blur radius. This adjusts the frosted amount; 0 disables native background blur."
	var buttons:=HBoxContainer.new();add_child(buttons)
	for entry in [["Apply","apply"],["Restore saved","restore"],["Reset defaults","reset"]]:
		var button:=Button.new();button.text=entry[0];button.name=entry[1];buttons.add_child(button)
		button.pressed.connect(button_action.bind(entry[1]))
	status=Label.new();status.name="PreferenceStatus";status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.add_theme_font_size_override("font_size",13);add_child(status)
	var help:=Label.new();help.text="Preview these preferences, then Apply. Closing restores unsaved changes.\nMovement and Sound tabs save immediately.";help.add_theme_font_size_override("font_size",13);help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;add_child(help)
	startup_toggle=CheckBox.new();startup_toggle.text="Start Desktop Pet when I sign in (this user)";add_child(startup_toggle)
	startup_status=Label.new();startup_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;startup_status.add_theme_font_size_override("font_size",13);add_child(startup_status)
	startup_toggle.toggled.connect(set_startup)
	refresh_startup()
	var permissions := preload("res://scripts/actions/FoxPermissionControls.gd").new()
	add_child(permissions); permissions.initialize()
	host.set_meta("fox_action_review", permissions.action_review)
	restore(app.preferences.values)
	status.text="Loaded saved preferences." if app.preferences.load_status=="ok" else "Settings: "+app.preferences.load_status.replace("_"," ")+"; safe defaults or valid backup loaded."
	if app.preferences.load_status=="unsupported_version":
		find_child("apply",true,false).disabled=true;status.text="Settings use a newer version. Saving is disabled to preserve that file."

func row(label:String,field:Control) -> void:
	var container:=HBoxContainer.new();add_child(container)
	var text:=Label.new();text.text=label;text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;container.add_child(text)
	field.custom_minimum_size.x=155;container.add_child(field)

func button_action(action:String) -> void:
	match action:
		"apply":
			var error:int=app.apply_preferences(candidate())
			status.text="Saved." if error==OK else "Could not save: "+error_string(error)+". Restore saved to undo preview."
		"restore":
			restore(app.preferences.values);app.preview_preferences(candidate());status.text="Saved preferences restored."
		"reset":
			restore(app.preferences.DEFAULTS);app.preview_preferences(candidate());status.text="Defaults previewed. Choose Apply to save them."

func restore(values:Dictionary) -> void:
	loading=true
	fields.pet_name.text=values.pet_name;fields.user_name.text=values.user_name;fields.size_percent.value=values.size_percent
	fields.eye_color.select(app.preferences.EYE_COLORS.find(values.eye_color))
	for key in ["topmost","taskbar","fullscreen_pause"]:fields[key].set_pressed_no_signal(values[key])
	for key in ["glass_opacity","glass_blur","glass_tint"]:fields[key].value=values.get(key,app.preferences.DEFAULTS[key])*100
	loading=false

func candidate() -> Dictionary:
	var result:Dictionary={"pet_name":fields.pet_name.text,"user_name":fields.user_name.text,"size_percent":fields.size_percent.value,"eye_color":app.preferences.EYE_COLORS[fields.eye_color.selected],"topmost":fields.topmost.button_pressed,"taskbar":fields.taskbar.button_pressed,"fullscreen_pause":fields.fullscreen_pause.button_pressed}
	for key in ["glass_opacity","glass_blur","glass_tint"]:result[key]=fields[key].value/100.0
	return app.preferences.sanitize(result)

func changed() -> void:
	if loading:return
	app.preview_preferences(candidate());status.text="Unsaved preview. Apply to keep it."

func refresh_startup() -> void:
	var result:Dictionary=app.startup.query()
	startup_toggle.set_pressed_no_signal(result.enabled)
	startup_toggle.disabled=not result.available or result.get("conflict",false)
	var explanation:String=str(result.get("error",""))
	if explanation.is_empty():explanation="A different Desktop Pet shortcut is preserved."
	startup_status.text="Startup is %s. This switch applies immediately, with your consent. No administrator access is used."%("On" if result.enabled else "Off") if result.available and not result.get("conflict",false) else "Startup unavailable: "+explanation

func set_startup(enabled:bool) -> void:
	# Only this direct UI gesture enables startup. JSON/reset/app launch cannot.
	var result:Dictionary=app.startup.query("Enable" if enabled else "Disable")
	startup_toggle.set_pressed_no_signal(result.enabled)
	startup_status.text="Startup is %s."%("On" if result.enabled else "Off") if result.available else str(result.error)
