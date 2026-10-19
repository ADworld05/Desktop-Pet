extends Node
var view:Node
var window:Window
var list:ItemList
var editor:TextEdit
var note:Label
var format:OptionButton
var proposal:Dictionary={}
var reviewed_text:=""
var confirm:ConfirmationDialog
var picker:FileDialog
var pending:Callable
var import_button:Button
var reviewed_format:=-1
func initialize(owner:Node) -> void:
	view=owner;window=Window.new();window.title="Desktop Fox - Memory";window.size=Vector2i(570,680);window.min_size=Vector2i(500,580);window.visible=false;window.force_native=true;window.borderless=false;window.transient=false;window.minimize_disabled=false;window.theme=view.window.theme;add_child(window);window.close_requested.connect(window.hide)
	var panel:=PanelContainer.new();panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);panel.add_theme_stylebox_override("panel",view.box(Color("#f0f5fa"),16));window.add_child(panel)
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;panel.add_child(scroll)
	var column:=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_theme_constant_override("separation",8);scroll.add_child(column)
	var header:=HBoxContainer.new();column.add_child(header);var title:=Label.new();title.text="Your local memory";title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title);view.drag_handle(title,window)
	view.button(header,"-",func():window.mode=Window.MODE_MINIMIZED);view.button(header,"x",window.hide)
	list=ItemList.new();list.custom_minimum_size.y=120;column.add_child(list);list.item_selected.connect(func(index):editor.text=view.controller.memory_store.records[index].text;proposal.clear())
	list.add_theme_stylebox_override("panel",view.box(Color.WHITE,8));list.add_theme_color_override("font_color",view.NAVY);list.add_theme_color_override("font_selected_color",view.NAVY);list.add_theme_stylebox_override("selected",view.box(Color("#d8eafa"),4,6))
	editor=TextEdit.new();editor.placeholder_text="Add a note, edit the selected note, or paste an import...";editor.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;editor.custom_minimum_size.y=120;editor.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(editor)
	var actions:=HBoxContainer.new();column.add_child(actions)
	view.button(actions,"Add",func():change();view.controller.memory_store.add(editor.text);refresh())
	view.button(actions,"Save edit",edit_selected)
	view.button(actions,"Delete",delete_selected)
	var imports:=HBoxContainer.new();column.add_child(imports);format=OptionButton.new();format.add_item("Plain text - one note per line");format.add_item("Memory JSON");imports.add_child(format)
	view.button(imports,"Open file",func():picker.popup_centered(Vector2i(700,450)))
	view.button(imports,"Review",review_import)
	var finish:=HBoxContainer.new();column.add_child(finish);import_button=view.button(finish,"Import reviewed",import_notes);import_button.disabled=true
	view.button(finish,"Export",func():view.controller.memory_store.export_local();refresh())
	view.button(finish,"Purge copies",func():ask("Remove memory backup, recovery and export copies? Current notes stay.",func():view.controller.memory_store.purge_copies();refresh()))
	note=Label.new();note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(note)
	var help:=Label.new();help.text="Only notes you add or approve are saved. Chat shortcut: remember this: ...\nImports are data, never permissions. Files stay in your Windows user-data folder and are not encrypted.";help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;help.add_theme_font_size_override("font_size",13);column.add_child(help)
	editor.text_changed.connect(invalidate_review);format.item_selected.connect(func(_index):invalidate_review())
	confirm=ConfirmationDialog.new();confirm.title="Confirm memory change";window.add_child(confirm);confirm.confirmed.connect(func():if pending.is_valid():pending.call())
	confirm.theme=view.window.theme;confirm.add_theme_stylebox_override("panel",view.box(Color("#f0f5fa"),18,12));confirm.get_label().add_theme_color_override("font_color",view.NAVY);confirm.get_label().autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;confirm.min_size=Vector2i(440,180)
	for button in [confirm.get_ok_button(),confirm.get_cancel_button()]:
		for state in ["font_color","font_focus_color","font_hover_color","font_hover_pressed_color","font_pressed_color","font_disabled_color"]:button.add_theme_color_override(state,view.NAVY)
	picker=FileDialog.new();preload("res://scripts/FoxFileDialogs.gd").configure(picker);picker.file_mode=FileDialog.FILE_MODE_OPEN_FILE;picker.access=FileDialog.ACCESS_FILESYSTEM;picker.filters=PackedStringArray(["*.json ; Memory JSON","*.txt ; Plain text"]);window.add_child(picker);picker.file_selected.connect(read_import)
