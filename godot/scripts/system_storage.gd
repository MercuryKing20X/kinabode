extends RefCounted

# The single inventory ledger. No routing, actor authority, food consumption,
# or capacity policy belongs here. Callers must authorize their own actions.
var _items: Dictionary = {}
var audit_enabled:=false
var audit:Array=[]

func count(item: String) -> int:
	return int(_items.get(item, 0))

static func valid_items(value: Variant) -> bool:
	if not value is Dictionary: return false
	for item in value:
		if not item is String or item.is_empty(): return false
		var amount: Variant = value[item]
		if not (amount is int or amount is float): return false
		if not is_finite(float(amount)) or amount < 0 or float(amount) != floor(float(amount)): return false
		# JSON numbers must round-trip exactly; this is a representation limit,
		# not a gameplay storage capacity.
		if amount > 9007199254740991: return false
	return true

func missing(costs: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for item in costs:
		var deficit: int = int(costs[item]) - count(item)
		if deficit > 0: result[item] = deficit
	return result

func has(costs: Dictionary) -> bool:
	return valid_items(costs) and missing(costs).is_empty()

func take(costs: Dictionary) -> Dictionary:
	if not valid_items(costs): return {"ok": false, "error": "invalid_items", "missing": {}}
	var deficit := missing(costs)
	if not deficit.is_empty(): return {"ok": false, "error": "insufficient_materials", "missing": deficit}
	var before:Dictionary=_items.duplicate(true)
	for item in costs:
		var remaining: int = count(item) - int(costs[item])
		if remaining == 0: _items.erase(item)
		else: _items[item] = remaining
	if audit_enabled:audit.append({"kind":"take","items":costs.duplicate(true),"before":before,"after":_items.duplicate(true)})
	return {"ok": true, "missing": {}}

func add(items: Dictionary) -> bool:
	if not valid_items(items): return false
	# Validate the entire transaction before touching the ledger.
	for item in items:
		if int(items[item]) > 9007199254740991 - count(item): return false
	var before:Dictionary=_items.duplicate(true)
	for item in items:
		if int(items[item]) > 0: _items[item] = count(item) + int(items[item])
	if audit_enabled:audit.append({"kind":"add","items":items.duplicate(true),"before":before,"after":_items.duplicate(true)})
	return true

func saved() -> Dictionary:
	return {"items": _items.duplicate(true)}

static func valid_saved(value: Variant) -> bool:
	return value is Dictionary and value.size() == 1 and value.has("items") and valid_items(value.items)

func restore(value: Dictionary) -> bool:
	if not valid_saved(value): return false
	var next: Dictionary = {}
	for item in value.items:
		if int(value.items[item]) > 0: next[item] = int(value.items[item])
	_items = next
	return true
