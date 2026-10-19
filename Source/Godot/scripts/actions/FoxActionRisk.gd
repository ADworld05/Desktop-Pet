extends RefCounted
const SAFE := ["open_application", "open_file", "open_folder", "find_file", "reveal_in_explorer", "get_system_information"]
const SENSITIVE := ["read_text_file", "close_application"]
static func classify(tool: String, one_time_area: bool = false) -> String:
	if tool in SENSITIVE or (one_time_area and tool in SAFE): return "SENSITIVE"
	return "SAFE" if tool in SAFE else "BLOCKED"
