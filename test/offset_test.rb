# frozen_string_literal: true

require "test_helper"

# Offset#correct: the learned model solved for the reference. Every
# value is made up.
class OffsetTest < Minitest::Test
    P10_P90 = Sensorium::P10_P90

    # sensor - ref = -0.5 + 0.4 (heating) - 0.4 (ref - neighbour)
    def test_the_model_solved_for_the_reference
        reference = 20.0
        neighbour = 15.0
        reading = reference - 0.5 + 0.4 - (0.4 * (reference - neighbour))
        found = offset.correct(reading, on: %w[heating], neighbour:)
        assert_in_delta reference, found.value
        assert_in_delta 0.2 / P10_P90 / 0.6, found.sigma
    end

    # A switch that is off adds nothing.
    def test_a_switch_off_is_no_term
        found = offset(neighbour: nil, coefficient: nil).correct(19.5)
        assert_in_delta 20.0, found.value
    end

    # sensor - ref = 0.3 + 0.05 × ref: a sensor that reads 5 % high.
    def test_the_gain_is_solved_for
        reference = 20.0
        found = offset(constant: 0.3, switches: {}, gain: 0.05,
                       neighbour: nil, coefficient: nil)
                .correct(reference + 0.3 + (0.05 * reference))
        assert_in_delta reference, found.value
        assert_in_delta 0.2 / P10_P90 / 1.05, found.sigma
    end

    # Without its neighbour, the constant alone and its wider spread.
    def test_without_the_neighbour_the_plain_offset
        found = offset.correct(19.0)
        assert_in_delta 19.0 + 0.8, found.value
        assert_in_delta 2.0 / P10_P90, found.sigma
    end

    # The aircon's shift on top of the plain offset it was learned over,
    # and its wider spread when it is wider.
    def test_the_aircon_shifts_and_widens
        found = offset(neighbour: nil, coefficient: nil)
                .correct(19.0, shifts: [shift])
        assert_in_delta 19.0 + 0.8 + 1.0, found.value
        assert_in_delta 3.0 / P10_P90, found.sigma
    end

    # The neighbour known and the heating on: still the plain offset
    # under the aircon, not the full model.
    def test_a_shift_is_over_the_plain_offset_whatever_else_holds
        found = offset.correct(19.0, on: %w[heating], neighbour: 15.0,
                                     shifts: [shift])
        assert_in_delta 19.0 + 0.8 + 1.0, found.value
    end

    # A Mode holding that no Shift was learned for: the plain offset
    # alone, with its own spread, not the full model.
    def test_a_mode_without_a_shift_takes_the_plain_offset
        found = offset.correct(19.0, on: %w[heating], neighbour: 15.0,
                                     held: true)
        assert_in_delta 19.0 + 0.8, found.value
        assert_in_delta 2.0 / P10_P90, found.sigma
    end

    private

    def shift
        Sensorium::Shift.new(location: "a", device: "s",
                             quantity: "temperature", regime: "summer",
                             influence: "aircon", mode: "cooling",
                             shift: -1.0, p10: -1.5, p90: 1.5, samples: 200)
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
