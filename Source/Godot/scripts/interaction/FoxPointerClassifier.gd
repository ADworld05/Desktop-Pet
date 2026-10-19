extends RefCounted
## Pure state machine. It never polls global buttons or commits on press.
## Times are monotonic seconds; every position is in logical viewport units.
var settings: Dictionary
var pressed := false
var holding := false
var cancelled := false
var down_time := 0.0
var down_position := Vector2.ZERO
var grab_offset := Vector2.ZERO
var second := false
var pending: Dictionary = {}
var output: Array[Dictionary] = []
var max_motion := 0.0

func initialize(values: Dictionary) -> void:
	settings=values

func _emit(kind: String, position: Vector2) -> void:
	output.append({"kind":kind,"position":position,"grab_offset":grab_offset})

func drain() -> Array[Dictionary]:
	var result := output.duplicate()
	output.clear()
	return result

func advance(now: float, position: Vector2, inside: bool) -> void:
	if not pressed:
		if not pending.is_empty() and now>float(pending.deadline):
			_emit("single",pending.position); pending.clear()
		return
	max_motion=maxf(max_motion,position.distance_to(down_position))
	if holding: return
	if not inside or max_motion>float(settings.movement_tolerance): cancelled=true
	if now-down_time>=float(settings.hold_seconds):
		# Movement before activation cancels the click, but still permits a hold.
		holding=true; pending.clear(); second=false
		_emit("hold",position)

func button(button_index: int, is_down: bool, now: float, position: Vector2, inside: bool) -> void:
	advance(now,position,inside)
	if button_index==MOUSE_BUTTON_RIGHT:
		if is_down and inside:
			cancel(position); _emit("right",position)
		return
	if button_index!=MOUSE_BUTTON_LEFT: return
	if is_down:
		if pressed or not inside: return
		second=not pending.is_empty() and now<=float(pending.deadline) and position.distance_to(pending.position)<=float(settings.double_distance)
		if not pending.is_empty() and not second: _emit("single",pending.position); pending.clear()
		pressed=true; holding=false; cancelled=false; max_motion=0.0
		down_time=now; down_position=position; grab_offset=position
	else:
		if not pressed: return
		pressed=false
		if holding:
			_emit("release",position); pending.clear()
		elif cancelled or not inside:
			pending.clear()
		elif second:
			_emit("double",position); pending.clear()
		else:
			pending={"deadline":now+float(settings.double_seconds),"position":position}
		holding=false; second=false; cancelled=false

func cancel(position: Vector2 = Vector2.ZERO) -> void:
	if holding: _emit("release",position)
	pressed=false; holding=false; second=false; cancelled=false; pending.clear()
