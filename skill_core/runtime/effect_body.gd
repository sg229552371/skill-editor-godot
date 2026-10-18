class_name EffectBody extends RefCounted

## Runtime lifecycle shell for the four effect carriers. Hit production is
## intentionally owned by the later hit/settlement tasks; this class only
## emits the frozen lifecycle event `vanish`.

const CARRIER_NONE: String = "none"
const CARRIER_SELF: String = "self"
const CARRIER_INDEPENDENT: String = "independent"
const CARRIER_ATTACHED: String = "attached"
const CARRIERS: Array[String] = [CARRIER_NONE, CARRIER_SELF, CARRIER_INDEPENDENT, CARRIER_ATTACHED]

const CREATED: String = "CREATED"
const ACTIVE: String = "ACTIVE"
const VANISHED: String = "VANISHED"
const PURGED: String = "PURGED"

const REASON_HIT_END: String = "hit_end"
const REASON_RANGE_END: String = "range_end"
const REASON_LANDED: String = "landed"
const REASON_EXPIRED: String = "expired"
const REASON_RETURNED: String = "returned"
const REASON_INTERRUPTED: String = "interrupted"
const REASON_INSTANT_END: String = "instant_end"
const VANISH_REASONS: Array[String] = [
	REASON_HIT_END,
	REASON_RANGE_END,
	REASON_LANDED,
	REASON_EXPIRED,
	REASON_RETURNED,
	REASON_INTERRUPTED,
	REASON_INSTANT_END,
]

var body_id: String
var carrier: String
var spawn_tick: int
var lifetime_ticks: int
var state: String
var parent_ref: Variant
var generation: int
var origin: Variant
var _vanish_reason: String
var _vanish_emitted: bool = false


static func create(carrier_value: String, cfg: Dictionary, spawn_tick_value: int) -> EffectBody:
	if not CARRIERS.has(carrier_value):
		return null
	if not cfg.has("lifetime_ticks"):
		return null
	var lifetime_value: Variant = cfg["lifetime_ticks"]
	if typeof(lifetime_value) != TYPE_INT:
		return null
	if carrier_value == CARRIER_NONE:
		if lifetime_value != 0:
			return null
	elif lifetime_value <= 0:
		return null

	var result := EffectBody.new()
	result.body_id = str(cfg.get("body_id", ""))
	result.carrier = carrier_value
	result.spawn_tick = spawn_tick_value
	result.lifetime_ticks = lifetime_value
	result.state = CREATED
	result.parent_ref = cfg.get("parent_ref", null)
	var generation_value: Variant = cfg.get("generation", 0)
	if typeof(generation_value) == TYPE_INT:
		result.generation = generation_value
	else:
		result.generation = 0
	result.origin = cfg.get("origin", null)
	result._vanish_reason = _resolve_reason(carrier_value, cfg)
	return result


static func _resolve_reason(carrier_value: String, cfg: Dictionary) -> String:
	if carrier_value == CARRIER_NONE:
		return REASON_INSTANT_END
	var configured: Variant = cfg.get("vanish_reason", cfg.get("reason", REASON_EXPIRED))
	if typeof(configured) == TYPE_STRING and VANISH_REASONS.has(configured) and configured != REASON_INSTANT_END:
		return configured
	return REASON_EXPIRED


## Advance lifecycle state and return zero or one frozen lifecycle event.
func step(current_tick: int) -> Array:
	if state == VANISHED or state == PURGED:
		return []
	if current_tick < spawn_tick:
		return []
	if state == CREATED:
		state = ACTIVE

	var should_vanish: bool = carrier == CARRIER_NONE or current_tick >= spawn_tick + lifetime_ticks
	if not should_vanish or _vanish_emitted:
		return []
	_vanish_emitted = true
	state = VANISHED
	return [_event(REASON_INSTANT_END if carrier == CARRIER_NONE else _vanish_reason, current_tick)]


func purge():
	if state != VANISHED:
		state = PURGED
	_vanish_emitted = true


func is_alive() -> bool:
	return state == CREATED or state == ACTIVE


func to_debug_record() -> Dictionary:
	return {
		"body_id": body_id,
		"carrier": carrier,
		"spawn_tick": spawn_tick,
		"lifetime_ticks": lifetime_ticks,
		"state": state,
		"parent_ref": parent_ref,
		"generation": generation,
		"origin": origin,
	}


func _event(reason: String, event_tick: int) -> Dictionary:
	return {
		"type": "vanish",
		"tick": event_tick,
		"body_id": body_id,
		"reason": reason,
	}
