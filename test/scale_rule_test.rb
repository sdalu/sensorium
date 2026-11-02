# frozen_string_literal: true

require "test_helper"

# The keep rule on the correction, not the gap: a linear term's residual
# is divided by |1 + gain + coefficient| when a reading is corrected, so
# a neighbour that narrows the gap to 60 % with k = -0.4 leaves the
# correction as wide as the constant alone (60 / 60), and one with
# k = +0.6 that narrows the gap to 90 % leaves it at 56 % (90 / 160).
# Made-up bins as ScaleGuardTest's: a reference swinging ±3 around 20, a
# neighbour ±5 around 10, the noise uniform.
class ScaleRuleTest < Minitest::Test
    BINS = (0...1000).to_a
    LATE = 900

    def setup
        @reference = BINS.to_h { [it, 20 + (3 * Math.sin(it / 50.0))] }
        @gaps = BINS.to_h { [it, @reference[it] - neighbour(it)] }
        @random = Random.new(7)
    end

    def test_a_neighbour_narrowing_the_gap_but_not_the_correction_is_refused
        diffs = diffs(-0.4, 4.2)
        ratio = gap_ratio(diffs, -0.4)
        assert_operator ratio, :<, 0.8
        assert_operator ratio / 0.6, :>, 0.8
        assert_nil fit(diffs).neighbour
    end

    def test_a_neighbour_narrowing_the_correction_is_kept_though_the_gap_barely
        diffs = diffs(0.6, 13.0)
        assert_in_delta 0.9, gap_ratio(diffs, 0.6), 0.05
        model = fit(diffs)
        assert_equal "n", model.neighbour
        assert_in_delta 0.6, model.coefficient, 0.03
    end

    # Exact while fitted, noisy on the bins held out: they still narrow
    # the gap to 60 %, which is the correction no narrower.
    def test_the_bins_held_out_judge_the_correction_too
        fitted, out = BINS.to_h { [it, noisy_late(it)] }
                          .partition { |bin, _| bin < LATE }
                          .map(&:to_h)
        assert_equal "n", fit(fitted).neighbour
        assert_nil fit(fitted, held_out: out).neighbour
    end

    def test_a_models_scale
        assert_in_delta 1.6, fit(diffs(0.6, 13.0)).scale, 0.03
        plain = Sensorium::Fit.new({ 1 => 0.0 }, setup_of, levels: {}).plain
        assert_in_delta 1.0, plain.scale
    end

    private

    def neighbour(bin) = 10 + (5 * Math.cos(bin / 37.0))

    def uniform = @random.rand - 0.5

    def diffs(k, noise)
        BINS.to_h { [it, (k * @gaps[it]) + (uniform * noise)] }
    end

    def noisy_late(bin)
        (-0.4 * @gaps[bin]) + (uniform * (bin < LATE ? 0.02 : 4.2))
    end

    # The spread the neighbour leaves on the gap over the constant's.
    def gap_ratio(diffs, k)
        left = diffs.map { |bin, d| d - (k * @gaps[bin]) }
        plain = Sensorium::Stats.median(diffs.values)
        Sensorium::Stats.spread(left) /
            Sensorium::Stats.spread(diffs.values.map { it - plain })
    end

    def setup_of
        Sensorium::Setup.new(quantity: Sensorium::Presets::TEMPERATURE,
                             gain: false)
    end

    def fit(diffs, held_out: nil)
        Sensorium::Fit.new(diffs, setup_of, levels: @reference,
                                            candidates: { "n" => @gaps },
                                            held_out:).model
    end
end
