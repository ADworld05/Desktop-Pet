extends RefCounted
const History=preload("FoxHistoryStore.gd")
const Atomic=preload("FoxHistoryAtomic.gd")
const SCHEMA:="desktop-fox.memory"
const MAX_BYTES:=1000000
var path:String
var records:Array=[]
var status:="Memory ready"
var writable:=true
var revision:=0
func _init(destination:String="") -> void:
	path=preload("res://scripts/Paths.gd").directory("memory").path_join("memory.json") if destination.is_empty() else destination
static func validate(raw:Dictionary) -> Dictionary:
	if not History.exact_keys(raw,["schema","version","records"]) or raw.get("schema")!=SCHEMA or raw.get("version")!=1 or not raw.get("records") is Array or raw.records.size()>500:return {"ok":false}
	var ids:Dictionary={};var texts:Dictionary={}
	for row in raw.records:
		if not row is Dictionary or not History.exact_keys(row,["id","type","text","provenance","created_at","updated_at","approval","tags"]):return {"ok":false}
		if not History.valid_id(row.get("id")) or ids.has(row.id) or not History.text_ok(row.get("text"),2000) or row.text.strip_edges().is_empty() or texts.has(row.text.strip_edges()):return {"ok":false}
		if row.get("type")!="note" or row.get("approval")!="user" or row.get("provenance") not in ["explicit","reviewed_import","edited"] or row.get("tags")!=[] or not History.time_ok(row.get("created_at")) or not History.time_ok(row.get("updated_at")):return {"ok":false}
		ids[row.id]=true;texts[row.text.strip_edges()]=true
	return {"ok":true,"data":raw.duplicate(true)}
func document() -> Dictionary:return {"schema":SCHEMA,"version":1,"records":records}
func open() -> void:
	revision+=1
	records=[];writable=true
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir())!=OK:writable=false;status="Memory folder unavailable";return
	var loaded:=Atomic.read_local(path,validate,MAX_BYTES)
	if loaded.status in ["ok","recovered_backup"]:records=loaded.data.records;status="Memory recovered from backup" if loaded.status=="recovered_backup" else "Memory ready"
	elif loaded.status!="missing":writable=false;status="Memory unavailable: "+loaded.status+"; original preserved"
func commit(next:Array,remove_from_backup:bool=false) -> bool:
	if not writable:return false
	var doc:={"schema":SCHEMA,"version":1,"records":next}
	var error:=Atomic.write_local(path,doc,validate,MAX_BYTES)
	if error!=OK:status="Memory could not save: "+error_string(error);return false
	records=next;revision+=1;status="Memory saved"
	if remove_from_backup:
		error=Atomic.replace(path+".bak",JSON.stringify(doc)+"\n")
		if error!=OK:status="Deleted from current memory; backup cleanup failed";return false
	return true
func add(text:String,provenance:String="explicit") -> bool:
	var clean:=text.strip_edges()
	if clean.is_empty() or clean.length()>2000:status="Use 1–2,000 characters per memory";return false
	for row in records:
		if row.text.strip_edges()==clean:status="That memory already exists";return false
	var next:=records.duplicate(true);var now:=History.stamp()
	next.append({"id":History.uuid(),"type":"note","text":clean,"provenance":provenance,"created_at":now,"updated_at":now,"approval":"user","tags":[]});return commit(next)
func edit(id:String,text:String) -> bool:
	var next:=records.duplicate(true)
	for row in next:
		if row.id==id:row.text=text.strip_edges();row.provenance="edited";row.updated_at=History.stamp();return commit(next,true)
	return false
