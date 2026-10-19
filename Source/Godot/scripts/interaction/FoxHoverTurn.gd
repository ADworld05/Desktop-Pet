extends RefCounted
## Face dwell, then a broad directional hover. No click or input capture.
## Up is an alternative for left; down for right. Accepted gaze is separate.
const MAX_RADIUS := 180.0
const FACE_RADIUS := 42.0
const FACE_DWELL := 0.35
const INTENT_TIMEOUT := 4.0
const DEPARTURE := 48.0
const RETURN_RADIUS := 32.0
const TARGET_DWELL := 0.25
const COOLDOWN := 1.1
var phase := "idle"
var cooldown_until := 0.0
var face_age := 0.0
var armed_at := 0.0
var face_anchor := Vector2.ZERO
var previous := Vector2.ZERO
var side := 0.0
var target_age := 0.0
var axis := ""

func reset() -> void:
	phase="idle";face_age=0.0;side=0.0;target_age=0.0;axis=""

func sample(delta: float, now: float, point: Vector2, center: Vector2, yaw: float, enabled: bool, face: Vector2=Vector2.INF) -> float:
	if not enabled or not is_finite(yaw) or not is_finite(point.x) or not is_finite(point.y) or delta<=0.0 or delta>0.25 or point.distance_to(center)>MAX_RADIUS:
		reset();return 0.0
	if now<cooldown_until:
		reset();phase="cooldown";return 0.0
	if phase=="cooldown":reset()
	if not is_finite(face.x) or not is_finite(face.y):face=center
	if phase in ["idle","priming"]:
		if point.distance_to(face)>FACE_RADIUS:
			reset();return 0.0
		phase="priming";face_age+=delta
		if face_age+0.000001>=FACE_DWELL:
			phase="armed";armed_at=now;face_anchor=face;previous=point
		return 0.0
	if now-armed_at>INTENT_TIMEOUT:
		reset();return 0.0
	var movement := point-previous;previous=point
	if movement.length()/delta>1400.0:
		reset();return 0.0
	var away := point-face_anchor
	if away.length()<RETURN_RADIUS:
		phase="armed";side=0.0;axis="";target_age=0.0
		return 0.0
	if phase=="armed":
		if maxf(absf(away.x),absf(away.y))<DEPARTURE:return 0.0
		axis="horizontal" if absf(away.x)>=absf(away.y) else "vertical"
		side=-signf(away.x if axis=="horizontal" else away.y)
		phase="aiming";target_age=0.0
	var component := away.x if axis=="horizontal" else away.y
	if component*side>RETURN_RADIUS:
		phase="armed";side=0.0;axis="";target_age=0.0
		return 0.0
	# A vertical extension retains the initial left/right choice. A curved
	# path works too, but no curvature or angular-excursion gate is required.
	if away.length()>=DEPARTURE:target_age+=delta
	else:target_age=maxf(0.0,target_age-delta*2.0)
	if target_age+0.000001>=TARGET_DWELL:
		var wanted := side*90.0
		cooldown_until=now+COOLDOWN;reset();phase="cooldown"
		return wanted
	return 0.0
