extends Node
const Markdown=preload("FoxSafeMarkdown.gd")
const ModelMenu=preload("FoxModelMenu.gd")
const WIDTH:=330
const INPUT_HEIGHT:=100
const ANSWER_HEIGHT:=180
var owner_view:Node
var host:Node
var controller:RefCounted
var window:Window
var surface:Control
var glass:ColorRect
var central:Panel
var composer:TextEdit
var scroll:ScrollContainer
var transcript:VBoxContainer
var model:OptionButton
var send_button:Button
var latest:Button
var title:Label
var cards:Array[Dictionary]=[]
var pair_key:=""
var displayed_indices:Array[int]=[]
var syncing:=false
var follow_latest:=true
var adjusting:=false
var expanded_answer:=false
var closing:=false
var transition:Tween
var height_transition:Tween
var anchor:=Rect2i()
var native_status:=0
var observer_status:=0
var observe_dismissal:=true
var prefs:Dictionary={}
var material:ShaderMaterial
var max_render_ms:=0.0
var content:Control
var layout_serial:=0
func initialize(view:Node) -> void:
	owner_view=view;host=view.host;controller=view.controller
	window=Window.new();window.visible=false;window.name="CompactChat";window.title="Desktop Pet — Compact Chat";window.force_native=true;window.borderless=true;window.transparent=true;window.transparent_bg=true;window.unfocusable=false;window.size=Vector2i(WIDTH,INPUT_HEIGHT);window.min_size=Vector2i(WIDTH,INPUT_HEIGHT);window.max_size=Vector2i(WIDTH,ANSWER_HEIGHT);window.visible=false;window.theme=view.window.theme;add_child(window)
	window.close_requested.connect(close_popup);window.size_changed.connect(_size_changed)
	surface=Control.new();surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);window.add_child(surface)
	glass=ColorRect.new();glass.mouse_filter=Control.MOUSE_FILTER_IGNORE;glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);surface.add_child(glass)
	material=ShaderMaterial.new();material.shader=preload("compact_glass.gdshader");glass.material=material
	var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,8)
	surface.add_child(margin)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",6);margin.add_child(column)
	var row:=HBoxContainer.new();row.custom_minimum_size.y=24;row.add_theme_constant_override("separation",4);column.add_child(row)
	title=Label.new();title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;title.add_theme_font_size_override("font_size",14);row.add_child(title)
	model=OptionButton.new();model.fit_to_longest_item=false;model.add_item("◈",0);model.add_item("◈",1);_icon_style(model);row.add_child(model)
	model.item_selected.connect(func(index):commit();controller.select_model(str(model.get_item_metadata(index)));model.text="◈")
	_icon(row,"＋",func():commit();controller.new_chat(),"New Chat").hide()
	_icon(row,"↗",open_full,"Expand / Open Full Chat")
	central=Panel.new();central.size_flags_vertical=Control.SIZE_EXPAND_FILL;central.add_theme_stylebox_override("panel",view.box(Color(.96,.98,1,.7),6,14));column.add_child(central)
	# One bounded shared field; no separate answer panel or footer.
	# Explicit bounded viewports; transcript/composer minimum sizes cannot grow the field.
	content=Control.new();content.clip_contents=true;content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);content.offset_left=6;content.offset_top=6;content.offset_right=-6;content.offset_bottom=-6;central.add_child(content)
	scroll=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.visible=false;scroll.clip_contents=true;content.add_child(scroll)
	transcript=VBoxContainer.new();transcript.add_theme_constant_override("separation",4);transcript.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(transcript)
	scroll.get_v_scroll_bar().changed.connect(func():
		if follow_latest:_bottom.call_deferred())
	# Range changes during streaming must never undo a user's scroll-up pause.
	scroll.get_v_scroll_bar().gui_input.connect(_scroll_input);scroll.gui_input.connect(_scroll_input)
	composer=TextEdit.new();composer.placeholder_text="Ask your pet…";composer.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;composer.scroll_fit_content_height=false;composer.scroll_fit_content_width=false;composer.scroll_smooth=true;composer.scroll_v_scroll_speed=200;composer.add_theme_font_size_override("font_size",14)
	for state in ["normal","focus","read_only"]:
		var style:=StyleBoxEmpty.new();style.content_margin_right=32;style.content_margin_top=4;style.content_margin_bottom=3;composer.add_theme_stylebox_override(state,style)
	composer.text_changed.connect(_draft);composer.gui_input.connect(_keyboard);content.add_child(composer)
	content.resized.connect(_field_layout)
	send_button=Button.new();send_button.text="↑";_icon_style(send_button);send_button.custom_minimum_size=Vector2(28,28);send_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT);send_button.position=Vector2(-34,-34);send_button.pressed.connect(send_or_stop);central.add_child(send_button)
	latest=Button.new();latest.text="↓";_icon_style(latest);latest.tooltip_text="Resume following newest lines";latest.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT);latest.position=Vector2(-32,4);latest.pressed.connect(func():follow_latest=true;latest.hide();_bottom());central.add_child(latest);latest.hide()
	controller.changed.connect(refresh);apply_glass(host.preference_preview);refresh()
