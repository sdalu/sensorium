# frozen_string_literal: true

require "test_helper"

# A reference frozen at 15.01, reporting every minute or so: a bin of
# ten minutes holds ten readings or eleven, and the mean of eleven
# 15.01 is 15.009999999999998. The column does not vary, an ulp aside:
# no gain can be told from it, and none is kept.
class FrozenReferenceCadenceTest < Minitest::Test
    BIN = 600

    def levels(bins)
        series = Sensorium::Series.new(BIN)
        readings = bins.flat_map do |bin|
            count = (bin % 3).zero? ? 10 : 11
            Array.new(count) do |i|
                Sensorium::Reading.new(time: (bin * BIN) + (i * 50),
                                       location: "room", device: "ref",
                                       value: 15.01, context: {})
            end
        end
        series.means(readings).transform_keys { it / BIN }
    end

    def test_the_bin_means_differ_by_an_ulp
        assert_equal 2, levels((0...4).to_a).values.uniq.size
    end

    def test_the_line_refuses_a_column_varying_by_an_ulp
        xs = [15.01, 15.009999999999998, 15.01, 15.009999999999998]
        assert_nil Sensorium::Stats.line(xs, [0.0, 0.1, 0.2, 0.3])
    end

    # The same reference's rate (Setup#rate's column): ±1e-11 °C/h of
    # rounding, no rate to fit a slope on.
    def test_the_line_refuses_the_rate_of_a_frozen_reference
        series = Sensorium::Series.new(BIN)
        rates = series.rates(levels((0...40).to_a)
                                 .transform_keys { it * BIN })
        refute rates.values.all?(&:zero?)
        ys = rates.keys.map { (it / BIN) * 0.001 }
        assert_nil Sensorium::Stats.line(rates.values, ys)
    end

    def test_no_gain_on_a_frozen_reference_read_at_an_uneven_cadence
        bins = (0...777).to_a
        random = Random.new(3)
        diffs = bins.to_h { [it, 0.3 + ((random.rand - 0.5) * 0.2)] }
        setup = Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE)
        model = Sensorium::Fit::Validated.learn(
            diffs, setup, levels: levels(bins)
        ).model
        assert_nil model.gain
    end
end
