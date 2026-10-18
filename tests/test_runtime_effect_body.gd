extends GutTest

const CARRIERS := ["none", "self", "independent", "attached"]


func test_all_four_carriers_have_expected_lifecycle():
	var body_none := EffectBody.create("none", {"body_id": "n", "lifetime_ticks": 0}, 4)
	var body_self := EffectBody.create("self", {"body_id": "s", "lifetime_ticks": 2}, 4)
	var body_independent := EffectBody.create("independent", {"body_id": "i", "lifetime_ticks": 2}, 4)
	var body_attached := EffectBody.create("attached", {"body_id": "a", "lifetime_ticks": 2}, 4)
	assert_eq(body_none.state, EffectBody.CREATED)
	assert_true(body_self.is_alive())
	assert_true(body_independent.is_alive())
	assert_true(body_attached.is_alive())
	assert_eq(body_none.step(4)[0]["reason"], "instant_end")
	assert_eq(body_none.state, EffectBody.VANISHED)
	assert_eq(body_self.step(4), [])
	assert_eq(body_self.step(5), [])
	var ended := body_self.step(6)
	assert_eq(ended.size(), 1)
	assert_eq(ended[0]["type"], "vanish")
	assert_eq(ended[0]["reason"], "expired")
	assert_false(body_self.is_alive())
	assert_eq(body_independent.step(6).size(), 1)
	assert_eq(body_attached.step(6).size(), 1)


func test_purge_is_silent_and_dead():
	var body := EffectBody.create("independent", {"body_id": "purge", "lifetime_ticks": 3}, 2)
	body.purge()
	assert_false(body.is_alive())
	assert_eq(body.state, EffectBody.PURGED)
	assert_eq(body.step(2), [])
	assert_eq(body.step(99), [])


func test_natural_termination_emits_at_most_one_vanish():
	var body := EffectBody.create("attached", {"body_id": "once", "lifetime_ticks": 1}, 8)
	assert_eq(body.step(8), [])
	assert_eq(body.step(9).size(), 1)
	assert_eq(body.step(10), [])
	assert_eq(body.step(11), [])


func test_none_requires_zero_lifetime():
	assert_null(EffectBody.create("none", {"lifetime_ticks": 1}, 0))
	assert_not_null(EffectBody.create("none", {"lifetime_ticks": 0}, 0))


func test_non_none_requires_positive_integer_lifetime():
	assert_null(EffectBody.create("self", {"lifetime_ticks": 0}, 0))
	assert_null(EffectBody.create("self", {"lifetime_ticks": -1}, 0))
	assert_null(EffectBody.create("self", {"lifetime_ticks": 1.0}, 0))


func test_invalid_carrier_is_rejected_without_migration():
	assert_null(EffectBody.create("instant", {"lifetime_ticks": 0}, 0))
	assert_null(EffectBody.create("unknown", {"lifetime_ticks": 1}, 0))


func test_step_only_emits_frozen_event_types():
	for carrier in CARRIERS:
		var lifetime := 0 if carrier == "none" else 1
		var body := EffectBody.create(carrier, {"body_id": carrier, "lifetime_ticks": lifetime}, 2)
		for event in body.step(2):
			assert_true(event["type"] in ["hit", "vanish"])
		for event in body.step(3):
			assert_true(event["type"] in ["hit", "vanish"])
