extends RefCounted
## Deterministic proximity-idle edge rest; actor/window writes in the adapter.
const LIE_SECONDS:=180.0
const SLEEP_AFTER_REST_SECONDS:=300.0
var phase:="awake"
var rest_age:=0.0
var last_idle:=0.0
func reset() -> void:
	phase="awake";rest_age=0;last_idle=0
func tick(delta:float,state:Dictionary,idle_age:float,_near_edge:bool) -> String:
	if state.get("paused",false):return ""
	if state.get("blocked",false) or state.get("proximity",false):reset();return ""
	if state.get("manual_sleep",false):return "" # Explicit tray Sleep lasts until wake/proximity.
	if idle_age+.1<last_idle:reset()
	last_idle=idle_age
	var stable:bool=state.get("stable",false)
	var posture:String=state.get("posture","")
	match phase:
		"awake":
			if idle_age>=LIE_SECONDS and stable:
				if posture=="standing":phase="moving";return "edge"
				phase="prepare_edge";return "standing"
		"prepare_edge":
			if stable and posture=="standing":phase="moving";return "edge"
		"moving":
			if state.get("arrived",false):phase="front";return "front"
			elif state.get("motion_failed",false):phase="failed" # No auto-retry oscillation.
		"front":
			if state.get("front_done",false) and stable:phase="wait_edge_lie";return "lying"
		"wait_edge_lie":
			if stable and posture=="lying":phase="resting";rest_age=0
		"resting":
			if stable and posture=="lying":
				rest_age+=maxf(0,delta)
				if rest_age>=SLEEP_AFTER_REST_SECONDS:phase="sleeping";return "sleeping"
	return ""
