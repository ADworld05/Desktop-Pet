extends RefCounted
## Screen placement only. The classifier owns hold/click timing; the director
## owns animation. No hooks, synthetic input, autonomous motion or other HWNDs.
const MAX_CURSOR_SPEED := 1600.0 # logical pixels/second
const MAX_FOLLOW_SPEED := 2200.0
const VELOCITY_SECONDS := 0.10
const FOLLOW_SECONDS := 0.055
const COOLDOWN_SECONDS := 0.65
var armed := false
var active := false
var position := Vector2.ZERO
var offset := Vector2.ZERO
var last_cursor := Vector2.ZERO
var velocity := Vector2.ZERO
var cooldown_until := 0.0
var direction := "calm"
var candidate := "calm"
var candidate_age := 0.0
var boundary_hits := 0

func finite(point: Vector2) -> bool:
	return is_finite(point.x) and is_finite(point.y)

func press(cursor: Vector2, origin: Vector2, grab: Vector2, now: float) -> bool:
	if armed or active or now<cooldown_until or not finite(cursor) or not finite(origin) or not finite(grab): return false
	armed=true; position=origin; offset=grab; last_cursor=cursor
	velocity=Vector2.ZERO; direction="calm"; candidate="calm"; candidate_age=0.0
	return true

func activate() -> bool:
	if not armed: return false
	active=true
	return true

func sample(cursor: Vector2, seconds: float, extent: Vector2, usable: Rect2, scale: Vector2, grab: Vector2) -> Vector2:
	if not armed or not finite(cursor) or not finite(grab) or not finite(scale) or seconds<=0.0 or not is_finite(seconds): return position
	var tick := clampf(seconds,0.001,0.05)
	var ratio := scale.max(Vector2(0.1,0.1))
	var raw := ((cursor-last_cursor)/ratio/tick).limit_length(MAX_CURSOR_SPEED)
	last_cursor=cursor
	velocity=velocity.lerp(raw,1.0-exp(-tick/VELOCITY_SECONDS)).limit_length(MAX_CURSOR_SPEED)
	_select_direction(tick)
	if not active: return position
	offset=grab
	var desired := cursor-offset
	var maximum := (usable.end-extent).max(usable.position)
	var bounded := desired.clamp(usable.position,maximum)
	if bounded.distance_to(desired)>0.01: boundary_hits+=1
	var change := (bounded-position)*(1.0-exp(-tick/FOLLOW_SECONDS))
	change=(change/ratio).limit_length(MAX_FOLLOW_SPEED*tick)*ratio
	position=(position+change).clamp(usable.position,maximum)
	return position

func _select_direction(seconds: float) -> void:
	var speed := velocity.length()
	var proposed := direction
	if speed<25.0: proposed="calm"
	elif speed>42.0:
		var vertical := absf(velocity.y)>absf(velocity.x)*(1.15 if direction in ["up","down"] else 1.45)
		proposed=("up" if velocity.y<0.0 else "down") if vertical else "horizontal"
	if proposed!=candidate: candidate=proposed;candidate_age=0.0
	candidate_age+=seconds
	if candidate_age>=0.10: direction=candidate

func finish(now: float) -> bool:
	var held := active
	armed=false;active=false;velocity=Vector2.ZERO;direction="calm"
	if held: cooldown_until=now+COOLDOWN_SECONDS
	return held

func reframe(origin: Vector2) -> void:
	# Work-area/DPI changes clamp the current placement, never the old home.
	position=origin
