class_name WindowGeometry
extends RefCounted

const LOGICAL_SIZE := Vector2i(320, 320)
# This is a drawing AND input envelope on Windows. Keep all motion inside it.
const LOGICAL_ENVELOPE := [
	Vector2(48, 24), Vector2(272, 24), Vector2(300, 70), Vector2(300, 258),
	Vector2(256, 300), Vector2(64, 300), Vector2(20, 258), Vector2(20, 70),
]

static func fit_position(requested: Vector2i, extent: Vector2i, usable: Rect2i) -> Vector2i:
	var last := usable.position + Vector2i(maxi(0, usable.size.x - extent.x), maxi(0, usable.size.y - extent.y))
	return Vector2i(clampi(requested.x, usable.position.x, last.x), clampi(requested.y, usable.position.y, last.y))

static func envelope(pixel_size: Vector2i) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	var scale_xy := Vector2(pixel_size) / Vector2(LOGICAL_SIZE)
	for point in LOGICAL_ENVELOPE:
		polygon.append(point * scale_xy)
	return polygon

static func pixel_extent(scale_factor: float, usable: Rect2i) -> Vector2i:
	var desired := Vector2i(Vector2(LOGICAL_SIZE) * clampf(scale_factor, 1.0, 2.0))
	return Vector2i(mini(desired.x, usable.size.x), mini(desired.y, usable.size.y))
