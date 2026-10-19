extends RefCounted
## Small approved mesh only. CPU skin samples support geometric validation and
## transient contact stabilization; no skin, weights or animation are changed.
const DIGITS := ["Fox_F_LLegDigit11_014","Fox_F_RLegDigit11_030","Fox_LLegDigit11_034","Fox_RLegDigit11_038"]
var skeleton: Skeleton3D
var mesh: MeshInstance3D
var vertices: PackedVector3Array
var influences: Array = []
var bind_bones: Array[int] = []
var bind_poses: Array[Transform3D] = []
var feet: Dictionary = {}

func initialize(actor: Node3D, bones: Skeleton3D) -> bool:
	skeleton = bones
	mesh = actor.find_child("*Mesh*",true,false) as MeshInstance3D
	if not mesh or not mesh.skin or mesh.mesh.get_surface_count()!=1: return false
	for slot in mesh.skin.get_bind_count():
		var name := mesh.skin.get_bind_name(slot)
		var bone := skeleton.find_bone(name) if not name.is_empty() else mesh.skin.get_bind_bone(slot)
		if bone < 0: return false
		bind_bones.append(bone)
		bind_poses.append(mesh.skin.get_bind_pose(slot))
	var arrays := mesh.mesh.surface_get_arrays(0)
	vertices = arrays[Mesh.ARRAY_VERTEX]
	var ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var stride := ids.size()/vertices.size()
	for name in DIGITS: feet[name] = []
	for vertex in vertices.size():
		var active: Array = []
		for index in stride:
			var offset := vertex*stride+index
			if weights[offset] <= 0.0: continue
			var bind: int = ids[offset]
			active.append([bind,float(weights[offset])])
			var name := skeleton.get_bone_name(bind_bones[bind])
			if name in DIGITS and weights[offset] > 0.45: feet[name].append(vertex)
		influences.append(active)
	return feet.values().all(func(ids_for_foot: Array):return not ids_for_foot.is_empty())

func points(space: Transform3D = Transform3D.IDENTITY) -> PackedVector3Array:
	skeleton.force_update_all_bone_transforms()
	var matrices: Array[Transform3D] = []
	for slot in bind_bones.size(): matrices.append(skeleton.get_bone_global_pose(bind_bones[slot])*bind_poses[slot])
	return _skin(matrices,space * mesh.global_transform)

func proposed_points(evaluated: Dictionary, placement: Transform3D) -> PackedVector3Array:
	var matrices: Array[Transform3D] = []
	for slot in bind_bones.size(): matrices.append(evaluated.bones[bind_bones[slot]]*bind_poses[slot])
	# This approved import shares skeleton and mesh transforms, verified by tests.
	return _skin(matrices,placement*evaluated.skeleton_to_stage)

func _skin(matrices: Array[Transform3D], placement: Transform3D) -> PackedVector3Array:
	var output := PackedVector3Array()
	output.resize(vertices.size())
	for vertex in vertices.size():
		var point := Vector3.ZERO
		for influence in influences[vertex]: point += (matrices[influence[0]]*vertices[vertex])*influence[1]
		output[vertex] = placement*point
	return output
