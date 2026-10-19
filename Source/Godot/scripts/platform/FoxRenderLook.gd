extends RefCounted
## The supplied GLB remains immutable. Its zero-roughness fur has sharp specular
## dots in Mobile/Direct3D12; use a local matte copy on that measured profile.
static func apply(actor:Node3D,driver:String)->Dictionary:
	var result:={"driver":driver,"modified_surfaces":0,"roughness":.85,"specular_disabled":true}
	if driver!="d3d12":return result
	for node in actor.find_children("*","MeshInstance3D",true,false):
		if not node.mesh:continue
		for index in node.mesh.get_surface_count():
			var original:Material=node.get_surface_override_material(index)
			if original==null:original=node.mesh.surface_get_material(index)
			if not original is BaseMaterial3D:continue
			var matte:BaseMaterial3D=original.duplicate()
			matte.roughness=.85;matte.specular_mode=BaseMaterial3D.SPECULAR_DISABLED
			node.set_surface_override_material(index,matte)
			result.modified_surfaces+=1
	return result