func _icon_style(item:Button) -> void:
	item.custom_minimum_size=Vector2(26,24);item.add_theme_font_size_override("font_size",16)
	for state in ["normal","hover","pressed","focus","disabled"]:
		var style:StyleBoxFlat=owner_view.box(Color(.85,.93,1,.7) if state in ["hover","pressed","focus"] else Color(1,1,1,.25),2,7);style.set_border_width_all(0);item.add_theme_stylebox_override(state,style)
func _icon(parent:Node,text:String,action:Callable,hint:String) -> Button:
	var item:=Button.new();item.text=text;_icon_style(item);item.tooltip_text=hint;item.pressed.connect(action);parent.add_child(item);return item
func visible() -> bool:return window.visible
func commit() -> void:controller.draft(composer.text)
func _draft() -> void:
	if syncing:return
	if composer.text.length()>owner_view.Controller.MAX_INPUT:composer.text=composer.text.left(owner_view.Controller.MAX_INPUT)
	commit();host.home_behavior.interact()
	composer.adjust_viewport_to_caret.call_deferred()
func _keyboard(event:InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE:composer.accept_event();close_popup()
		elif event.keycode in [KEY_ENTER,KEY_KP_ENTER] and not event.shift_pressed:
			composer.accept_event()
			if not controller.busy():send_or_stop()
func send_or_stop() -> void:
	if controller.busy():controller.stop();return
	var prompt:=composer.text
	syncing=true;composer.text="";syncing=false
	if not controller.send(prompt,owner_view.scenario.get_item_text(owner_view.scenario.selected)):
		syncing=true;composer.text=prompt;syncing=false
func open_popup() -> void:
	owner_view.cancel_approach("compact opened")
	if owner_view.window.visible:controller.draft(owner_view.composer.text)
	owner_view.window.hide();owner_view.bubble.hide()
	host.home_motion.stop(host,"compact chat opened");host.rest_routine.cancel(host,"compact chat opened");host.home_behavior.interact();host._cancel_pointer()
	if host.panel.visible:host.panel.close_requested.emit()
	closing=false;syncing=true;composer.text=controller.session().draft;syncing=false
	refresh(true);place();window.always_on_top=host.preference_preview.topmost;window.show();window.grab_focus()
	if not controller.busy():composer.grab_focus()
	apply_native();observer_status=FoxGlassBridge.observe((window.get_window_id()<<8)|1)
	if observer_status!=1:push_warning("Compact outside-click observer unavailable; Escape/fox-click remain available.")
	if transition:transition.kill()
	surface.modulate.a=0;surface.pivot_offset=Vector2(window.size)*.5;surface.scale=Vector2(.98,.98)
	transition=create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	transition.tween_property(surface,"modulate:a",1.0,.14);transition.tween_property(surface,"scale",Vector2.ONE,.14)
func open_full() -> void:commit();hide_immediate();owner_view.open_full_chat()
func close_popup() -> void:
	if not window.visible or closing:return
	commit();closing=true;FoxGlassBridge.observe(window.get_window_id()<<8);observer_status=0
	if transition:transition.kill()
	transition=create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	transition.tween_property(surface,"modulate:a",0.0,.10);transition.tween_callback(window.hide)
func hide_immediate() -> void:
	if window.visible:commit()
	FoxGlassBridge.observe(window.get_window_id()<<8);observer_status=0;closing=false
	if transition:transition.kill()
	window.hide()
func set_answer_height() -> void:
	if expanded_answer:return
	expanded_answer=true;_animate_height(ANSWER_HEIGHT)
func _animate_height(height:int) -> void:
	var final:=mini(height,work_area().size.y)
	if height_transition:height_transition.kill()
	if not window.visible:window.size=Vector2i(WIDTH,final);return
	height_transition=create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	height_transition.tween_method(func(value):window.size.y=roundi(value),float(window.size.y),float(final),.16)
func work_area() -> Rect2i:return DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen(host.pet.get_window_id()))
func place() -> void:
	var area:=work_area();var pet_rect:=Rect2i(host.pet.position,host.pet.size)
	window.size=Vector2i(mini(WIDTH,area.size.x),clampi(window.size.y,INPUT_HEIGHT,ANSWER_HEIGHT))
	var bounds:=Rect2(Vector2.ZERO,Vector2(pet_rect.size))
	var mask:PackedVector2Array=host.pet.mouse_passthrough_polygon
	if mask.size()>=3:
		bounds=Rect2(mask[0],Vector2.ZERO)
		for vertex in mask:bounds=bounds.expand(vertex)
	var point:=pet_rect.position+Vector2i(roundi(bounds.end.x)+6,roundi(bounds.position.y)+6)
	if point.x+window.size.x>area.end.x:point.x=pet_rect.position.x+roundi(bounds.position.x)-window.size.x-6
	window.position=host.Geometry.fit_position(point,window.size,area);anchor=pet_rect
