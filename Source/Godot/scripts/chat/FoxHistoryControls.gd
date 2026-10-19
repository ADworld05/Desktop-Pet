extends Node
var view:Node
var window:Window
var info:Label
var sessions:SpinBox
var megabytes:SpinBox
var notice:Label
func initialize(owner_view:Node) -> void:
	view=owner_view;window=Window.new();window.title="Desktop Fox — History storage";window.size=Vector2i(500,480);window.min_size=Vector2i(480,440);window.visible=false;window.force_native=true;window.borderless=false;window.transient=false;window.popup_window=false;window.minimize_disabled=false;window.theme=view.window.theme;add_child(window);window.close_requested.connect(window.hide)
	var panel:=PanelContainer.new();panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);panel.add_theme_stylebox_override("panel",view.box(Color("#f0f5fa"),16));window.add_child(panel)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",10);panel.add_child(column)
	var header:=HBoxContainer.new();column.add_child(header);var title:=Label.new();title.text="Saved chats";title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title.add_theme_font_size_override("font_size",20);header.add_child(title);view.drag_handle(title,window)
	view.button(header,"—",func():window.mode=Window.MODE_MINIMIZED).tooltip_text="Minimize history storage"
	view.button(header,"×",window.hide).tooltip_text="Close history storage"
	info=Label.new();info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(info)
	sessions=field(column,"Review after this many chats",20,1000,1)
	megabytes=field(column,"Storage ceiling (MB)",16,512,1)
	view.button(column,"Save limits",save_limits)
	view.button(column,"Import previous data…",import_previous)
	notice=Label.new();notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;notice.add_theme_font_size_override("font_size",13);column.add_child(notice)
	var help:=Label.new();help.text="No chats are deleted automatically. New Chat and app launch start a fresh conversation; History restores older chats.\n\nFiles and recovery copies stay in your Windows user-data folder. They contain chat text and are not encrypted.";help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;help.add_theme_font_size_override("font_size",13);column.add_child(help)
func field(parent:Node,label:String,minimum:int,maximum:int,step:int) -> SpinBox:
	var row:=HBoxContainer.new();parent.add_child(row);var text:=Label.new();text.text=label;text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(text)
	var input:=SpinBox.new();input.min_value=minimum;input.max_value=maximum;input.step=step;row.add_child(input);return input
func refresh() -> void:
	var store:RefCounted=view.controller.history_store
	info.text="%d saved chats · %.2f MB including recovery copies\nWindows user-data / History"%[store.entries.size(),float(store.storage_bytes())/1000000.0]
	sessions.value=store.settings.session_limit;megabytes.value=store.settings.storage_mb;notice.text=store.status
func open() -> void:
	refresh();window.position=view.host.Geometry.fit_position(view.window.position,window.size,DisplayServer.screen_get_usable_rect());window.mode=Window.MODE_WINDOWED;window.show();window.grab_focus()
func save_limits() -> void:
	view.controller.history_store.save_settings(roundi(sessions.value),roundi(megabytes.value));refresh()

func import_previous()->void:
	view.controller.stop("Reviewing data import")
	if not view.controller.flush_history():notice.text="Save the current chat before importing.";return
	var setup:=preload("res://scripts/settings/FoxFirstRun.gd").new()
	await setup.run(view)
	view.controller.use_history(view.controller.history_store)
	view.controller.memory_store.open();refresh()
