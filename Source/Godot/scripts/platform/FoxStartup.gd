extends RefCounted
## Trusted fixed helper only; no model/user text can choose a path or command.
static func helper_path()->String:
	return preload("res://scripts/Paths.gd").development_root().path_join(".build/Helpers/DesktopFoxStartup.exe") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("DesktopFoxStartup.exe")
func query(action:String="Status",fixture:bool=false) -> Dictionary:
	if action not in ["Status","Enable","Disable"]:return {"available":false,"enabled":false,"error":"Invalid startup action."}
	if not FileAccess.file_exists(helper_path()):return {"available":false,"enabled":false,"error":"Startup helper missing. Build the native helpers or reinstall the complete application."}
	var output:Array=[]
	var args:=PackedStringArray([action])
	if fixture:args.append("Fixture")
	var error:=OS.execute(helper_path(),args,output,true,false)
	var text:="\n".join(output).strip_edges()
	if text.is_empty():return {"available":false,"enabled":false,"error":"Startup helper returned no status (%s)."%error}
	var response:Variant=JSON.parse_string(text)
	if response is Dictionary and response.get("available") is bool and response.get("enabled") is bool:
		return response
	return {"available":false,"enabled":false,"error":"Windows startup helper unavailable (%s). Build the native helpers first or reinstall the complete application."%error}