func delete(id:String) -> bool:return commit(records.filter(func(row):return row.id!=id),true) if records.any(func(row):return row.id==id) else false
func review(text:String,json_format:bool) -> Dictionary:
	if text.to_utf8_buffer().size()>MAX_BYTES:return {"ok":false,"error":"Import exceeds 1 MB"}
	var proposals:Array=[]
	if json_format:
		var parser:=JSON.new()
		if parser.parse(text)!=OK or not parser.data is Dictionary:return {"ok":false,"error":"Malformed JSON"}
		var valid:=validate(parser.data)
		if not valid.ok:return {"ok":false,"error":"Unsupported memory schema or duplicate records"}
		for row in valid.data.records:proposals.append(row.text)
	else:
		for line in text.split("\n"):
			var clean:=line.strip_edges()
			if clean.is_empty():continue
			if clean.length()>2000 or clean in proposals:return {"ok":false,"error":"Oversized or duplicate note"}
			proposals.append(clean)
	if proposals.is_empty():return {"ok":false,"error":"Import contains no notes"}
	var additions:Array=[];var skipped:=0
	for value in proposals:
		if records.any(func(row):return row.text.strip_edges()==value.strip_edges()):skipped+=1
		else:additions.append(value.strip_edges())
	if additions.size()+records.size()>500:return {"ok":false,"error":"500-note limit exceeded"}
	return {"ok":true,"notes":additions,"skipped":skipped}
func import_reviewed(proposal:Dictionary) -> bool:
	# UI passes reviewed text only; revalidate against current state at confirmation.
	if not proposal.get("notes") is Array:return false
	var notes:Array=proposal.notes
	if notes.is_empty():status="No new notes to import; existing memory kept";return false
	if notes.size()+records.size()>500:status="500-note limit exceeded";return false
	var seen:Array=[]
	for text in notes:
		if not History.text_ok(text,2000) or text.strip_edges().is_empty() or text in seen or records.any(func(row):return row.text.strip_edges()==text.strip_edges()):status="Memory changed since review; review the import again";return false
		seen.append(text)
	var next:=records.duplicate(true);var now:=History.stamp()
	for text in notes:next.append({"id":History.uuid(),"type":"note","text":text,"provenance":"reviewed_import","created_at":now,"updated_at":now,"approval":"user","tags":[]})
	return commit(next)
func context(prompt:String="") -> String:
	var notes:Array=[]
	var ranked:=records.duplicate(true)
	# Preserve repeated-word weighting, but normalize the prompt once and each
	# note once. Previously a long query lowercased every note for every word.
	var terms:Dictionary={}
	for word in prompt.to_lower().split(" "):
		if word.length()>2:terms[word]=int(terms.get(word,0))+1
	for row in ranked:
		row.rank=0
		var text:String=row.text.to_lower()
		for word in terms:
			if text.contains(word):row.rank+=terms[word]
	ranked.sort_custom(func(a,b):return a.rank>b.rank if a.rank!=b.rank else a.updated_at>b.updated_at)
	var encoded_bytes:=2 # JSON array brackets; count quoted UTF-8 text exactly.
	for row in ranked:
		var cost:int=JSON.stringify(row.text).to_utf8_buffer().size()+(0 if notes.is_empty() else 1)
		if encoded_bytes+cost>2000:continue
		notes.append(row.text);encoded_bytes+=cost
	return JSON.stringify(notes) if not notes.is_empty() else ""
func export_local() -> bool:
	# Export the actual committed document, never a blank fallback/read-only store.
	if not writable:status="Memory unavailable; export disabled to preserve any existing backup";return false
	var data:=document();var checked:=validate(data)
	if not checked.ok:status="Memory export rejected invalid data";return false
	# Compact UTF-8 ensures our export can pass the same 1MB import ceiling.
	var text:=JSON.stringify(data)+"\n"
	if text.to_utf8_buffer().size()>MAX_BYTES:status="Memory export exceeds 1 MB";return false
	var target:=path.get_base_dir()+"/export.json"
	var error:=Atomic.replace(target,text)
	status="Exported memory to "+target if error==OK else "Export failed: "+error_string(error);return error==OK
func purge_copies() -> bool:
	var directory:=DirAccess.open(path.get_base_dir())
	if directory==null:return false
	for name in directory.get_files():
		if name in [path.get_file()+".bak",path.get_file()+".tmp","export.json"] or name.begins_with(path.get_file()+".corrupt-"):
			if DirAccess.remove_absolute(path.get_base_dir()+"/"+name)!=OK:status="Some recovery/export copies could not be removed";return false
	status="Memory recovery/export copies removed; current notes kept";return true
