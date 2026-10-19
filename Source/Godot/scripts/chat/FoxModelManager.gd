extends RefCounted
const HTTP=preload("FoxOllamaHTTP.gd")
var transfer:=HTTP.new()
var status:="Ready"
var operation:=""
var completed:=false
var refresh_needed:=false
static func valid_tag(tag:String)->bool:
	if tag.is_empty() or tag.length()>180 or tag!=tag.strip_edges():return false
	var regex:=RegEx.new();regex.compile("^[a-zA-Z0-9][a-zA-Z0-9_.-]*(/[a-zA-Z0-9][a-zA-Z0-9_.-]*)?(:[a-zA-Z0-9][a-zA-Z0-9_.-]*)?$")
	return regex.search(tag)!=null and not tag.contains("..")
func begin(tag:String,remove:bool=false)->bool:
	if transfer.running:return false
	if not valid_tag(tag):status="Enter a valid local Ollama tag";return false
	if not remove and (tag.to_lower().ends_with(":cloud") or tag.to_lower().ends_with("-cloud")):status="Cloud-only downloads are disabled. Choose a local-weight model.";return false
	operation="remove" if remove else "install";completed=false
	transfer.first_seconds=180;transfer.total_seconds=7200
	status=("Removing " if remove else "Installing ")+tag
	return transfer.start("/api/delete" if remove else "/api/pull",{"model":tag,"stream":true})
func cancel()->void:
	if not transfer.running:return
	transfer.cancel();status="Download cancelled; partial downloads may remain resumable";refresh_needed=true
func advance(delta:float)->void:
	for event in transfer.advance(delta):
		if event.kind=="progress":
			var value:Dictionary=event.value;status=str(value.get("status","Downloading"))
			if float(value.get("total",0))>0:status+=" %d%%"%int(100.0*float(value.get("completed",0))/float(value.total))
			if value.get("status")=="success":completed=true
		elif event.kind=="error":status=str(event.text);refresh_needed=true
		elif event.kind=="management_end":
			if operation=="remove":completed=true
			status="Complete" if completed else "Transfer ended before success; refresh and retry"
			refresh_needed=true
