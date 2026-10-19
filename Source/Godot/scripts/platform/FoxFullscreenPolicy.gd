extends RefCounted
## Optional foreground pause, separate from Windows lock/suspend recovery.
const RETURN_SECONDS:=10.0
var foreground:=false
var quiet_remaining:=0.0
func observe(state:int,enabled:bool) -> void:
	if not enabled:foreground=false;quiet_remaining=0;return
	if state<0:return
	var now:bool=state==1
	if foreground and not now:quiet_remaining=RETURN_SECONDS
	if now:quiet_remaining=0
	foreground=now
func advance(delta:float,enabled:bool) -> bool:
	if not enabled:foreground=false;quiet_remaining=0;return false
	if not foreground:quiet_remaining=maxf(0,quiet_remaining-clampf(delta,0,1))
	return foreground or quiet_remaining>0
