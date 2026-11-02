# frozen_string_literal: true

require "test_helper"

# Fit::Validated.learn: two Series kept, the second known on the bins
# held out only over a stretch where the sensor read its reference
# exactly (the plain constant leaves nothing to narrow there). Each
# term passed HeldOut#keeps? against the model before it, but
# confirmed measures the final model against the plain constant over
# that stretch alone: 0 wide before, wider after, an infinite
# inflation, and Learned.widened cannot round it.
class WidenedBoundTest < Minitest::Test
    BINS = (0...1000).to_a
    FLAT = (900...915).to_a

    def setup
        @a = BINS.to_h { [it, Math.sin(it / 23.0) * 10] }
        b = BINS.to_h { [it, Math.cos(it / 31.0) * 10] }
        @b = b.select { |bin, _| bin < 900 }
        FLAT.each { @b[it] = -0.75 * @a[it] }
        @diffs = diffs(b, Random.new(5))
    end

    def test_the_inflation_is_finite
        assert_predicate learned.inflation, :finite?
    end

    def test_the_widened_widths_are_finite
        values = { p10: -0.1, p90: 0.1, states: { "a" => [0.0, 0.0] } }
        widened = Sensorium::Learned.widened(values, learned.inflation)
        assert_predicate widened[:p90] - widened[:p10], :finite?
        assert_predicate widened[:states]["a"].sum, :finite?
    end

    private

    # 0.3 a + 0.2 b on the bins fitted, exactly 1 on FLAT, 0.3 a on the
    # other bins held out, with a little noise.
    def diffs(b, random)
        BINS.to_h do |bin|
            noise = (random.rand - 0.5) * 0.02
            next [bin, 1.0] if FLAT.include?(bin)
            value = bin < 900 ? (0.3 * @a[bin]) + (0.2 * b[bin]) : 0.3 * @a[bin]
            [bin, value + noise]
        end
    end

    def learned
        setup = Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE,
                                     gain: false, rate: false)
        Sensorium::Fit::Validated.learn(@diffs, setup,
                                        levels: BINS.to_h { [it, 20.0] },
                                        series: { "a" => @a, "b" => @b })
    end
end
