class_name SimClock extends RefCounted

## Deterministic fixed-step simulation clock.
##
## `tick()` is the explicit one-tick driver. `advance()` represents elapsed
## driver steps and applies `time_scale`; fractional progress is retained so a
## slow-motion clock never has to round a tick early. Pause is intentionally a
## separate state and does not consume fractional time or RNG values.

const _PRESENTATION_SEED_OFFSET: int = 0x5EED5EED

var _tick: int = 0
var _paused: bool = false
var _time_scale: float = 1.0
var _scale_remainder: float = 0.0
var _logic_rng: RandomNumberGenerator
var _presentation_rng: RandomNumberGenerator

func _init(seed_value: int):
	_logic_rng = RandomNumberGenerator.new()
	_presentation_rng = RandomNumberGenerator.new()
	_logic_rng.seed = seed_value
	# Keep presentation randomness deterministic, but on a separate stream.
	_presentation_rng.seed = seed_value + _PRESENTATION_SEED_OFFSET


## Advance exactly one simulation tick, ignoring time scale.
func tick() -> int:
	if _paused:
		return _tick
	_tick += 1
	return _tick


## Advance `n` driver steps. Returns the current simulation tick.
## A paused clock does not consume steps, fractional scale, or RNG state.
func advance(n: int = 1) -> int:
	if _paused or n <= 0:
		return _tick
	_scale_remainder += float(n) * _time_scale
	var ticks_to_run: int = int(floor(_scale_remainder))
	_scale_remainder -= float(ticks_to_run)
	for _i in range(ticks_to_run):
		tick()
	return _tick


## Set the rate at which `advance()` converts driver steps to simulation ticks.
## Zero is accepted as a stopped rate, but is not the pause mechanism.
func set_time_scale(scale: float):
	if not is_finite(scale) or scale < 0.0:
		return
	_time_scale = scale


func pause():
	_paused = true


func resume():
	_paused = false


func is_paused() -> bool:
	return _paused


func rng_logic() -> RandomNumberGenerator:
	return _logic_rng


func rng_presentation() -> RandomNumberGenerator:
	return _presentation_rng


func snapshot_state() -> Dictionary:
	return {
		"tick": _tick,
		"paused": _paused,
		"time_scale": _time_scale,
		"scale_remainder": _scale_remainder,
		"logic_rng": {
			"seed": _logic_rng.seed,
			"state": _logic_rng.state,
		},
		"presentation_rng": {
			"seed": _presentation_rng.seed,
			"state": _presentation_rng.state,
		},
	}
