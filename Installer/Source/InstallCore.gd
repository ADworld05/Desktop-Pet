extends RefCounted
## Local setup only: fixed target, exact payload names, native metadata checks.
static var DEFAULT:String:
	get: return OS.get_environment("LOCALAPPDATA").replace("\\","/").path_join("Programs/DesktopFox")
static var TEST_ROOT:String:
	get: return OS.get_environment("LOCALAPPDATA").replace("\\","/").path_join("DesktopFox/SetupTests")
const STATE:=".desktopfox-install.json"
const JOURNAL:=".desktopfox-transaction.json"
const STAGE:=".desktopfox-stage"
const BACKUP:=".desktopfox-previous"
const PAYLOAD:="res://payload.zip"
const META:="res://payload.json"
var root:=DEFAULT
var manifest:Dictionary={}
var last_error:=""
var fail_after:=-1 # Test-only fault injection; never supplied by setup UI.
var fixture:=false
var shortcut_runner:Callable
func _init(destination:String="")->void:
	root=DEFAULT if destination.is_empty() else destination
	fixture=OS.has_feature("editor") and root.begins_with(TEST_ROOT+"/")
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(META))
	if parsed is Dictionary:manifest=parsed
func bad(reason:String)->Dictionary:return {"ok":false,"reason":reason,"data_kept":true}
func names()->Array:return manifest.get("files",{}).keys()
func valid_name(name:Variant)->bool:
	return name is String and name in names() and not name.contains("\\") and not name.contains(":") and not ".." in name and not name.begins_with("/")
func metadata(path:String)->Dictionary:
	if not ClassDB.class_exists("FoxPathBoundary"):return {"ok":false,"reason":"Windows file checks unavailable"}
	var value:Variant=JSON.parse_string(ClassDB.class_call_static("FoxPathBoundary","resolve_metadata",path))
	return value if value is Dictionary else {"ok":false,"reason":"Windows file check failed"}
func guard(path:String,missing:bool=false)->bool:
	if root!=DEFAULT and not fixture:last_error="Setup target is not allowed";return false
	if path!=root and not path.begins_with(root+"/"):last_error="Path is outside the application folder";return false
	var parts:=path.split("/");var current:=parts[0]+"/"
	for index in range(1,parts.size()):
		if parts[index].is_empty() or parts[index] in [".",".."] or parts[index].ends_with(".") or parts[index].ends_with(" "):last_error="Ambiguous application path";return false
		current=current.path_join(parts[index])
		var result:=metadata(current)
		if not result.get("ok",false):
			if missing and result.get("reason")=="missing_or_denied":continue
			last_error="Unsafe or unavailable application path: "+str(result.get("reason"));return false
		if str(result.path).to_lower()!=current.to_lower():last_error="Application path resolves elsewhere";return false
	return true
func mkdir(path:String)->bool:
	if not guard(path,true):return false
	var code:=DirAccess.make_dir_recursive_absolute(path)
	if code!=OK:last_error="Cannot create application folder: "+error_string(code);return false
	return guard(path)
func read_json(path:String)->Dictionary:
	if not guard(path):return {}
	if FileAccess.get_file_as_bytes(path).size()>65536:last_error="Setup metadata too large";return {}
	var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}
func valid_state(value:Dictionary)->bool:
	if value.get("schema")!="desktopfox.install" or value.get("version")!=1 or not value.get("files") is Dictionary:return false
	for name in value.files:
		if not valid_name(name) or not value.files[name] is String or value.files[name].length()!=64:return false
	return true
func installed()->Dictionary:
	if not guard(root,true):return {}
	if not FileAccess.file_exists(root+"/"+STATE):return {}
	var state:=read_json(root+"/"+STATE)
	return state if valid_state(state) else {}
func write_json(path:String,value:Dictionary)->bool:
	if not guard(path,true):return false
	var tmp:=path+".tmp"
	if FileAccess.file_exists(tmp) or not guard(tmp,true):last_error="A setup temporary file already exists";return false
	var f:=FileAccess.open(tmp,FileAccess.WRITE)
	if not f:last_error="Cannot save setup metadata";return false
	f.store_string(JSON.stringify(value,"\t"));var okay:=f.get_error()==OK;f.close()
	if not okay:return false
	if FileAccess.file_exists(path):
		if not guard(path) or DirAccess.remove_absolute(path)!=OK:return false
	return DirAccess.rename_absolute(tmp,path)==OK
func file_hash(path:String,expected:String)->bool:
	return guard(path) and FileAccess.get_sha256(path)==expected
