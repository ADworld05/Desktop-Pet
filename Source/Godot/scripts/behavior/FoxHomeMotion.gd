extends RefCounted
## Reuses the accepted grounded director, without owning a pointer or saving home.
var active:=false
var braking:=false
var target:=Vector2.ZERO
var origin:=Vector2.ZERO
var velocity:=Vector2.ZERO
var tempo:=1.0
var age:=0.0
var outcome:="idle"

func start(app: Node, destination: Vector2) -> bool:
	if active or app.director.body!="idle_stand" or not app.director.pending.is_empty():return false
	target=destination;origin=Vector2(app.pet.position);velocity=Vector2.ZERO;tempo=1;age=0;braking=false;active=true;outcome="moving"
	return true

func stop(app: Node, reason: String="interrupted") -> void:
	if not active:return
	app.director.follow_stop();velocity=Vector2.ZERO;active=false;braking=false;outcome=reason

func step(app: Node, delta: float, behavior: RefCounted) -> bool:
	if not active:return false
	age+=delta
	var director:Node=app.director
	var screen:=DisplayServer.window_get_current_screen(app.pet.get_window_id())
	var area:=Rect2(DisplayServer.screen_get_usable_rect(screen))
	var scale:Vector2=app._drag_scale()
	var distance:Vector2=target-origin
	if (distance/scale).length()<=8 or age>=15:braking=true
	var old:=Vector3(director.stage.position.x,0,director.stage.position.z)
	var wanted:=1.0
	if braking:director.follow_stop()
	else:
		director.follow_drive(app._screen_direction_world(distance),"walk",delta)
		if director.body in ["turn_left","turn_right"]:wanted=.75
		elif director.body=="walk":
			var forward:Vector3=director.follow_forward()
			var pixels:Vector2=(app.camera.unproject_position(old+forward)-app.camera.unproject_position(old))*scale
			var length:float=director.catalog.animations.walk.length
			var stride:float=director.catalog.travel("walk",length).origin.length()/length
			var requested:=minf(38.0*scale.length()/sqrt(2.0),distance.length()/.4)
			wanted=clampf(requested/maxf(1,pixels.length()*stride),.1,1.0)
			if absf(director.follow_error_degrees)>30:wanted=minf(wanted,.55)
	tempo=move_toward(tempo,wanted,delta*3)
	director.step(delta*(1 if braking else tempo))
	var placed:=Vector3(director.stage.position.x,0,director.stage.position.z)
	if braking:velocity=velocity.move_toward(Vector2.ZERO,400*delta)
	else:
		var measured:Vector2=(app.camera.unproject_position(placed)-app.camera.unproject_position(old))*scale/maxf(.001,delta)
		velocity=velocity.lerp(measured,1-exp(-delta/.08))
	var movement:=velocity*delta
	if braking:movement=movement.limit_length(distance.length())
	origin=behavior.bounded(origin+movement,scale,area,Vector2(app.pet.size))
	app.pet.position=Vector2i(roundi(origin.x),roundi(origin.y))
	if braking and director.body=="idle_stand" and director.blend_age>=director.blend_duration:
		velocity=Vector2.ZERO;active=false;braking=false;outcome="arrived" if age<15 else "bounded_timeout"
	return true
