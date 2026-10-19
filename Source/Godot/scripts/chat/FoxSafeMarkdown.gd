extends RefCounted
## Small bounded presentation converter. User text cannot supply BBCode tags,
## URLs, image resources, font paths or HTML. Unsupported Markdown stays text.
const MAX_TEXT:=48000
const MAX_LINES:=600
const MAX_COLUMNS:=6
static func escape(value:String) -> String:
	return literal(value)
static func literal(value:String) -> String:
	var out:=""
	for letter in value:
		out+="[lb]" if letter=="[" else ("[rb]" if letter=="]" else letter)
	return out
static func inline(value:String) -> String:
	var out:="";var index:=0
	while index<value.length():
		if value.substr(index,1)=="`":
			var end:=value.find("`",index+1)
			if end>=0:out+="[code]"+literal(value.substr(index+1,end-index-1))+"[/code]";index=end+1;continue
		if value.substr(index,2)=="**":
			var end:=value.find("**",index+2)
			if end>=0:out+="[b]"+literal(value.substr(index+2,end-index-2))+"[/b]";index=end+2;continue
		out+=literal(value.substr(index,1));index+=1
	return out
static func cells(line:String) -> PackedStringArray:
	var value:=line.strip_edges().trim_prefix("|").trim_suffix("|")
	var result:=value.split("|");return result
static func separator(line:String) -> bool:
	if not line.contains("|"):return false
	for cell in cells(line):
		var value:=cell.strip_edges().replace(":","")
		if value.length()<3 or value.replace("-","")!="":return false
	return true
static func render(value:String) -> Dictionary:
	var plain:=value.left(MAX_TEXT);var lines:=plain.split("\n")
	if value.length()>MAX_TEXT or lines.size()>MAX_LINES:
		return {"bbcode":literal(plain),"plain":plain,"fallback":true,"truncated":value.length()>MAX_TEXT}
	var out:="";var index:=0;var code:=false;var code_text:=""
	while index<lines.size():
		var line:String=lines[index]
		if line.strip_edges().begins_with("```"):
			if code:out+="[code]"+literal(code_text.trim_suffix("\n"))+"[/code]\n";code_text=""
			code=not code;index+=1;continue
		if code:code_text+=line+"\n";index+=1;continue
		if index+1<lines.size() and line.contains("|") and separator(lines[index+1]):
			var head:=cells(line);var columns:=head.size()
			if columns<=MAX_COLUMNS and columns>=2:
				out+="[table=%d]"%columns
				for cell in head:out+="[cell][b]"+inline(cell.strip_edges().left(1000))+"[/b][/cell]"
				index+=2;var rows:=0
				while index<lines.size() and lines[index].contains("|") and rows<24:
					var row:=cells(lines[index])
					if row.size()!=columns:break
					for cell in row:out+="[cell]"+inline(cell.strip_edges().left(1000))+"[/cell]"
					index+=1;rows+=1
				out+="[/table]\n";continue
		var trimmed:=line.strip_edges()
		if trimmed.begins_with("# ") or trimmed.begins_with("## ") or trimmed.begins_with("### "):
			out+="[b]"+inline(trimmed.trim_prefix("### ").trim_prefix("## ").trim_prefix("# "))+"[/b]\n"
		elif trimmed.begins_with("- ") or trimmed.begins_with("* "):out+="• "+inline(trimmed.substr(2))+"\n"
		else:out+=inline(line)+"\n"
		index+=1
	# Incomplete fenced blocks stream as literal code, never as executable markup.
	if code:out+="[code]"+literal(code_text.trim_suffix("\n"))+"[/code]"
	return {"bbcode":out.trim_suffix("\n"),"plain":plain,"fallback":false,"truncated":false}
