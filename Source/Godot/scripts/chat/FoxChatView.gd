extends Node
const Controller=preload("FoxChatController.gd")
const Markdown=preload("FoxSafeMarkdown.gd")
const Compact=preload("FoxCompactChat.gd")
const LocalProvider=preload("FoxOllamaProvider.gd")
const LocalSettings=preload("FoxOllamaSettings.gd")
const ModelMenu=preload("FoxModelMenu.gd")
const Approach=preload("FoxChatApproach.gd")
const HistoryStore=preload("FoxHistoryStore.gd")
const HistoryControls=preload("FoxHistoryControls.gd")
var history_controls:Node
var memory_controls:Node
const MemoryStore=preload("FoxMemoryStore.gd")
const MemoryControls=preload("FoxMemoryControls.gd")
var storage_note:Label
var data_sections:Node
var data_tabs:TabContainer
var approach:=Approach.new()
var full_placed:=false
var local_settings:Node
var compact:Node
var controller:=Controller.new()
var host:Node
var window:Window
var full_glass:ColorRect
var full_material:ShaderMaterial
var full_glass_status:=0
var toolbar:HBoxContainer
var bubble:Window
var composer:TextEdit
var transcript:VBoxContainer
var scroll:ScrollContainer
var model:OptionButton
var scenario:OptionButton
var history_signature:=""
var mono_font:SystemFont
var history:OptionButton
var history_row:HBoxContainer
var status:Label
var send_button:Button
var retry_button:Button
var action_proposal:Dictionary={}
var action_review_button:Button
var latest:Button
var bubble_text:Label
var cards:Array[Dictionary]=[]
var full_presentation_active:=false
var rendered_session:=""
var syncing:=false
var adjusting_scroll:=false
var rendering:=false
var follow_latest:=true
var layout_serial:=0
var wheel_tween:Tween
var wheel_target:=0.0
var clipboard_writer:Callable=func(value:String):DisplayServer.clipboard_set(value)
var copied_text:=""
var max_render_ms:=0.0
var last_anchor:=Rect2i()
var bubble_dismissed:=false
const NAVY:=Color("#24384e")
const MUTED:=Color("#64788c")
static func box(color:Color,padding:float=12,radius:int=12) -> StyleBoxFlat:
	var style:=StyleBoxFlat.new();style.bg_color=color;style.border_color=Color("#cedbe7")
	style.set_border_width_all(1);style.set_corner_radius_all(radius);style.set_content_margin_all(padding)
	return style
static func button(parent:Node,text:String,action:Callable) -> Button:
	var item:=Button.new();item.text=text;item.custom_minimum_size.y=34;item.pressed.connect(action);parent.add_child(item);return item
static func drag_handle(handle:Control,target:Window) -> void:
	handle.mouse_filter=Control.MOUSE_FILTER_STOP
	handle.mouse_default_cursor_shape=Control.CURSOR_MOVE
	handle.tooltip_text="Drag here to move this window"
	handle.gui_input.connect(func(event:InputEvent):
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
			handle.accept_event();target.start_drag())
func _clear_action_proposal(_id:String) -> void:
	action_proposal.clear()
	if action_review_button: action_review_button.disabled=true

func _offer_action_proposal(session_id:String, row:Dictionary) -> void:
	_clear_action_proposal(session_id)
	if session_id!=controller.session().id or row.get("state")!="complete" or row.get("role")!="assistant" or str(row.get("text", "")).to_utf8_buffer().size()>4096: return
	var parser:=JSON.new()
	if parser.parse(str(row.text))!=OK: return
	var raw:Variant=parser.data
	var checked:=preload("res://scripts/actions/FoxActionSchema.gd").validate(raw)
	if not checked.ok: return
	action_proposal=checked.request.duplicate(true)
	if action_review_button: action_review_button.disabled=false

