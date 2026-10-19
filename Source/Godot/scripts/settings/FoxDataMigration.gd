extends RefCounted
## Explicit, reviewed import. No recursive copies, executable/settings paths from data,
## Windows permissions, model preferences, logs, cache or model weights are imported.
const History=preload("res://scripts/chat/FoxHistoryStore.gd")
const Memory=preload("res://scripts/chat/FoxMemoryStore.gd")
const Atomic=preload("res://scripts/chat/FoxHistoryAtomic.gd")
const Paths=preload("res://scripts/Paths.gd")
const CONFIGS:=["preferences.json","pointer.json","follow.json","audio.json","autonomy.json","home.json","history.json"]

static func config_valid(raw:Dictionary)->Dictionary:
	return {"ok":raw.get("version",1)==1,"data":raw}

static func plan(source:String)->Dictionary:
	var root:=source.replace("\\","/").trim_suffix("/")
	var boundary=preload("res://scripts/actions/FoxActionPaths.gd")
	var resolved:Dictionary=boundary.resolve(root)
	if not resolved.get("ok",false) or not resolved.get("directory",false):return {"ok":false,"error":"Choose an accessible local Runtime folder (no links or junctions)."}
	if root.to_lower()==Paths.RUNTIME_ROOT.to_lower():return {"ok":false,"error":"Choose the old data folder, not the current profile."}
	var entries:Array=[];var skipped:=0
	for name in CONFIGS:
		var from:=root.path_join("Config").path_join(name)
		if FileAccess.file_exists(from):
			var entry:=candidate(from,Paths.directory("config").path_join(name),config_valid,16384,boundary)
			if not entry.is_empty():entries.append(entry)
			else:skipped+=1
	var memory:=root.path_join("Memory/memory.json")
	if FileAccess.file_exists(memory):
		var entry:=candidate(memory,Paths.directory("memory").path_join("memory.json"),Memory.validate,Memory.MAX_BYTES,boundary)
		if not entry.is_empty():entries.append(entry)
		else:skipped+=1
	var history:=root.path_join("History")
	if boundary.resolve(history).get("ok",false):
		var count:=0
		for name in DirAccess.get_files_at(history):
			if not name.ends_with(".json") or not History.valid_id(name.trim_suffix(".json")):continue
			count+=1
			if count>History.HARD_SESSIONS:return {"ok":false,"error":"Too many chat files; use a smaller reviewed import."}
			var from:=history.path_join(name)
			var entry:=candidate(from,Paths.directory("history").path_join(name),History.validate_session,History.MAX_SESSION_BYTES,boundary)
			if not entry.is_empty():entries.append(entry)
			else:skipped+=1
	# Index is rebuilt by HistoryStore from valid committed sessions. Respect deletion markers.
	entries=entries.filter(func(row):return not FileAccess.file_exists(row.source.trim_suffix(".json")+".deleted"))
	var total:=0
	for row in entries:total+=row.bytes
	if total>100000000:return {"ok":false,"error":"Import exceeds 100 MB; originals are untouched."}
	return {"ok":true,"entries":entries,"bytes":total,"skipped":skipped,"source":root}

static func candidate(source:String,destination:String,validate:Callable,maximum:int,boundary:Script)->Dictionary:
	if FileAccess.file_exists(destination) or not boundary.resolve(source).get("ok",false):return {}
	var read:=Atomic.read_one(source,validate,maximum)
	if read.status!="ok":return {}
	var file:=FileAccess.open(source,FileAccess.READ)
	if file==null:return {}
	var size:=file.get_length();file.close()
	return {"source":source,"destination":destination,"sha256":FileAccess.get_sha256(source),"bytes":size}

static func copy_reviewed(review:Dictionary)->Dictionary:
	if not review.get("ok",false):return {"ok":false,"copied":0}
	# Re-plan from the explicitly chosen root: never trust imported destinations.
	var current:=plan(str(review.get("source","")))
	if not current.get("ok",false) or current.entries!=review.get("entries"):return {"ok":false,"copied":0,"error":"Files changed since review; review again."}
	var copied:=0
	for row in current.entries:
		if FileAccess.file_exists(row.destination) or FileAccess.get_sha256(row.source)!=row.sha256:return {"ok":false,"copied":copied,"error":"File changed; existing files were preserved."}
		if DirAccess.copy_absolute(row.source,row.destination)!=OK:return {"ok":false,"copied":copied,"error":"Copy failed; originals remain. Review again to resume."}
		if FileAccess.get_sha256(row.destination)!=row.sha256:return {"ok":false,"copied":copied,"error":"Copy verification failed; originals remain."}
		copied+=1
	return {"ok":true,"copied":copied}