func _size_changed() -> void:
	material.set_shader_parameter("dimensions",Vector2(window.size));place();_field_layout.call_deferred()
	if window.visible:apply_native()
func apply_glass(values:Dictionary) -> void:
	owner_view.apply_full_glass()
	prefs=values.duplicate();title.text=prefs.get("pet_name","Pet");material.set_shader_parameter("opacity",prefs.get("glass_opacity",.72));material.set_shader_parameter("tint",prefs.get("glass_tint",.3));material.set_shader_parameter("frost",prefs.get("glass_blur",.75))
	# Contrast underlay adapts to opacity without sampling desktop pixels.
	central.add_theme_stylebox_override("panel",owner_view.box(Color(.97,.985,1,lerpf(.80,.56,float(prefs.get("glass_opacity",.72)))),6,14))
	if window.visible:window.always_on_top=prefs.topmost;apply_native()
func apply_native() -> void:
	native_status=FoxGlassBridge.configure((window.get_window_id()<<8)|roundi(prefs.get("glass_blur",.75)*100))
	title.tooltip_text="Windows blur request: %s. Visual desktop blur still depends on Windows composition."%("direct blur" if native_status&64 else ("Acrylic" if native_status&2 else "unavailable; translucent fallback"))
func _process(_delta:float) -> void:
	if not window.visible:return
	var outside_signal:=FoxGlassBridge.observe((window.get_window_id()<<8)|2)
	if observe_dismissal and not closing and (outside_signal&1)!=0:close_popup()
	if anchor!=Rect2i(host.pet.position,host.pet.size):place()
	if host.pet_hidden_by_user or host.panel_minimized or host.director.full_screen:hide_immediate()
func _input(event:InputEvent) -> void:
	if event is InputEventMouseButton and event.window_id==window.get_window_id() and event.button_index==MOUSE_BUTTON_WHEEL_UP:_scroll_input(event)
func _scroll_input(event:InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_LEFT]:follow_latest=false;latest.show()
func _bottom() -> void:
	adjusting=true;scroll.scroll_vertical=roundi(scroll.get_v_scroll_bar().max_value);adjusting=false
