extends RefCounted
## Decode only complete newline-delimited UTF-8 records. Never decode a partial character.
const MAX_LINE:=65536
const MAX_TOTAL:=262144
var pending:=PackedByteArray()
var total:=0
var done:=false
var failed:=false
var metrics:Dictionary={}
var thinking_activity:=false
static func valid_utf8(bytes:PackedByteArray) -> bool:
	var i:=0
	while i<bytes.size():
		var b:int=bytes[i];var n:=0;var low:=128;var high:=191
		if b<128:i+=1;continue
		if b>=194 and b<=223:n=1
		elif b>=224 and b<=239:
			n=2
			if b==224:low=160
			if b==237:high=159
		elif b>=240 and b<=244:
			n=3
			if b==240:low=144
			if b==244:high=143
		else:return false
		if i+n>=bytes.size() or bytes[i+1]<low or bytes[i+1]>high:return false
		for j in range(2,n+1):
			if bytes[i+j]<128 or bytes[i+j]>191:return false
		i+=n+1
	return true
func error(text:String) -> Array[Dictionary]:
	failed=true;return [{"kind":"error","text":text+" · incomplete"}]
func feed(bytes:PackedByteArray) -> Array[Dictionary]:
	var result:Array[Dictionary]=[]
	if failed:return result
	total+=bytes.size()
	if total>MAX_TOTAL:return error("Stream byte limit")
	pending.append_array(bytes)
	while true:
		var newline:=pending.find(10)
		if newline<0:break
		if newline>MAX_LINE:return error("Stream record too large")
		var line:=pending.slice(0,newline);pending=pending.slice(newline+1)
		if line.is_empty():continue
		if done:return error("Data after final done")
		if not valid_utf8(line):return error("Invalid UTF-8")
		var decoder:=JSON.new()
		if decoder.parse(line.get_string_from_utf8())!=OK or not decoder.data is Dictionary:return error("Malformed stream JSON")
		var row:Dictionary=decoder.data
		if row.has("error"):return error(str(row.error).left(240))
		if not row.get("done") is bool:return error("Missing/invalid done flag")
		var message:Variant=row.get("message",{})
		if not message is Dictionary:return error("Invalid message")
		var tools:Variant=message.get("tool_calls",[])
		if not tools is Array or not tools.is_empty():return error("Tools are disabled")
		var content:Variant=message.get("content","")
		if message.get("thinking") is String and not str(message.thinking).is_empty():thinking_activity=true
		if not content is String:return error("Invalid content")
		if not content.is_empty():result.append({"kind":"chunk","text":content})
		# Thinking is neither displayed, persisted nor logged as an answer.
		if row.done:
			done=true
			for key in ["total_duration","load_duration","prompt_eval_count","prompt_eval_duration","eval_count","eval_duration","done_reason"]:
				if row.has(key):metrics[key]=row[key]
			result.append({"kind":"done","metrics":metrics.duplicate()})
	if pending.size()>MAX_LINE:return error("Stream record too large")
	return result
func finish() -> Array[Dictionary]:
	if failed:return []
	var result:Array[Dictionary]=[]
	if not pending.is_empty():result=feed(PackedByteArray([10]))
	if not failed and not done:result.append_array(error("Disconnected before final done"))
	return result
