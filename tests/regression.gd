extends SceneTree
const Manager=preload("res://scripts/chat/FoxModelManager.gd")
const Provider=preload("res://scripts/chat/FoxOllamaProvider.gd")
const Paths=preload("res://scripts/Paths.gd")
var checks:Array=[]
func check(label:String,ok:bool)->void:
	checks.append({"check":label,"pass":ok})
	if not ok:push_error(label)

class MemoryView extends Node:
	const NAVY=Color("203b54")
	var window:Window
	var controller:RefCounted
	func box(color:Color,_radius:int,_margin:int=12)->StyleBoxFlat:
		var result:=StyleBoxFlat.new();result.bg_color=color;return result
	func button(parent:Node,label:String,callback:Callable)->Button:
		var result:=Button.new();result.text=label;result.pressed.connect(callback);parent.add_child(result);return result
	func drag_handle(_control:Control,_window:Window)->void:pass
class MemoryController extends RefCounted:
	var memory_store:RefCounted
	var real_provider:=false
	var stops:=0
	func stop(_reason:String)->void:stops+=1

func press_memory(memory:Node,label:String)->void:
	var buttons:Array=memory.window.find_children("*","Button",true,false).filter(func(button):return button.text==label)
	assert(buttons.size()==1,"Memory action is not unique: "+label)
	buttons[0].pressed.emit()

func check_memory_buttons()->void:
	var view:=MemoryView.new();root.add_child(view)
	view.window=Window.new();view.window.visible=false;view.window.theme=Theme.new();root.add_child(view.window)
	var controller:=MemoryController.new();view.controller=controller
	var folder:=OS.get_environment("APPDATA")+"/ButtonFixture"
	controller.memory_store=preload("res://scripts/chat/FoxMemoryStore.gd").new(folder+"/memory.json");controller.memory_store.open()
	var memory:=preload("res://scripts/chat/FoxMemoryControls.gd").new();root.add_child(memory);memory.initialize(view)
	check("Memory Open file uses native dialog",memory.picker.use_native_dialog)
	check("Memory picker isolates fallback theme",memory.picker.theme!=view.window.theme and memory.picker.theme!=null)
	check("Memory picker retains file-only filters",memory.picker.file_mode==FileDialog.FILE_MODE_OPEN_FILE and memory.picker.filters.size()==2)
	check("Memory Open file is connected",memory.window.find_children("*","Button",true,false).any(func(button):return button.text=="Open file" and not button.pressed.get_connections().is_empty()))
	memory.editor.text="SYNTHETIC fox button check";press_memory(memory,"Add")
	check("Memory Add callback persists note",controller.memory_store.records.size()==1 and memory.list.item_count==1)
	memory.list.select(0);memory.list.item_selected.emit(0)
	check("Memory selection loads note editor",memory.editor.text=="SYNTHETIC fox button check")
	memory.editor.text="SYNTHETIC edited button check";press_memory(memory,"Save edit")
	check("Memory Save edit callback persists change",controller.memory_store.records[0].text==memory.editor.text)
	press_memory(memory,"Export")
	check("Memory Export writes actual document",FileAccess.file_exists(folder+"/export.json") and JSON.parse_string(FileAccess.get_file_as_string(folder+"/export.json")).records[0].text==memory.editor.text)
	memory.format.select(0);memory.editor.text="SYNTHETIC import A\nSYNTHETIC import B";press_memory(memory,"Review")
	check("Memory Review enables reviewed import",memory.proposal.get("ok",false) and not memory.import_button.disabled and memory.proposal.notes.size()==2)
	press_memory(memory,"Import reviewed")
	check("Memory Import waits for confirmation",controller.memory_store.records.size()==1 and memory.pending.is_valid())
	memory.confirm.confirmed.emit();memory.confirm.hide()
	check("Memory confirmed Import persists both notes",controller.memory_store.records.size()==3)
	memory.editor.text="SYNTHETIC import A";press_memory(memory,"Review")
	check("Memory duplicate import disabled",memory.import_button.disabled and memory.proposal.skipped==1)
	memory.editor.text="SYNTHETIC unreviewed";memory.invalidate_review()
	check("Memory edit invalidates previous review",memory.import_button.disabled and memory.proposal.is_empty())
	var file:=FileAccess.open(folder+"/fixture.txt",FileAccess.WRITE);file.store_string("SYNTHETIC file import");file.close();memory.read_import(folder+"/fixture.txt")
	check("Memory file-selected route loads and reviews text",memory.editor.text=="SYNTHETIC file import" and not memory.import_button.disabled)
	memory.read_import(folder+"/export.json")
	check("Memory JSON file import detects saved duplicate",memory.format.selected==1 and memory.import_button.disabled and memory.proposal.skipped==1)
	memory.format.select(1);memory.editor.text="broken JSON";press_memory(memory,"Review")
	check("Memory malformed JSON remains disabled",memory.import_button.disabled and memory.note.text=="Malformed JSON")
	memory.list.select(0);memory.list.item_selected.emit(0);press_memory(memory,"Delete")
	check("Memory Delete waits for confirmation",controller.memory_store.records.size()==3 and memory.pending.is_valid())
	memory.confirm.canceled.emit();memory.confirm.hide()
	check("Memory Delete cancel keeps notes",controller.memory_store.records.size()==3)
	press_memory(memory,"Delete");memory.confirm.confirmed.emit();memory.confirm.hide()
	check("Memory Delete confirmed callback deletes fixture only",controller.memory_store.records.size()==2)
	press_memory(memory,"Export");press_memory(memory,"Purge copies")
	check("Memory Purge waits for confirmation",FileAccess.file_exists(folder+"/export.json"))
	memory.confirm.canceled.emit();memory.confirm.hide()
	check("Memory Purge cancel keeps export",FileAccess.file_exists(folder+"/export.json"))
	press_memory(memory,"Purge copies");memory.confirm.confirmed.emit();memory.confirm.hide()
	check("Memory Purge removes copies not primary notes",not FileAccess.file_exists(folder+"/export.json") and FileAccess.file_exists(folder+"/memory.json") and controller.memory_store.records.size()==2)
	check("Memory change callbacks stop stale generation",controller.stops>=3)
	check("Memory header close remains connected",memory.window.find_children("*","Button",true,false).any(func(button):return button.text=="x" and not button.pressed.get_connections().is_empty()))
	check("Memory header minimize remains connected",memory.window.find_children("*","Button",true,false).any(func(button):return button.text=="-" and not button.pressed.get_connections().is_empty()))
	for mode in [FileDialog.FILE_MODE_OPEN_FILE,FileDialog.FILE_MODE_OPEN_DIR]:
		var picker:=FileDialog.new();picker.file_mode=mode;preload("res://scripts/FoxFileDialogs.gd").configure(picker)
		check("Shared native picker preserves file/folder mode "+str(mode),picker.use_native_dialog and picker.file_mode==mode);picker.free()
	memory.queue_free();view.window.queue_free();view.queue_free()
