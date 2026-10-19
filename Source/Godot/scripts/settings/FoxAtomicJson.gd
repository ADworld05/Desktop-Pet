extends RefCounted
## Trusted code supplies fixed local paths, never paths from imported settings.
const MAX_BYTES:=16384

static func _read(path:String,allow_legacy:bool) -> Dictionary:
	if not FileAccess.file_exists(path):return {"status":"missing","data":{}}
	var file:=FileAccess.open(path,FileAccess.READ)
	if not file:return {"status":"unreadable","data":{}}
	if file.get_length()>MAX_BYTES:return {"status":"invalid","data":{}}
	var parser:=JSON.new()
	if parser.parse(file.get_as_text())!=OK or not parser.data is Dictionary:return {"status":"invalid","data":{}}
	var value:Dictionary=parser.data
	if value.has("version") and value.version!=1:return {"status":"unsupported_version","data":{}}
	if not value.has("version") and not allow_legacy:return {"status":"invalid","data":{}}
	return {"status":"ok","data":value}

static func read_local(path:String,allow_legacy:bool=false) -> Dictionary:
	var primary:=_read(path,allow_legacy)
	if primary.status in ["ok","missing","unsupported_version"]:return primary
	var backup:=_read(path+".bak",allow_legacy)
	if backup.status=="ok":return {"status":"recovered_backup","data":backup.data}
	return primary

static func _replace(path:String,text:String) -> Error:
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if not file:return FileAccess.get_open_error()
	file.store_string(text);file.flush()
	var error:=file.get_error();file.close()
	if error!=OK:return error
	return DirAccess.rename_absolute(path+".tmp",path)

static func write_local(path:String,candidate:Dictionary) -> Error:
	# Refuse to overwrite a newer format, including on shutdown.
	var old:=_read(path,true)
	if old.status=="unsupported_version":return ERR_UNAVAILABLE
	var value:=candidate.duplicate(true);value.version=1
	var text:=JSON.stringify(value,"\t")+"\n"
	if text.to_utf8_buffer().size()>MAX_BYTES:return ERR_PARAMETER_RANGE_ERROR
	if old.status=="ok":
		var previous:Dictionary=old.data.duplicate(true);previous.version=1
		var error:=_replace(path+".bak",JSON.stringify(previous,"\t")+"\n")
		if error!=OK:return error
	return _replace(path,text)
