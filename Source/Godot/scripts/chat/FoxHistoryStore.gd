extends RefCounted
const Paths=preload("res://scripts/Paths.gd")
const Atomic=preload("FoxHistoryAtomic.gd")
const SettingsAtomic=preload("res://scripts/settings/FoxAtomicJson.gd")
const SESSION_SCHEMA:="desktop-fox.history.session"
const INDEX_SCHEMA:="desktop-fox.history.index"
const MAX_SESSION_BYTES:=6000000
const MAX_INDEX_BYTES:=524288
const HARD_SESSIONS:=1000
const MAX_MESSAGES:=80
const DEFAULTS:={"version":1,"session_limit":200,"storage_mb":100}
var root:String
var settings_path:String
var entries:Array[Dictionary]=[]
var settings:Dictionary=DEFAULTS.duplicate()
var status:="History not opened"
var writable:=true
var settings_writable:=true
var recovered:=false
func _init(history_root:String="",config_path:String="") -> void:
	root=Paths.directory("history") if history_root.is_empty() else history_root
	settings_path=Paths.directory("config")+"/history.json" if config_path.is_empty() else config_path
static func uuid() -> String:
	var bytes:=Crypto.new().generate_random_bytes(16);bytes[6]=(bytes[6]&15)|64;bytes[8]=(bytes[8]&63)|128
	var value:=bytes.hex_encode();return "%s-%s-%s-%s-%s"%[value.substr(0,8),value.substr(8,4),value.substr(12,4),value.substr(16,4),value.substr(20,12)]
static func valid_id(value:Variant) -> bool:
	if not value is String or value.length()!=36:return false
	for index in 36:
		if index in [8,13,18,23]:
			if value[index]!="-":return false
		elif not value[index] in "0123456789abcdef":return false
	return true
static func stamp() -> String:return Time.get_datetime_string_from_system(true)+"Z"
static func text_ok(value:Variant,limit:int) -> bool:return value is String and value.length()<=limit
static func time_ok(value:Variant) -> bool:
	if not value is String or value.length()!=20 or value[4]!="-" or value[7]!="-" or value[10]!="T" or value[13]!=":" or value[16]!=":" or value[19]!="Z":return false
	for part in [value.substr(0,4),value.substr(5,2),value.substr(8,2),value.substr(11,2),value.substr(14,2),value.substr(17,2)]:
		if not part.is_valid_int() or part.begins_with("+") or part.begins_with("-"):return false
	var year:=int(value.substr(0,4));var month:=int(value.substr(5,2));var day:=int(value.substr(8,2))
	if year<1970 or month<1 or month>12 or day<1:return false
	var days:=[31,29 if year%4==0 and (year%100!=0 or year%400==0) else 28,31,30,31,30,31,31,30,31,30,31]
	return day<=days[month-1] and int(value.substr(11,2))<24 and int(value.substr(14,2))<60 and int(value.substr(17,2))<60
static func exact_keys(value:Dictionary,allowed:Array) -> bool:
	for key in value:
		if key not in allowed:return false
	return true
static func validate_summary(row:Variant) -> bool:
	return row is Dictionary and exact_keys(row,["id","title","model","created_at","updated_at"]) and valid_id(row.get("id")) and text_ok(row.get("title"),100) and text_ok(row.get("model"),100) and time_ok(row.get("created_at")) and time_ok(row.get("updated_at"))
static func validate_index(raw:Dictionary) -> Dictionary:
	if not exact_keys(raw,["schema","version","sessions"]) or raw.get("schema")!=INDEX_SCHEMA or raw.get("version") not in [0,1] or not raw.get("sessions") is Array or raw.sessions.size()>HARD_SESSIONS:return {"ok":false}
	var ids:Dictionary={}
	for row in raw.sessions:
		if not validate_summary(row) or ids.has(row.id):return {"ok":false}
		ids[row.id]=true
	var data:=raw.duplicate(true);data.version=1;return {"ok":true,"data":data}
