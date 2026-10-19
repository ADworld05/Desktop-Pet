extends RefCounted
## One final writer. Body supplies baseline; five disjoint masks compose
## rotation only. No AnimationPlayer/Tree is allowed to write concurrently.
var actor: Node3D
var skeleton: Skeleton3D
var bindings: Dictionary = {}
var tracks: Dictionary = {}
var rest: Dictionary = {}
var last_pose: Dictionary = {}
var ownership: Dictionary = {}
var catalog: RefCounted
var bone_channels: Dictionary = {}
var node_channels: Dictionary = {}
var anatomical_forward := Vector3.FORWARD
var anatomical_up := Vector3.UP

func initialize(model: Node3D, data: RefCounted) -> bool:
	actor = model
	catalog = data
	skeleton = actor.find_child("*Skeleton*", true, false) as Skeleton3D
	var player := actor.find_child("*AnimationPlayer*", true, false) as AnimationPlayer
	if not skeleton or skeleton.get_bone_count() != 40 or not player or not player.has_animation("T05_RestPose"): return false
	player.stop()
	player.active = false
	var rest_animation := player.get_animation("T05_RestPose")
	if not _bind("_rest", rest_animation): return false
	rest = _sample("_rest", rest_animation, 0.0)
	for id in catalog.rows:
		if not _bind(id, catalog.animations[id]): return false
		var row: Dictionary = catalog.rows[id]
		if not catalog.is_body(id):
			for binding in tracks[id]:
				if binding.type != Animation.TYPE_ROTATION_3D or binding.bone_name not in row.bone_mask: return false
			for name in row.bone_mask:
				if ownership.has(name) and ownership[name] != row.layer: return false
				ownership[name] = row.layer
	write_pose(rest)
	var calibration := evaluate_pose(rest,actor.get_parent_node_3d())
	var head: Transform3D=calibration.bones[skeleton.find_bone("Fox_Head_016")]
	var eyes: Vector3=(calibration.bones[skeleton.find_bone("Fox_LEye_021")].origin+calibration.bones[skeleton.find_bone("Fox_REye_022")].origin)*0.5
	var model_up: Vector3=(calibration.skeleton_to_stage.basis.inverse()*Vector3.UP).normalized()
	var horizontal: Vector3=eyes-head.origin-model_up*(eyes-head.origin).dot(model_up)
	anatomical_forward=(head.basis.inverse()*horizontal).normalized()
	anatomical_up=(head.basis.inverse()*model_up).normalized()
	return true

func _bind(id: String, animation: Animation) -> bool:
	var bound: Array = []
	var keys: Dictionary = {}
	for index in animation.get_track_count():
		if not animation.track_is_enabled(index): continue
		var type: int = animation.track_get_type(index)
		if type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]: return false
		var path := animation.track_get_path(index)
		var node := actor.get_node_or_null(NodePath(path.get_concatenated_names())) as Node3D
		if not node: return false
		var bone_name := str(path.get_subname(0)) if path.get_subname_count() else ""
		var bone := skeleton.find_bone(bone_name) if bone_name else -1
		if bone_name and (node != skeleton or bone < 0): return false
		var key := str(path) + "|" + str(type)
		if keys.has(key): return false
		keys[key] = true
		var binding := {"key": key, "node": node, "bone": bone, "bone_name": bone_name, "type": type, "index": index}
		bindings[key] = binding
		if bone >= 0:
			if not bone_channels.has(bone): bone_channels[bone] = {}
			bone_channels[bone][type] = key
		else:
			if not node_channels.has(node): node_channels[node] = {}
			node_channels[node][type] = key
		bound.append(binding)
	tracks[id] = bound
	return true

func _sample(id: String, animation: Animation, seconds: float) -> Dictionary:
	var pose: Dictionary = {}
	for binding in tracks[id]:
		match int(binding.type):
			Animation.TYPE_POSITION_3D: pose[binding.key] = animation.position_track_interpolate(binding.index, seconds)
			Animation.TYPE_ROTATION_3D: pose[binding.key] = animation.rotation_track_interpolate(binding.index, seconds).normalized()
			Animation.TYPE_SCALE_3D: pose[binding.key] = animation.scale_track_interpolate(binding.index, seconds)
	return pose

