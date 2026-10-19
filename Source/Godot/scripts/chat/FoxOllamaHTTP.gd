extends RefCounted
const Stream=preload("FoxOllamaStream.gd")
const PATHS:=["/api/tags","/api/show","/api/chat","/api/ps","/api/version","/api/pull","/api/delete"]
var client:=HTTPClient.new()
var stream:RefCounted
var running:=false
var sent:=false
var body_seen:=false
var response_checked:=false
var error_status:=0
var path:=""
var payload:=""
var streaming:=false
var buffer:=PackedByteArray()
var started:=0
var first_output:=false
var first_seconds:=30.0
var total_seconds:=180.0
var connect_seconds:=3.0
var port:=11434 # Not exposed in UI; tests use an isolated loopback port.
var metrics:Dictionary={}
static func valid_endpoint(value:String) -> bool:return value=="http://127.0.0.1:11434"
func start(route:String,data:Dictionary={},is_stream:bool=false) -> bool:
	if running or route not in PATHS:return false
	path=route;payload="" if route in ["/api/tags","/api/ps","/api/version"] else JSON.stringify(data)
	streaming=is_stream;stream=Stream.new();buffer.clear();metrics.clear();sent=false;body_seen=false;response_checked=false;error_status=0;first_output=false
	started=Time.get_ticks_msec();running=true
	client=HTTPClient.new();client.read_chunk_size=4096
	if client.connect_to_host("127.0.0.1",port)!=OK:client.close();running=false;return false
	return true
func cancel() -> void:client.close();running=false;buffer.clear()
func fail(reason:String) -> Array[Dictionary]:cancel();return [{"kind":"error","text":reason+" · incomplete"}]
func elapsed() -> float:return float(Time.get_ticks_msec()-started)/1000.0
static func api_error_message(code:int,bytes:PackedByteArray)->String:
	# Only classify known errors. Never display arbitrary server text, paths or markup.
	var json:=JSON.new()
	var parsed:Variant=json.data if Stream.valid_utf8(bytes) and json.parse(bytes.get_string_from_utf8())==OK else null
	var detail:String=str(parsed.get("error","")) if parsed is Dictionary else ""
	if detail.contains("model requires more system memory"):
		return "Not enough free memory for this model. Choose a smaller local model or close unused apps, then Retry"
	if detail.contains("llama runner process has terminated"):
		return "Local model runner stopped. Choose a smaller local model or free memory before retrying"
	return "Ollama HTTP %d"%code
func finish() -> Array[Dictionary]:
	if error_status!=0:return fail(api_error_message(error_status,buffer))
	if path in ["/api/pull","/api/delete"]:
		var events:Array[Dictionary]=[]
		if not buffer.is_empty():
			var json:=JSON.new()
			if not Stream.valid_utf8(buffer) or json.parse(buffer.get_string_from_utf8())!=OK or not json.data is Dictionary:return fail("Incomplete model-management response")
			var parsed:Dictionary=json.data
			if parsed.has("error"):return fail("Model-management request failed")
			if path=="/api/pull":events.append({"kind":"progress","value":parsed})
		cancel();events.append({"kind":"management_end"});return events
	var result:Array[Dictionary]=[]
	if streaming:result=stream.finish();metrics=stream.metrics.duplicate()
	else:
		var json:=JSON.new()
		if not Stream.valid_utf8(buffer) or json.parse(buffer.get_string_from_utf8())!=OK or not json.data is Dictionary:return fail("Invalid API JSON")
		if json.data.has("error"):return fail(str(json.data.error).left(240))
		result.append({"kind":"json","value":json.data})
	cancel();return result
func advance(_delta:float) -> Array[Dictionary]:
	if not running:return []
	if elapsed()>total_seconds:return fail("Total request deadline")
	if not first_output and elapsed()>first_seconds:return fail("First output timeout")
	if not sent and elapsed()>connect_seconds:return fail("Loopback connection timeout")
	if response_checked and client.get_status() in [HTTPClient.STATUS_CONNECTED,HTTPClient.STATUS_DISCONNECTED]:return finish()
	var error:=client.poll()
	if error!=OK:
		if response_checked and client.get_status()==HTTPClient.STATUS_DISCONNECTED:return finish()
		return fail("Ollama connection lost")
	var state:=client.get_status()
	if state==HTTPClient.STATUS_CONNECTED:
		if sent:return finish() if body_seen or response_checked else fail("Disconnected before response")
		sent=true
		var method:=HTTPClient.METHOD_GET if payload.is_empty() else HTTPClient.METHOD_POST
		if path=="/api/delete":method=HTTPClient.METHOD_DELETE
		if client.request(method,path,PackedStringArray(["Content-Type: application/json","Connection: close"]),payload)!=OK:return fail("Request failed")
	elif state==HTTPClient.STATUS_BODY:
		if not response_checked:
			response_checked=true
			var code:=client.get_response_code()
			if code>=300 and code<400:return fail("Redirect refused")
			if code!=200:error_status=code
		body_seen=true;var result:Array[Dictionary]=[];var budget:=Time.get_ticks_usec()
		# Bound each frame's socket/parse work; remaining chunks wait until next frame.
		for index in 16:
			if client.get_status()!=HTTPClient.STATUS_BODY:break
			var chunk:=client.read_response_body_chunk()
			if chunk.is_empty():break
			if error_status!=0:
				buffer.append_array(chunk)
				if buffer.size()>4096:return fail("Ollama HTTP %d (error detail exceeded limit)"%error_status)
			elif path=="/api/pull":
				buffer.append_array(chunk);first_output=true
				if buffer.size()>65536:return fail("Model progress record exceeded limit")
				while buffer.find(10)>=0:
					var end:=buffer.find(10);var line:=buffer.slice(0,end);buffer=buffer.slice(end+1)
					if line.is_empty():continue
					var json:=JSON.new()
					if not Stream.valid_utf8(line) or json.parse(line.get_string_from_utf8())!=OK or not json.data is Dictionary:return fail("Invalid model progress")
					var parsed:Dictionary=json.data
					if parsed.has("error"):return fail(str(parsed.error).left(240))
					result.append({"kind":"progress","value":parsed})
			elif streaming:
				var events:Array[Dictionary]=stream.feed(chunk)
				# A valid hidden-thinking record is activity, not a visible token.
				# Total deadline still bounds generation and Stop remains available.
				if stream.thinking_activity:first_output=true
				for event in events:
					if event.kind=="chunk":first_output=true
				result.append_array(events)
				if stream.failed:cancel();return result
				if stream.done:metrics=stream.metrics.duplicate();cancel();return result
			else:
				buffer.append_array(chunk)
				if buffer.size()>2097152:return fail("API body limit")
			if Time.get_ticks_usec()-budget>=2000:break
		return result
	elif state in [HTTPClient.STATUS_DISCONNECTED,HTTPClient.STATUS_CONNECTION_ERROR,HTTPClient.STATUS_CANT_CONNECT,HTTPClient.STATUS_CANT_RESOLVE,HTTPClient.STATUS_TLS_HANDSHAKE_ERROR]:
		if response_checked:return finish()
		return fail("Ollama unavailable; use Start Ollama or Retry")
	return []
