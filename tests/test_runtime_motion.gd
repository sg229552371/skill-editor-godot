extends GutTest

const MotionScript = preload("res://skill_core/runtime/motion.gd")
const ClockScript = preload("res://skill_core/runtime/sim_clock.gd")
const BodyScript = preload("res://skill_core/runtime/effect_body.gd")


func _body():
	return BodyScript.create(BodyScript.CARRIER_INDEPENDENT, {"lifetime_ticks": 100}, 0)


# Source: ch05 5.5.1 speed is pixels per tick; ED-17-24.
func test_straight_ticks_pause_duplicate_and_cfg_isolation():
	var clock = ClockScript.new(17)
	var motion = MotionScript.new()
	var cfg: Dictionary = {"motion": {"mode": "straight", "speed": 3.0, "range": 10.0}}
	var original: Dictionary = cfg.duplicate(true)
	assert_true(motion.configure(cfg, _body(), clock, {"position": Vector2(1, 2)}))
	assert_false(motion.step())
	clock.tick()
	assert_true(motion.step())
	assert_eq(motion.position, Vector2(4, 2))
	assert_false(motion.step())
	clock.pause()
	clock.advance(10)
	assert_false(motion.step())
	assert_eq(motion.position, Vector2(4, 2))
	clock.resume()
	for i in range(3):
		clock.tick()
		assert_true(motion.step())
	assert_eq(motion.position, Vector2(11, 2))
	assert_true(motion.finished)
	assert_eq(cfg, original)


# ch04 4.2.2 / 4.8: the parabola is presentation, landing uses ground position.
func test_lob_lands_at_fixed_ground_target_without_overshoot():
	var clock = ClockScript.new(1)
	var motion = MotionScript.new()
	assert_true(motion.configure({"motion": {"mode": "lob"}}, _body(), clock,
		{"target": Vector2(6, 0), "flight_ticks": 2}))
	clock.tick()
	assert_true(motion.step())
	assert_eq(motion.position, Vector2(3, 0))
	clock.tick()
	assert_true(motion.step({"target": Vector2(900, 0)}))
	assert_eq(motion.position, Vector2(6, 0))
	assert_true(motion.finished)


# ch04 4.2.8 fixed origin and heading after spawning.
func test_stationary_ignores_moving_target_and_anchor():
	var clock = ClockScript.new(1)
	var motion = MotionScript.new()
	assert_true(motion.configure({"motion": {"mode": "stationary"}}, _body(), clock,
		{"position": Vector2(2, 3), "direction": Vector2.UP}))
	clock.tick()
	assert_true(motion.step({"target": Vector2(50, 0), "center": Vector2(100, 0)}))
	assert_eq(motion.position, Vector2(2, 3))
	assert_eq(motion.direction, Vector2.UP)


# ch05 5.6: wavefront speed belongs to geometry, not translational speed.
func test_wavefront_clamps_radius_without_moving_center_or_changing_cfg():
	var clock = ClockScript.new(1)
	var motion = MotionScript.new()
	var cfg: Dictionary = {"motion": {"mode": "wavefront"}, "geometry": {
		"wavefront_start_radius": 2.0, "wavefront_end_radius": 7.0, "wavefront_speed": 3.0}}
	var original: Dictionary = cfg.duplicate(true)
	assert_true(motion.configure(cfg, _body(), clock, {"position": Vector2(10, 20)}))
	assert_eq(motion.radius, 2.0)
	clock.tick()
	assert_true(motion.step())
	assert_eq(motion.radius, 5.0)
	clock.tick()
	assert_true(motion.step())
	assert_eq(motion.radius, 7.0)
	assert_true(motion.finished)
	assert_eq(motion.position, Vector2(10, 20))
	assert_eq(cfg, original)


# ch04 4.2.6: a moving reference center does not turn the body into self.
# Angle conversion is an explicit host policy until its units are frozen.
func test_orbit_phase_radius_and_moving_reference_center():
	var clock = ClockScript.new(1)
	var body = _body()
	var motion = MotionScript.new()
	assert_true(motion.configure({"motion": {"mode": "orbit", "orbit_radius": 10.0,
		"angular_speed": 90.0, "phase": 0.0}}, body, clock,
		{"center": Vector2(2, 3), "angle_scale": PI / 180.0}))
	assert_eq(motion.position, Vector2(12, 3))
	clock.tick()
	assert_true(motion.step({"center": Vector2(5, 6)}))
	assert_almost_eq(motion.position.x, 5.0, 0.00001)
	assert_almost_eq(motion.position.y, 16.0, 0.00001)
	assert_eq(body.carrier, BodyScript.CARRIER_INDEPENDENT)
	assert_true(body.is_alive())


