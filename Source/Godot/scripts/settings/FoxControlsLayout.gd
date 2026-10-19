extends RefCounted
static func build(app:Node,column:VBoxContainer,old_scroll:ScrollContainer)->TabContainer:
 var panel:Window=app.panel
 panel.title="Desktop Fox — Settings";panel.size=Vector2i(720,760);panel.min_size=Vector2i(560,420);panel.unresizable=false;panel.minimize_disabled=false
 panel.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;panel.content_scale_size=Vector2i.ZERO;panel.content_scale_factor=1.0
 var background:=panel.get_child(0) as ColorRect
 background.color=Color("f1f6fb")
 panel.theme=app.chat_view.window.theme.duplicate()
 for type in ["Label","Button","OptionButton","CheckBox","CheckButton","LineEdit","TextEdit","ItemList"]:
  for state in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color","font_selected_color","font_readonly_color"]:panel.theme.set_color(state,type,Color("20364e"))
  panel.theme.set_color("font_disabled_color",type,Color("607388"))
 panel.theme.set_color("default_color","RichTextLabel",Color("20364e"))
 for type in ["Button","OptionButton","LineEdit","TextEdit","ItemList"]:
  for state in ["normal","hover","pressed","focus","disabled","read_only","panel"]:
   panel.theme.set_stylebox(state,type,app.chat_view.box(Color("dce9f5") if state in ["hover","pressed","focus"] else Color("f9fcff"),7,8))
 var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,16)
 panel.add_child(margin)
 var shell:=VBoxContainer.new();shell.add_theme_constant_override("separation",12);margin.add_child(shell)
 var header:=HBoxContainer.new();shell.add_child(header)
 var title:=Label.new();title.text="Fox settings";title.add_theme_font_size_override("font_size",24);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title);app.chat_view.drag_handle(title,panel)
 app.chat_view.button(header,"—",func():panel.mode=Window.MODE_MINIMIZED).tooltip_text="Minimize settings"
 app.chat_view.button(header,"×",func():panel.close_requested.emit()).tooltip_text="Close settings"
 var tabs:=TabContainer.new();tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL;tabs.add_theme_color_override("font_selected_color",Color("20364e"));tabs.add_theme_color_override("font_unselected_color",Color("536a80"));tabs.add_theme_font_size_override("font_size",14);shell.add_child(tabs)
 tabs.add_theme_stylebox_override("panel",app.chat_view.box(Color("f9fcff"),10,12));tabs.add_theme_stylebox_override("tab_selected",app.chat_view.box(Color("dce9f5"),7,7));tabs.add_theme_stylebox_override("tab_unselected",app.chat_view.box(Color("edf3f9"),7,7))
 var pages:Dictionary={}
 for name in ["General","Gestures","Movement","Sound","Permissions","Thresholds","Advanced"]:
  var scroll:=ScrollContainer.new();scroll.name=name;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;tabs.add_child(scroll)
  var group:=VBoxContainer.new();group.size_flags_horizontal=Control.SIZE_EXPAND_FILL;group.add_theme_constant_override("separation",10);scroll.add_child(group);pages[name]=group
 # Keep the original widgets, bound callbacks and approval state. Reparent only.
 var permission:Node=app.preferences_controls.find_child("PermissionControls",true,false)
 if permission:permission.reparent(pages.Permissions)
 for node in column.get_children():
  var group:String=str(node.get_meta("settings_group","Advanced"))
  if node==app.preferences_controls:group="General"
  if node.name=="AudioControls":group="Sound"
  node.reparent(pages[group])
 var hint:=Label.new();hint.text="Preferences: Apply to save. Movement and sound changes save immediately.";hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;hint.add_theme_font_size_override("font_size",13);shell.add_child(hint)
 old_scroll.queue_free()
 return tabs
