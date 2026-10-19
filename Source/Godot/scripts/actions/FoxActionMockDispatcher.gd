extends RefCounted
## Deliberately has no Windows adapters or success assertions.
const Schema = preload("res://scripts/actions/FoxActionSchema.gd")
var calls := 0

func dispatch_validated(plan: Dictionary) -> Dictionary:
	if not plan.get("request") is Dictionary or not Schema.validate(plan.request).ok: return {"ok": false, "status": "invalid_plan", "simulated": true, "executed": false}
	calls += 1
	return {"ok": true, "status": "mock_validated_only", "simulated": true, "executed": false, "tool": plan.request.tool}
