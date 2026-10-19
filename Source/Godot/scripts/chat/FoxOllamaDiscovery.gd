extends RefCounted
const Paths=preload("res://scripts/Paths.gd")
static func configuration_path()->String:return Paths.directory("machine_config").path_join("ollama_host.json")
static func configuration()->Dictionary:
	var path:=configuration_path()
	if not FileAccess.file_exists(path):return {}
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>4096:return {}
	var parser:=JSON.new()
	if parser.parse(file.get_as_text())!=OK or not parser.data is Dictionary:return {}
	var data:Dictionary=parser.data
	return data if data.get("version")==1 else {}

static func save_selection(kind:String,path:String)->bool:
	# Only explicit Local AI file/folder selection calls this; never chat/model data.
	var boundary=preload("res://scripts/actions/FoxActionPaths.gd")
	var resolved:Dictionary=boundary.resolve_application(path) if kind=="executable" else boundary.resolve(path)
	if kind not in ["executable","store"] or not resolved.get("ok",false):return false
	if kind=="executable" and (resolved.directory or resolved.path.get_file().to_lower()!="ollama.exe"):return false
	if kind=="store" and not resolved.directory:return false
	var data:=configuration();data.version=1;data[kind]=resolved.path
	return preload("res://scripts/settings/FoxAtomicJson.gd").write_local(configuration_path(),data)==OK
## Inspect host configuration only. Never download, move stores or stop a server.
static func select_store(environment:String,home:String) -> Dictionary:
	var explicit:=environment.strip_edges().replace("\\","/").trim_suffix("/")
	if not explicit.is_empty():
		return {"path":explicit if explicit.is_absolute_path() else "", "source":"OLLAMA_MODELS", "valid":explicit.is_absolute_path(), "explicit":true}
	var path:=home.path_join(".ollama/models").replace("\\","/") if home.is_absolute_path() else ""
	return {"path":path,"source":"user default (service configuration not proven)","valid":not path.is_empty(),"explicit":false}

static func version_parts(value:String) -> Array[int]:
	var result:Array[int]=[]
	for part in value.split("."):
		if not part.is_valid_int() or int(part)<0:return []
		result.append(int(part))
	return result if result.size()==3 else []

static func version_newer(a:String,b:String) -> bool:
	var left:=version_parts(a);var right:=version_parts(b)
	if left.is_empty():return false
	if right.is_empty():return true
	for i in 3:
		if left[i]!=right[i]:return left[i]>right[i]
	return false

static func executable_candidates(local_data:String,program_files:String,path_value:String,editor_tools:String="") -> Array[String]:
	var result:Array[String]=[]
	# Explicit developer tool inventory is editor-only; release never walks ancestors.
	if not editor_tools.is_empty() and DirAccess.dir_exists_absolute(editor_tools):
		var versions:Array[String]=[]
		for name in DirAccess.get_directories_at(editor_tools):
			if not version_parts(name).is_empty():versions.append(name)
		versions.sort_custom(func(a,b):return version_newer(a,b))
		for name in versions:result.append(editor_tools.path_join(name).path_join("ollama.exe"))
	for base in [local_data.path_join("Programs/Ollama"),program_files.path_join("Ollama")]:
		if base.is_absolute_path():result.append(base.path_join("ollama.exe"))
	for base in path_value.split(";",false):
		var clean:=base.strip_edges().trim_prefix('"').trim_suffix('"').replace("\\","/")
		if clean.is_absolute_path():
			var candidate:=clean.path_join("ollama.exe")
			if candidate not in result:result.append(candidate)
	return result

static func inspect() -> Dictionary:
	var tools:=""
	if OS.has_feature("editor"):tools=preload("res://scripts/Paths.gd").development_root().path_join("Tools/Ollama")
	var candidates:=executable_candidates(OS.get_environment("LOCALAPPDATA"),OS.get_environment("ProgramFiles"),OS.get_environment("PATH"),tools)
	var executable:=""
	for candidate in candidates:
		if FileAccess.file_exists(candidate):executable=candidate;break
	var store:=select_store(OS.get_environment("OLLAMA_MODELS"),OS.get_environment("USERPROFILE"))
	var selected:=configuration()
	var chosen_exe:=str(selected.get("executable",""))
	if chosen_exe.is_absolute_path() and chosen_exe.get_file().to_lower()=="ollama.exe" and FileAccess.file_exists(chosen_exe):executable=chosen_exe
	var chosen_store:=str(selected.get("store",""))
	if chosen_store.is_absolute_path():store={"path":chosen_store,"source":"explicit per-machine selection","valid":true,"explicit":true}
	store.exists=store.valid and DirAccess.dir_exists_absolute(store.path)
	return {"executable":executable,"store":store,"service":"checked separately by loopback API; never inferred from exe existence"}