func initialize(owner:Node) -> void:
	host=owner
	controller.completed_message.connect(_offer_action_proposal)
	controller.session_changed.connect(_clear_action_proposal)
	var mock_fixture:=false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--t15-"):mock_fixture=true
	if not mock_fixture:controller.use_local_provider(LocalProvider.new())
	if "--t17-validation" in OS.get_cmdline_user_args():
		controller.use_history(HistoryStore.new(preload("res://scripts/Paths.gd").development_root().path_join("Validation/T17/iteration-1/desktop/History"),preload("res://scripts/Paths.gd").development_root().path_join("Validation/T17/iteration-1/desktop/history.json")))
	elif not mock_fixture:controller.use_history(HistoryStore.new())
	if controller.history_store!=null:
		controller.memory_store=MemoryStore.new(preload("res://scripts/Paths.gd").development_root().path_join("Validation/T17/iteration-2/ui-memory/memory.json")) if "--t17-validation" in OS.get_cmdline_user_args() else MemoryStore.new()
		controller.memory_store.open()
	window=Window.new();window.name="ChatWindow";window.title="Desktop Pet — Chat";window.size=Vector2i(720,700);window.min_size=Vector2i(680,500);window.visible=false;window.transparent=true;window.transparent_bg=true;window.force_native=true;window.unfocusable=false;window.borderless=false;window.transient=false;window.popup_window=false;window.unresizable=false;window.minimize_disabled=false;window.maximize_disabled=false;window.keep_title_visible=true;window.always_on_top=false
	add_child(window);window.close_requested.connect(close_chat)
	mono_font=SystemFont.new();mono_font.font_names=PackedStringArray(["Consolas"])
	var theme:=Theme.new();theme.default_font_size=16
	var font:=SystemFont.new();font.font_names=PackedStringArray(["Segoe UI"]);theme.default_font=font
	var bold:=SystemFont.new();bold.font_names=PackedStringArray(["Segoe UI"]);bold.font_weight=700
	theme.set_font("normal_font","RichTextLabel",font);theme.set_font("bold_font","RichTextLabel",bold)
	theme.set_font_size("normal_font_size","RichTextLabel",16);theme.set_font_size("bold_font_size","RichTextLabel",16)
	theme.set_color("font_color","Label",NAVY);theme.set_color("font_color","Button",NAVY)
	theme.set_color("font_pressed_color","Button",NAVY);theme.set_color("font_hover_color","Button",NAVY);theme.set_color("font_focus_color","Button",NAVY);theme.set_color("font_hover_pressed_color","Button",NAVY);theme.set_color("font_disabled_color","Button",MUTED);theme.set_color("font_readonly_color","TextEdit",NAVY)
	theme.set_color("font_color","OptionButton",NAVY);theme.set_color("font_color","TextEdit",NAVY)
	theme.set_color("font_placeholder_color","TextEdit",MUTED);theme.set_color("caret_color","TextEdit",NAVY)
	theme.set_color("selection_color","TextEdit",Color("#bbd9f4"))
	theme.set_stylebox("normal","TextEdit",box(Color.WHITE,10));theme.set_stylebox("focus","TextEdit",box(Color("#ffffff"),10))
	theme.set_stylebox("read_only","TextEdit",box(Color.WHITE,10))
	for type in ["Button","OptionButton"]:
		for state in ["normal","hover","pressed","focus","disabled"]:theme.set_stylebox(state,type,box(Color("#e1edf8") if state in ["hover","pressed","focus"] else Color("#f7faff"),9,8))
	window.theme=theme
	full_glass=ColorRect.new();full_glass.mouse_filter=Control.MOUSE_FILTER_IGNORE;full_glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);window.add_child(full_glass)
	full_material=ShaderMaterial.new();full_material.shader=preload("compact_glass.gdshader");full_glass.material=full_material
	window.size_changed.connect(apply_full_glass)
	var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,16)
	window.add_child(margin)
	data_tabs=TabContainer.new();data_tabs.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);margin.add_child(data_tabs)
	data_tabs.add_theme_color_override("font_selected_color",NAVY);data_tabs.add_theme_color_override("font_unselected_color",MUTED);data_tabs.add_theme_stylebox_override("panel",box(Color(.94,.97,1,.10),8));data_tabs.add_theme_stylebox_override("tab_selected",box(Color.WHITE,8,7));data_tabs.add_theme_stylebox_override("tab_unselected",box(Color("#e4eef8"),8,7))
	var column:=VBoxContainer.new();column.name="Chat";column.add_theme_constant_override("separation",10);data_tabs.add_child(column)
	var caption:=HBoxContainer.new();column.add_child(caption)
	var title:=Label.new();title.text="Pet chat";title.add_theme_font_size_override("font_size",22);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;caption.add_child(title);drag_handle(title,window)
	var minimize:=button(caption,"—",minimize_chat);minimize.name="MinimizeChat";minimize.tooltip_text="Minimize chat"
	var close:=button(caption,"×",close_chat);close.name="CloseChat";close.tooltip_text="Close chat; preserve history"
	var header:=HBoxContainer.new();header.add_theme_constant_override("separation",6);toolbar=header;column.add_child(header)
	button(header,"New Chat",new_chat).hide() # Sessions restart with the pet, per user preference.
	button(header,"History",show_history).name="History"
	button(header,"Settings",func():host._menu_action("settings")).name="Settings"
	button(header,"Compact",func():compact.open_popup()).name="CollapseChat"
	if controller.real_provider:button(header,"Local AI",func():local_settings.open()).name="LocalAI"
	else:button(header,"Local AI",func():pass).disabled=true
	var models:=HBoxContainer.new();models.add_theme_constant_override("separation",8);column.add_child(models);models.hide()
	model=OptionButton.new();model.name="Model";model.fit_to_longest_item=false;model.size_flags_horizontal=Control.SIZE_EXPAND_FILL;model.custom_minimum_size.y=34;header.add_child(model)
	model.item_selected.connect(func(index):controller.draft(composer.text);controller.select_model(str(model.get_item_metadata(index)));model.text="Model")
	scenario=OptionButton.new();scenario.name="MockScenario"
	for value in ["Automatic","Short","Formatted","Long","Error"]:scenario.add_item(value)
	scenario.tooltip_text="Local demonstration replies; no model is loaded.";scenario.custom_minimum_size.y=34;models.add_child(scenario)
	history_row=HBoxContainer.new();history_row.visible=false;column.add_child(history_row)
	action_review_button=Button.new();action_review_button.text="Review";action_review_button.tooltip_text="Review suggested action";action_review_button.disabled=true;header.add_child(action_review_button)
	action_review_button.pressed.connect(func():
		var review:Variant=host.get_meta("fox_action_review",null)
		if review!=null and is_instance_valid(review): review.offer_candidate(action_proposal)
		else: status.text="Open Settings → Permissions to review this action. Nothing executed.")
	var history_label:=Label.new();history_label.text="Saved chats" if controller.history_store!=null else "This run";history_row.add_child(history_label)
	history=OptionButton.new();history.name="SessionHistory";history.size_flags_horizontal=Control.SIZE_EXPAND_FILL;history_row.add_child(history)
	history.item_selected.connect(func(index):choose_session(str(history.get_item_metadata(index))))
	if controller.history_store!=null:button(history_row,"Storage",func():history_controls.open()).name="HistoryStorage"
	if controller.memory_store!=null:button(history_row,"Memory",func():memory_controls.open()).name="MemoryManager"
	scenario.visible=false
	for control in header.get_children():
		if control is Button:
			control.add_theme_font_size_override("font_size",13);control.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			for state in ["normal","hover","pressed","focus","disabled"]:control.add_theme_stylebox_override(state,box(Color("#c5d6e9") if state in ["hover","pressed","focus"] else Color("#dbe5f0"),6,8))
	var note:=Label.new();note.text="Installed local weights only · no tools or cloud fallback" if controller.real_provider else "Mock preview · local AI connects in the next task";note.add_theme_font_size_override("font_size",13);note.add_theme_color_override("font_color",MUTED);column.add_child(note);note.hide()
	scroll=ScrollContainer.new();scroll.name="TranscriptScroll";scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.follow_focus=false;scroll.add_theme_stylebox_override("panel",box(Color(.97,.985,1,.97),12,14));column.add_child(scroll)
	transcript=VBoxContainer.new();transcript.name="Transcript";transcript.size_flags_horizontal=Control.SIZE_EXPAND_FILL;transcript.add_theme_constant_override("separation",22);scroll.add_child(transcript)
	scroll.get_v_scroll_bar().value_changed.connect(_scrolled)
	scroll.get_v_scroll_bar().changed.connect(func():
		if follow_latest:_bottom.call_deferred())
	scroll.gui_input.connect(_scroll_input);scroll.gui_input.connect(_wheel_scroll);scroll.get_v_scroll_bar().gui_input.connect(_scroll_input)
	latest=button(column,"Jump to latest",jump_latest);latest.name="JumpLatest";latest.visible=false
	composer=TextEdit.new();composer.name="ChatDraft";composer.placeholder_text="Ask your pet…";composer.custom_minimum_size.y=64;composer.scroll_fit_content_height=false;composer.scroll_fit_content_width=false;composer.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;composer.text_changed.connect(_draft_changed);composer.gui_input.connect(_composer_input);column.add_child(composer)
	var actions:=HBoxContainer.new();actions.add_theme_constant_override("separation",8);column.add_child(actions)
	var help:=Label.new();help.text="Enter sends · Shift+Enter adds a line";help.add_theme_font_size_override("font_size",12);help.add_theme_color_override("font_color",MUTED);help.size_flags_horizontal=Control.SIZE_EXPAND_FILL;actions.add_child(help)
	retry_button=button(actions,"Retry",func():controller.retry(scenario.get_item_text(scenario.selected)));retry_button.name="Retry";retry_button.visible=false
	send_button=button(actions,"Send",send_or_stop);send_button.name="SendStop";send_button.custom_minimum_size.x=82
	status=Label.new();status.name="ChatStatus";status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.add_theme_font_size_override("font_size",13);status.add_theme_color_override("font_color",MUTED);column.add_child(status)
	storage_note=Label.new();storage_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;storage_note.add_theme_font_size_override("font_size",12);storage_note.add_theme_color_override("font_color",MUTED);column.add_child(storage_note)
	_make_bubble(theme)
	controller.changed.connect(refresh)
	controller.request_started.connect(func(_id):bubble_dismissed=false;host.director.request_overlay("thinking","assistant"))
	controller.request_finished.connect(_finished)
	refresh()
	compact=Compact.new();add_child(compact);compact.initialize(self)
	if controller.history_store!=null:history_controls=HistoryControls.new();add_child(history_controls);history_controls.initialize(self)
	if controller.memory_store!=null:memory_controls=MemoryControls.new();add_child(memory_controls);memory_controls.initialize(self)
	if controller.history_store!=null:data_sections=preload("FoxDataSections.gd").new();add_child(data_sections);data_sections.initialize(self,data_tabs)
	if controller.real_provider:
		local_settings=LocalSettings.new();add_child(local_settings);local_settings.initialize(self)
