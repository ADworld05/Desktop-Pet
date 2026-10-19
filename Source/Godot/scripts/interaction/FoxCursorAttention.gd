extends RefCounted
## Rate-limited by the caller. No cursor samples are saved to disk.
var settings: Dictionary
var gaze := Vector2.ZERO
var zone := ""
var dwell := 0.0
var cooldown_until := 0.0
var fired := false
var sample_count := 0
const GazeGeometry=preload("FoxGazeGeometry.gd")
var eye_angles := Vector2.ZERO
var neck_angles := Vector2.ZERO
var neck_delay := 0.0
var previous_target := Vector2.ZERO
var neck_velocity := Vector2.ZERO

func initialize(values: Dictionary) -> void:
	settings=values

func sample(delta: float, now: float, point: Vector2, center: Vector2, candidate_zone: String, enabled: bool, relative: Vector2=Vector2.INF) -> String:
	sample_count+=1
	var direction := point-center
	var distance := direction.length()
	var target := Vector2.ZERO
	if enabled and distance<=float(settings.attention_radius) and distance>float(settings.dead_zone):
		target=direction.normalized()*clampf((distance-float(settings.dead_zone))/95.0*float(settings.sensitivity),0.0,1.0)
	# Exact exponential smoothing remains stable at both 30Hz and resting 10Hz.
	gaze=gaze.lerp(target,1.0-exp(-clampf(delta,0,0.25)/float(settings.smoothing_seconds)))
	if is_finite(relative.x) and is_finite(relative.y):
		var active := enabled and distance<=float(settings.attention_radius)
		var wanted := relative*float(settings.sensitivity) if active else Vector2.ZERO
		# Eyes cover the small central band. Sustained larger offsets recruit the
		# neck; a reversal restarts a short delay rather than whipping the head.
		var neck_target := Vector2(signf(wanted.x)*maxf(absf(wanted.x)-5.0,0.0),signf(wanted.y)*maxf(absf(wanted.y)-3.0,0.0))
		neck_target=GazeGeometry.ellipse_limit(neck_target,Vector2(18,8))
		if neck_target.dot(previous_target)<0.0 or neck_target.distance_to(previous_target)>7.0: neck_delay=0.10
		previous_target=neck_target
		neck_delay=maxf(0.0,neck_delay-delta)
		if neck_delay<=0.0 or not active:
			var seconds := clampf(delta,0.000001,0.25)
			var remaining := neck_target-neck_angles
			var wanted_velocity := (remaining*(1.0-exp(-seconds/0.28))/seconds).limit_length(60.0)
			neck_velocity=neck_velocity.move_toward(wanted_velocity,240.0*seconds)
			var movement := neck_velocity*seconds
			if movement.dot(remaining)>0 and movement.length()>remaining.length(): movement=remaining; neck_velocity=Vector2.ZERO
			neck_angles=GazeGeometry.ellipse_limit(neck_angles+movement,Vector2(18,8))
		var eye_target := GazeGeometry.ellipse_limit(wanted-neck_angles,Vector2(6,4))
		eye_angles=eye_angles.lerp(eye_target,1.0-exp(-clampf(delta,0,0.25)/0.08))
	if not enabled: candidate_zone=""
	if zone!=candidate_zone: zone=candidate_zone; dwell=0.0; fired=false
	if zone.is_empty(): return ""
	dwell+=clampf(delta,0,0.25)
	if not fired and dwell>=float(settings.hover_dwell) and now>=cooldown_until:
		fired=true; cooldown_until=now+float(settings.hover_cooldown)
		return {"head":"hover_curious","ears":"ear_twitch","body":"hover_curious","tail":"tail_idle"}.get(zone,"")
	return ""

static func pick_zone(point: Vector2, anchors: Dictionary) -> String:
	var best := 1.0
	var result := ""
	for name in ["ears","head","tail","body"]:
		for anchor in anchors.get(name,[]):
			var relative: Vector2 = (point-anchor.center)/anchor.radius
			var distance := relative.length()
			if distance<best: best=distance; result=name
	return result
