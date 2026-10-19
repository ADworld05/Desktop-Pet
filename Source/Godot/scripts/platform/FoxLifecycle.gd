extends RefCounted
## Own-window notifications; frozen time cannot become accumulated idle/motion.
var locked:=false
var suspended:=false
var quiet_remaining:=0.0
var status:=0
var tray_recoveries:=0
var duplicate_recoveries:=0

func consume(app:Node,events:int,delta:float) -> void:
	if events&2:suspended=true
	if events&8:locked=true
	if events&4:suspended=false;quiet_remaining=10.0
	if events&16:locked=false;quiet_remaining=10.0
	var paused_now:bool=locked or suspended or quiet_remaining>0.0
	if events&(2|4|8|16):
		app._cancel_pointer();app.home_motion.stop(app,"Windows lifecycle");app.rest_routine.cancel(app,"Windows lifecycle")
		app.home_behavior.interact();app.home_behavior.ready_after=app.home_behavior.clock+10
		if events&(4|16):app._place_pet(false)
	if events&32:
		app.recover_tray();tray_recoveries+=1
	if events&1:
		duplicate_recoveries+=1
		# Explicit user recovery cancels a stale quiet gate, never a real lock/suspend.
		quiet_remaining=0;paused_now=locked or suspended
		app.windows_paused=paused_now;app.recover_instance()
	if not locked and not suspended:quiet_remaining=maxf(0,quiet_remaining-clampf(delta,0,1))
	# Preserve user hide/minimize flags. Temporary Windows pause is a director gate.
	app.windows_paused=paused_now

func paused() -> bool:return locked or suspended or quiet_remaining>0.0
