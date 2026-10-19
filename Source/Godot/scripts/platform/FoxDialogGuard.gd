extends Node
## Bounds only, never changes focus/visibility/approval or pet position.
var host:Node
var windows:Array[Window]=[]
var age:=0.0
func initialize(app:Node)->void:
 host=app
 for node in get_tree().root.find_children("*","Window",true,false):watch(node)
 get_tree().node_added.connect(func(node):
  if node is Window:watch.call_deferred(node))
func watch(window:Window)->void:
 if not is_instance_valid(window) or window==host.pet or window==get_tree().root or window in windows:return
 windows.append(window);window.visibility_changed.connect(func():
  if is_instance_valid(window) and window.visible:fit_window.call_deferred(window))
func fit_window(window:Window)->void:
 if not is_instance_valid(window) or not window.visible or window.is_embedded() or window.mode!=Window.MODE_WINDOWED:return
 var screen:=DisplayServer.window_get_current_screen(window.get_window_id())
 var area:=DisplayServer.screen_get_usable_rect(screen)
 if area.size.x<100 or area.size.y<100:return
 var decoration:=window.get_size_with_decorations()-window.size
 var allowed:Vector2i=(area.size-decoration-Vector2i(8,8)).max(Vector2i(100,80))
 if not window.has_meta("original_minimum"):window.set_meta("original_minimum",window.min_size)
 window.min_size=Vector2i(window.get_meta("original_minimum")).min(allowed)
 window.size=window.size.min(allowed)
 var outer:=window.get_position_with_decorations()
 var extent:=window.get_size_with_decorations()
 var fitted:=Vector2i(clampi(outer.x,area.position.x+4,maxi(area.position.x+4,area.end.x-extent.x-4)),clampi(outer.y,area.position.y+4,maxi(area.position.y+4,area.end.y-extent.y-4)))
 if fitted!=outer:window.position+=fitted-outer
func _process(delta:float)->void:
 age+=delta
 if age<.2:return
 age=0
 # Let native move/resize finish before bringing a misplaced dialog back.
 if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):return
 var retained:Array[Window]=[]
 for window in windows:
  if is_instance_valid(window):retained.append(window);fit_window(window)
 windows=retained
