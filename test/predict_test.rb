# frozen_string_literal: true

require "test_helper"

# Offset#predict: the reading a sensor is expected to give while its
# reference is r, the model as stated; Knowledge's readers of a
# sensor's Offset, Shift and Track; Track#foresee. Every value is made
# up.
class PredictTest < Minitest::Test
    P10_P90 = Sensorium::P10_P90

    # sensor - ref = -0.5 + 0.4 (heating) - 0.4 (ref - neighbour), its
    # σ the gap's, not over scale.
    def test_the_model_as_stated
        found = offset.predict(20.0, on: %w[heating], neighbour: 15.0)
        assert_in_delta 20.0 - 0.5 + 0.4 - 2.0, found.value
        assert_in_delta 0.2 / P10_P90, found.sigma
    end

    # The reading predicted, corrected, is the reference again, and
    # the correction's σ is the reading's over scale.
    def test_correct_is_its_inverse
        moment = { on: %w[heating], neighbour: 15.0 }
        found = offset.predict(20.0, **moment)
        back = offset.correct(found.value, **moment)
        assert_in_delta 20.0, back.value
        assert_in_delta found.sigma / offset.scale.abs, back.sigma
    end

    # With a gain: r × scale, the sensor 5 % high.
    def test_the_gain_multiplies_the_reference
        found = offset(constant: 0.3, switches: {}, gain: 0.05,
                       neighbour: nil, coefficient: nil).predict(20.0)
        assert_in_delta 20.0 + 0.3 + 1.0, found.value
    end

    # Without the neighbour, the plain offset and its spread, as
    # correct falls back.
    def test_without_the_neighbour_the_plain_offset
        found = offset.predict(20.0)
        assert_in_delta 20.0 - 0.8, found.value
        assert_in_delta 2.0 / P10_P90, found.sigma
        assert_in_delta 20.0, offset.correct(found.value).value
    end

    # Under a Mode, the plain offset and the Shift, the wider spread;
    # a Mode with no Shift learned: the plain offset alone.
    def test_under_a_mode_the_plain_offset_and_its_shift
        found = offset.predict(20.0, on: %w[heating], neighbour: 15.0,
                                     shifts: [shift])
        assert_in_delta 20.0 - 0.8 - 1.0, found.value
        assert_in_delta 3.0 / P10_P90, found.sigma
        alone = offset.predict(20.0, neighbour: 15.0, held: true)
        assert_in_delta 20.0 - 0.8, alone.value
    end

    def test_the_knowledge_finds_a_sensors_offset
        knowledge = Sensorium::Knowledge.new(offsets: [offset])
        assert_equal offset, knowledge.offset("a", "s", "winter")
        assert_nil knowledge.offset("a", "s", "summer")
    end

    # What holds, one Mode or two named as one; none: no Shift.
    def test_the_knowledge_finds_a_sensors_shift
        knowledge = Sensorium::Knowledge.new(shifts: [shift, pair])
        holding = [%w[aircon cooling]]
        assert_equal shift, knowledge.shift("a", "s", "summer", holding)
        assert_equal pair, knowledge.shift("a", "s", "summer",
                                           [%w[fan on], %w[aircon cooling]])
        assert_nil knowledge.shift("a", "s", "winter", holding)
        assert_nil knowledge.shift("a", "s", "summer", [])
    end

    # The track of the Offset it follows, none after a relearn.
    def test_the_knowledge_finds_the_track_of_the_offset
        knowledge = Sensorium::Knowledge.new(tracks: { %w[a s] => track })
        assert_equal track, knowledge.track("a", "s", offset)
        assert_nil knowledge.track("a", "s", offset.with(constant: -0.4))
        assert_nil knowledge.track("a", "t", offset)
    end

    # foresee puts back what apply takes out; nothing while jumped.
    def test_a_track_foresees_the_reading_now
        estimate = Sensorium::Estimate.new(value: 19.0, sigma: 0.1)
        found = track.foresee(estimate)
        assert_in_delta 19.3, found.value
        assert_in_delta Math.sqrt(0.01 + 0.0004), found.sigma
        assert_nil track.with(state: :jumped).foresee(estimate)
    end

    private

    def track
        Sensorium::Track.fresh(offset, 0.0004).with(delta: 0.3)
    end

    def shift
        Sensorium::Shift.new(location: "a", device: "s",
                             quantity: "temperature", regime: "summer",
                             influence: "aircon", mode: "cooling",
                             shift: -1.0, p10: -1.5, p90: 1.5, samples: 200)
    end

    # Both Modes at once: a value of its own.
    def pair
        shift.with(influence: "aircon+fan", mode: "cooling+on", shift: -2.0)
    end

    def offset(**changes)
        Sensorium::Offset.new(location: "a", device: "s",
                              quantity: "temperature", regime: "winter",
                              reference: "r", constant: -0.5,
                              switches: { "heating" => 0.4 }, gain: nil,
                              neighbour: "b/n", coefficient: -0.4,
                              p10: -0.1, p90: 0.1, samples: 1000,
                              plain: -0.8, plain_p10: -1.0, plain_p90: 1.0)
                         .with(**changes)
    end
end
