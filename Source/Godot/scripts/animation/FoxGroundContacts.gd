extends RefCounted
## Transient two-bone planted-foot constraint. Rotations only, no bone length,
## scale, mesh, weight or source-clip edits. The mixer remains the sole writer.
const FLOOR := 0.002
const RELEASE_HEIGHT := 0.006
const MAX_REACH_CORRECTION := 0.06
var locks: Dictionary = {}
var previous_bones: Array[Transform3D] = []
var previous_minima: Dictionary = {}
var corrected_frames := 0
var unreachable_targets := 0
var maximum_error := 0.0
var maximum_rotation := 0.0
var dropped_locks: Array[Dictionary] = []
var maximum_position_change := 0.0
var maximum_scale_change := 0.0
var ownership_violations := 0

func clear() -> void:
	locks.clear()
	previous_bones.clear()
	previous_minima.clear()

func solve(pose: Dictionary, mixer: RefCounted, surface: RefCounted, stage: Node3D, points: PackedVector3Array, enabled: bool, delta_seconds: float) -> Dictionary:
	var original := pose.duplicate()
	var evaluated: Dictionary = mixer.evaluate_pose(pose,stage)
	var placement: Transform3D = stage.transform*evaluated.skeleton_to_stage
	var inverse := placement.affine_inverse()
	for name in surface.feet:
		var minimum := INF
		for vertex in surface.feet[name]: minimum = minf(minimum,points[vertex].y)
		var digit: int = mixer.skeleton.find_bone(name)
		var ankle: int = mixer.skeleton.get_bone_parent(digit)
		# A blend ending is not a toe-off: retain existing support until the
		# authored paw lifts. Unmodified steady gaits do not acquire new locks.
		if not locks.has(name) and enabled and minimum <= FLOOR and previous_minima.get(name,INF) <= FLOOR and not previous_bones.is_empty():
			locks[name] = {"ankle":previous_bones[ankle],"digit":previous_bones[digit],"release_age":0.0}
		if not locks.has(name): continue
		if minimum > RELEASE_HEIGHT or locks[name].release_age > 0.0:
			locks[name].release_age += delta_seconds
			if locks[name].release_age >= 0.12:
				_drop(name,"toe_off",minimum)
				continue
		var release_weight := smoothstep(0.0,0.12,locks[name].release_age)
		var ankle_world: Transform3D = locks[name].ankle
		var digit_world: Transform3D = locks[name].digit
		# Follow the authored lift vertically while keeping the support's
		# horizontal location. Fade the correction during the airborne swing.
		var lift := maxf(0.0,minimum-FLOOR)
		ankle_world.origin.y += lift
		digit_world.origin.y += lift
		var target: Transform3D = (inverse*ankle_world).interpolate_with(evaluated.bones[ankle],release_weight)
		var current: Transform3D = evaluated.bones[ankle]
		if (placement.basis*(target.origin-current.origin)).length() > MAX_REACH_CORRECTION:
			# A moving/lifting paw must leave its old support; never stretch a leg.
			_drop(name,"distance",(placement.basis*(target.origin-current.origin)).length())
			continue
		var knee: int = mixer.skeleton.get_bone_parent(ankle)
		var hip: int = mixer.skeleton.get_bone_parent(knee)
		var a: Vector3 = evaluated.bones[hip].origin
		var b: Vector3 = evaluated.bones[knee].origin
		var c: Vector3 = current.origin
		var l1 := a.distance_to(b)
		var l2 := b.distance_to(c)
		var delta := target.origin-a
		var distance := delta.length()
		if distance < 0.000001: continue
		var direction := delta/distance
		var reachable := clampf(distance,absf(l1-l2)+0.000001,l1+l2-0.000001)
		if absf(reachable-distance) > 0.00001: unreachable_targets += 1
		var pole := b-a-direction*(b-a).dot(direction)
		if pole.length_squared() < 0.000001:
			pole = evaluated.bones[hip].basis.y-direction*evaluated.bones[hip].basis.y.dot(direction)
		pole = pole.normalized()
		var along := (reachable*reachable+l1*l1-l2*l2)/(2.0*reachable)
		var height := sqrt(maxf(0.0,l1*l1-along*along))
		var knee_target := a+direction*along+pole*height
		var ankle_target := a+direction*reachable
		var hip_delta := Quaternion((b-a).normalized(),(knee_target-a).normalized())
		maximum_rotation = maxf(maximum_rotation,hip_delta.get_angle())
		mixer.rotate_global(pose,evaluated,hip,(hip_delta*evaluated.bones[hip].basis.get_rotation_quaternion()).normalized())
		evaluated = mixer.evaluate_pose(pose,stage)
		b = evaluated.bones[knee].origin
		c = evaluated.bones[ankle].origin
		var knee_delta := Quaternion((c-b).normalized(),(ankle_target-b).normalized())
		maximum_rotation = maxf(maximum_rotation,knee_delta.get_angle())
		mixer.rotate_global(pose,evaluated,knee,(knee_delta*evaluated.bones[knee].basis.get_rotation_quaternion()).normalized())
		evaluated = mixer.evaluate_pose(pose,stage)
		mixer.rotate_global(pose,evaluated,ankle,target.basis.get_rotation_quaternion())
		evaluated = mixer.evaluate_pose(pose,stage)
		var digit_target: Transform3D = (inverse*digit_world).interpolate_with(evaluated.bones[digit],release_weight)
		mixer.rotate_global(pose,evaluated,digit,digit_target.basis.get_rotation_quaternion())
		evaluated = mixer.evaluate_pose(pose,stage)
		maximum_error = maxf(maximum_error,(placement*evaluated.bones[ankle]).origin.distance_to(placement*target.origin))
		corrected_frames += 1
	for key in pose:
		var channel: int = mixer.bindings[key].type
		if pose[key] != original[key] and (channel != Animation.TYPE_ROTATION_3D or mixer.bindings[key].bone not in [11,12,13,14,28,29,30,31,32,33,34,35,36,37,38,39]): ownership_violations += 1
		if channel == Animation.TYPE_POSITION_3D: maximum_position_change = maxf(maximum_position_change,pose[key].distance_to(original[key]))
		if channel == Animation.TYPE_SCALE_3D: maximum_scale_change = maxf(maximum_scale_change,pose[key].distance_to(original[key]))
	return pose

func _drop(name: String, reason: String, value: float) -> void:
	dropped_locks.append({"foot":name,"reason":reason,"value":value})
	if dropped_locks.size() > 128: dropped_locks.pop_front()
	locks.erase(name)

func remember(evaluated: Dictionary, placement: Transform3D, surface: RefCounted, points: PackedVector3Array) -> void:
	previous_bones.clear()
	for value in evaluated.bones: previous_bones.append(placement*evaluated.skeleton_to_stage*value)
	for name in surface.feet:
		var minimum := INF
		for vertex in surface.feet[name]: minimum = minf(minimum,points[vertex].y)
		previous_minima[name] = minimum
