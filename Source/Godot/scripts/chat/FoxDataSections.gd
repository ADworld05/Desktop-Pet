extends Node
var view:Node
var tabs:TabContainer
var past:ItemList
var memories:ItemList
var detail:TextEdit
var confirm:ConfirmationDialog
var pending:Callable
var signature:=""
var age:=0.0
var memory_info:Label
var transfer_status:Label
func initialize(owner:Node,container:TabContainer) -> void:
	view=owner;tabs=container
	var chats:=VBoxContainer.new();chats.name="Past chats";tabs.add_child(chats)
	var help:=Label.new();help.text="Select a saved conversation to read or continue it.";help.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;chats.add_child(help)
	past=make_list(chats);past.item_activated.connect(func(_index):open_selected())
	var actions:=HBoxContainer.new();chats.add_child(actions);view.button(actions,"Open chat",open_selected)
	view.button(actions,"Delete chat",delete_selected)
	view.button(actions,"Purge recovery copies",func():ask("Remove history recovery copies? Conversations and deletion markers stay. This reduces recovery options.",func():view.controller.history_store.purge_recovery();view.controller.storage_status=view.controller.history_store.status;view.refresh()))
	var memory:=VBoxContainer.new();memory.name="Memory";tabs.add_child(memory)
	var label:=Label.new();label.text="Long-term notes you explicitly saved or approved.";label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;memory.add_child(label)
	memory_info=Label.new();memory_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;memory_info.add_theme_font_size_override("font_size",13);memory.add_child(memory_info)
	memories=make_list(memory);memories.custom_minimum_size.y=150;memories.size_flags_vertical=Control.SIZE_FILL
	detail=TextEdit.new();detail.editable=false;detail.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;detail.size_flags_vertical=Control.SIZE_EXPAND_FILL;detail.placeholder_text="Select a memory to see its full text.";memory.add_child(detail)
	memories.item_selected.connect(func(index):detail.text=view.controller.memory_store.records[index].text)
	var transfers:=HBoxContainer.new();memory.add_child(transfers)
	view.button(transfers,"Manage notes",func():view.memory_controls.open())
	view.button(transfers,"Import memory",func():view.memory_controls.open_import()).name="ImportMemory"
	view.button(transfers,"Export memory",export_memory).name="ExportMemory"
	transfer_status=Label.new();transfer_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;transfer_status.add_theme_font_size_override("font_size",13);memory.add_child(transfer_status)
	confirm=ConfirmationDialog.new();confirm.title="Confirm history change";confirm.theme=view.window.theme;confirm.add_theme_stylebox_override("panel",view.box(Color("#f0f5fa"),18));confirm.get_label().add_theme_color_override("font_color",view.NAVY);confirm.get_label().autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;confirm.min_size=Vector2i(440,180);view.window.add_child(confirm);confirm.confirmed.connect(func():if pending.is_valid():pending.call())
	refresh()
func make_list(parent:Node) -> ItemList:
	var item:=ItemList.new();item.size_flags_vertical=Control.SIZE_EXPAND_FILL;item.add_theme_stylebox_override("panel",view.box(Color.WHITE,8));item.add_theme_color_override("font_color",view.NAVY);item.add_theme_color_override("font_selected_color",view.NAVY);item.add_theme_stylebox_override("selected",view.box(Color("#d8eafa"),4));parent.add_child(item);return item
func refresh() -> void:
	var key:=""
	for row in view.controller.sessions:key+=row.id+row.title
	if view.controller.memory_store!=null:key+=str(view.controller.memory_store.revision)
	if key==signature:return
	signature=key;past.clear();memories.clear();detail.text=""
	for row in view.controller.sessions:past.add_item(row.created_at.left(10)+" · "+row.title);past.set_item_metadata(past.item_count-1,row.id)
	if view.controller.memory_store!=null:
		var count:int=view.controller.memory_store.records.size()
		memory_info.text="%d saved %s · kept after restarting the pet · used in later chats"%[count,"note" if count==1 else "notes"] if view.controller.memory_store.writable else "Memory storage unavailable; open Manage notes for details."
		for row in view.controller.memory_store.records:memories.add_item(row.text.replace("\n"," ").left(70));memories.set_item_tooltip(memories.item_count-1,row.text)
func export_memory() -> void:
	view.controller.memory_store.export_local();transfer_status.text=view.controller.memory_store.status
func _process(delta:float) -> void:
	age+=delta
	if age>=.5:
		age=0
		if view.window.visible and view.window.mode!=Window.MODE_MINIMIZED and tabs.current_tab>0:refresh()
func open_selected() -> void:
	if past.get_selected_items().is_empty():return
	view.choose_session(str(past.get_item_metadata(past.get_selected_items()[0])));tabs.current_tab=0
func ask(text:String,action:Callable) -> void:pending=action;confirm.dialog_text=text;confirm.popup_centered()
func delete_selected() -> void:
	if past.get_selected_items().is_empty():return
	var id:String=past.get_item_metadata(past.get_selected_items()[0])
	ask("Delete this conversation and its saved copies? Long-term memory and model files will stay.",func():view.controller.delete_chat(id);signature="";refresh();view.refresh())