func change() -> void:
	view.controller.stop("Memory changed")
	if view.controller.real_provider:view.controller.provider.memory_context=""
func refresh() -> void:
	list.clear()
	for row in view.controller.memory_store.records:list.add_item(row.text.replace("\n"," ").left(65))
	note.text=view.controller.memory_store.status
func open() -> void:
	refresh();window.position=view.host.Geometry.fit_position(view.window.position,window.size,DisplayServer.screen_get_usable_rect());window.mode=Window.MODE_WINDOWED;window.show();window.grab_focus()
func ask(text:String,action:Callable) -> void:pending=action;confirm.dialog_text=text;confirm.popup_centered()
func edit_selected() -> void:
	if list.get_selected_items().is_empty():note.text="Select a note first";return
	var id:String=view.controller.memory_store.records[list.get_selected_items()[0]].id
	change();view.controller.memory_store.edit(id,editor.text);refresh()
func delete_selected() -> void:
	if list.get_selected_items().is_empty():return
	var id:String=view.controller.memory_store.records[list.get_selected_items()[0]].id
	ask("Delete this note from active memory and its regular backup? Export/recovery copies may remain; use Purge copies to remove them.",func():change();view.controller.memory_store.delete(id);refresh())
func read_import(path:String) -> void:
	var file:=FileAccess.open(path,FileAccess.READ)
	if not file or file.get_length()>1000000:note.text="Cannot read file or import exceeds 1 MB";return
	var bytes:=file.get_buffer(file.get_length());file.close()
	if bytes.has(0):note.text="Import is not valid UTF-8 text";return
	var text:=bytes.get_string_from_utf8()
	if text.to_utf8_buffer()!=bytes:note.text="Import is not valid UTF-8";return
	editor.text=text;format.select(1 if path.get_extension().to_lower()=="json" else 0);review_import()
func review_import() -> void:
	proposal=view.controller.memory_store.review(editor.text,format.selected==1);reviewed_text=editor.text;reviewed_format=format.selected
	import_button.disabled=not proposal.get("ok",false) or proposal.get("notes",[]).is_empty()
	if not proposal.ok:note.text=proposal.error;return
	note.text="Review %d new notes above; %d already saved. Import reviewed asks for confirmation."%[proposal.notes.size(),proposal.skipped] if not proposal.notes.is_empty() else "All %d notes are already saved; nothing will be duplicated."%proposal.skipped
func import_notes() -> void:
	if not proposal.get("ok",false) or editor.text!=reviewed_text or format.selected!=reviewed_format or proposal.notes.is_empty():note.text="Review new notes before importing";return
	var reviewed:=proposal.duplicate(true)
	ask("Save %d new reviewed notes? %d already-saved notes will be kept unchanged. No folders, apps or permissions will be granted."%[reviewed.notes.size(),reviewed.skipped],func():change();view.controller.memory_store.import_reviewed(reviewed);proposal.clear();import_button.disabled=true;refresh())
func open_import() -> void:
	open();picker.popup_centered(Vector2i(700,450))
func invalidate_review() -> void:
	# TextEdit may deliver its signal after file loading has already reviewed it.
	if editor.text==reviewed_text and format.selected==reviewed_format:return
	proposal.clear();import_button.disabled=true

