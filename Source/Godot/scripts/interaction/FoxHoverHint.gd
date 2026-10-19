extends Control
## Visual-only badge; remains inside the pet's existing native envelope.
var caption := ""
var location := Vector2.ZERO
var progress := 0.0

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func show_state(gesture: RefCounted, center: Vector2, stepping: bool) -> void:
	location=center;caption="";progress=0.0
	if stepping:caption="Turning…"
	elif gesture.phase=="priming":
		caption="Hold…";progress=clampf(gesture.face_age/gesture.FACE_DWELL,0.0,1.0)
	elif gesture.phase=="armed":
		caption="Ready";progress=1.0
	elif gesture.phase=="aiming":
		caption="← Left" if gesture.side>0 else "Right →"
		progress=clampf(gesture.target_age/gesture.TARGET_DWELL,0.0,1.0)
	queue_redraw()

func _draw() -> void:
	if caption.is_empty():return
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x+12
	var rectangle := Rect2(location-Vector2(width/2,9),Vector2(width,25))
	var box := StyleBoxFlat.new()
	box.bg_color=Color(0.07,0.10,0.17,0.87);box.set_corner_radius_all(6)
	draw_style_box(box,rectangle)
	draw_string(font,rectangle.position+Vector2(6,15),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("#f4f7ff"))
	if progress>0:draw_line(rectangle.position+Vector2(5,22),rectangle.position+Vector2(5+(width-10)*progress,22),Color("#9acbff"),2)
