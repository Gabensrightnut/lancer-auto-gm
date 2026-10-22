class_name RuleResult
extends RefCounted
## Answer from the rules engine: is this allowed, and if not, why (with a book reference).
## `grey_area` marks a legal-but-unclear case the table must rule on (DESIGN.md section 7).

var ok: bool = true
var reason: String = ""
## Where the rule comes from, e.g. "Core p.62 Engaged" or "glossary: Hidden".
var rule_ref: String = ""
## Set when the book is unclear: an id for the ruling, and the readings to choose from.
var grey_area: String = ""
var options: Array = []
## Every problem found, for checks that collect several (e.g. loadout legality):
## [{"reason": String, "rule_ref": String}].
var details: Array = []


static func allow() -> RuleResult:
	return RuleResult.new()


static func deny(why: String, ref: String) -> RuleResult:
	var r := RuleResult.new()
	r.ok = false
	r.reason = why
	r.rule_ref = ref
	return r


static func ruling_needed(ruling_id: String, why: String, ref: String, choices: Array) -> RuleResult:
	var r := RuleResult.new()
	r.grey_area = ruling_id
	r.reason = why
	r.rule_ref = ref
	r.options = choices
	return r


func to_dict() -> Dictionary:
	return {"ok": ok, "reason": reason, "rule_ref": rule_ref, "grey_area": grey_area, "options": options, "details": details}