# ch04 4.2.7: same body for both legs, no reset of identity or origin.
func test_returning_reverses_then_clamps_to_reference_without_events():
	var clock = ClockScript.new(1)
	var body = _body()
	var identity: Dictionary = body.to_debug_record().duplicate(true)
	var motion = MotionScript.new()
	assert_true(motion.configure({"motion": {"mode": "returning", "speed": 4.0, "range": 6.0}},
		body, clock, {"return_point": Vector2.ZERO}))
	var expected: Array = [Vector2(4, 0), Vector2(6, 0), Vector2(2, 0), Vector2.ZERO]
	for point in expected:
		clock.tick()
		assert_true(motion.step({"return_point": Vector2.ZERO}))
		assert_eq(motion.position, point)
	assert_true(motion.returning)
	assert_true(motion.finished)
	assert_eq(body.to_debug_record(), identity)
	# Nonempty positive control: lifecycle alone emits the existing event.
	var events: Array = body.step(100)
	assert_eq(events.size(), 1)
	assert_eq(events[0]["type"], "vanish")
	assert_eq(body.step(101), [])


func _aim(_position: Vector2, _direction: Vector2, target: Vector2, rng: RandomNumberGenerator) -> Vector2:
	return target.rotated(rng.randf_range(-0.1, 0.1)).normalized()


# ch05 5.5.1: profile owns turning; ED-17-24 logic RNG is isolated.
func test_homing_profile_uses_clock_rng_and_replays_tick_for_tick():
	var tracks: Array = []
	for run in range(2):
		var clock = ClockScript.new(89)
		var motion = MotionScript.new()
		assert_true(motion.register_tracking_profile("test_aim", _aim))
		assert_true(motion.configure({"motion": {"mode": "homing", "speed": 2.0,
			"tracking_profile": "test_aim"}}, _body(), clock))
		var track: Array = []
		for i in range(4):
			if run == 1:
				clock.rng_presentation().randf()
			clock.tick()
			assert_true(motion.step({"target": Vector2(0, 10)}))
			track.append(motion.position)
			var rng_state: int = clock.rng_logic().state
			assert_false(motion.step({"target": Vector2(0, 10)}))
			assert_eq(clock.rng_logic().state, rng_state)
		assert_gt(motion.position.y, 7.0)
		tracks.append(track)
	assert_eq(tracks[0].size(), 4)
	assert_eq(tracks[0], tracks[1])


func test_homing_without_profile_keeps_heading_and_lost_target_policies_are_explicit():
	var clock = ClockScript.new(2)
	var plain = MotionScript.new()
	assert_true(plain.configure({"motion": {"mode": "homing", "speed": 2.0}}, _body(), clock))
	clock.tick()
	assert_true(plain.step({"target": Vector2(0, 10)}))
	assert_eq(plain.position, Vector2(2, 0))
	for policy in ["continue", "terminate"]:
		var lost_clock = ClockScript.new(3)
		var motion = MotionScript.new()
		assert_true(motion.register_tracking_profile("test_aim", _aim))
		assert_true(motion.configure({"motion": {"mode": "homing", "speed": 2.0,
			"tracking_profile": "test_aim"}, "on_target_lost": policy}, _body(), lost_clock))
		lost_clock.tick()
		var before: int = lost_clock.rng_logic().state
		assert_true(motion.step({"target": null}))
		assert_true(motion.target_lost)
		assert_eq(lost_clock.rng_logic().state, before)
		assert_eq(motion.finished, policy == "terminate")
		assert_eq(motion.position, Vector2.ZERO if policy == "terminate" else Vector2(2, 0))


func test_acceleration_is_bounded_and_never_reverses():
	var clock = ClockScript.new(1)
	var motion = MotionScript.new()
	assert_true(motion.configure({"motion": {"mode": "straight", "speed": 5.0,
		"acceleration": -3.0, "speed_cap": 6.0}}, _body(), clock))
	clock.tick()
	assert_true(motion.step())
	assert_eq(motion.position, Vector2(2, 0))
	clock.tick()
	assert_true(motion.step())
	assert_eq(motion.speed, 0.0)
	assert_eq(motion.position, Vector2(2, 0))
	var fast = MotionScript.new()
	assert_true(fast.configure({"motion": {"mode": "straight", "speed": 5.0,
		"acceleration": 3.0, "speed_cap": 6.0}}, _body(), clock))
	clock.tick()
	assert_true(fast.step())
	assert_eq(fast.position, Vector2(6, 0))