func _field_layout() -> void:
	if not content or not composer:return
	var has_reply:bool=scroll.visible
	var typing_height:float=content.size.y if not has_reply else 30.0
	if controller.busy():typing_height=0
	composer.position=Vector2(0,content.size.y-typing_height);composer.size=Vector2(content.size.x,typing_height)
	scroll.position=Vector2.ZERO;scroll.size=Vector2(content.size.x,maxf(1,content.size.y-typing_height-(2 if typing_height>0 and has_reply else 0)))
	if controller.busy():scroll.size.x=maxf(1,content.size.x-30)
	composer.adjust_viewport_to_caret.call_deferred()
func _finish_layout(expected:int) -> void:
	await get_tree().process_frame
	if expected!=layout_serial:return
	_field_layout()
	if follow_latest:_bottom()
func refresh(force:bool=false) -> void:
	# Opening catches up from the shared controller; don't lay out a duplicate
	# hidden transcript while the full window is receiving tokens.
	if not force and not visible():return
	var start:=Time.get_ticks_usec();ModelMenu.refresh(model,controller,true)
	send_button.text="■" if controller.busy() else "↑";send_button.tooltip_text="Stop response; keep partial answer" if controller.busy() else "Send · Enter (Shift+Enter for new line)"
	var messages:Array=controller.session().messages;var user_index:=-1;var answer_index:=-1
	for index in range(messages.size()-1,-1,-1):
		if answer_index<0 and messages[index].role=="assistant":answer_index=index
		if messages[index].role=="user":user_index=index;break
	var key:=str(controller.session().id)+"/%d/%d"%[user_index,answer_index]
	if key!=pair_key:
		pair_key=key
		for child in transcript.get_children():child.free()
		cards.clear();displayed_indices.clear();follow_latest=true;latest.hide()
		syncing=true;composer.text=controller.session().draft;syncing=false
		if user_index>=0:
			for index in [user_index,answer_index]:
				if index>=0:displayed_indices.append(index);cards.append(_card(messages[index].role))
		else:expanded_answer=false;_animate_height(INPUT_HEIGHT)
	for index in cards.size():
		var row:Dictionary=messages[displayed_indices[index]];var card:Dictionary=cards[index]
		if card.text!=row.text:card.label.text=Markdown.render(row.text).bbcode if row.role=="assistant" else Markdown.literal(row.text);card.text=row.text
		card.state.text={"streaming":"Replying…","cancelled":"Stopped · partial answer","error":"Error · partial answer"}.get(row.state,"");card.state.visible=not card.state.text.is_empty()
	scroll.visible=not cards.is_empty();composer.visible=not controller.busy();composer.placeholder_text="Ask again…" if scroll.visible else "Ask your pet…"
	if scroll.visible:set_answer_height()
	_field_layout();layout_serial+=1;_finish_layout.call_deferred(layout_serial)
	max_render_ms=maxf(max_render_ms,float(Time.get_ticks_usec()-start)/1000.0)
func _card(role:String) -> Dictionary:
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",1);transcript.add_child(column)
	var who:=Label.new();who.text="Pet" if role=="assistant" else "You";who.add_theme_font_size_override("font_size",11);who.add_theme_color_override("font_color",owner_view.MUTED);column.add_child(who)
	var label:=RichTextLabel.new();label.bbcode_enabled=true;label.fit_content=true;label.scroll_active=false;label.selection_enabled=true;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.add_theme_color_override("default_color",owner_view.NAVY);label.add_theme_font_size_override("normal_font_size",14);label.add_theme_font_size_override("bold_font_size",14);column.add_child(label)
	var mono:=SystemFont.new();mono.font_names=PackedStringArray(["Consolas"]);label.add_theme_font_override("mono_font",mono);label.add_theme_font_size_override("mono_font_size",12)
	var state:=Label.new();state.add_theme_font_size_override("font_size",11);state.add_theme_color_override("font_color",owner_view.MUTED);column.add_child(state)
	return {"label":label,"state":state,"text":""}
func _exit_tree() -> void:
	if window:FoxGlassBridge.observe(window.get_window_id()<<8)