func _make_bubble(theme:Theme) -> void:
	bubble=Window.new();bubble.name="ChatBubble";bubble.title="Fox reply";bubble.size=Vector2i(285,220);bubble.visible=false;bubble.borderless=true;bubble.unfocusable=true;bubble.theme=theme;add_child(bubble)
	var panel:=PanelContainer.new();panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);panel.add_theme_stylebox_override("panel",box(Color("#f6faff"),14,14));bubble.add_child(panel)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",8);panel.add_child(column)
	var row:=HBoxContainer.new();column.add_child(row)
	var title:=Label.new();title.text="Pet";title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(title)
	button(row,"×",func():bubble_dismissed=true;bubble.hide())
	bubble_text=Label.new();bubble_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;bubble_text.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(bubble_text)
	button(column,"Open chat",open_chat)
func _process(delta:float) -> void:
	if controller.real_provider:controller.provider.pet_name=host.preference_preview.get("pet_name","Pet")
	controller.advance(delta)
	var showing:bool=window.visible and window.mode!=Window.MODE_MINIMIZED
	if showing and not full_presentation_active:refresh()
	full_presentation_active=showing
	if storage_note and storage_note.text!=controller.storage_status:storage_note.text=controller.storage_status;storage_note.visible=controller.storage_status.to_lower().contains("error") or controller.storage_status.to_lower().contains("could not") or controller.storage_status.to_lower().contains("limit")
	if host.pet_hidden_by_user or host.panel_minimized or host.director.full_screen:bubble.hide()
