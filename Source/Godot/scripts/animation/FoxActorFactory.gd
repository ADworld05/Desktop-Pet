extends RefCounted
const Paths = preload("../Paths.gd")
const MODEL = Paths.ASSET_ROOT + "/Models/fox.glb.bin"

static func create_actor() -> Node3D:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_buffer(FileAccess.get_file_as_bytes(MODEL),Paths.ASSET_ROOT+"/Models/",state) != OK: return null
	# Retain constant corrective/default channels, as verified in T05/T07.
	return document.generate_scene(state, 30.0, false, false) as Node3D