func body_pose(id: String, seconds: float) -> Dictionary:
	var pose := rest.duplicate()
	pose.merge(_sample(id, catalog.animations[id], catalog.sample_time(id, seconds)), true)
	return pose

func blend_pose(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	var output := b.duplicate()
	for key in b:
		if a.has(key): output[key] = a[key].slerp(b[key], weight).normalized() if b[key] is Quaternion else a[key].lerp(b[key], weight)
	return output

func compose(base: Dictionary, layers: Dictionary) -> Dictionary:
	var output := base.duplicate()
	for layer in ["head", "gaze", "blink", "ears", "tail"]:
		if not layers.has(layer): continue
		var command: Dictionary = layers[layer]
		var id: String = command.id
		var sampled := _sample(id, catalog.animations[id], catalog.sample_time(id, command.time))
		var weight: float = clampf(command.weight, 0.0, 1.0)
		for key in sampled:
			var base_rotation: Quaternion = output[key]
			if catalog.rows[id].blend_mode == "additive_relative_rest":
				var delta: Quaternion = (rest[key].inverse() * sampled[key]).normalized()
				output[key] = (base_rotation * Quaternion.IDENTITY.slerp(delta, weight)).normalized()
			else:
				output[key] = base_rotation.slerp(sampled[key], weight).normalized()
	return output

func write_pose(pose: Dictionary) -> void:
	for key in pose:
		var binding: Dictionary = bindings[key]
		var value: Variant = pose[key]
		if binding.bone >= 0:
			match int(binding.type):
				Animation.TYPE_POSITION_3D: skeleton.set_bone_pose_position(binding.bone, value)
				Animation.TYPE_ROTATION_3D: skeleton.set_bone_pose_rotation(binding.bone, value)
				Animation.TYPE_SCALE_3D: skeleton.set_bone_pose_scale(binding.bone, value)
		else:
			match int(binding.type):
				Animation.TYPE_POSITION_3D: binding.node.position = value
				Animation.TYPE_ROTATION_3D: binding.node.quaternion = value
				Animation.TYPE_SCALE_3D: binding.node.scale = value
	skeleton.force_update_all_bone_transforms()
	last_pose = pose.duplicate()

func compose_cursor(pose: Dictionary, direction: Vector2, placement: Node3D, screen_right: Vector3, screen_up: Vector3, use_eyes: bool, use_head: bool) -> Dictionary:
	# Blend within the approved four eye targets. L1 weights keep diagonals
	# inside their convex rotation envelope; no new eye axes or animation tracks.
	var output := pose.duplicate()
	var weights := direction / maxf(1.0,absf(direction.x)+absf(direction.y))
	if use_eyes:
		var horizontal := "gaze_right" if weights.x>=0 else "gaze_left"
		var vertical := "gaze_down" if weights.y>=0 else "gaze_up"
		var a := _sample(horizontal,catalog.animations[horizontal],0.2)
		var b := _sample(vertical,catalog.animations[vertical],0.2)
		for key in a:
			var da: Quaternion = rest[key].inverse()*a[key]
			var db: Quaternion = rest[key].inverse()*b[key]
			var delta := (Quaternion.IDENTITY.slerp(da,absf(weights.x))*Quaternion.IDENTITY.slerp(db,absf(weights.y))).normalized()
			output[key]=(output[key]*delta).normalized()
	if use_head and direction.length_squared()>0.000001:
		var evaluated := evaluate_pose(output,placement)
		var head := skeleton.find_bone("Fox_Head_016")
		var outer: Basis = (placement.global_transform*evaluated.skeleton_to_stage).basis.orthonormalized()
		var rotation_vector := (screen_up*direction.x*deg_to_rad(4.0)-screen_right*direction.y*deg_to_rad(3.0)).limit_length(deg_to_rad(4.0))
		var local_vector := outer.inverse()*rotation_vector
		var current: Quaternion = evaluated.bones[head].basis.get_rotation_quaternion()
		rotate_global(output,evaluated,head,(Quaternion(local_vector.normalized(),local_vector.length())*current).normalized())
	return output

func evaluate_pose(pose: Dictionary, placement: Node3D) -> Dictionary:
	# Pure forward kinematics: constraints read proposed poses before the single
	# final skeleton write. Imported poses are full local transforms, not deltas.
	var local: Array[Transform3D] = []
	var global: Array[Transform3D] = []
	for bone in skeleton.get_bone_count():
		var value := _channel_transform(skeleton.get_bone_rest(bone),bone_channels.get(bone,{}),pose)
		local.append(value)
		var parent := skeleton.get_bone_parent(bone)
		global.append(global[parent]*value if parent >= 0 else value)
	return {"local":local,"bones":global,"skeleton_to_stage":_node_transform(skeleton,placement,pose)}

func cursor_frame(pose: Dictionary, placement: Node3D) -> Dictionary:
	var evaluated := evaluate_pose(pose,placement)
	var outer: Transform3D=placement.global_transform*evaluated.skeleton_to_stage
	var head: Transform3D=outer*evaluated.bones[skeleton.find_bone("Fox_Head_016")]
	var front: Vector3=(head.basis*anatomical_forward).normalized()
	var up: Vector3=(head.basis*anatomical_up).normalized()
	var right := up.cross(front).normalized()
	return {"origin":head.origin,"forward":front,"up":front.cross(right).normalized(),"right":right}

func compose_oriented_cursor(pose: Dictionary, eyes: Vector2, neck: Vector2, placement: Node3D, use_eyes: bool, use_neck: bool) -> Dictionary:
	# Retain calibrated eye targets; anatomical yaw/pitch replace screen signs.
	var output := compose_cursor(pose,Vector2(eyes.x/6.0,-eyes.y/4.0),placement,Vector3.RIGHT,Vector3.UP,use_eyes,false)
	if use_neck and neck.length_squared()>0.000001:
		var frame := cursor_frame(pose,placement)
		var evaluated := evaluate_pose(output,placement)
		var outer: Basis=(placement.global_transform*evaluated.skeleton_to_stage).basis.orthonormalized()
		var yaw_axis: Vector3=(outer.inverse()*frame.up).normalized()
		var pitch_axis: Vector3=(outer.inverse()*frame.right).normalized()
		# This rig's Fox_Spine_015 is the short neck between ribcage and head.
		for entry in [["Fox_Spine_015",0.65],["Fox_Head_016",0.35]]:
			var bone := skeleton.find_bone(entry[0])
			var delta := Quaternion(yaw_axis,deg_to_rad(neck.x)*entry[1])*Quaternion(pitch_axis,-deg_to_rad(neck.y)*entry[1])
			var current: Quaternion=evaluated.bones[bone].basis.get_rotation_quaternion()
			rotate_global(output,evaluated,bone,(delta*current).normalized())
			evaluated=evaluate_pose(output,placement)
	return output

func _channel_transform(original: Transform3D, channels: Dictionary, pose: Dictionary) -> Transform3D:
	var position: Vector3 = pose.get(channels.get(Animation.TYPE_POSITION_3D,""),original.origin)
	var rotation: Quaternion = pose.get(channels.get(Animation.TYPE_ROTATION_3D,""),original.basis.get_rotation_quaternion())
	var scale: Vector3 = pose.get(channels.get(Animation.TYPE_SCALE_3D,""),original.basis.get_scale())
	return Transform3D(Basis(rotation).scaled_local(scale),position)

func _node_transform(node: Node3D, placement: Node3D, pose: Dictionary) -> Transform3D:
	if node == placement: return Transform3D.IDENTITY
	var value := _channel_transform(node.transform,node_channels.get(node,{}),pose)
	var parent := node.get_parent_node_3d()
	return _node_transform(parent,placement,pose)*value if parent else value

func rotate_global(pose: Dictionary, evaluated: Dictionary, bone: int, rotation: Quaternion) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var parent_rotation: Quaternion = evaluated.bones[parent].basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
	pose[bone_channels[bone][Animation.TYPE_ROTATION_3D]] = (parent_rotation.inverse()*rotation).normalized()
