extends RefCounted
## Pure native-pixel geometry. Empty transparent window margins are not the pet.
const REST_BAND:=150.0
const REST_GAP:=40.0
static func gaps(bounds:Rect2,area:Rect2) -> Dictionary:
	return {"left":bounds.position.x-area.position.x,"right":area.end.x-bounds.end.x,"top":bounds.position.y-area.position.y,"bottom":area.end.y-bounds.end.y}
static func nearest_gap(bounds:Rect2,area:Rect2) -> float:
	var values:=gaps(bounds,area)
	return minf(minf(values.left,values.right),minf(values.top,values.bottom))
static func choose(current:Rect2,rest_local:Rect2,origin:Vector2,area:Rect2) -> Dictionary:
	var distance:=gaps(current,area)
	# Nearest feasible corner by distance from the current window origin.
	var selected:Array[String]=[]
	var best:=INF
	for horizontal in ["left","right"]:
		for vertical in ["top","bottom"]:
			var candidate:=Vector2(area.position.x+REST_GAP-rest_local.position.x if horizontal=="left" else area.end.x-REST_GAP-rest_local.end.x,area.position.y+REST_GAP-rest_local.position.y if vertical=="top" else area.end.y-REST_GAP-rest_local.end.y)
			var travel:=origin.distance_squared_to(candidate)
			if travel<best:best=travel;selected.assign([horizontal,vertical])
	var target:=origin
	for side in selected:
		match side:
			"left":target.x=area.position.x+REST_GAP-rest_local.position.x
			"right":target.x=area.end.x-REST_GAP-rest_local.end.x
			"top":target.y=area.position.y+REST_GAP-rest_local.position.y
			"bottom":target.y=area.end.y-REST_GAP-rest_local.end.y
	return {"sides":selected,"target":clamp_origin(target,rest_local,area),"initial_gaps":distance,"near_edge":nearest_gap(current,area)<=REST_BAND}
static func clamp_origin(origin:Vector2,local_bounds:Rect2,area:Rect2,padding:float=12.0) -> Vector2:
	var minimum:=area.position+Vector2.ONE*padding-local_bounds.position
	var maximum:=area.end-Vector2.ONE*padding-local_bounds.end
	return origin.clamp(minimum,maximum.max(minimum))