func copy_checked(source:String,dest:String,expected:String)->bool:
	if not file_hash(source,expected) or not mkdir(dest.get_base_dir()) or not guard(dest,true):return false
	if FileAccess.file_exists(dest):last_error="Refusing to overwrite an unexpected setup file";return false
	var code:=DirAccess.copy_absolute(source,dest)
	if code!=OK:last_error="Cannot copy application file: "+error_string(code);return false
	return file_hash(dest,expected)
func remove_checked(path:String,expected:String)->bool:
	if not file_hash(path,expected):last_error="Changed application file kept: "+path.get_file();return false
	var result:=DirAccess.remove_absolute(path)
	if result!=OK:last_error="Close Desktop Pet and retry. File could not be replaced: "+path.get_file();return false
	return true
func commit_staged(name:String)->bool:
	var source:String=root+"/"+STAGE+"/"+name
	var dest:String=root+"/"+name
	if not file_hash(source,manifest.files[name]) or not mkdir(dest.get_base_dir()) or not guard(dest,true):return false
	if FileAccess.file_exists(dest):last_error="Unexpected file appeared during setup";return false
	# Both paths are within the same validated App directory/volume. Rename
	# the complete verified file, avoiding a partly copied live application.
	var code:=DirAccess.rename_absolute(source,dest)
	if code!=OK:last_error="Cannot commit application file: "+error_string(code);return false
	return file_hash(dest,manifest.files[name])
func clean_work(folder:String)->bool:
	if not DirAccess.dir_exists_absolute(folder):return guard(folder,true)
	if not guard(folder):return false
	var state:=read_json(folder+"/"+STATE)
	if not valid_state(state):last_error="Unrecognized setup work folder kept";return false
	var allowed:Array=state.files.keys();allowed.append(STATE)
	for name in DirAccess.get_files_at(folder):
		if name not in allowed:last_error="Unknown file kept in setup work folder";return false
	for name in DirAccess.get_directories_at(folder):
		if name!="Notices" or not guard(folder+"/Notices"):last_error="Unknown directory kept in setup work folder";return false
		for file in DirAccess.get_files_at(folder+"/Notices"):
			if "Notices/"+file not in allowed:last_error="Unknown notice kept in setup work folder";return false
		if not DirAccess.get_directories_at(folder+"/Notices").is_empty():last_error="Unknown nested directory kept";return false
	for name in state.files:
		if FileAccess.file_exists(folder+"/"+name) and not file_hash(folder+"/"+name,state.files[name]):last_error="Changed backup kept";return false
	for name in state.files:
		var p:String=folder+"/"+name
		if FileAccess.file_exists(p) and not remove_checked(p,state.files[name]):return false
	if not guard(folder+"/"+STATE) or DirAccess.remove_absolute(folder+"/"+STATE)!=OK:return false
	# Remove only known empty directories; never recursively erase user files.
	if DirAccess.dir_exists_absolute(folder+"/Notices"):
		if not guard(folder+"/Notices") or DirAccess.remove_absolute(folder+"/Notices")!=OK:last_error="Unexpected file kept in setup notices folder";return false
	if not guard(folder) or DirAccess.remove_absolute(folder)!=OK:last_error="Unexpected file kept in setup work folder";return false
	return true
func prepare()->Dictionary:
	last_error=""
	if manifest.get("schema")!="desktopfox.payload" or names().is_empty() or names().size()>64:return bad("Setup payload metadata is invalid")
	if not guard(root,true) or not mkdir(root):return bad(last_error)
	if FileAccess.file_exists(root+"/"+JOURNAL):return bad("An interrupted update needs Restore previous version before another change")
	var old:=installed()
	if FileAccess.file_exists(root+"/"+STATE) and old.is_empty():return bad("Unrecognized installation record kept; no files changed")
	for name in names():
		var path:String=root+"/"+name
		if not guard(path,true):return bad(last_error)
		if FileAccess.file_exists(path) and (not old.get("files",{}).has(name) or not file_hash(path,old.files[name])):return bad("Existing or changed file kept: "+name)
	for name in old.get("files",{}):
		if not file_hash(root+"/"+name,old.files[name]):return bad("Changed installed file kept: "+name)
	return {"ok":true,"old":old}
