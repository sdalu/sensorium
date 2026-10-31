# frozen_string_literal: true

require "test_helper"
require "support/filter_helpers"

# Filter: a location's fused values followed over time by a Kalman
# filter, the room's Dynamics::Model (or the drift rule) predicting
# between them. FusionHelpers' room, in winter.
class FilterTest < Minitest::Test
    include FilterHelpers

    def test_a_first_fused_starts_the_state
        state = filter.step(nil, fused(20.0, 0.1, at: AT))
        assert_in_delta 20.0, state.value
        assert_in_delta 0.01, state.variance
        assert_equal AT, state.at
    end

    # A steady room (drift 0.1 °C/h) read with noise every 10 min: the
    # state settles nearer the truth, and tighter, than any one reading.
    def test_noisy_readings_of_a_steady_room_settle
        random = Random.new(5)
        state = (0...48).reduce(nil) do |kept, step|
            noisy = 20.0 + ((random.rand - 0.5) * 0.6)
            calm.step(kept, fused(noisy, 0.2, at: AT + (step * 600)))
        end
        assert_in_delta 20.0, state.value, 0.08
        assert_operator Math.sqrt(state.variance), :<, 0.1
    end

    # One update at the state's moment: gain 0.01 / (0.01 + 0.04).
    def test_an_update_weighs_state_and_reading_by_their_variances
        state = filter.step(start, fused(21.0, 0.2, at: AT))
        assert_in_delta 20.2, state.value
        assert_in_delta 0.008, state.variance
    end

    # Without a model, the drift rule: the value stays, the variance
    # grows by (drift × hours)² before the update.
    def test_without_a_model_the_drift_rule
        state = filter.predict(start, AT + HOUR, snapshot("room", {}))
        assert_in_delta 20.0, state.value
        assert_in_delta 0.01 + 1.0, state.variance
    end

    # With one: moved as the model says, its variance by q × hours.
    def test_with_a_model_it_predicts
        snap = with_outside(snapshot("room", {}), 10.0)
        state = filter(dynamics: [model]).predict(start, AT + HOUR, snap)
        expected = model.change(20.0, 10.0, [], 1.0)
        assert_in_delta 20.0 + expected, state.value
        assert_in_delta 0.01 + 0.04, state.variance
    end

    # A Fused without a value, or without σ (no reference), predicts only.
    def test_a_fused_without_value_or_sigma_does_not_update
        later = AT + HOUR
        [fused(nil, nil, at: later), fused(21.0, nil, at: later)].each do |one|
            state = filter.step(start, one)
            assert_in_delta 20.0, state.value
            assert_in_delta 1.01, state.variance
        end
    end

    # Older than the state: nothing to learn from.
    def test_a_fused_older_than_the_state_is_ignored
        state = start
        assert_same state, filter.step(state, fused(25.0, 0.1, at: AT - 60))
    end

    def test_another_location_is_refused
        other = fused(20.0, 0.1, at: AT + 60).with(location: "elsewhere")
        assert_raises(ArgumentError) { filter.step(start, other) }
    end

    # A mismatch from the Fused, or from the setup's own quantity.
    def test_another_quantity_is_refused
        other = fused(20.0, 0.1, at: AT + 60).with(quantity: "humidity")
        assert_raises(ArgumentError) { filter.step(start, other) }
        mismatched = start.with(quantity: "humidity")
        assert_raises(ArgumentError) { filter.step(mismatched, other) }
    end

    # Predicting backward is a no-op: the state is given back as it was.
    def test_predicting_backward_leaves_the_state_unchanged
        state = start
        assert_same state, filter.predict(state, AT - HOUR)
    end

    # Humidity followed as absolute humidity, read back as relative at
    # the room's temperature.
    def test_a_state_reads_back_as_the_quantity
        humidity = Sensorium::Filter.new(
            Sensorium::Presets.room(Sensorium::Presets::HUMIDITY)
        )
        inside = Sensorium::Transform::AbsoluteHumidity
                 .forward(50.0, { temperature: 20.0 })
        state = start.with(quantity: "humidity", value: inside)
        read = humidity.estimate(state, { temperature: 20.0 })
        assert_in_delta 50.0, read.value
        assert_in_delta 0.1 * 50.0 / inside, read.sigma
    end
end
