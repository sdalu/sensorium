# frozen_string_literal: true

require "test_helper"
require "support/dynamic_room"

# Dynamics.learn on made-up rooms (DynamicRoom): one that follows the
# outside and its radiators, one that runs away from the outside, one
# seen too briefly, one that is only noise around a constant.
class DynamicsTest < Minitest::Test
    START = Time.utc(2026, 1, 5)
    DAYS  = 30

    # Per hour 0.1 and 0.5: per bin a sixth of each.
    def test_a_room_recovers_its_outside_and_heating_terms
        model = learn(room).first
        assert_equal "all", model.regime
        assert_in_delta 0.1 / 6, model.a, 0.1 / 60
        assert_in_delta 0.5 / 6, model.b.fetch("heating"), 0.5 / 60
        assert_in_delta 0.0, model.c, 0.01
    end

    def test_a_room_the_model_predicts_is_kept_with_its_validation
        model = learn(room).first
        assert_operator model.rms_model, :<, model.rms_hold
        assert_equal 600, model.bin
        assert_operator model.steps, :>=, DAYS * 144
    end

    def test_noise_around_a_constant_gives_no_model
        assert_empty learn(room(constant: true))
    end

    def test_an_unstable_room_gives_no_model
        assert_empty learn(room(a: -0.06))
    end

    def test_too_short_a_history_gives_no_model
        assert_empty learn(DynamicRoom.new(START, 300))
    end

    # A room the outside does not move, learned without it.
    def test_without_an_outside_there_is_no_outside_term
        model = learn(room(a: 0.0), outside: nil).first
        assert_in_delta 0.0, model.a
        assert_in_delta 0.5 / 6, model.b.fetch("heating"), 0.5 / 60
    end

    # The aircon cools by 0.3 a bin two hours a day: left out, it does
    # not bias a.
    def test_the_bins_under_a_mode_are_left_out
        aircon = [DynamicRoom::HEATING, DynamicRoom::AIRCON]
        model = learn(room(aircon: true), influences: aircon).first
        assert_in_delta 0.1 / 6, model.a, 0.1 / 60
    end

    # The noise is correlated from bin to bin: q is what an hour ahead
    # really misses, not six times a bin's.
    def test_q_is_the_error_of_an_hour_ahead
        ar1 = room(noise: :ar1)
        model = learn(ar1).first
        errors = ar1.hour_errors
        truth = errors.sum { it**2 } / errors.size
        assert_in_delta truth, model.q, 0.25 * truth
    end

    private

    def room(**) = DynamicRoom.new(START, DAYS * 144, **)

    def learn(room, outside: "outside", influences: [DynamicRoom::HEATING])
        setup = Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE,
                                     places: %w[ceiling], outside:,
                                     influences:)
        Sensorium::Dynamics.learn(room, setup,
                                  from: START,
                                  to: START + (room.size * DynamicRoom::STEP))
    end
end
