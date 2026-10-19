extends RefCounted
## DisplayServer cursor and window positions share the virtual-screen origin.
## Logical coordinates follow the actual viewport, not an assumed DPI scalar.
static func screen_to_logical(screen: Vector2, origin: Vector2, native_size: Vector2, logical_size: Vector2) -> Vector2:
	return (screen-origin)*logical_size/native_size.max(Vector2.ONE)

static func logical_to_screen(point: Vector2, origin: Vector2, native_size: Vector2, logical_size: Vector2) -> Vector2:
	return origin+point*native_size/logical_size.max(Vector2.ONE)

static func in_native_mask(logical: Vector2, native_size: Vector2, logical_size: Vector2, mask: PackedVector2Array) -> bool:
	return mask.size()>=3 and Geometry2D.is_point_in_polygon(logical*native_size/logical_size.max(Vector2.ONE),mask)

static func clamp_popup(screen: Vector2i, extent: Vector2i, usable: Rect2i) -> Vector2i:
	return Vector2i(clampi(screen.x,usable.position.x,maxi(usable.position.x,usable.end.x-extent.x)),clampi(screen.y,usable.position.y,maxi(usable.position.y,usable.end.y-extent.y)))