func stage_payload()->bool:
	var folder:=root+"/"+STAGE
	if not clean_work(folder) or not mkdir(folder):return false
	var state:={"schema":"desktopfox.install","version":1,"release":manifest.release,"files":manifest.files.duplicate(true),"shortcuts":{}}
	if not write_json(folder+"/"+STATE,state):return false
	var zip:=ZIPReader.new()
	if zip.open(PAYLOAD)!=OK:last_error="Cannot open setup payload";return false
	var entries:=zip.get_files()
	if entries.size()!=names().size():zip.close();last_error="Unexpected payload file count";return false
	for name in entries:
		if not valid_name(name):zip.close();last_error="Unsafe payload file name";return false
	for name in names():
		var bytes:=zip.read_file(name)
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
		if hash.finish().hex_encode()!=manifest.files[name]:zip.close();last_error="Payload checksum mismatch: "+name;return false
		var dest:String=folder+"/"+name
		if not mkdir(dest.get_base_dir()) or not guard(dest,true) or FileAccess.file_exists(dest):zip.close();return false
		var f:=FileAccess.open(dest,FileAccess.WRITE)
		if not f:zip.close();last_error="Cannot stage application file";return false
		f.store_buffer(bytes);var okay:=f.get_error()==OK;f.close()
		if not okay or not file_hash(dest,manifest.files[name]):zip.close();last_error="Staged checksum failed";return false
	zip.close();return true
func shortcut(kind:String,action:String)->Dictionary:
	if shortcut_runner.is_valid():return shortcut_runner.call(kind,action)
	if fixture:return {"available":false,"enabled":false,"error":"Real shortcut changes disabled in test mode"}
	var out:Array=[]
	var helper:=OS.get_executable_path().get_base_dir()+"/DesktopFoxShortcuts.exe"
	var code:=OS.execute(helper,PackedStringArray([kind,action]),out,true,false)
	var value:Variant=JSON.parse_string("\n".join(out))
	return value if value is Dictionary else {"available":false,"enabled":false,"error":"Shortcut helper unavailable (%s)"%code}
func apply_shortcuts(wanted:Dictionary,previous:Dictionary)->Dictionary:
	var actual:=previous.duplicate(true);var failures:Array=[]
	for kind in ["Desktop","Menu","Startup"]:
		var desired:bool=bool(wanted.get(kind,false));var prior:bool=bool(previous.get(kind,false))
		if not desired and not prior:actual[kind]=false;continue
		var response:=shortcut(kind,"Enable" if desired else "Disable")
		if not response.get("available",false) or response.get("enabled",false)!=desired:failures.append(kind+": "+str(response.get("error","unavailable")))
		else:actual[kind]=desired
	return {"ok":failures.is_empty(),"actual":actual,"errors":failures}
func lock_operation()->bool:
	if not ClassDB.class_exists("FoxWindowBridge"):last_error="Setup instance checks unavailable";return false
	var result:int=ClassDB.class_call_static("FoxWindowBridge","acquire_instance",fixture)
	if result!=1:last_error="Close Desktop Pet or the other setup operation, then retry.";return false
	return true
func unlock_operation()->void:ClassDB.class_call_static("FoxWindowBridge","release_instance")
func install(wanted:Dictionary)->Dictionary:
	if not lock_operation():return bad(last_error)
	var result:=_install(wanted);unlock_operation();return result
func _install(wanted:Dictionary)->Dictionary:
	var ready:=prepare()
	if not ready.ok:return ready
	var old:Dictionary=ready.old
	for kind in ["Desktop","Menu","Startup"]:
		if wanted.get(kind,false):
			var status:=shortcut(kind,"Status")
			if not status.get("available",false) or status.get("conflict",false):return bad("Existing/conflicting "+kind+" shortcut kept. Clear that selection or review it first.")
	if not stage_payload():return bad(last_error)
	var backup:=root+"/"+BACKUP
	if not clean_work(backup) or not mkdir(backup):return bad(last_error)
	var empty:={"schema":"desktopfox.install","version":1,"release":"none","files":{},"shortcuts":{}}
	if not write_json(backup+"/"+STATE,old if not old.is_empty() else empty):return bad(last_error)
	for name in old.get("files",{}):
		if not copy_checked(root+"/"+name,backup+"/"+name,old.files[name]):return bad(last_error)
	var journal:={"schema":"desktopfox.transaction","old":old,"new":manifest.files.duplicate(true)}
	if not write_json(root+"/"+JOURNAL,journal):return bad(last_error)
	var done:=0
	for name in names():
		if fixture and fail_after==done:last_error="Injected test interruption";break
		var dest:String=root+"/"+name
		if old.get("files",{}).has(name) and not remove_checked(dest,old.files[name]):break
		if not commit_staged(name):break
		done+=1
	if done!=names().size():
		var cause:=last_error;var recovered:=_restore(true)
		return {"ok":false,"reason":cause,"rollback_ok":recovered.ok,"data_kept":true}
	var current:={"schema":"desktopfox.install","version":1,"release":manifest.release,"files":manifest.files.duplicate(true),"shortcuts":old.get("shortcuts",{}).duplicate(true)}
	if not write_json(root+"/"+STATE,current):return bad("Files installed but state commit failed; use Restore previous version")
	if not guard(root+"/"+JOURNAL) or DirAccess.remove_absolute(root+"/"+JOURNAL)!=OK:return bad("Files installed; recovery journal could not close")
	if not clean_work(root+"/"+STAGE):return bad(last_error)
	var links:=apply_shortcuts(wanted,current.shortcuts);current.shortcuts=links.actual
	if not write_json(root+"/"+STATE,current):return bad("Application installed; shortcut state save failed")
	return {"ok":links.ok,"reason":"Installed. Your chats, memory, settings and models were kept." if links.ok else "Application installed; shortcut changes need review: "+", ".join(links.errors),"installed":true,"data_kept":true}