static func validate_session(raw:Dictionary) -> Dictionary:
	if not exact_keys(raw,["schema","version","id","title","model","created_at","updated_at","draft","messages"]) or raw.get("schema")!=SESSION_SCHEMA or raw.get("version") not in [0,1]:return {"ok":false}
	var summary:={}
	for key in ["id","title","model","created_at","updated_at"]:summary[key]=raw.get(key)
	if not validate_summary(summary) or not text_ok(raw.get("draft"),4000) or not raw.get("messages") is Array or raw.messages.size()>MAX_MESSAGES:return {"ok":false}
	var data:=raw.duplicate(true);data.version=1;var ids:Dictionary={}
	for message in data.messages:
		if not message is Dictionary:return {"ok":false}
		if raw.version==0 and message.has("content"):message.text=message.content;message.erase("content")
		if not exact_keys(message,["id","role","text","state","model","created_at","updated_at","tool_summaries"]) or not valid_id(message.get("id")) or ids.has(message.id):return {"ok":false}
		ids[message.id]=true
		if message.get("role") not in ["user","assistant"] or message.get("state") not in ["complete","streaming","cancelled","error"] or not text_ok(message.get("text"),48000) or not text_ok(message.get("model"),100):return {"ok":false}
		if not time_ok(message.get("created_at")) or not time_ok(message.get("updated_at")) or message.get("tool_summaries")!=[]:return {"ok":false}
		if message.role=="user" and (message.text.length()>4000 or message.state!="complete"):return {"ok":false}
	return {"ok":true,"data":data}
func path_for(id:String) -> String:return root+"/"+id+".json" if valid_id(id) else ""
func _summary(data:Dictionary) -> Dictionary:
	var row:={}
	for key in ["id","title","model","created_at","updated_at"]:row[key]=data[key]
	return row
func open() -> void:
	entries.clear();settings=DEFAULTS.duplicate();writable=true;settings_writable=true;recovered=false
	if DirAccess.make_dir_recursive_absolute(root)!=OK:status="History folder unavailable";writable=false;return
	if DirAccess.open(root)==null:status="History folder unavailable";writable=false;return
	var prefs:=SettingsAtomic.read_local(settings_path)
	settings_writable=prefs.status!="unsupported_version"
	if prefs.data.get("session_limit") is float or prefs.data.get("session_limit") is int:settings.session_limit=clampi(int(prefs.data.session_limit),20,HARD_SESSIONS)
	if prefs.data.get("storage_mb") is float or prefs.data.get("storage_mb") is int:settings.storage_mb=clampi(int(prefs.data.storage_mb),16,512)
	var index:=Atomic.read_local(root+"/index.json",validate_index,MAX_INDEX_BYTES)
	if index.status=="future_version":writable=false;status="History uses a newer format; saving is disabled";return
	if index.status in ["ok","recovered_backup"]:
		for row in index.data.sessions:entries.append(row.duplicate(true))
		recovered=index.status=="recovered_backup" or index.get("migrated",false)
	elif index.status!="missing":recovered=true
	# Reconcile orphan committed sessions after an interrupted index replacement.
	var known:Dictionary={}
	for row in entries:known[row.id]=true
	var directory:=DirAccess.open(root)
	var names:=directory.get_files();var inspected:=0
	for name in names:
		if not name.ends_with(".json") or not valid_id(name.trim_suffix(".json")):continue
		inspected+=1
		if inspected>HARD_SESSIONS:status="Too many history files; saving disabled for review";writable=false;return
		var id:=name.trim_suffix(".json")
		if known.has(id):continue
		var loaded:=Atomic.read_local(path_for(id),validate_session,MAX_SESSION_BYTES)
		if loaded.status in ["ok","recovered_backup"] and loaded.data.id==id:entries.append(_summary(loaded.data));known[id]=true;recovered=true
	if entries.size()>HARD_SESSIONS:writable=false;status="History index limit exceeded";return
	var before_delete:=entries.size()
	entries=entries.filter(func(row):return not FileAccess.file_exists(root+"/"+row.id+".deleted"))
	if entries.size()!=before_delete:recovered=true
	entries.sort_custom(func(a,b):return a.created_at<b.created_at)
	status="History recovered; previous copies preserved" if recovered else "History ready"
	if index.status not in ["ok","missing"] and entries.is_empty():writable=false;status="History is damaged; original files preserved, saving disabled";return
	if recovered and not _save_index():writable=false
func _save_index() -> bool:
	var data:={"schema":INDEX_SCHEMA,"version":1,"sessions":entries}
	var error:=Atomic.write_local(root+"/index.json",data,validate_index,MAX_INDEX_BYTES)
	if error!=OK:status="History index could not save: "+error_string(error);return false
	return true
func summaries() -> Array[Dictionary]:return entries.duplicate(true)
func storage_bytes() -> int:
	var total:=0;var directory:=DirAccess.open(root)
	if not directory:return 0
	for name in directory.get_files():
		var file:=FileAccess.open(root+"/"+name,FileAccess.READ)
		if file:total+=file.get_length();file.close()
	return total
