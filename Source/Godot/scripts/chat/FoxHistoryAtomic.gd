extends RefCounted
## Callers supply app-owned paths. Imported data never supplies a destination.
static func read_one(path:String,validate:Callable,maximum:int) -> Dictionary:
	if not FileAccess.file_exists(path):return {"status":"missing","data":{}}
	var file:=FileAccess.open(path,FileAccess.READ)
	if not file:return {"status":"unreadable","data":{}}
	if file.get_length()>maximum:return {"status":"oversize","data":{}}
	var bytes:=file.get_buffer(file.get_length());file.close()
	if bytes.has(0):return {"status":"invalid_utf8","data":{}}
	var text:=bytes.get_string_from_utf8()
	if text.to_utf8_buffer()!=bytes:return {"status":"invalid_utf8","data":{}}
	var parser:=JSON.new()
	if parser.parse(text)!=OK or not parser.data is Dictionary:return {"status":"invalid","data":{}}
	var raw:Dictionary=parser.data
	if raw.get("version",-1) is float and int(raw.version)==raw.version:raw.version=int(raw.version)
	if raw.get("version",-1) is int and raw.version>1:return {"status":"future_version","data":{}}
	var checked:Dictionary=validate.call(raw)
	if not checked.get("ok",false):return {"status":"invalid_schema","data":{}}
	return {"status":"ok","data":checked.data,"migrated":raw.version==0}
static func read_local(path:String,validate:Callable,maximum:int) -> Dictionary:
	var primary:=read_one(path,validate,maximum)
	if primary.status in ["ok","future_version"]:return primary
	var backup:=read_one(path+".bak",validate,maximum)
	if backup.status=="ok":backup.status="recovered_backup";return backup
	return primary
static func replace(path:String,text:String) -> Error:
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if not file:return FileAccess.get_open_error()
	file.store_string(text);file.flush();var error:=file.get_error();file.close()
	if error!=OK:return error
	return DirAccess.rename_absolute(path+".tmp",path)
static func write_local(path:String,data:Dictionary,validate:Callable,maximum:int) -> Error:
	var candidate:Dictionary=validate.call(data)
	if not candidate.get("ok",false) or data.get("version")!=1:return ERR_INVALID_DATA
	var text:=JSON.stringify(candidate.data)+"\n"
	if text.to_utf8_buffer().size()>maximum:return ERR_PARAMETER_RANGE_ERROR
	var old:=read_one(path,validate,maximum)
	if old.status=="future_version":return ERR_UNAVAILABLE
	if old.status=="ok":
		# Preserve the actual legacy document before conversion, once.
		if old.get("migrated",false) and not FileAccess.file_exists(path+".v0.bak"):
			var migration_error:=DirAccess.copy_absolute(path,path+".v0.bak")
			if migration_error!=OK:return migration_error
		var backup_error:=replace(path+".bak",JSON.stringify(old.data)+"\n")
		if backup_error!=OK:return backup_error
	elif old.status!="missing":
		# Never destroy the sole corrupt document while repairing from a backup.
		var suffix:=".corrupt-"+str(Time.get_unix_time_from_system()).replace(".","-")
		var preserve_error:=DirAccess.copy_absolute(path,path+suffix)
		if preserve_error!=OK:return preserve_error
	return replace(path,text)
