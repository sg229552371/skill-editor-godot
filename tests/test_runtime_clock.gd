extends GutTest


func test_pause_does_not_advance_or_consume_rng():
	var clock := SimClock.new(17)
	var before := clock.snapshot_state()
	clock.pause()
	assert_eq(clock.advance(10), 0)
	var after: Dictionary = clock.snapshot_state()
	assert_eq(after["tick"], before["tick"])
	assert_eq(after["logic_rng"]["seed"], before["logic_rng"]["seed"])
	assert_eq(after["logic_rng"]["state"], before["logic_rng"]["state"])
	assert_eq(after["presentation_rng"]["seed"], before["presentation_rng"]["seed"])
	assert_eq(after["presentation_rng"]["state"], before["presentation_rng"]["state"])
	assert_true(after["paused"])
	assert_true(clock.is_paused())


func test_same_seed_same_operations_are_stepwise_deterministic():
	var first := SimClock.new(1234)
	var second := SimClock.new(1234)
	var first_values: Array = []
	var second_values: Array = []
	for i in range(4):
		first_values.append([first.advance(1), first.rng_logic().randi(), first.rng_presentation().randi()])
		second_values.append([second.advance(1), second.rng_logic().randi(), second.rng_presentation().randi()])
	assert_eq(first_values, second_values)
	assert_eq(first.snapshot_state(), second.snapshot_state())


func test_logic_and_presentation_streams_do_not_interfere():
	var with_presentation := SimClock.new(99)
	var without_presentation := SimClock.new(99)
	var expected_logic: Array = []
	var actual_logic: Array = []
	for i in range(5):
		with_presentation.rng_presentation().randi()
		actual_logic.append(with_presentation.rng_logic().randi())
		expected_logic.append(without_presentation.rng_logic().randi())
	assert_eq(actual_logic, expected_logic)


func test_slow_motion_is_not_pause():
	var clock := SimClock.new(3)
	clock.set_time_scale(0.5)
	assert_eq(clock.advance(1), 0)
	assert_false(clock.is_paused())
	assert_eq(clock.advance(1), 1)
	clock.pause()
	assert_eq(clock.advance(100), 1)
	clock.resume()
	assert_eq(clock.advance(1), 1)
	assert_eq(clock.advance(1), 2)