func cancel_approach(reason:String) -> void:approach.cancel(host,reason)
func observe_window_motion(delta:float) -> void:
	var held:=false
	# Poll one mouse button/move-size metadata only for this owned chat while pending.
	if window.visible and (approach.pending or approach.active()):
		var state:int=FoxChatWindowBridge.window_state(window.get_window_id())
		held=state==0 or (state&6)!=0
	approach.observe(host,window,delta,held)
func step_approach(delta:float) -> bool:return approach.step(host,delta)
func _input(event:InputEvent) -> void:
	if event is InputEventMouseButton and event.window_id==window.get_window_id() and event.button_index==MOUSE_BUTTON_WHEEL_UP:_scroll_input(event)
func interacting() -> bool:return (window.visible and window.mode!=Window.MODE_MINIMIZED) or (compact!=null and compact.visible()) or (local_settings!=null and local_settings.window.visible and local_settings.window.mode!=Window.MODE_MINIMIZED) or (history_controls!=null and history_controls.window.visible and history_controls.window.mode!=Window.MODE_MINIMIZED) or (memory_controls!=null and memory_controls.window.visible and memory_controls.window.mode!=Window.MODE_MINIMIZED) or controller.busy()
func open_chat() -> void:
	compact.open_popup()
func open_full_chat() -> void:
	compact.hide_immediate()
	syncing=true;composer.text=controller.session().draft;syncing=false
	host.home_motion.stop(host,"chat opened");host.rest_routine.cancel(host,"chat opened");host.home_behavior.interact();host._cancel_pointer()
	if host.panel.visible:host.panel.close_requested.emit()
	bubble.hide();bubble_dismissed=false
	if not full_placed:place();full_placed=true
	window.mode=Window.MODE_WINDOWED;window.show();apply_full_glass();window.grab_focus();composer.grab_focus()
	refresh()
	approach.opened(host,Rect2(Vector2(window.get_position_with_decorations()),Vector2(window.get_size_with_decorations())))
