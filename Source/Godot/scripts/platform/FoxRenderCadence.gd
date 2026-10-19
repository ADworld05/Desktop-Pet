extends RefCounted
## Visual sampling is independent of the 30Hz visible-window input pump.
const ACTIVE_HZ:=30
const REST_HZ:=12
const SLEEP_HZ:=5
var pose_age:=0.0
var draw_age:=0.0
var pose_hz:=-1
var draw_hz:=-1
func pose_tick(delta:float,hz:int)->float:
	if hz!=pose_hz:pose_age=0.0;pose_hz=hz
	if hz==0:pose_age=0.0;return 0.0
	pose_age+=clampf(delta,0,.25)
	if hz==ACTIVE_HZ or pose_age+0.000001>=1.0/hz:
		var elapsed:=pose_age;pose_age=0.0
		return elapsed
	return 0.0
func draw_tick(delta:float,hz:int)->bool:
	var changed:=hz!=draw_hz
	if changed:draw_age=0.0;draw_hz=hz
	if hz==0:draw_age=0.0;return false
	draw_age+=clampf(delta,0,.25)
	if changed or hz==ACTIVE_HZ:return true
	if draw_age+0.000001>=1.0/hz:
		draw_age=fmod(draw_age,1.0/hz);return true
	return false