func restore(interrupted:bool=false)->Dictionary:
	if not lock_operation():return bad(last_error)
	var result:=_restore(interrupted);unlock_operation();return result
func _restore(interrupted:bool=false)->Dictionary:
	if not guard(root):return bad(last_error)
	var backup:=root+"/"+BACKUP
	var previous:=read_json(backup+"/"+STATE)
	if not valid_state(previous):return bad("No verified previous version is available")
	var current:=installed();var new_files:Dictionary=current.get("files",{})
	var journal:=read_json(root+"/"+JOURNAL) if FileAccess.file_exists(root+"/"+JOURNAL) else {}
	if not journal.is_empty():
		if journal.get("schema")!="desktopfox.transaction" or not journal.get("new") is Dictionary:return bad("Invalid recovery record kept")
		new_files=journal.new
	for name in new_files:
		if not valid_name(name) or not new_files[name] is String:return bad("Invalid recovery file kept")
	for name in previous.files:
		if not file_hash(backup+"/"+name,previous.files[name]):return bad("Previous-version checksum failed")
	for name in new_files:
		var path:String=root+"/"+name
		if FileAccess.file_exists(path) and not file_hash(path,new_files[name]) and not (previous.files.has(name) and file_hash(path,previous.files[name])):return bad("Changed current file kept: "+name)
	for name in new_files:
		var path:String=root+"/"+name
		if FileAccess.file_exists(path):
			if not remove_checked(path,FileAccess.get_sha256(path)):return bad(last_error)
	for name in previous.files:
		if not copy_checked(backup+"/"+name,root+"/"+name,previous.files[name]):return bad(last_error)
	if previous.files.is_empty():
		if FileAccess.file_exists(root+"/"+STATE) and (not guard(root+"/"+STATE) or DirAccess.remove_absolute(root+"/"+STATE)!=OK):return bad("Cannot clear empty installation state")
	elif not write_json(root+"/"+STATE,previous):return bad(last_error)
	if FileAccess.file_exists(root+"/"+JOURNAL):
		if not guard(root+"/"+JOURNAL) or DirAccess.remove_absolute(root+"/"+JOURNAL)!=OK:return bad("Cannot finish recovery journal")
	if not clean_work(root+"/"+STAGE):return bad(last_error)
	return {"ok":true,"reason":"Previous application files restored. Your data was kept.","data_kept":true,"interrupted":interrupted}
func uninstall()->Dictionary:
	if not lock_operation():return bad(last_error)
	var result:=_uninstall();unlock_operation();return result
func _uninstall()->Dictionary:
	if not guard(root):return bad(last_error)
	if FileAccess.file_exists(root+"/"+JOURNAL):return bad("Restore the interrupted update before uninstalling")
	var state:=installed()
	if state.is_empty():return bad("No recognized Desktop Pet installation; nothing removed")
	for name in state.files:
		if not file_hash(root+"/"+name,state.files[name]):return bad("Changed installed file kept; uninstall stopped: "+name)
	var links:=apply_shortcuts({"Desktop":false,"Menu":false,"Startup":false},state.get("shortcuts",{}))
	if not links.ok:return bad("Shortcut conflict kept; uninstall stopped: "+", ".join(links.errors))
	if not clean_work(root+"/"+BACKUP) or not clean_work(root+"/"+STAGE):return bad(last_error)
	for name in state.files:
		if not remove_checked(root+"/"+name,state.files[name]):return bad(last_error)
	if not guard(root+"/"+STATE) or DirAccess.remove_absolute(root+"/"+STATE)!=OK:return bad("Cannot remove application record")
	if DirAccess.dir_exists_absolute(root+"/Notices") and guard(root+"/Notices"):DirAccess.remove_absolute(root+"/Notices")
	if guard(root):DirAccess.remove_absolute(root) # Empty only. Unknown user files stay.
	return {"ok":true,"reason":"Application removed. Chats, memory, settings, models and any unknown files were kept.","data_kept":true}