func minimize_chat() -> void:
	controller.draft(composer.text);cancel_approach("chat minimized");window.mode=Window.MODE_MINIMIZED
func close_chat() -> void:
	controller.draft(composer.text);cancel_approach("chat closed");window.hide();update_bubble()
func hide_all() -> void:
	cancel_approach("chat hidden")
	if window.visible:controller.draft(composer.text)
	if compact:compact.hide_immediate()
	window.hide();bubble.hide()
	if local_settings:local_settings.window.hide()
	if history_controls:history_controls.window.hide()
	if memory_controls:memory_controls.window.hide()
func place() -> void:
	if not host or not host.pet:return
	var screen:=DisplayServer.window_get_current_screen(host.pet.get_window_id());var area:=DisplayServer.screen_get_usable_rect(screen)
	var pet_rect:=Rect2i(host.pet.position,host.pet.size)
	last_anchor=pet_rect
	for target in [window]:
		target.size=target.size.min(area.size)
		var desired:=pet_rect.position+Vector2i(pet_rect.size.x+12,0)
		if desired.x+target.size.x>area.end.x:desired.x=pet_rect.position.x-target.size.x-12
		target.position=host.Geometry.fit_position(desired,target.size,area)
func _draft_changed() -> void:
	if syncing:return
	if composer.text.length()>Controller.MAX_INPUT:
		composer.text=composer.text.left(Controller.MAX_INPUT);composer.set_caret_column(composer.get_line(composer.get_caret_line()).length())
	controller.draft(composer.text);host.home_behavior.interact();host.home_motion.stop(host,"chat typing")
	composer.adjust_viewport_to_caret.call_deferred()
