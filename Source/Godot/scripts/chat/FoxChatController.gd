extends RefCounted
const Provider=preload("FoxMockProvider.gd")
const History=preload("FoxHistoryStore.gd")
signal changed
signal request_started(id:int)
signal request_finished(state:String)
signal completed_message(session:String,message:Dictionary)
signal history_requested
signal session_changed(id:String)
const MAX_INPUT:=4000
const MAX_OUTPUT:=48000
const MAX_MESSAGES:=80
var provider:RefCounted=Provider.new()
var sessions:Array[Dictionary]=[]
var current:=0
var serial:=0
var session_serial:=0
var active_request:Dictionary={}
var status:="Ready"
var dirty:=false
var batch_age:=0.0
var discarded_events:=0
var refreshes:=0
var provider_serial:=-1
var real_provider:=false
var history_store:RefCounted
var memory_store:RefCounted
var storage_status:=""
var storage_dirty:=false
var storage_age:=0.0
var loaded_order:Array[String]=[]
func _init() -> void:new_chat()
func use_history(value:RefCounted) -> void:
	history_store=value;history_store.open();sessions.clear();loaded_order.clear()
	for summary in history_store.summaries():
		var row:Dictionary=summary.duplicate(true);row.merge({"draft":"","messages":[],"loaded":false});sessions.append(row)
	current=-1;new_chat();storage_status=history_store.status
func _ensure_loaded() -> void:
	if current<0 or current>=sessions.size() or sessions[current].get("loaded",true):return
	var row:Dictionary=sessions[current];var result:Dictionary=history_store.load_session(row.id)
	if result.ok:
		row.merge(result.data,true);row.loaded=true;storage_status=result.status
	else:row.loaded=true;row.storage_error=true;storage_status=result.status
	_touch_loaded(row.id)
func _touch_loaded(id:String) -> void:
	loaded_order.erase(id);loaded_order.append(id)
	while loaded_order.size()>4:
		var older:String=loaded_order.pop_front()
		for row in sessions:
			if row.id==older and row.id!=sessions[current].id and row.get("saved",true) and not row.get("storage_error",false):row.messages=[];row.draft="";row.loaded=false
func _document() -> Dictionary:
	var row:=session();var data:={"schema":History.SESSION_SCHEMA,"version":1}
	for key in ["id","title","model","created_at","updated_at","draft","messages"]:data[key]=row[key]
	return data
func flush_history() -> bool:
	if history_store==null or not storage_dirty:return true
	if session().get("storage_error",false):return false
	storage_age=0
	var saved:bool=history_store.save(_document());storage_status=history_store.status
	if saved:storage_dirty=false;storage_age=0;session().saved=true
	return saved
func _storage_changed(immediate:bool=false) -> void:
	if history_store==null:return
	session().updated_at=History.stamp();storage_dirty=true;session().saved=false
	if immediate:flush_history()
func use_local_provider(value:RefCounted) -> void:
	stop("Provider changed");provider=value;real_provider=true;status=provider.state;changed.emit()
func model_label(slot:String) -> String:return provider.label(slot) if real_provider else slot+" · Mock"
func selected_model_name() -> String:return provider.resolve_model(session().model) if real_provider else session().model
func model_choices() -> Array[Dictionary]:
	if real_provider:return provider.model_choices()
	return [{"name":"FAST","label":"FAST · Mock","tooltip":"Validation fixture"},{"name":"SMART","label":"SMART · Mock","tooltip":"Validation fixture"}]
func session() -> Dictionary:
	_ensure_loaded();return sessions[current]
func busy() -> bool:return not active_request.is_empty()
func draft(value:String) -> void:
	if session().get("storage_error",false):return
	if session().draft==value.left(MAX_INPUT):return
	session().draft=value.left(MAX_INPUT);_storage_changed()
func new_chat() -> void:
	stop("New chat")
	if history_store!=null and not flush_history():status="Previous chat could not save; New Chat deferred";changed.emit();return
	if history_store!=null and current>=0 and sessions.size()>=History.HARD_SESSIONS:status="History limit reached; review saved chats";changed.emit();return
	session_serial+=1;var now:=History.stamp()
	sessions.append({"id":History.uuid(),"title":"New chat","draft":"","model":"FAST","messages":[],"created_at":now,"updated_at":now,"loaded":true,"saved":false})
	current=sessions.size()-1;status="Ready";changed.emit();session_changed.emit(session().id)
	_touch_loaded(session().id);_storage_changed(true)
func select_session(id:String) -> bool:
	for index in sessions.size():
		if sessions[index].id==id:
			stop("Chat changed")
			if history_store!=null and not flush_history():status="Current chat could not save; switch deferred";changed.emit();return false
			current=index;_ensure_loaded();_touch_loaded(id);status="Ready";changed.emit();session_changed.emit(id);return true
	return false
func select_model(model:String) -> void:
	if session().model==model:return
	if model not in ["FAST","SMART"] and (not real_provider or not provider.catalog.has(model)):return
	stop("Model changed");session().model=model;_storage_changed(true);changed.emit()
