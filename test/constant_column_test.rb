# frozen_string_literal: true

require "test_helper"

# A column that does not vary, whose mean is not exact in binary: the
# centred values are rounding, not variation, and no slope is there.
class ConstantColumnTest < Minitest::Test
    YS = [0.0, 0.1, 0.2].freeze

    def test_the_line_refuses_a_constant_column
        assert_nil Sensorium::Stats.line([0.1] * 3, YS)
    end

    def test_the_plane_refuses_a_constant_column
        assert_nil Sensorium::Stats.plane([0.1] * 3, [1.0, 2.0, 4.0], YS)
    end

    def test_least_squares_refuses_a_constant_column
        assert_nil Sensorium::Stats.least_squares([[0.1] * 3], YS)
    end

    # A reference that read 15.07 throughout (a frozen sensor), over
    # 777 bins: no gain can be told from it, and none is kept.
    def test_no_gain_on_a_reference_that_does_not_vary
        bins = (0...777).to_a
        random = Random.new(3)
        diffs = bins.to_h { [it, 0.3 + ((random.rand - 0.5) * 0.2)] }
        setup = Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE)
        model = Sensorium::Fit::Validated.learn(
            diffs, setup, levels: bins.to_h { [it, 15.07] }
        ).model
        assert_nil model.gain
    end
end
