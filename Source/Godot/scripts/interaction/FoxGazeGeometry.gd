extends RefCounted
## Anatomical angles, independent of screen axes and body/world yaw.
static func relative_angles(direction: Vector3, forward: Vector3, up: Vector3) -> Vector2:
	if direction.length_squared()<0.000001: return Vector2.ZERO
	var front := forward.normalized()
	var right := up.cross(front).normalized()
	var vertical := front.cross(right).normalized()
	var target := direction.normalized()
	return Vector2(rad_to_deg(atan2(target.dot(right),target.dot(front))),rad_to_deg(atan2(target.dot(vertical),sqrt(pow(target.dot(front),2)+pow(target.dot(right),2)))))

static func ellipse_limit(angles: Vector2, limits: Vector2) -> Vector2:
	return angles/maxf(1.0,(angles/limits).length())