func test_slow_motion_skipped_tick_and_purge():
	var clock = ClockScript.new(1)
	var body = _body()
	var motion = MotionScript.new()
	assert_true(motion.configure({"motion": {"mode": "straight", "speed": 2.0}}, body, clock))
	clock.set_time_scale(0.5)
	clock.advance()
	assert_false(motion.step())
	clock.advance()
	assert_true(motion.step())
	assert_eq(motion.position, Vector2(2, 0))
	clock.advance(4)
	assert_false(motion.step())
	assert_true(motion.last_error.contains("Skipped"))
	assert_eq(motion.position, Vector2(2, 0))
	body.purge()
	clock.tick()
	assert_false(motion.step())
	assert_eq(motion.position, Vector2(2, 0))
	assert_eq(body.state, BodyScript.PURGED)
	assert_eq(body.step(100), [])


func _extension(_inputs: Dictionary) -> bool:
	return true


func test_registry_lists_seven_and_leaves_three_unimplemented_extension_slots():
	var motion = MotionScript.new()
	var expected: Array = ["straight", "lob", "orbit", "stationary", "wavefront", "returning", "homing"]
	var actual: Array = motion.registered_modes()
	expected.sort()
	actual.sort()
	assert_eq(actual.size(), 7)
	assert_eq(actual, expected)
	for mode in ["ricochet", "expanding", "follow", "return", "arc", "unknown"]:
		var rejected = MotionScript.new()
		assert_false(rejected.configure({"motion": {"mode": mode, "speed": 2.0}}, _body(), ClockScript.new(1)))
		assert_true(rejected.last_error.contains("Unsupported"))
	assert_false(motion.register_mode("unknown", _extension, []))
	assert_false(motion.register_mode("expanding", _extension, ["invented_key"]))
	assert_true(motion.register_mode("expanding", _extension, []))
	assert_eq(motion.registered_modes().size(), 8)
	var clock = ClockScript.new(1)
	assert_true(motion.configure({"motion": {"mode": "expanding"}}, _body(), clock))
	clock.tick()
	assert_true(motion.step())


func test_invalid_numeric_and_required_inputs_fail_with_reasons():
	var invalid: Array = [
		{"mode": "straight"},
		{"mode": "straight", "speed": -1},
		{"mode": "straight", "speed": "2"},
		{"mode": "straight", "speed": null},
		{"mode": "straight", "speed": INF},
		{"mode": "straight", "speed": NAN},
		{"mode": "straight", "speed": 1, "acceleration": 1},
		{"mode": "straight", "speed": 1, "range": 0},
		{"mode": "straight", "speed": 1, "unexpected": 9},
		{"mode": "stationary", "speed": 1},
		{"mode": "lob", "speed": 1},
		{"mode": "orbit", "orbit_radius": 2, "phase": 0, "angular_speed": 1},
		{"mode": "returning", "speed": 1, "range": 2},
		{"mode": "homing", "speed": 1, "tracking_profile": "missing"},
	]
	assert_eq(invalid.size(), 14)
	for cfg in invalid:
		var motion = MotionScript.new()
		assert_false(motion.configure({"motion": cfg}, _body(), ClockScript.new(1)), str(cfg))
		assert_ne(motion.last_error, "")
	var wave = MotionScript.new()
	assert_false(wave.configure({"motion": {"mode": "wavefront"}, "geometry": {
		"wavefront_start_radius": 3, "wavefront_end_radius": 3, "wavefront_speed": 1}}, _body(), ClockScript.new(1)))
	assert_true(wave.last_error.contains("ordered radii"))


func test_expiry_prevents_extra_movement_without_emitting_or_mutating_lifecycle():
	var clock = ClockScript.new(1)
	var body = BodyScript.create(BodyScript.CARRIER_INDEPENDENT, {"lifetime_ticks": 2}, 0)
	var motion = MotionScript.new()
	assert_true(motion.configure({"motion": {"mode": "straight", "speed": 2}}, body, clock))
	clock.tick()
	assert_true(motion.step())
	assert_eq(motion.position, Vector2(2, 0))
	clock.tick()
	assert_false(motion.step())
	assert_eq(motion.position, Vector2(2, 0))
	assert_eq(body.state, BodyScript.CREATED)
	var events: Array = body.step(2)
	assert_eq(events.size(), 1)
	assert_eq(events[0]["type"], "vanish")


func test_rejects_nonspatial_carriers_without_modifying_body():
	for carrier in [BodyScript.CARRIER_NONE, BodyScript.CARRIER_ATTACHED, BodyScript.CARRIER_SELF]:
		var body = BodyScript.create(carrier, {"lifetime_ticks": 0 if carrier == BodyScript.CARRIER_NONE else 10}, 0)
		var before: Dictionary = body.to_debug_record().duplicate(true)
		var motion = MotionScript.new()
		assert_false(motion.configure({"motion": {"mode": "straight", "speed": 1}}, body, ClockScript.new(1)))
		assert_true(motion.last_error.contains("carrier"))
		assert_eq(body.to_debug_record(), before)
