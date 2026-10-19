class_name FoxPaths
extends RefCounted
## Pack assets are read-only; mutable data belongs to this Windows user.
## Never fall back into the installation folder or a development drive.
const ASSET_ROOT := "res://runtime_assets"
const AREAS := {"config":"Config", "history":"History", "memory":"Memory", "notes":"Notes", "logs":"Logs", "cache":"Cache"}
static var RUNTIME_ROOT: String:
	get: return OS.get_user_data_dir().replace("\\", "/").trim_suffix("/")
static var PROJECT_ROOT: String:
	get: return application_root()
static var DIRECTORIES: Dictionary:
	get:
		var result := {}
		for kind: String in AREAS: result[kind] = directory(kind)
		return result

static func application_root() -> String:
	return OS.get_executable_path().get_base_dir().replace("\\", "/") if not OS.has_feature("editor") else development_root()

static func development_root() -> String:
	# Only editor/debug proof helpers use the checkout, never release data.
	return ProjectSettings.globalize_path("res://").path_join("../..").simplify_path().trim_suffix("/")

static func directory(kind: String) -> String:
	if kind == "machine_config":
		var base:=OS.get_environment("LOCALAPPDATA").replace("\\","/")
		return base.path_join("DesktopFox/Config") if base.is_absolute_path() else ""
	return RUNTIME_ROOT.path_join(AREAS[kind]) if AREAS.has(kind) else ""

static func prepare_runtime() -> Error:
	if not RUNTIME_ROOT.is_absolute_path() or RUNTIME_ROOT.is_empty(): return ERR_FILE_BAD_PATH
	if directory("machine_config").is_empty():return ERR_FILE_BAD_PATH
	var machine_error:=DirAccess.make_dir_recursive_absolute(directory("machine_config"))
	if machine_error!=OK:return machine_error
	for path: String in DIRECTORIES.values():
		var result := DirAccess.make_dir_recursive_absolute(path)
		if result != OK:
			return result
	# Check actual write/read/remove, not just directory existence.
	var probe := directory("cache").path_join("write-check-" + Crypto.new().generate_random_bytes(12).hex_encode())
	var file := FileAccess.open(probe, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string("Desktop Pet write check"); file.close()
	var readable := FileAccess.get_file_as_string(probe) == "Desktop Pet write check"
	var removed := DirAccess.remove_absolute(probe)
	return OK if readable and removed == OK else ERR_FILE_CANT_WRITE

static func write_startup_record() -> Error:
	var path := directory("logs").path_join("bootstrap.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({
		"schema_version": 1,
		"engine": Engine.get_version_info()["string"],
		"runtime_root": RUNTIME_ROOT,
		"started_at": Time.get_datetime_string_from_system(),
	}, "\t") + "\n")
	var result := file.get_error()
	file.close()
	return result

