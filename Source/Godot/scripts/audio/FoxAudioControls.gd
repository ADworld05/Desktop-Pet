extends RefCounted
## T12-only controls; broader settings Apply/Reset belongs to T13.
static func build(audio:Node) -> VBoxContainer:
	var column:=VBoxContainer.new();column.name="AudioControls"
	var title:=Label.new();title.text="Sounds";column.add_child(title)
	var mute:=CheckBox.new();mute.name="Mute";mute.text="Mute all sounds";mute.button_pressed=audio.settings.values.muted;column.add_child(mute)
	mute.toggled.connect(func(value):set_value(audio,"muted",value))
	for entry in [["Pet volume","pet_volume"],["Interface volume","ui_volume"]]:
		var row:=HBoxContainer.new();column.add_child(row)
		var label:=Label.new();label.text=entry[0];label.custom_minimum_size.x=135;row.add_child(label)
		var slider:=HSlider.new();slider.name=entry[1];slider.min_value=0;slider.max_value=1;slider.step=.05;slider.value=audio.settings.values[entry[1]];slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(slider)
		slider.value_changed.connect(func(value):set_value(audio,entry[1],value))
	var frequency:=OptionButton.new();frequency.name="Frequency"
	for value in ["Off","Low","Normal"]:frequency.add_item(value)
	frequency.select(["Off","Low","Normal"].find(audio.settings.values.frequency))
	frequency.item_selected.connect(func(index):set_value(audio,"frequency",["Off","Low","Normal"][index]))
	var frequency_row:=HBoxContainer.new();column.add_child(frequency_row)
	var text:=Label.new();text.text="Sound frequency";text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;frequency_row.add_child(text);frequency_row.add_child(frequency)
	var previews:=HBoxContainer.new();column.add_child(previews)
	for entry in [["Try chirp","interaction"],["Try result","result"],["Try tap","ui"]]:
		var button:=Button.new();button.text=entry[0];previews.add_child(button)
		button.pressed.connect(func():audio.request(entry[1],true))
	var help:=Label.new();help.text="Low: occasional sounds. Off silences everything.\nSamples obey mute and quiet states; wait 1 second between them.";help.add_theme_font_size_override("font_size",13);column.add_child(help)
	return column

static func set_value(audio:Node,key:String,value:Variant) -> void:
	audio.update_setting(key,value)
	if audio.settings.save_local()!=OK:push_error("Could not save sound preferences.")