func save(data:Dictionary) -> bool:
	if not writable: return false
	if valid_id(data.get("id")) and FileAccess.file_exists(root+"/"+data.id+".deleted"):status="Deleted chat cannot be saved again";return false
	var checked:=validate_session(data)
	if not checked.get("ok",false):status="History rejected invalid session data";return false
	var existing:=-1
	for index in entries.size():
		if entries[index].id==data.id:existing=index;break
	if existing<0 and entries.size()>=HARD_SESSIONS:status="History hard limit reached; review saved chats";return false
	var path:=path_for(data.id);var new_bytes:=JSON.stringify(data).to_utf8_buffer().size()+1
	# Conservative reserve for primary + one complete backup; never prune silently.
	var reserve:=2*new_bytes
	if FileAccess.file_exists(path):
		var previous:=FileAccess.open(path,FileAccess.READ)
		if not previous:status="History cannot read the prior file; saving deferred";return false
		reserve=maxi(reserve,previous.get_length()+new_bytes);previous.close()
	if storage_bytes()+reserve>int(settings.storage_mb)*1000000:status="History storage limit reached; no chats were deleted";return false
	var error:=Atomic.write_local(path,data,validate_session,MAX_SESSION_BYTES)
	if error!=OK:status="History could not save: "+error_string(error);return false
	if existing<0:entries.append(_summary(data))
	else:entries[existing]=_summary(data)
	if not _save_index():return false
	status="History saved" if entries.size()<int(settings.session_limit) else "Session review limit reached; no chats were deleted"
	return true
func load_session(id:String) -> Dictionary:
	if not valid_id(id):return {"ok":false,"status":"Invalid history ID"}
	if FileAccess.file_exists(root+"/"+id+".deleted"):return {"ok":false,"status":"This chat was deleted"}
	var read:=Atomic.read_local(path_for(id),validate_session,MAX_SESSION_BYTES)
	if read.status not in ["ok","recovered_backup"] or read.data.id!=id:return {"ok":false,"status":"Chat unavailable: "+read.status+"; original preserved"}
	var data:Dictionary=read.data;var interrupted:=false
	for row in data.messages:
		if row.state=="streaming":row.state="cancelled";row.updated_at=stamp();interrupted=true
	var detail:="Interrupted response retained as partial" if interrupted else "Recovered saved chat" if read.status=="recovered_backup" else "Saved chat loaded"
	if interrupted or read.status=="recovered_backup" or read.get("migrated",false):
		if not save(data):detail+="; repair could not save"
	return {"ok":true,"data":data,"status":detail}
func save_settings(session_limit:int,storage_mb:int) -> bool:
	if not settings_writable:status="Retention settings use a newer format";return false
	var next:={"version":1,"session_limit":clampi(session_limit,20,HARD_SESSIONS),"storage_mb":clampi(storage_mb,16,512)}
	var error:=SettingsAtomic.write_local(settings_path,next)
	if error!=OK:status="Retention settings could not save: "+error_string(error);return false
	settings=next;status="Retention limits saved; no automatic deletion";return true
func delete_session(id:String) -> bool:
	if not writable or not valid_id(id) or not entries.any(func(row):return row.id==id):return false
	# Permanent app-owned tombstone excludes this UUID even during index rebuild.
	if Atomic.replace(root+"/"+id+".deleted",'{"version":1,"deleted":true}\n')!=OK:status="Deletion marker could not save; chat kept";return false
	entries=entries.filter(func(row):return row.id!=id)
	var index_ok:=_save_index();var removed:=true
	for name in DirAccess.open(root).get_files():
		if name==id+".json" or name.begins_with(id+".json."):
			if DirAccess.remove_absolute(root+"/"+name)!=OK:removed=false
	status="Chat deleted with its saved copies" if index_ok and removed else "Chat excluded; some index/copy cleanup failed"
	return true
func purge_recovery() -> bool:
	if not writable:return false
	for name in DirAccess.open(root).get_files():
		var base:=name.split(".json")[0]
		if base!="index" and not valid_id(base):continue
		if name.ends_with(".json.bak") or name.ends_with(".json.tmp") or name.ends_with(".json.v0.bak") or name.contains(".json.corrupt-"):
			if DirAccess.remove_absolute(root+"/"+name)!=OK:status="Some recovery copies could not be removed";return false
	status="History recovery copies removed; chats and deletion markers kept";return true
