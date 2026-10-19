extends RefCounted
## Replace only a derived runtime texture, never mesh, rig, gaze or model files.
const ROOT:=preload("res://scripts/Paths.gd").ASSET_ROOT+"/Textures/T13/"
const COLORS:={"Blue":Color("83b8d6"),"Green":Color("86b993"),"Amber":Color("d5a35f")}
var mesh:MeshInstance3D
var original:Material
var palettes:Dictionary={}
var changed_pixels:=0

func initialize(actor:Node3D) -> bool:
	var meshes:=actor.find_children("*","MeshInstance3D",true,false)
	if meshes.size()!=1:return false
	mesh=meshes[0];original=mesh.get_active_material(0)
	return original is StandardMaterial3D

func apply(color:String) -> bool:
	if not mesh:return false
	if color=="Original":
		# Preserve a derived rendering-profile material when restoring its atlas.
		mesh.set_surface_override_material(0,null if original==mesh.mesh.surface_get_material(0) else original);return true
	if not COLORS.has(color):return false
	if not palettes.has(color):
		var image:=Image.new();var mask:=Image.new()
		if image.load_png_from_buffer(FileAccess.get_file_as_bytes(ROOT+"eye_atlas_original.png.bin"))!=OK or mask.load_png_from_buffer(FileAccess.get_file_as_bytes(ROOT+"iris_tint_mask.png.bin"))!=OK or image.get_size()!=mask.get_size():return false
		var tint:Color=COLORS[color];changed_pixels=0
		image.convert(Image.FORMAT_RGBA8);mask.convert(Image.FORMAT_L8)
		var bytes:=image.get_data();var masked:=mask.get_data()
		var info:Variant=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"eye_palette_manifest.json"))
		if not info is Dictionary or not info.get("mask_bbox") is Array:return false
		var box:Array=info.mask_bbox
		for y in range(int(box[1]),int(box[3])):
			for x in range(int(box[0]),int(box[2])):
				var index:=y*image.get_width()+x
				if masked[index]<128:continue
				var offset:=index*4
				var intensity:=maxi(bytes[offset],maxi(bytes[offset+1],bytes[offset+2]))
				bytes[offset]=roundi(tint.r*intensity);bytes[offset+1]=roundi(tint.g*intensity);bytes[offset+2]=roundi(tint.b*intensity);changed_pixels+=1
		image.set_data(image.get_width(),image.get_height(),false,Image.FORMAT_RGBA8,bytes)
		var material:=original.duplicate() as StandardMaterial3D
		material.albedo_texture=ImageTexture.create_from_image(image)
		palettes[color]=material
	mesh.set_surface_override_material(0,palettes[color]);return true
