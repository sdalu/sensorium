# frozen_string_literal: true

require "test_helper"

# Learned.widened: an Offset's model widths widened about their middles
# by what the bins held out confirmed (Fit::Validated), the plain
# constant's left as they are.
class WidenedTest < Minitest::Test
    VALUES = { p10: -0.2, p90: 0.4, plain_p10: -0.5, plain_p90: 0.5,
               off_p10: -0.1, off_p90: 0.1,
               states: { "heating" => [-0.3, 0.5],
                         "solar:high" => [-0.2, 0.2, 350.0] } }.freeze

    def test_the_models_widths_widen_about_their_middles
        widened = Sensorium::Learned.widened(VALUES, 1.5)
        assert_equal [-0.35, 0.55, -0.15, 0.15],
                     widened.values_at(:p10, :p90, :off_p10, :off_p90)
        assert_equal({ "heating" => [-0.5, 0.7],
                       "solar:high" => [-0.3, 0.3, 350.0] },
                     widened[:states])
    end

    def test_the_plain_constants_do_not
        widened = Sensorium::Learned.widened(VALUES, 1.5)
        assert_equal [-0.5, 0.5], widened.values_at(:plain_p10, :plain_p90)
    end

    def test_no_off_widths_stay_none
        values = VALUES.merge(off_p10: nil, off_p90: nil)
        widened = Sensorium::Learned.widened(values, 2.0)
        assert_nil widened[:off_p10]
    end

    def test_a_factor_of_one_changes_nothing
        assert_equal VALUES, Sensorium::Learned.widened(VALUES, 1.0)
    end
end
