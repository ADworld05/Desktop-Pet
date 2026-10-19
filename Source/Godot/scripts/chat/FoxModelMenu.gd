extends RefCounted
static func refresh(menu:OptionButton,controller:RefCounted,icon:bool=false) -> void:
	var choices:Array[Dictionary]=controller.model_choices()
	var signature:=JSON.stringify(choices)
	if menu.get_meta("catalog_signature","")!=signature:
		menu.clear()
		for row in choices:
			menu.add_item(row.label);menu.set_item_metadata(menu.item_count-1,row.name);menu.get_popup().set_item_tooltip(menu.item_count-1,row.tooltip)
		menu.set_meta("catalog_signature",signature)
	menu.disabled=choices.is_empty()
	var current:String=controller.selected_model_name()
	for index in choices.size():
		if choices[index].name==current:menu.select(index);break
	if icon:menu.text="◈"
	elif choices.is_empty():menu.text="Detecting local models…"
	menu.tooltip_text="Model: "+current if not current.is_empty() else "Local model unavailable; use Refresh in Local AI"
