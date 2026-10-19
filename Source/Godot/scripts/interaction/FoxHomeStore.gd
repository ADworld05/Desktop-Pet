extends RefCounted
const Atomic=preload("res://scripts/settings/FoxAtomicJson.gd")
## Fixed app-owned file; bounded schema, no imported paths or policy.
static var PATH: String:
	get: return preload("res://scripts/Paths.gd").directory("config").path_join("home.json")
static var TEMP: String:
	get: return PATH + ".tmp"
var last_error := OK

func decode(candidate: Variant) -> Dictionary:
	if not candidate is Dictionary or candidate.get("version")!=1: return {}
	for key in ["position","extent","work_area","fraction"]:
		var row: Variant=candidate.get(key)
		if not row is Array or row.size()!=(4 if key=="work_area" else 2): return {}
		for value in row:
			if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value))>1000000: return {}
	if candidate.extent[0]<=0 or candidate.extent[1]<=0 or candidate.work_area[2]<=0 or candidate.work_area[3]<=0: return {}
	if candidate.fraction[0]<0 or candidate.fraction[0]>1 or candidate.fraction[1]<0 or candidate.fraction[1]>1: return {}
	return candidate

func load_local() -> Dictionary:
	return decode(Atomic.read_local(PATH).data)

func restored(record: Dictionary, extent: Vector2i, areas: Array[Rect2i], fallback: Vector2i) -> Vector2i:
	if record.is_empty() or areas.is_empty(): return fallback
	var prior := Rect2i(record.work_area[0],record.work_area[1],record.work_area[2],record.work_area[3])
	var selected := areas[0]
	for area in areas:
		if area==prior: selected=area;break
	var span := (selected.size-extent).max(Vector2i.ZERO)
	var desired := selected.position+Vector2i(roundi(span.x*record.fraction[0]),roundi(span.y*record.fraction[1]))
	if selected==prior and extent==Vector2i(record.extent[0],record.extent[1]): desired=Vector2i(record.position[0],record.position[1])
	return desired.clamp(selected.position,selected.position+span)

func save_local(origin: Vector2i, extent: Vector2i, area: Rect2i) -> Error:
	var span := (area.size-extent).max(Vector2i.ZERO)
	var bounded := origin.clamp(area.position,area.position+span)
	var fraction := Vector2(bounded-area.position)/Vector2(span.max(Vector2i.ONE))
	var record := {"version":1,"position":[bounded.x,bounded.y],"extent":[extent.x,extent.y],"work_area":[area.position.x,area.position.y,area.size.x,area.size.y],"fraction":[fraction.x,fraction.y]}
	last_error=Atomic.write_local(PATH,record)
	return last_error