func check_memory_help()->void:
	var view:=MemoryView.new();root.add_child(view)
	view.window=Window.new();view.window.visible=false;view.window.theme=Theme.new();root.add_child(view.window);view.controller=RefCounted.new()
	var memory:=preload("res://scripts/chat/FoxMemoryControls.gd").new();root.add_child(memory);memory.initialize(view)
	var labels:=memory.window.find_children("*","Label",true,false)
	check("exported Memory help uses Windows user data",labels.any(func(label):return label.text.contains("Files stay in your Windows user-data folder")))
	check("exported Memory help has no G drive claim",labels.all(func(label):return not label.text.contains("Files stay on G:")))
	check("Memory native title is clean",memory.window.title=="Desktop Pet - Memory")
	check("Memory editor keeps compact minimum",memory.editor.custom_minimum_size.y==120)
	check("Memory overflow has scroll fallback",memory.editor.get_parent().get_parent() is ScrollContainer)
	memory.queue_free();view.window.queue_free();view.queue_free()

func _initialize()->void:
	if not OS.get_environment("APPDATA").contains("DesktopPetTests"):quit(2);return
	check("profile prepared",Paths.prepare_runtime()==OK)
	check("cloud word in local model allowed",Manager.valid_tag("myteam/cloudfox:local"))
	check("local catalog cloud word allowed",Provider.local_tag({"name":"myteam/cloudfox:local","size":2000000,"digest":"a".repeat(64)}))
	check("remote metadata still rejected",not Provider.local_tag({"name":"myteam/cloudfox:local","size":2000000,"digest":"a".repeat(64),"remote_host":"remote.example"}))
	check("small metadata-only proxy rejected",not Provider.local_tag({"name":"model:cloud","size":100,"digest":"a".repeat(64)}))
	for tag in ["../model:tag","model;echo:tag","model:tag extra","https://host/model","model:$(command)"]:
		check("invalid tag denied "+tag,not Manager.valid_tag(tag))
	var manager:=Manager.new()
	check("known cloud-only pull denied",not manager.begin("model:cloud"))
	check("cloud-only pull does not start network",not manager.transfer.running)
	var provider:=Provider.new();provider.autostart=false;provider.control.cancel();provider.queue.clear()
	provider.catalog={"example:small":{"size":1500000000,"details":{},"capabilities":["completion"],"digest":"a".repeat(64)}}
	var controller:=preload("res://scripts/chat/FoxChatController.gd").new();controller.use_local_provider(provider)
	controller.select_model("example:small")
	check("one arbitrary model immediately selectable",controller.selected_model_name()=="example:small")
	check("no automatic SLOW mapping",provider.prefs.SLOW=="qwen3:8b")
	check("production FAST recommendation unchanged",provider.prefs.FAST=="qwen3:1.7b")
	check("model prefs are machine-local",Provider.PREFS.begins_with(Paths.directory("machine_config")+"/"))
	check("history is user-owned",preload("res://scripts/chat/FoxHistoryStore.gd").new().root==Paths.directory("history"))
	check("required assets in pack",preload("res://scripts/settings/FoxFirstRun.gd").missing_assets().is_empty())
	var catalog:=preload("res://scripts/animation/FoxAnimationCatalog.gd").new()
	check("39 approved animation entries available",catalog.initialize() and catalog.rows.size()==39)
	check("Qwen required-thinking safe",Provider.thinking_value({"values":[true],"default":true},false)==true)
	check("context remains conservative",provider.prefs.context==4096)
	check("bounded thinking allowance",Provider.generation_budget(384,{"values":[true]})==1408)
	check_memory_help()
	check_memory_buttons()
	var f:=FileAccess.open(OS.get_environment("APPDATA")+"/checks.json",FileAccess.WRITE);f.store_string(JSON.stringify(checks,"\t"));f.close()
	print(JSON.stringify(checks));quit(0 if checks.all(func(row):return row.pass) else 1)