func _composer_input(event:InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER,KEY_KP_ENTER] and not event.shift_pressed:
		composer.accept_event()
		if not controller.busy():send_or_stop()
func send_or_stop() -> void:
	if controller.busy():controller.stop();return
	if controller.send(composer.text,scenario.get_item_text(scenario.selected)):
		syncing=true;composer.text="";syncing=false
func new_chat() -> void:
	controller.draft(composer.text);controller.new_chat()
func choose_session(id:String) -> void:
	controller.draft(composer.text);controller.select_session(id)
func show_history() -> void:
	if data_sections:data_tabs.current_tab=1
	else:history_row.visible=not history_row.visible
	controller.history_requested.emit();refresh()
func _finished(state:String) -> void:
	# Release only our thinking cue; protected body motion is owned by director.
	if host.director.overlays.has("head") and host.director.overlays.head.id=="thinking":host.director.overlays.erase("head")
	if state=="error":host.director.request_overlay("error_cue","assistant")
	elif state=="complete":host.director.request_overlay("click_react","assistant");host._sync_audio_lifecycle();host.local_audio.request("result")
	update_bubble()
func update_bubble() -> void:
	# Compact input/reply surface supersedes the old passive short-answer bubble.
	bubble.hide()
func _scrolled(_value:float) -> void:
	if adjusting_scroll or rendering:return
	var bar:=scroll.get_v_scroll_bar()
	# Only explicit user scroll can disengage following; content growth cannot.
	if not follow_latest and bar.value>=bar.max_value-bar.page-12:follow_latest=true
	latest.visible=not follow_latest
func _scroll_input(event:InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_LEFT]:
		# Explicit wheel/scrollbar intent wins even during an async label relayout.
		follow_latest=false;latest.show()
func jump_latest() -> void:
	follow_latest=true;latest.hide();_bottom()
func _bottom() -> void:
	if wheel_tween:wheel_tween.kill()
	adjusting_scroll=true;scroll.scroll_vertical=roundi(scroll.get_v_scroll_bar().max_value);adjusting_scroll=false
func refresh() -> void:
	if not composer:return
	# Hidden/minimized full chat catches up from the shared controller on open.
	# Avoid laying out a duplicate streamed transcript behind the compact popup.
	if not window.visible or window.mode==Window.MODE_MINIMIZED:return
	var started:=Time.get_ticks_usec();syncing=true
	# Stream refreshes must never overwrite an in-progress next-message draft.
	if rendered_session!=controller.session().id:composer.text=controller.session().draft
	ModelMenu.refresh(model,controller);model.text="Model"
	status.text=controller.status;status.visible=controller.busy() or controller.status not in ["Ready","Saved chat loaded"];send_button.text="Stop" if controller.busy() else "Send"
	storage_note.text=controller.storage_status;storage_note.visible=controller.storage_status.to_lower().contains("error") or controller.storage_status.to_lower().contains("could not") or controller.storage_status.to_lower().contains("limit")
	var messages:Array=controller.session().messages
	retry_button.visible=not controller.busy() and not messages.is_empty() and messages.back().state in ["cancelled","error"]
	var summaries:=PackedStringArray()
	for row in controller.sessions:summaries.append(str(row.id)+"/"+str(row.title))
	var key:=str(controller.current)+"/"+"|".join(summaries)
	if key!=history_signature:
		history_signature=key;history.clear()
		for row in controller.sessions:
			history.add_item(row.title);history.set_item_metadata(history.item_count-1,row.id)
		history.select(controller.current)
	if rendered_session!=controller.session().id:
		for child in transcript.get_children():child.free()
		cards.clear();rendered_session=controller.session().id;follow_latest=true
	if messages.is_empty() and transcript.get_child_count()==0:
		var welcome:=Label.new();welcome.name="Welcome";welcome.text="Ask your pet anything.";welcome.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;welcome.add_theme_color_override("font_color",MUTED);transcript.add_child(welcome)
	elif not messages.is_empty() and transcript.has_node("Welcome"):transcript.get_node("Welcome").free()
	rendering=true;layout_serial+=1
	for index in messages.size():
		if index>=cards.size():cards.append(_card(index,messages[index].role))
		var row:Dictionary=messages[index];var card:Dictionary=cards[index]
		if card.content!=row.text:
			card.label.text=Markdown.render(row.text).bbcode if row.role=="assistant" else Markdown.literal(row.text);card.content=row.text
		card.state.text={"streaming":"Replying…","complete":"","cancelled":"Stopped · incomplete","error":"Error · incomplete"}.get(row.state,"")
		card.state.visible=card.state.text!=""
	syncing=false;max_render_ms=maxf(max_render_ms,float(Time.get_ticks_usec()-started)/1000.0)
	_finish_layout.call_deferred(layout_serial)
