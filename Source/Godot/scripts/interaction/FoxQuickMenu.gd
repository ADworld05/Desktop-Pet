extends Window
## Small glass command surface. Fixed original action IDs, no new tool routes.
signal id_pressed(id:int)
var host:Node
var column:VBoxContainer
var material:ShaderMaterial
var entries:Array[Button]=[]
var item_count:int:
 get:return entries.size()
var native_status:=0
var observer_status:=0
func initialize(app:Node)->void:
 host=app;visible=false;title="Desktop Pet — Quick Menu";force_native=true;borderless=true;transparent=true;transparent_bg=true;transient=false;unresizable=true
 content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;content_scale_size=Vector2i.ZERO;content_scale_factor=1
 var glass:=ColorRect.new();glass.mouse_filter=Control.MOUSE_FILTER_IGNORE;glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(glass)
 material=ShaderMaterial.new();material.shader=preload("res://scripts/chat/compact_glass.gdshader");glass.material=material
 var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,6)
 add_child(margin);column=VBoxContainer.new();column.add_theme_constant_override("separation",1);margin.add_child(column)
 close_requested.connect(hide)
 visibility_changed.connect(func():
  if not visible:FoxGlassBridge.observe(get_window_id()<<8);observer_status=0)
func add_item(label:String)->void:
 var id:=entries.size();var button:=Button.new();button.text=label;button.alignment=HORIZONTAL_ALIGNMENT_LEFT;button.custom_minimum_size=Vector2(164,28);button.add_theme_font_size_override("font_size",14)
 var font:=SystemFont.new();font.font_names=PackedStringArray(["Segoe UI"]);button.add_theme_font_override("font",font)
 for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_hover_pressed_color"]:button.add_theme_color_override(key,Color("20364e"))
 for state in ["normal","hover","pressed","focus","disabled"]:
  var box:=StyleBoxFlat.new();box.bg_color=Color(.88,.94,1,.86) if state in ["hover","pressed","focus"] else Color(1,1,1,0);box.set_corner_radius_all(7);box.content_margin_left=10;box.content_margin_right=10;button.add_theme_stylebox_override(state,box)
 button.pressed.connect(func():hide();id_pressed.emit(id));column.add_child(button);entries.append(button)
func set_item_disabled(index:int,value:bool)->void:entries[index].disabled=value
func menu_extent()->Vector2:return Vector2(176,12+entries.size()*29-1)
func open_at(bounds:Rect2i=Rect2i())->void:
 size=Vector2i(menu_extent());position=bounds.position;always_on_top=host.preference_preview.topmost
 material.set_shader_parameter("dimensions",Vector2(size));material.set_shader_parameter("opacity",host.preference_preview.get("glass_opacity",.72));material.set_shader_parameter("tint",host.preference_preview.get("glass_tint",.3));material.set_shader_parameter("frost",host.preference_preview.get("glass_blur",.75))
 show();grab_focus();apply_backdrop.call_deferred()
 if not entries.is_empty():entries[0].grab_focus()
func apply_backdrop()->void:
 if not visible:return
 native_status=FoxGlassBridge.configure((get_window_id()<<8)|roundi(host.preference_preview.get("glass_blur",.75)*100))
 observer_status=FoxGlassBridge.observe((get_window_id()<<8)|1)
func _process(_delta:float)->void:
 if visible and (FoxGlassBridge.observe((get_window_id()<<8)|2)&1)!=0:hide()
func _input(event:InputEvent)->void:
 if visible and event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:hide();set_input_as_handled()
func _exit_tree()->void:
 if get_window_id()>0:FoxGlassBridge.observe(get_window_id()<<8)
