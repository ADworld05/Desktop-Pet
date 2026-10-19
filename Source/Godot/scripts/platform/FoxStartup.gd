extends RefCounted
## Trusted fixed helper only; no model/user text can choose a path or command.
static func helper_path()->String:
	return preload("res://scripts/Paths.gd").development_root().path_join("Build/DesktopFoxStartup.exe") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("DesktopFoxStartup.exe")
func query(action:String="Status",fixture:bool=false) -> Dictionary:
	if action not in ["Status","Enable","Disable"]:return {"available":false,"enabled":false,"error":"Invalid startup action."}
	var output:Array=[]
	var args:=PackedStringArray([action])
	if fixture:args.append("Fixture")
	var error:=OS.execute(helper_path(),args,output,true,false)
	var response:Variant=JSON.parse_string("\n".join(output))
	if response is Dictionary and response.get("available") is bool and response.get("enabled") is bool:
		return response
	return {"available":false,"enabled":false,"error":"Windows startup helper unavailable (%s). See Docs/windows_lifecycle.md."%error}