func _finish_layout(expected:int) -> void:
	await get_tree().process_frame
	if expected!=layout_serial:return
	if follow_latest:_bottom()
	rendering=false
func _card(index:int,role:String) -> Dictionary:
	var outer:=MarginContainer.new();outer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;transcript.add_child(outer)
	if role=="user":outer.add_theme_constant_override("margin_left",44)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",4)
	if role=="user":
		var panel:=PanelContainer.new();panel.add_theme_stylebox_override("panel",box(Color("#e4edf7"),12,16));outer.add_child(panel);panel.add_child(column)
	else:outer.add_child(column)
	var label:=RichTextLabel.new();label.name="MessageText";label.bbcode_enabled=true;label.fit_content=true;label.scroll_active=false;label.selection_enabled=true;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.add_theme_color_override("default_color",NAVY)
	label.add_theme_font_override("mono_font",mono_font);label.add_theme_font_size_override("mono_font_size",14);column.add_child(label)
	var footer:=HBoxContainer.new();column.add_child(footer)
	var state:=Label.new();state.add_theme_font_size_override("font_size",12);state.add_theme_color_override("font_color",MUTED);state.size_flags_horizontal=Control.SIZE_EXPAND_FILL;footer.add_child(state)
	if role=="assistant":
		var copy:=button(footer,"Copy",func():copy_reply(index));copy.add_theme_font_size_override("font_size",12);copy.custom_minimum_size.y=24
	return {"label":label,"state":state,"content":""}
func _wheel_scroll(event:InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		follow_latest=false;latest.show();scroll.accept_event()
		if wheel_tween and wheel_tween.is_running():wheel_tween.kill()
		else:wheel_target=float(scroll.scroll_vertical)
		var bar:=scroll.get_v_scroll_bar()
		wheel_target=clampf(wheel_target+(-72.0 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 72.0)*event.factor,bar.min_value,maxf(bar.min_value,bar.max_value-bar.page))
		wheel_tween=create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		wheel_tween.tween_property(scroll,"scroll_vertical",roundi(wheel_target),.12)
func copy_reply(index:int) -> void:
	if index<0 or index>=controller.session().messages.size():return
	copied_text=controller.session().messages[index].text;clipboard_writer.call(copied_text)
	status.text="Copied"+(" · partial answer" if controller.session().messages[index].state!="complete" else "")





func apply_full_glass() -> void:
	if not full_material:return
	var values:Dictionary=host.preference_preview
	full_material.set_shader_parameter("dimensions",Vector2(window.size))
	full_material.set_shader_parameter("opacity",values.get("glass_opacity",.72))
	full_material.set_shader_parameter("tint",values.get("glass_tint",.3))
	full_material.set_shader_parameter("frost",values.get("glass_blur",.75))
	if window.visible:full_glass_status=FoxGlassBridge.configure((window.get_window_id()<<8)|roundi(values.get("glass_blur",.75)*100))
