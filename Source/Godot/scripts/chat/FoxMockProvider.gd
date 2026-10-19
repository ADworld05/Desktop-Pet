extends RefCounted
## Deterministic local presentation fixture. No HTTP, processes or model loads.
var request_id:=0
var session_id:=""
var answer:=""
var offset:=0
var age:=0.0
var credit:=0.0
var active:=false
var fail:=false
const INTERVAL:=0.04
const CHUNK_SIZE:=64
func start(id:int,session:String,prompt:String,scenario:String) -> void:
	request_id=id;session_id=session;answer=response(prompt,scenario);offset=0;age=0;credit=0;active=true;fail=scenario=="Error"
func cancel() -> void:active=false
func advance(delta:float) -> Array[Dictionary]:
	var events:Array[Dictionary]=[]
	if not active:return events
	age+=clampf(delta,0,.25)
	if age<.24:return events
	credit+=clampf(delta,0,.25)
	while credit>=INTERVAL and active:
		credit-=INTERVAL
		if fail and offset>=128:
			events.append({"request":request_id,"session":session_id,"kind":"error","text":"The preview connection stopped. Your partial answer is kept; Retry starts a fresh request."});active=false
		elif offset<answer.length():
			var text:=answer.substr(offset,CHUNK_SIZE);offset+=text.length()
			events.append({"request":request_id,"session":session_id,"kind":"chunk","text":text})
		else:events.append({"request":request_id,"session":session_id,"kind":"done","text":""});active=false
	return events
static func response(prompt:String,scenario:String) -> String:
	if scenario=="Automatic":scenario="Formatted" if prompt.to_lower().contains("code") or prompt.to_lower().contains("table") else "Short"
	if scenario=="Short":return "I'm here! Your pet can keep you company while you work. Try a question, or open Settings to adjust the pet. 🦊"
	var formatted:="# A little help from your pet\n\nThis is a **local mock answer**. Your real local model connects in a later step.\n\n- Keep the next action small.\n- Take a short break when you need one.\n- You can stop a reply without losing your draft.\n\n## Example code\n\n```python\ndef greet(name):\n    return f\"Hello, {name}! 🦊\"\n\nprint(greet(\"Abir\"))\n```\n\n## A simple comparison\n\n| Option | Useful for | State |\n| --- | --- | --- |\n| FAST | Short replies | Mock |\n| SMART | Longer explanations | Mock |\n\n**Nothing in a reply runs as a command.** Links, images and code remain text here.\n\nUnicode check: café · বাংলা · 日本語 · 🦊"
	if scenario=="Error":return "I started this mock reply, but the preview will simulate a connection error after some text. The partial response stays labeled incomplete so you can decide whether to retry."
	if scenario=="Long":
		for index in 32:formatted+="\n\n## Note %d\n\nA longer answer should let you read at your own pace. Scroll up while new text arrives: the panel keeps your place. Use Jump to latest when you want to catch up. **Small, clear steps** are easier to follow than a wall of text.\n\n- Start with one concrete action.\n- Review what changed.\n- Keep useful notes for later."%(index+1)
	return formatted