func send(value:String,scenario:String="Automatic") -> bool:
	var text:=value.strip_edges()
	if busy() or text.is_empty():return false
	if text.length()>MAX_INPUT or session().get("storage_error",false) or session().messages.size()>MAX_MESSAGES-2:status="This chat cannot accept another message; start a New Chat or shorten the input";changed.emit();return false
	var remember:=""
	for prefix in ["remember this:","remember this ","remember that ","remember:"]:
		if text.to_lower().begins_with(prefix):remember=text.substr(prefix.length());break
	if memory_store!=null and not remember.is_empty():
		if not memory_store.add(remember):status=memory_store.status;changed.emit();return false
		var now:=History.stamp();session().draft=""
		for entry in [["user",text],["assistant","Saved to your local memory."]]:session().messages.append({"id":History.uuid(),"role":entry[0],"text":entry[1],"state":"complete","model":"local-memory","created_at":now,"updated_at":now,"tool_summaries":[]})
		_storage_changed(true);status=memory_store.status;changed.emit();return true
	if session().get("storage_error",false):status="This saved chat is unavailable; start a New Chat";changed.emit();return false
	if text.length()>MAX_INPUT:status="Message too long: use up to4,000characters.";changed.emit();return false
	if session().messages.size()>MAX_MESSAGES-2:status="This chat is full. Start a New Chat.";changed.emit();return false
	session().draft="";session().title=text.replace("\n"," ").left(35)
	var now:=History.stamp();session().messages.append({"id":History.uuid(),"role":"user","text":text,"state":"complete","model":selected_model_name(),"created_at":now,"updated_at":now,"tool_summaries":[]})
	_begin(text,scenario);return true
func _begin(text:String,scenario:String) -> void:
	serial+=1;var now:=History.stamp();var row:={"id":History.uuid(),"role":"assistant","text":"","state":"streaming","model":selected_model_name(),"created_at":now,"updated_at":now,"tool_summaries":[]}
	session().messages.append(row)
	active_request={"id":serial,"session":session().id,"index":session().messages.size()-1,"prompt":text,"scenario":scenario}
	if real_provider:
		provider.memory_context=memory_store.context(text) if memory_store!=null else ""
		provider.set_context(session().model,session().messages)
	provider.start(serial,session().id,text,scenario);status="Thinking…";dirty=false;batch_age=0;_storage_changed(true);changed.emit();request_started.emit(serial)
func retry(scenario:String="Automatic") -> bool:
	if busy() or session().messages.is_empty() or session().messages.size()>=MAX_MESSAGES:return false
	var messages:Array=session().messages
	if messages.back().state not in ["error","cancelled"]:return false
	for index in range(messages.size()-1,-1,-1):
		if messages[index].role=="user":_begin(messages[index].text,scenario);return true
	return false
func stop(reason:String="Stopped") -> void:
	if not busy():return
	_finish("cancelled",reason+" · partial answer")
func _finish(state:String,detail:String) -> void:
	if not busy():return
	var row:Dictionary=session().messages[active_request.index];row.state=state;row.updated_at=History.stamp()
	provider.cancel();active_request.clear();status=detail;dirty=false;batch_age=0;_storage_changed(true);changed.emit();request_finished.emit(state)
	# The completion hook never receives cancelled/error/incomplete messages.
	if state=="complete":completed_message.emit(session().id,row.duplicate(true))
func receive(event:Dictionary) -> void:
	if not busy() or event.get("request")!=active_request.id or event.get("session")!=active_request.session or session().id!=active_request.session:
		discarded_events+=1;return
	var row:Dictionary=session().messages[active_request.index]
	match str(event.get("kind")):
		"chunk":
			var value:Variant=event.get("text")
			if not value is String:_finish("error","Malformed preview chunk · partial answer");return
			if row.text.length()+value.length()>MAX_OUTPUT:_finish("error","Answer limit reached · partial answer");return
			row.text+=value;row.updated_at=History.stamp();_storage_changed();status="Receiving…";dirty=true
		"done":
			if str(row.text).strip_edges().is_empty():_finish("error","No visible answer was produced. Increase the reply budget or manually choose another model, then Retry")
			else:_finish("complete","Ready")
		"error":_finish("error",str(event.get("text","Preview error")))
func advance(delta:float) -> void:
	for event in provider.advance(delta):receive(event)
	if real_provider and provider_serial!=provider.catalog_serial:
		provider_serial=provider.catalog_serial
		if not busy():status=provider.state
		changed.emit()
	batch_age+=clampf(delta,0,.25)
	if dirty and batch_age>=.03:dirty=false;batch_age=0;refreshes+=1;changed.emit()
	storage_age+=clampf(delta,0,.25)
	if storage_dirty and storage_age>=1.0:flush_history()
func completed() -> Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for row in session().messages:
		if row.state=="complete":result.append(row.duplicate(true))
	return result
func delete_chat(id:String) -> bool:
	stop("Chat deleted")
	if not flush_history() or history_store==null or not history_store.delete_session(id):return false
	var active_id:String=session().id;sessions=sessions.filter(func(row):return row.id!=id);loaded_order.erase(id);storage_dirty=false
	if sessions.is_empty():current=-1;new_chat()
	else:
		current=0
		for index in sessions.size():
			if sessions[index].id==active_id:current=index;break
		_ensure_loaded();changed.emit();session_changed.emit(session().id)
	storage_status=history_store.status;return true
