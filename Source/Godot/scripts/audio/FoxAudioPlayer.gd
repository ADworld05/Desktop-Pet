extends Node
## One output voice; fixed event allowlist; no backlog, per-token hook or microphone.
const Settings=preload("FoxAudioSettings.gd")
const ROOT:=preload("res://scripts/Paths.gd").ASSET_ROOT+"/Audio/"
const SOUND_IDS:={"interaction":"pet_chirp","result":"pet_result","ui":"ui_tap"}
const FILES:={"pet_chirp":"pet_chirp.wav.bin","pet_result":"pet_result.wav.bin","ui_tap":"ui_tap.wav.bin"}
var settings:=Settings.new()
var output:AudioStreamPlayer
var streams:Dictionary={}
var clock:=0.0
var next_any:=0.0
var next_pet:=0.0
var next_ui:=0.0
var blocked:=false
var current_channel:=""
var played:={"interaction":0,"result":0,"ui":0}

func initialize(load_preferences:bool=true) -> bool:
	if load_preferences:settings.load_local()
	output=AudioStreamPlayer.new();add_child(output)
	output.max_polyphony=1
	for id in FILES:
		var stream:=AudioStreamWAV.load_from_buffer(FileAccess.get_file_as_bytes(ROOT+FILES[id]))
		if not stream:return false
		streams[id]=stream
	return true

func advance(delta:float) -> void:
	clock+=maxf(0.0,delta)

func silence() -> void:
	if output:output.stop()
	current_channel=""

func set_lifecycle(hidden:bool,fullscreen:bool,asleep:bool) -> void:
	var previous:=blocked
	blocked=hidden or fullscreen or asleep
	if blocked:silence()
	elif previous:next_any=maxf(next_any,clock+10.0)

func update_setting(key:String,value:Variant) -> void:
	if not Settings.DEFAULTS.has(key) or key=="version":return
	settings.values[key]=value
	settings.values=settings.sanitize(settings.values)
	if settings.values.muted or settings.values.frequency=="Off":silence()
	elif output and output.playing:
		var volume:float=settings.values.get(current_channel+"_volume",0.0)
		if volume<=0:silence()
		else:output.volume_db=linear_to_db(volume)

func request(event:String,preview:bool=false) -> bool:
	# Preview bypasses long pet-frequency cooldown only, never mute/lifecycle/overlap.
	if not SOUND_IDS.has(event) or not output or not streams.has(SOUND_IDS[event]) or blocked or settings.values.muted or settings.values.frequency=="Off":return false
	var channel:="ui" if event=="ui" else "pet"
	var volume:float=settings.values[channel+"_volume"]
	if volume<=0 or output.playing or clock<next_any:return false
	if clock<next_ui and channel=="ui":return false
	if clock<next_pet and channel=="pet" and not preview:return false
	output.stream=streams[SOUND_IDS[event]]
	output.volume_db=linear_to_db(volume)
	current_channel=channel
	output.play()
	played[event]+=1
	next_any=clock+1.0
	if channel=="pet":next_pet=clock+(12.0 if settings.values.frequency=="Low" else 6.0)
	else:next_ui=clock+0.6
	return true

func snapshot() -> Dictionary:
	return {"settings":settings.values.duplicate(),"playing":output.playing if output else false,"blocked":blocked,"counts":played.duplicate(),"next_pet":next_pet,"clock":clock}
